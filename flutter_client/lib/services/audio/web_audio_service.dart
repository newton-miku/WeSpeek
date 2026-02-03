import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'audio_client.dart';
import 'webrtc_manager.dart';

// RNNoise bridge for Web
@JS('rnnoiseBridge')
external RNNoiseBridge get rnnoiseBridge;

extension type RNNoiseBridge._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> init(JSString wasmUrl);
  external JSFloat32Array process(JSFloat32Array input);
}

/// WebRTC Audio Service - Pure WebRTC mode, no WS audio
class AudioService implements AudioClient {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );

  final String baseUrl;

  web.AudioContext? _audioCtx;
  web.GainNode? _masterGainNode;

  // WebRTC Manager for pure WebRTC audio
  WebRTCManager? _webRTCManager;
  Timer? _statsTimer;
  String? _myUid;
  bool _isSpeakerMuted = false;
  double _speakerGain = 1.0;

  // Peer volumes - store volume for each remote user
  final Map<String, double> _peerVolumes = {};
  // Remote audio elements - map stream id to audio element
  final Map<String, web.HTMLAudioElement> _remoteAudioElements = {};

  // ICE Configuration from server
  final Map<String, dynamic> _iceConfig = {};

  final _volumeController = StreamController<double>.broadcast();
  final _remoteVolumeController =
      StreamController<MapEntry<String, double>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _outboundSignalController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<double> get onVolume => _volumeController.stream;

  @override
  Stream<MapEntry<String, double>> get onRemoteVolume =>
      _remoteVolumeController.stream;

  @override
  Stream<String> get onError => _errorController.stream;

  @override
  Stream<Map<String, dynamic>> get outboundSignal =>
      _outboundSignalController.stream;

  AudioService(this.baseUrl);

  @override
  Future<void> init() async {
    _logger.i("Initializing Audio Service (WebRTC only mode)");
    try {
      // Create audio context for local playback
      final options = web.AudioContextOptions(sampleRate: 48000);
      _audioCtx = web.AudioContext(options);

      _masterGainNode = _audioCtx!.createGain();
      _masterGainNode!.connect(_audioCtx!.destination);
      _masterGainNode!.gain.value = _speakerGain;

      _logger.i("Audio Service initialized (WebRTC mode)");
    } catch (e) {
      _logger.e("Failed to initialize audio: $e");
    }
  }

  @override
  Future<void> connect(String roomId, String uid) async {
    _myUid = uid;
    _logger.i("Connecting to room $roomId as $uid (WebRTC mode)");

    // Initialize audio context
    await init();

    // Build ICE servers (uses current server as default TURN if not configured)
    final iceServers = _buildIceServers();
    _logger.i("Using $iceServers.length ICE servers for WebRTC");

    // Create WebRTC manager for SFU mode
    _webRTCManager = WebRTCManager(
      myUid: _myUid!,
      label: 'audio',
      iceServers: iceServers.isNotEmpty ? iceServers : null,
      onSignal: (data) => _outboundSignalController.add(data),
      onRemoteStream: (stream, remoteUid) {
        _logger.i("Received remote audio stream from $remoteUid");
        // Play the remote audio stream using Web Audio API
        _playRemoteStream(stream, remoteUid);
      },
      onRemoteStreamRemoved: (remoteUid) {
        _logger.i("Remote audio stream removed from $remoteUid");
        _removeRemoteStream(remoteUid);
      },
    );

    // Start WebRTC with audio capture
    await _webRTCManager!.start(
      [], // Will receive member UIDs from updateRoomState
      captureMedia: true,
    );

    // Start stats polling
    _startStatsPolling();

    // Notify that we're using WebRTC (for screen sharing check)
    // Use microtask to ensure listeners are set up
    Future.microtask(() {
      _outboundSignalController.add({
        'method': 'transport.change',
        'params': {'mode': 'webrtc'}
      });
    });

    _logger.i("WebRTC connected successfully");
  }

  void _playRemoteStream(MediaStream stream, String remoteUid) {
    try {
      _logger.i("Playing remote audio stream from $remoteUid: ${stream.id}, tracks: ${stream.getTracks().length}");

      // Create audio element for the remote stream
      final audioElement = web.HTMLAudioElement();

      // On web, MediaStream is actually MediaStreamWeb which has a 'jsStream' field
      // that contains the underlying JS MediaStream object.
      // We use dynamic to bypass type checking and access the field directly.
      try {
        // Try to access the jsStream property dynamically
        // MediaStreamWeb on web has a public final field 'jsStream' of type web.MediaStream
        final dynamic streamWeb = stream;
        final jsStream = streamWeb.jsStream as web.MediaStream?;
        if (jsStream != null) {
          audioElement.srcObject = jsStream;
          _logger.d("Assigned stream via jsStream property");
        } else {
          _logger.w("jsStream is null, trying direct cast");
          audioElement.srcObject = stream as web.MediaProvider?;
        }
      } catch (e) {
        _logger.w("Failed to access jsStream: $e, using direct cast");
        audioElement.srcObject = stream as web.MediaProvider?;
      }

      audioElement.autoplay = true;
      audioElement.muted = false;

      // Set volume
      if (!_isSpeakerMuted) {
        audioElement.volume = _speakerGain;
      }

      // Listen for play events and errors
      audioElement.onCanPlay.listen((_) {
        _logger.d("Audio element can play: ${stream.id}");
      });

      audioElement.onEnded.listen((_) {
        _logger.d("Audio element ended: ${stream.id}");
      });

      audioElement.onError.listen((web.Event e) {
        final error = audioElement.error;
        _logger.e("Audio element error: ${error?.code}, ${error?.message}");
      });

      // Append to document so it can play
      web.document.body!.append(audioElement);
      // Store audio element keyed by remoteUid for volume control
      _remoteAudioElements[remoteUid] = audioElement;
      // Initialize peer volume at 1.0
      _peerVolumes[remoteUid] = 1.0;
      // Apply current speaker gain if not muted
      if (!_isSpeakerMuted) {
        audioElement.volume = _speakerGain;
      }

      // Force play if autoplay was blocked
      Future.delayed(const Duration(milliseconds: 100), () {
        if (audioElement.paused) {
          _logger.w("Autoplay blocked, forcing play for uid: $remoteUid");
          try {
            audioElement.play();
            _logger.i("Forced play initiated for: $remoteUid");
          } catch (e) {
            _logger.e("Forced play failed for $remoteUid: $e");
          }
        }
      });

      _logger.i("Audio element created and appended for uid: $remoteUid");
    } catch (e, stack) {
      _logger.e("Failed to play remote stream: $e\n$stack");
      _errorController.add("Failed to play remote audio: $e");
    }
  }

  void _removeRemoteStream(String remoteUid) {
    final audioElement = _remoteAudioElements.remove(remoteUid);
    if (audioElement != null) {
      audioElement.pause();
      audioElement.remove();
      _logger.i("Removed audio element for uid: $remoteUid");
    }
    _peerVolumes.remove(remoteUid);
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (_webRTCManager == null) {
        timer.cancel();
        return;
      }
      final levels = await _webRTCManager!.getAudioLevels();

      // Update Local
      if (_myUid != null && levels.containsKey(_myUid)) {
        _volumeController.add(levels[_myUid]!);
      }

      // Update Remotes
      levels.forEach((uid, level) {
        if (uid != _myUid) {
          _remoteVolumeController.add(MapEntry(uid, level));
        }
      });
    });
  }

  @override
  Future<List<String>> listInputDevices() async {
    // Handled by WebRTCManager internally
    return [];
  }

  @override
  Future<List<String>> listOutputDevices() async {
    // Handled by WebRTCManager internally
    return [];
  }

  @override
  void setInputDevice(String deviceId) {
    _logger.i("Input device change requested: $deviceId");
  }

  @override
  void setOutputDevice(String deviceId) {
    _logger.i("Output device change requested: $deviceId");
  }

  @override
  void setMute(bool muted) {
    if (_webRTCManager != null) {
      _webRTCManager!.mute(muted);
    }
    _logger.i("Microphone ${muted ? 'muted' : 'unmuted'}");
  }

  @override
  void setMicGain(double value) {
    // Mic gain handled by WebRTC internally
  }

  @override
  void setSpeakerMute(bool muted) {
    _isSpeakerMuted = muted;
    if (_masterGainNode != null) {
      _masterGainNode!.gain.value = muted ? 0.0 : _speakerGain;
    }
    // Update all remote audio elements
    _remoteAudioElements.forEach((uid, audioElement) {
      if (muted) {
        audioElement.volume = 0.0;
      } else {
        // Restore individual peer volume
        final peerVolume = _peerVolumes[uid] ?? 1.0;
        audioElement.volume = peerVolume * _speakerGain;
      }
    });
    if (_webRTCManager != null) {
      _webRTCManager!.muteOutput(muted);
    }
    _logger.i("Speaker ${muted ? 'muted' : 'unmuted'}");
  }

  @override
  void setSpeakerGain(double value) {
    _speakerGain = value;
    if (_masterGainNode != null && !_isSpeakerMuted) {
      _masterGainNode!.gain.value = value;
    }
    // Update all remote audio elements with new gain
    if (!_isSpeakerMuted) {
      _remoteAudioElements.forEach((uid, audioElement) {
        final peerVolume = _peerVolumes[uid] ?? 1.0;
        audioElement.volume = peerVolume * _speakerGain;
      });
    }
    _logger.d("Speaker gain set to: $value");
  }

  @override
  void setNoiseMode(String mode) {
    _logger.i("Noise mode set to: $mode");
  }

  @override
  void setGateThreshold(double value) {}

  void setGateHold(int value) {}

  @override
  void setPeerVolume(String uid, double volume) {
    // Store the peer volume
    _peerVolumes[uid] = volume;

    // Update the audio element if it exists
    final audioElement = _remoteAudioElements[uid];
    if (audioElement != null) {
      if (_isSpeakerMuted) {
        audioElement.volume = 0.0;
      } else {
        // Apply volume with speaker gain
        audioElement.volume = volume * _speakerGain;
      }
      _logger.i("Set peer $uid volume to $volume (effective: ${audioElement.volume})");
    } else {
      _logger.w("No audio element found for peer $uid");
    }
  }

  @override
  void setPeerMute(String uid, bool muted) {
    final audioElement = _remoteAudioElements[uid];
    if (audioElement != null) {
      audioElement.muted = muted;
      _logger.i("Peer $uid ${muted ? 'muted' : 'unmuted'}");
    } else {
      _logger.w("No audio element found for peer $uid");
    }
  }

  @override
  Future<void> setAudioConfig(String codec, int quality) async {}

  @override
  void updateRoomState(List<dynamic> members) {
    if (_myUid == null || _webRTCManager == null) return;

    // Extract member UIDs (excluding self)
    final activeMemberUids = <String>[];
    for (final m in members) {
      final uid = (m as dynamic).uid;
      if (uid != _myUid) {
        activeMemberUids.add(uid);
      }
    }

    // Update WebRTC peers
    _webRTCManager!.updatePeers(activeMemberUids);
    _logger.d("Updated WebRTC peers: ${activeMemberUids.length} members");
  }

  @override
  void handleSignal(Map<String, dynamic> data) {
    if (_webRTCManager != null) {
      String? sender = data['sender'] ?? data['uid'];
      if (sender != null) {
        _webRTCManager!.handleSignal(sender, data['type'], data['payload']);
      }
    }
  }

  @override
  void setIceConfig(Map<String, dynamic> config) {
    _iceConfig.clear();
    _iceConfig.addAll(config);
    _logger.i("ICE config received for Web Audio Service: ${config.length} entries");

    // Update WebRTCManager with new ICE servers if already connected
    if (_webRTCManager != null) {
      final servers = _buildIceServers();
      _logger.i("Updated WebRTC with ${servers.length} ICE servers");
    }
  }

  /// Build ICE servers - uses current server domain as default TURN if not configured
  List<Map<String, dynamic>> _buildIceServers() {
    final servers = <Map<String, dynamic>>[];

    // Add STUN servers from config
    if (_iceConfig['stun'] != null) {
      final stunList = _iceConfig['stun'];
      if (stunList is List) {
        for (var server in stunList) {
          if (server is String) {
            servers.add({'urls': server});
          }
        }
      }
    }

    // Check if we have TURN servers from server config
    bool hasTurnFromServer = _iceConfig['turn'] != null;

    // Add TURN servers from server config
    if (hasTurnFromServer) {
      final turnList = _iceConfig['turn'];
      if (turnList is List) {
        for (var server in turnList) {
          if (server is String) {
            servers.add({
              'urls': server,
              'username': _iceConfig['username'],
              'credential': _iceConfig['password'],
            });
          } else if (server is Map) {
            servers.add({
              'urls': server['url'] ?? server['urls'],
              'username': server['username'] ?? _iceConfig['username'],
              'credential': server['password'] ?? server['credential'] ?? _iceConfig['password'],
            });
          }
        }
      }
    }

    // If no TURN server configured, use current server as default TURN
    if (!hasTurnFromServer) {
      final turnHost = _extractHostFromUrl(baseUrl);
      if (turnHost != null && turnHost.isNotEmpty) {
        servers.add({
          'urls': 'turn:$turnHost:3478?transport=udp',
        });
        _logger.i("Using default TURN server: turn:$turnHost:3478");
      }
    }

    return servers;
  }

  /// Extract host/domain from URL
  String? _extractHostFromUrl(String url) {
    try {
      String normalizedUrl = url;
      if (normalizedUrl.startsWith('wss://')) {
        normalizedUrl = normalizedUrl.substring(6);
      } else if (normalizedUrl.startsWith('ws://')) {
        normalizedUrl = normalizedUrl.substring(5);
      } else if (normalizedUrl.startsWith('https://')) {
        normalizedUrl = normalizedUrl.substring(8);
      } else if (normalizedUrl.startsWith('http://')) {
        normalizedUrl = normalizedUrl.substring(7);
      }

      final portIndex = normalizedUrl.indexOf(':');
      if (portIndex > 0) {
        normalizedUrl = normalizedUrl.substring(0, portIndex);
      }

      final pathIndex = normalizedUrl.indexOf('/');
      if (pathIndex > 0) {
        normalizedUrl = normalizedUrl.substring(0, pathIndex);
      }

      if (normalizedUrl.isNotEmpty) {
        return normalizedUrl;
      }
    } catch (e) {
      _logger.w("Failed to extract host from URL: $url, error: $e");
    }
    return null;
  }

  @override
  Future<void> close() async {
    _logger.i("Closing Audio Service");

    _statsTimer?.cancel();
    _webRTCManager?.stop();
    _webRTCManager = null;

    if (_audioCtx != null) {
      await _audioCtx!.close().toDart;
      _audioCtx = null;
    }

    _volumeController.close();
    _remoteVolumeController.close();
    _errorController.close();
    _outboundSignalController.close();
  }
}
