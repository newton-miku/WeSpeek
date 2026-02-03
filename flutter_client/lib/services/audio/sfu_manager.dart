import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import '../signaling_service.dart';

/// WebRTC Manager using SFU (Selective Forwarding Unit) mode
/// This replaces the Mesh/P2P mode with a centralized SFU architecture
class SFUManager {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );

  RTCPeerConnection? _pc;
  MediaStream? _localAudioStream;
  MediaStream? _localVideoStream; // For screen sharing
  final SignalingClient _signaling;
  final String _myUid;
  final String _roomId;

  final Function(MediaStream stream, String uid) onRemoteStream;
  final Function(String uid) onRemoteStreamRemoved;
  final Function(Map<String, dynamic> signal) onNeedSignal;
  final VoidCallback? onConnected;
  final Function(dynamic error) onError;

  bool _isActive = false;
  bool _isScreenSharing = false;

  bool get isActive => _isActive;
  bool get isScreenSharing => _isScreenSharing;
  MediaStream? get localAudioStream => _localAudioStream;
  MediaStream? get localVideoStream => _localVideoStream;

  // ICE Servers configuration
  final Map<String, dynamic> _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  SFUManager({
    required String myUid,
    required String roomId,
    required SignalingClient signaling,
    required this.onRemoteStream,
    required this.onRemoteStreamRemoved,
    required this.onNeedSignal,
    this.onConnected,
    required this.onError,
    List<Map<String, dynamic>>? iceServers,
  })  : _myUid = myUid,
        _roomId = roomId,
        _signaling = signaling {
    if (iceServers != null && iceServers.isNotEmpty) {
      _config['iceServers'] = iceServers;
    }
  }

  Future<void> start({bool captureAudio = true, bool captureVideo = false}) async {
    _logger.i("Starting SFU mode for room: $_roomId, user: $_myUid");

    if (_isActive) {
      _logger.w("SFU is already active");
      return;
    }

    _isActive = true;

    try {
      // Create peer connection
      _pc = await createPeerConnection(_config);

      // Set up callbacks
      _setupPeerConnectionCallbacks();

      // Set up signaling callbacks
      _setupSignalingCallbacks();

      // Capture local media
      if (captureAudio) {
        await _captureAudio();
      }

      if (captureVideo) {
        await _captureVideo();
      }

      // Start the SFU session by sending an offer
      await _createAndSendOffer("audio");

      onConnected?.call();
      _logger.i("SFU connected successfully");
    } catch (e) {
      _logger.e("Failed to start SFU: $e");
      _isActive = false;
      onError(e);
    }
  }

  Future<void> _captureAudio() async {
    try {
      _localAudioStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'autoGainControl': false,
          'echoCancellation': true,
          'noiseSuppression': true,
        },
        'video': false,
      });

      // Add audio track to peer connection
      if (_pc != null) {
        for (var track in _localAudioStream!.getTracks()) {
          await _pc!.addTrack(track, _localAudioStream!);
        }
      }

      _logger.i("Local audio stream captured");
    } catch (e) {
      _logger.e("Failed to capture audio: $e");
      rethrow;
    }
  }

  Future<void> _captureVideo() async {
    try {
      _localVideoStream = await navigator.mediaDevices.getUserMedia({
        'video': {
          'mandatory': {
            'minWidth': 1280,
            'minHeight': 720,
            'maxFrameRate': 15,
          },
        },
      });

      // Add video track to peer connection
      if (_pc != null) {
        for (var track in _localVideoStream!.getTracks()) {
          await _pc!.addTrack(track, _localVideoStream!);
        }
      }

      _logger.i("Local video stream captured for screen sharing");
    } catch (e) {
      _logger.e("Failed to capture video: $e");
      rethrow;
    }
  }

  void _setupPeerConnectionCallbacks() {
    _pc!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null) {
        _signaling.sendSFUSignal("candidate", candidate.toMap());
      }
    };

    _pc!.onTrack = (event) {
      final stream = event.streams[0];
      final trackKind = event.track.kind;

      _logger.i("Received remote $trackKind track from SFU");

      if (trackKind == "audio") {
        onRemoteStream(stream, "sfu");
      } else if (trackKind == "video") {
        onRemoteStream(stream, "sfu-video");
      }
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      _logger.i("SFU connection state: $state");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _logger.e("SFU connection failed");
        onError("Connection failed");
      }
    };
  }

  void _setupSignalingCallbacks() {
    _signaling.onMessage.listen((message) {
      if (message['method'] == 'sfu.signal') {
        _handleSFUSignal(message['params']);
      }
    });
  }

  void _handleSFUSignal(dynamic params) {
    final type = params['type'];
    final payload = params['payload'];

    switch (type) {
      case 'answer':
        _handleAnswer(payload);
        break;
      case 'candidate':
        _handleCandidate(payload);
        break;
      default:
        _logger.w("Unknown SFU signal type: $type");
    }
  }

  Future<void> _handleAnswer(dynamic payload) async {
    final answer = RTCSessionDescription(
      payload['sdp'],
      payload['type'],
    );

    try {
      await _pc!.setRemoteDescription(answer);
      _logger.i("SFU remote description set");
    } catch (e) {
      _logger.e("Failed to set remote description: $e");
      onError(e);
    }
  }

  Future<void> _handleCandidate(dynamic payload) async {
    final candidate = RTCIceCandidate(
      payload['candidate'],
      payload['sdpMid'],
      payload['sdpMLineIndex'],
    );

    try {
      await _pc!.addCandidate(candidate);
    } catch (e) {
      _logger.e("Failed to add ICE candidate: $e");
    }
  }

  Future<void> _createAndSendOffer(String trackType) async {
    if (_pc == null) {
      _logger.e("Peer connection is null");
      return;
    }

    try {
      // Ensure we have local description set if we added tracks
      RTCSessionDescription offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);

      // Send offer to SFU
      _signaling.sendSFUSignal("offer", offer.toMap(), track: trackType);

      _logger.i("SFU offer sent for $trackType track");
    } catch (e) {
      _logger.e("Failed to create offer: $e");
      onError(e);
    }
  }

  // Start screen sharing
  Future<void> startScreenShare() async {
    if (_isScreenSharing) {
      _logger.w("Screen sharing is already active");
      return;
    }

    try {
      _logger.i("Starting screen sharing");

      // Create a video stream for screen sharing
      _localVideoStream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'mandatory': {
            'minWidth': 1280,
            'minHeight': 720,
            'maxFrameRate': 15,
          },
        },
      });

      // Replace the video track in the peer connection
      if (_pc != null && _localVideoStream != null) {
        final videoTrack = _localVideoStream!.getVideoTracks()[0];

        // Find sender and replace track
        final senders = await _pc!.getSenders();
        RTCRtpSender? videoSender;
        for (var sender in senders) {
          if (sender.track?.kind == 'video') {
            videoSender = sender;
            break;
          }
        }

        if (videoSender != null) {
          await videoSender.replaceTrack(videoTrack);
        } else {
          await _pc!.addTrack(videoTrack, _localVideoStream!);
        }

        // Renegotiate
        RTCSessionDescription offer = await _pc!.createOffer();
        await _pc!.setLocalDescription(offer);
        _signaling.sendSFUSignal("offer", offer.toMap(), track: "video");
      }

      _isScreenSharing = true;
      _logger.i("Screen sharing started");

      // Listen for screen share stop using the track's onended callback
      _localVideoStream!.getVideoTracks()[0].onEnded = () {
        stopScreenShare();
      };
    } catch (e) {
      _logger.e("Failed to start screen sharing: $e");
      onError(e);
    }
  }

  // Stop screen sharing
  Future<void> stopScreenShare() async {
    if (!_isScreenSharing) {
      return;
    }

    _logger.i("Stopping screen sharing");

    // Stop the video stream
    if (_localVideoStream != null) {
      _localVideoStream!.getTracks().forEach((track) {
        track.stop();
      });
      _localVideoStream = null;
    }

    // Remove video track from peer connection
    if (_pc != null) {
      final senders = await _pc!.getSenders();
      for (var sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(null);
        }
      }

      // Renegotiate
      if (_localAudioStream != null) {
        RTCSessionDescription offer = await _pc!.createOffer();
        await _pc!.setLocalDescription(offer);
        _signaling.sendSFUSignal("offer", offer.toMap(), track: "audio");
      }
    }

    _isScreenSharing = false;
    _logger.i("Screen sharing stopped");
  }

  // Mute/unmute local audio
  Future<void> setMuted(bool muted) async {
    if (_localAudioStream != null) {
      _localAudioStream!.getAudioTracks().forEach((track) {
        track.enabled = !muted;
      });
      _logger.i("Audio ${muted ? 'muted' : 'unmuted'}");
    }
  }

  // Stop and cleanup
  Future<void> stop() async {
    _logger.i("Stopping SFU");

    _isActive = false;
    _isScreenSharing = false;

    // Stop local streams
    if (_localAudioStream != null) {
      _localAudioStream!.getTracks().forEach((track) {
        track.stop();
      });
      _localAudioStream = null;
    }

    if (_localVideoStream != null) {
      _localVideoStream!.getTracks().forEach((track) {
        track.stop();
      });
      _localVideoStream = null;
    }

    // Close peer connection
    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }

    _logger.i("SFU stopped");
  }
}
