import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'platform_adapter.dart';

PlatformAdapter createAdapter() => DesktopAdapter();

class DesktopAdapter extends PlatformAdapter with WindowListener, TrayListener {
  final _fullScreenController = StreamController<bool>.broadcast();
  VoidCallback? _onShow;
  VoidCallback? _onExit;
  VoidCallback? _onToggleMic;
  VoidCallback? _onToggleSpeaker;

  @override
  Stream<bool> get onFullScreenChanged => _fullScreenController.stream;

  @override
  void onWindowEnterFullScreen() {
    _fullScreenController.add(true);
  }

  @override
  void onWindowLeaveFullScreen() {
    _fullScreenController.add(false);
  }

  @override
  Future<void> init(VoidCallback onShow) async {
    _onShow = onShow;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1080, 720),
      minimumSize: Size(800, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await windowManager.setPreventClose(true);
    await _initTray();
  }

  Future<void> _initTray() async {
    String iconPath = 'assets/app_icon.ico';
    if (Platform.isWindows) {
      File f = File(iconPath);
      if (await f.exists()) {
        iconPath = f.absolute.path;
      }
    }
    await trayManager.setIcon(iconPath);
  }

  @override
  Future<void> onAppReady() async {
    // Already handled in init for desktop usually, but can be used for other things
  }

  @override
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> focusWindow() async {
    await windowManager.focus();
  }

  @override
  Future<void> registerDeepLink(String protocol) async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        await protocolHandler.register(protocol);
      } catch (e) {
        debugPrint('Failed to register protocol: $e');
      }
    }
  }

  @override
  Future<void> updateTray({
    required bool isMicMuted,
    required bool isSpeakerMuted,
    required VoidCallback onShow,
    required VoidCallback onExit,
    required VoidCallback onToggleMic,
    required VoidCallback onToggleSpeaker,
  }) async {
    _onShow = onShow;
    _onExit = onExit;
    _onToggleMic = onToggleMic;
    _onToggleSpeaker = onToggleSpeaker;

    final bool isVisible = await windowManager.isVisible();
    Menu menu = Menu(
      items: [
        MenuItem(key: 'toggle_window', label: isVisible ? '隐藏' : '显示'),
        MenuItem.separator(),
        MenuItem(
          key: 'toggle_mic',
          label: isMicMuted ? '取消麦克风静音' : '麦克风静音',
          checked: isMicMuted,
        ),
        MenuItem(
          key: 'toggle_speaker',
          label: isSpeakerMuted ? '取消扬声器静音' : '扬声器静音',
          checked: isSpeakerMuted,
        ),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: '退出'),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    _onShow?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle_window':
        _onShow?.call();
        break;
      case 'toggle_mic':
        _onToggleMic?.call();
        break;
      case 'toggle_speaker':
        _onToggleSpeaker?.call();
        break;
      case 'exit_app':
        _onExit?.call();
        break;
    }
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  @override
  Future<void> exitApp() async {
    await windowManager.destroy();
  }

  @override
  Future<void> setFullScreen(bool isFullScreen) async {
    await windowManager.setFullScreen(isFullScreen);
  }

  @override
  bool get isPageVisible => true; // Always true for desktop for now
}
