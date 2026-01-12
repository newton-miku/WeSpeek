import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:window_manager/window_manager.dart';
import '../../utils/pip_helper.dart';

class ScreenShareView extends StatefulWidget {
  final MediaStream stream;
  final bool isLocal;
  final bool isFullScreen;
  final VoidCallback? onHide;
  final ValueChanged<bool>? onFullScreen;
  final VoidCallback? onPiP;
  final ValueChanged<double>? onAspectRatioChanged;
  final bool isAudioMuted;
  final VoidCallback? onToggleAudioMute;

  const ScreenShareView({
    super.key,
    required this.stream,
    this.isLocal = false,
    this.isFullScreen = false,
    this.onHide,
    this.onFullScreen,
    this.onPiP,
    this.onAspectRatioChanged,
    this.isAudioMuted = false,
    this.onToggleAudioMute,
  });

  @override
  State<ScreenShareView> createState() => _ScreenShareViewState();
}

class _ScreenShareViewState extends State<ScreenShareView> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream;
    
    _renderer.onResize = () {
      if (mounted) {
        setState(() {});
        if (widget.onAspectRatioChanged != null && _renderer.videoWidth > 0 && _renderer.videoHeight > 0) {
          widget.onAspectRatioChanged!(_renderer.videoWidth / _renderer.videoHeight);
        }
      }
    };

    if (mounted) {
      setState(() {});
      // Initial check if size is already available
      if (_renderer.videoWidth > 0 && _renderer.videoHeight > 0 && widget.onAspectRatioChanged != null) {
         widget.onAspectRatioChanged!(_renderer.videoWidth / _renderer.videoHeight);
      }
    }
  }

  @override
  void didUpdateWidget(covariant ScreenShareView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream.id != widget.stream.id) {
      _renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  Future<void> _toggleFullScreen() async {
    final newStatus = !widget.isFullScreen;

    if (widget.onFullScreen != null) {
      widget.onFullScreen!(newStatus);
    } else {
      // Fallback if no callback provided
      await windowManager.setFullScreen(newStatus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _showControls = true),
      onExit: (_) => setState(() => _showControls = false),
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            RTCVideoView(
              _renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              mirror: false, // Screens should not be mirrored
            ),
            // Controls Overlay
            if (!widget.isLocal)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  color: Colors.black38,
                  padding: const EdgeInsets.all(8.0),
                  alignment: Alignment.topRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Audio Mute Button
                      if (!widget.isLocal && widget.onToggleAudioMute != null)
                        IconButton(
                          icon: Icon(
                            widget.isAudioMuted ? Icons.volume_off : Icons.volume_up,
                            color: widget.isAudioMuted ? Colors.red : Colors.white,
                          ),
                          onPressed: widget.onToggleAudioMute,
                          tooltip: widget.isAudioMuted ? "开启共享声音" : "静音共享声音",
                        ),
                      // PiP / Window Button
                      IconButton(
                        icon: const Icon(Icons.picture_in_picture_alt,
                            color: Colors.white),
                        onPressed: () {
                          if (kIsWeb) {
                            requestPiP(_renderer.textureId);
                          } else {
                            widget.onPiP?.call();
                          }
                        },
                        tooltip: "小窗播放",
                      ),
                      IconButton(
                        icon: Icon(
                          widget.isFullScreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white,
                        ),
                        onPressed: _toggleFullScreen,
                        tooltip: widget.isFullScreen ? "退出全屏" : "全屏",
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: widget.onHide,
                        tooltip: "隐藏共享",
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.isLocal)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    "You are sharing",
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
