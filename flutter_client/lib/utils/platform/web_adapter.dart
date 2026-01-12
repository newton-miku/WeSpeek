import 'dart:async';
import 'dart:js_interop';
import 'dart:ui';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'platform_adapter.dart';

PlatformAdapter createAdapter() => WebAdapter();

class WebAdapter extends PlatformAdapter {
  final _fullScreenController = StreamController<bool>.broadcast();

  WebAdapter() {
    web.window.document.addEventListener('fullscreenchange', (web.Event event) {
      final isFullScreen = web.window.document.fullscreenElement != null;
      _fullScreenController.add(isFullScreen);
    }.toJS);
  }

  @override
  Stream<bool> get onFullScreenChanged => _fullScreenController.stream;

  @override
  Future<void> init(VoidCallback onShow) async {
    // Web initialization if needed
  }

  @override
  Future<void> onAppReady() async {}

  @override
  Future<void> showWindow() async {
    // Browser handles window
  }

  @override
  Future<void> focusWindow() async {
    // Browser handles focus
  }

  @override
  Future<void> registerDeepLink(String protocol) async {
    // Handled by URL
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
    // No tray on web
  }

  @override
  Future<void> exitApp() async {
    // Web usually doesn't support programmatic exit in the same way,
    // maybe redirect or just do nothing.
    // window.close() only works if script opened the window.
  }

  @override
  Future<void> setFullScreen(bool isFullScreen) async {
    final document = web.window.document;
    if (isFullScreen) {
      document.documentElement?.requestFullscreen().toDart;
    } else {
      document.exitFullscreen().toDart;
    }
  }

  @override
  bool get isPageVisible => web.window.document.visibilityState == 'visible';
}
