import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:io';
import 'dart:async';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:wespeek_client/utils/loading_helper.dart';
import 'providers/call_provider.dart';
import 'screens/main_screen.dart';
import 'utils/platform_utils.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    initOpus(await opus_flutter.load());
  } catch (_) {}

  await platformAdapter.init(() {
    // Initial show callback, mostly handled internally or via listener in adapter
  });

  // Preload settings
  final callProvider = CallProvider();
  // await callProvider.loadSettings(); // Settings are loaded in constructor

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: callProvider)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  CallProvider? _provider;
  bool _lastMicMuted = false;
  bool _lastSpeakerMuted = false;
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider = Provider.of<CallProvider>(context, listen: false);
      _provider?.addListener(_onProviderChange);
      _updateTrayMenu();
    });

    _initDeepLink();
  }

  Future<void> _initDeepLink() async {
    // Register protocol via platform adapter
    await platformAdapter.registerDeepLink('wespeek');

    _appLinks = AppLinks();

    // Check initial link
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _handleDeepLink(initialLink);
      }
    } catch (e) {
      // ignore
    }

    // Listen to changes
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    // Check scheme
    bool isProtocol = uri.scheme == 'wespeek';
    bool isWeb = kIsWeb && (uri.scheme == 'http' || uri.scheme == 'https');

    if (!isProtocol && !isWeb) return;

    String server = "";
    String? roomId = uri.queryParameters['room'];
    String? setupToken = uri.queryParameters['setup_admin'];

    if (isProtocol) {
      // Format: wespeek://server/?room=id
      server = uri.authority;
      // Handle simplified host if protocol stripped or added
      if (server.isEmpty) {
        // fallback parsing for some cases where authority is missed
        if (uri.path.isNotEmpty) {
          server = uri.path;
        }
      }
    } else {
      // Web: just use current window location or extracted param if logic allows
      if (uri.queryParameters.containsKey('server')) {
        server = uri.queryParameters['server']!;
      } else if (kIsWeb) {
        // Use current origin as server if not specified
        if (uri.hasScheme && uri.hasAuthority) {
           server = "${uri.scheme}://${uri.authority}";
        }
      }
    }

    if (roomId != null || setupToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_provider != null) {
          if (setupToken != null) {
            _provider!.handleSetupLink(server, setupToken, roomId: roomId);
          } else {
            _provider!.handleDeepLink(server, roomId);
          }
          platformAdapter.showWindow();
          platformAdapter.focusWindow();
        }
      });
    }
  }

  Future<void> _init() async {
    // Most initialization is done in main() via platformAdapter.init()
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _provider?.removeListener(_onProviderChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-apply wakelock when app becomes visible on web
    if (kIsWeb && state == AppLifecycleState.resumed) {
      _updateWakelock();
    }
  }

  void _onProviderChange() {
    if (_provider == null) return;
    bool mic = _provider!.isMicMuted;
    bool spk = _provider!.isSpeakerMuted;

    _updateWakelock();

    if (mic != _lastMicMuted || spk != _lastSpeakerMuted) {
      _lastMicMuted = mic;
      _lastSpeakerMuted = spk;
      _updateTrayMenu();
    }
  }

  void _updateWakelock() {
    if (_provider == null) return;
    bool inCall = _provider!.isInCall;

    // Handle Wakelock
    // Wrap in try-catch to avoid "NotAllowedError" on Web when page is not visible
    if (kIsWeb) {
      // On Web, requesting wakelock when hidden throws NotAllowedError
      // So we only request if we are visible
      if (!platformAdapter.isPageVisible) {
        return;
      }
    }

    WakelockPlus.toggle(enable: inCall).catchError((e) {
      debugPrint("Wakelock toggle error: $e");
    });
  }

  Future<void> _updateTrayMenu() async {
    await platformAdapter.updateTray(
      isMicMuted: _provider?.isMicMuted ?? false,
      isSpeakerMuted: _provider?.isSpeakerMuted ?? false,
      onShow: () {
        platformAdapter.showWindow();
      },
      onExit: () {
        if (!kIsWeb) exit(0);
      },
      onToggleMic: () {
        _provider?.toggleMicMute();
      },
      onToggleSpeaker: () {
        _provider?.toggleSpeakerMute();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hide loading indicator when the app builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      hideLoading();
    });

    return MaterialApp(
      title: 'WeSpeek',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScreen(),
    );
  }
}
