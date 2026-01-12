import 'package:flutter/material.dart';

abstract class PlatformAdapter {
  Future<void> init(VoidCallback onShow);
  Future<void> onAppReady();
  Future<void> showWindow();
  Future<void> focusWindow();
  Future<void> updateTray({
    required bool isMicMuted,
    required bool isSpeakerMuted,
    required VoidCallback onShow,
    required VoidCallback onExit,
    required VoidCallback onToggleMic,
    required VoidCallback onToggleSpeaker,
  });
  Future<void> registerDeepLink(String protocol);
  Future<void> exitApp();
  Future<void> setFullScreen(bool isFullScreen);
  Stream<bool> get onFullScreenChanged;
  bool get isPageVisible;
}
