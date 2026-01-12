import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/platform_utils.dart';
import '../providers/call_provider.dart';
import '../theme/app_colors.dart';
import 'connect_screen.dart';
import 'components/left_sidebar.dart';
import 'components/top_bar.dart';
import 'components/chat_panel.dart';
import 'components/members_list.dart';
import 'components/screen_share_view.dart';
import 'components/custom_title_bar.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _showMembers = true;
  bool _isScreenShareHidden = false;
  bool _isVideoFullScreen = false;
  bool _isMiniWindow = false;
  bool _isSidebarCollapsed = false; // For mobile responsive design
  double _screenShareAspectRatio = 16 / 9;
  Size? _restoreSize;
  Offset? _restorePos;
  StreamSubscription? _errorSub;
  StreamSubscription? _fullScreenSub;

  @override
  void initState() {
    super.initState();

    // Listen for fullscreen changes
    _fullScreenSub = platformAdapter.onFullScreenChanged.listen((isFullScreen) {
      if (mounted && _isVideoFullScreen != isFullScreen) {
        setState(() => _isVideoFullScreen = isFullScreen);
      }
    });

    // Listen for audio errors
    final provider = context.read<CallProvider>();
    _errorSub = provider.errorEvents.listen((error) {
      if (!mounted) return;

      if (error.startsWith("WARNING: ")) {
        final message = error.substring("WARNING: ".length);
        // Clear existing SnackBars to ensure only one is visible at a time (Toast-like behavior)
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.black87,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("警告"),
            content: Text(error),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("确定"),
              ),
            ],
          ),
        );
      }
    });

    // Schedule post-frame check for connection
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CallProvider>();
      if (!provider.isConnected) {
        // If not connected, navigate to ConnectScreen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ConnectScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _fullScreenSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  Future<void> _enterFullScreen() async {
    // Only call platform if not already in that state (though adapter should handle it)
    await platformAdapter.setFullScreen(true);
    // State update handled by listener, but we can set it optimistically or ensure it
    if (mounted && !_isVideoFullScreen) {
      setState(() => _isVideoFullScreen = true);
    }
  }

  Future<void> _exitFullScreen() async {
    await platformAdapter.setFullScreen(false);
    if (mounted && _isVideoFullScreen) {
      setState(() => _isVideoFullScreen = false);
    }
  }

  Future<void> _enterMiniMode() async {
    // Web handles PiP internally in ScreenShareView
    if (kIsWeb) return;

    if (_isVideoFullScreen) {
      await _exitFullScreen();
    }

    _restoreSize = await windowManager.getSize();
    _restorePos = await windowManager.getPosition();

    // Set mini size (16:9 ratio, width 320)
    // Ensure window is visible and focused
    await windowManager.setSize(const Size(320, 180));
    await windowManager.setAlwaysOnTop(true);
    // Remove frame for cleaner look in mini mode? User didn't strictly ask, but it's common.
    // However, without frame, we need custom drag/close.
    // For now, keep frame to allow moving/closing easily.

    if (mounted) setState(() => _isMiniWindow = true);
  }

  Future<void> _exitMiniMode() async {
    if (kIsWeb) return;

    await windowManager.setAlwaysOnTop(false);

    if (_restoreSize != null) {
      await windowManager.setSize(_restoreSize!);
    }
    if (_restorePos != null) {
      await windowManager.setPosition(_restorePos!);
    }

    if (mounted) setState(() => _isMiniWindow = false);
  }

  @override
  Widget build(BuildContext context) {
    // Safety check: if somehow we are here but disconnected (e.g. lost connection), redirect
    return Selector<CallProvider, bool>(
      selector: (_, p) => p.isConnected,
      builder: (context, isConnected, child) {
        if (!isConnected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ConnectScreen()),
              );
            }
          });
        }

        // Fullscreen or MiniWindow Mode
        if (_isVideoFullScreen || _isMiniWindow) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Consumer<CallProvider>(
              builder: (context, provider, _) {
                MediaStream? screenStream;
                bool isLocalScreen = false;

                if (provider.remoteScreenStreams.isNotEmpty) {
                  screenStream = provider.remoteScreenStreams.values.first;
                } else if (provider.localScreenStream != null) {
                  screenStream = provider.localScreenStream;
                  isLocalScreen = true;
                }

                if (screenStream == null) {
                  // If stream ended while in fullscreen/mini mode, exit
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_isVideoFullScreen) _exitFullScreen();
                    if (_isMiniWindow) _exitMiniMode();
                  });
                  return const Center(child: CircularProgressIndicator());
                }

                return ScreenShareView(
                  stream: screenStream,
                  isLocal: isLocalScreen,
                  isFullScreen: _isVideoFullScreen,
                  onHide: () {
                    if (_isVideoFullScreen) _exitFullScreen();
                    if (_isMiniWindow) _exitMiniMode();
                    setState(() {
                      _isScreenShareHidden = true;
                    });
                  },
                  onFullScreen: (isFs) {
                    if (!isFs) _exitFullScreen();
                  },
                  onPiP: () {
                    if (_isMiniWindow) {
                      _exitMiniMode();
                    } else {
                      if (_isVideoFullScreen) _exitFullScreen();
                      _enterMiniMode();
                    }
                  },
                );
              },
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: Column(
            children: [
              if (!kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.linux ||
                      defaultTargetPlatform == TargetPlatform.macOS))
                const CustomTitleBar(),
              Expanded(
                child: Row(
                  children: [
                    // Left Sidebar (Rooms)
                    // Responsive sidebar: show on desktop, hide on mobile with toggle
                    Consumer<CallProvider>(
                      builder: (context, provider, child) {
                        final screenWidth = MediaQuery.of(context).size.width;
                        final isMobile = screenWidth < 768;

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: isMobile && _isSidebarCollapsed ? 0 : 250,
                          child: isMobile && _isSidebarCollapsed
                              ? null
                              : const LeftSidebar(),
                        );
                      },
                    ),

                    // Vertical Divider (only show if sidebar is visible)
                    Consumer<CallProvider>(
                      builder: (context, provider, child) {
                        final screenWidth = MediaQuery.of(context).size.width;
                        final isMobile = screenWidth < 768;
                        return isMobile && _isSidebarCollapsed
                            ? const SizedBox()
                            : const VerticalDivider(
                                width: 1,
                                color: AppColors.border,
                              );
                      },
                    ),

                    // Right Content (Active Room / Chat)
                    Expanded(
                      child: Column(
                        children: [
                          // Top Bar (Room Title & Controls)
                          TopBar(
                            isMembersVisible: _showMembers,
                            onToggleMembers: () {
                              setState(() {
                                _showMembers = !_showMembers;
                              });
                            },
                            onToggleSidebar: () {
                              setState(() {
                                _isSidebarCollapsed = !_isSidebarCollapsed;
                              });
                            },
                          ),

                          // Main Content Area
                          Expanded(
                            child: Consumer<CallProvider>(
                              builder: (context, provider, _) {
                                MediaStream? screenStream;
                                bool isLocalScreen = false;

                                if (provider.viewingScreenShareUid != null &&
                                    provider.remoteScreenStreams.containsKey(
                                      provider.viewingScreenShareUid,
                                    )) {
                                  screenStream =
                                      provider.remoteScreenStreams[provider
                                          .viewingScreenShareUid];
                                  isLocalScreen = false;
                                } else if (provider.localScreenStream != null) {
                                  screenStream = provider.localScreenStream;
                                  isLocalScreen = true;
                                } else if (provider
                                    .remoteScreenStreams
                                    .isNotEmpty) {
                                  screenStream =
                                      provider.remoteScreenStreams.values.first;
                                  isLocalScreen = false;
                                }

                                final bool hasScreenShare =
                                    screenStream != null;
                                final bool showScreenShare =
                                    hasScreenShare && !_isScreenShareHidden;

                                // Responsive layout based on screen width
                                final screenWidth = MediaQuery.of(
                                  context,
                                ).size.width;
                                final isMobile = screenWidth < 768;

                                return Column(
                                  children: [
                                    // Resume Banner
                                    if (hasScreenShare && _isScreenShareHidden)
                                      Container(
                                        width: double.infinity,
                                        color: AppColors.accent.withValues(
                                          alpha: 0.1,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: TextButton.icon(
                                          icon: const Icon(
                                            Icons.screen_share,
                                            size: 16,
                                          ),
                                          label: const Text("有人正在共享屏幕，点击观看"),
                                          onPressed: () => setState(
                                            () => _isScreenShareHidden = false,
                                          ),
                                        ),
                                      ),

                                    // Upper Section
                                    if (showScreenShare)
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final double width =
                                              constraints.maxWidth;
                                          // Calculate width of the screen share part
                                          // For mobile, always take full width
                                          final double screenShareWidth =
                                              isMobile || !_showMembers
                                              ? width
                                              : width * 0.75;

                                          double targetHeight =
                                              screenShareWidth /
                                              _screenShareAspectRatio;

                                          // Constraints - adjust for mobile
                                          final double maxHeight = isMobile
                                              ? MediaQuery.of(
                                                      context,
                                                    ).size.height *
                                                    0.5
                                              : MediaQuery.of(
                                                      context,
                                                    ).size.height *
                                                    0.7;
                                          if (targetHeight > maxHeight) {
                                            targetHeight = maxHeight;
                                          }
                                          if (targetHeight < 200) {
                                            targetHeight = 200;
                                          }

                                          return SizedBox(
                                            height: targetHeight,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 3,
                                                  child: ScreenShareView(
                                                    stream: screenStream!,
                                                    isLocal: isLocalScreen,
                                                    isFullScreen: false,
                                                    onHide: () {
                                                      setState(() {
                                                        _isScreenShareHidden =
                                                            true;
                                                      });
                                                    },
                                                    onFullScreen: (isFs) {
                                                      if (isFs) {
                                                        _enterFullScreen();
                                                      }
                                                    },
                                                    onPiP: _enterMiniMode,
                                                    onAspectRatioChanged: (ratio) {
                                                      if ((_screenShareAspectRatio -
                                                                  ratio)
                                                              .abs() >
                                                          0.01) {
                                                        WidgetsBinding.instance
                                                            .addPostFrameCallback((
                                                              _,
                                                            ) {
                                                              if (mounted) {
                                                                setState(
                                                                  () =>
                                                                      _screenShareAspectRatio =
                                                                          ratio,
                                                                );
                                                              }
                                                            });
                                                      }
                                                    },
                                                    isAudioMuted: provider
                                                        .isScreenShareAudioMuted,
                                                    onToggleAudioMute: provider
                                                        .toggleScreenShareAudioMute,
                                                  ),
                                                ),
                                                if (!isMobile &&
                                                    _showMembers) ...[
                                                  const VerticalDivider(
                                                    width: 1,
                                                    color: AppColors.border,
                                                  ),
                                                  Expanded(
                                                    flex: 1,
                                                    child: const MembersList(
                                                      isVertical: true,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      )
                                    else
                                      AnimatedCrossFade(
                                        firstChild: Container(
                                          height: isMobile
                                              ? 200 // More space for vertical list on mobile
                                              : 140, // Compact height for desktop
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          color: Colors.transparent,
                                          child: Consumer<CallProvider>(
                                            builder: (context, provider, child) {
                                              final screenWidth = MediaQuery.of(
                                                context,
                                              ).size.width;
                                              // On mobile, use vertical list for members
                                              return MembersList(
                                                isVertical: screenWidth < 768,
                                              );
                                            },
                                          ),
                                        ),
                                        secondChild: const SizedBox(
                                          width: double.infinity,
                                        ),
                                        crossFadeState: _showMembers
                                            ? CrossFadeState.showFirst
                                            : CrossFadeState.showSecond,
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                      ),

                                    if (_showMembers || showScreenShare)
                                      const Divider(
                                        height: 1,
                                        color: AppColors.border,
                                      ),

                                    // Chat Area - adjust height for mobile
                                    Expanded(
                                      flex: isMobile ? 2 : 1,
                                      child: Selector<CallProvider, int>(
                                        selector: (_, p) => p.publicChatVersion,
                                        builder:
                                            (
                                              context,
                                              publicChatVersion,
                                              child,
                                            ) => Container(
                                              padding: const EdgeInsets.all(8),
                                              color: Colors.transparent,
                                              child: const ChatPanel(),
                                            ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
