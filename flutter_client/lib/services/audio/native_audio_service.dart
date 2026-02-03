import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:opus_dart/opus_dart.dart';
import 'deep_filter_net.dart' if (dart.library.js) 'package:wespeek_client/services/audio/deep_filter_net_stub.dart';
import '../windows_audio_player.dart' if (dart.library.js) 'package:wespeek_client/services/audio/windows_audio_player_stub.dart';
import 'audio_client.dart';
import 'webrtc_manager.dart';
import '../../models/room_model.dart';

/// 默认实现：使用 flutter_recorder + flutter_pcm_sound (Windows下使用 native winmm)
/// 支持 Opus 编码/解码
class AudioService implements AudioClient {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );

  final String baseUrl;

  // Capture
  final Recorder _recorder = Recorder.instance;

  // Playback
  final _windowsPlayer = WindowsAudioPlayer();

  StreamSubscription? _audioDataSubscription;

  bool _isMuted = false;
  bool _isSpeakerMuted = false;
  double _micGain = 1.0;
  String _noiseMode = "gate";
  int _gateHold = 0;
  double _gateThreshold = 0.015; // ~ -36dB for float
  bool _fallbackWarningShown = false;

  // Soft Gate & Fade
  double _gateEnvelope = 0.0;
  double _fadeVolume = 0.0;
  static const double _attackRate = 0.5; // Fast attack
  static const double _releaseRate = 0.05; // Slow release
  static const double _fadeInRate = 0.05; // Global fade in

  // Smart Denoise
  final _audioProcessingController = StreamController<Uint8List>();

  // Opus & Buffer
  SimpleOpusEncoder? _opusEncoder;
  final Map<String, SimpleOpusDecoder> _opusDecoders = {};
  final List<double> _sendBuffer = [];

  String _targetCodec = 'opus';
  int _sampleRate = 48000;
  int _channels = 2; // Default to Stereo to match Web
  int _targetBitrate = 64000; // Default bitrate

  int get _frameSize => (_sampleRate * 0.02).floor(); // 20ms frame size

  final _volumeController = StreamController<double>.broadcast();
  final _remoteVolumeController =
      StreamController<MapEntry<String, double>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // WebRTC Support
  WebRTCManager? _webRTCManager;
  bool _isWebRTC = false;
  Timer? _statsTimer;
  final _outboundSignalController = StreamController<Map<String, dynamic>>.broadcast();
  String? _myUid;
  // ignore: unused_field
  String? _currentRoomId;

  // Local Peer Audio Control
  final Map<String, double> _peerVolumes = {};
  final Set<String> _mutedPeers = {};

  // ICE Configuration from server
  final Map<String, dynamic> _iceConfig = {};

  @override
  Stream<double> get onVolume => _volumeController.stream;

  @override
  Stream<MapEntry<String, double>> get onRemoteVolume =>
      _remoteVolumeController.stream;

  @override
  Stream<String> get onError => _errorController.stream;

  @override
  Stream<Map<String, dynamic>> get outboundSignal => _outboundSignalController.stream;

  AudioService(this.baseUrl);

  @override
  Future<void> init() async {
    await _initAudioSystem();
  }

  Future<void> _initAudioSystem() async {
    // On Windows, get actual sample rate first (with fallback)
    if (Platform.isWindows) {
      await _windowsPlayer.init(sampleRate: _sampleRate, channels: _channels);
      if (_windowsPlayer.actualSampleRate != _sampleRate) {
        _sampleRate = _windowsPlayer.actualSampleRate;
        _logger.i('Device sample rate: $_sampleRate Hz');
      }
    }

    _logger.i(
      "Initializing Audio System: ${_sampleRate}Hz (Auto-detect channels), Codec: $_targetCodec",
    );

    // Init DeepFilterNet (Desktop)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await DeepFilterNetService().init(sampleRate: _sampleRate, frameSize: _frameSize);
    }

    // Start processing loop
    if (!_audioProcessingController.hasListener) {
      _audioProcessingController.stream
          .asyncMap((data) async {
            await _processAndSendAudioInternal(data);
          })
          .listen(null, onError: (e) => _logger.e("Audio Proc Error: $e"));
    }

    // Auto-detect: Try Stereo (2) first, fallback to Mono (1)
    _channels = 2;
    bool success = await _tryInitWithChannels(_channels);

    if (!success) {
      _logger.i("Stereo init failed, falling back to Mono");
      _channels = 1;
      success = await _tryInitWithChannels(_channels);
      if (!success) {
        _logger.e("Audio Init Failed completely");
      }
    } else {
      _logger.i("Audio Initialized with ${_channels}ch");
    }
  }

  Future<bool> _tryInitWithChannels(int channels) async {
    try {
      // Init Opus
      if (_targetCodec == 'opus') {
        try {
          _opusEncoder?.destroy();
          _opusEncoder = SimpleOpusEncoder(
            sampleRate: _sampleRate,
            channels: channels,
            application: Application.voip,
          );
          // _opusEncoder!.bitrate = _targetBitrate; // Hypothetical API
        } catch (e) {
          _logger.w("Opus Encoder Init Failed (channels=$channels): $e");
          return false;
        }
      } else {
        _opusEncoder?.destroy();
        _opusEncoder = null;
      }

      // Init Playback & Recording
      if (Platform.isWindows) {
        await _windowsPlayer.init(sampleRate: _sampleRate, channels: channels);
        // Volume is calculated in _processFrame
      } else {
        await FlutterPcmSound.setup(
          sampleRate: _sampleRate,
          channelCount: channels,
        );

        await _recorder.init(
          sampleRate: _sampleRate,
          channels: channels == 1
              ? RecorderChannels.mono
              : RecorderChannels.stereo,
          format: PCMFormat.f32le,
        );
      }
      return true;
    } catch (e) {
      _logger.d("Init failed for channels=$channels: $e");
      return false;
    }
  }

  @override
  Future<List<String>> listInputDevices() async {
    if (Platform.isWindows) {
      return _windowsPlayer.listInputDevices();
    }
    try {
      final devices = _recorder.listCaptureDevices();
      return devices.map((d) => d.name).toList();
    } catch (e) {
      _logger.e("Error listing input devices: $e");
      return [];
    }
  }

  @override
  Future<List<String>> listOutputDevices() async {
    if (Platform.isWindows) {
      return _windowsPlayer.listOutputDevices();
    }
    return ["Default"];
  }

  @override
  void setInputDevice(String deviceId) {
    if (Platform.isWindows) {
      int newIndex = -1;
      if (deviceId == "系统默认") {
        newIndex = -1;
      } else {
        final devices = _windowsPlayer.listInputDevices();
        final index = devices.indexOf(deviceId);
        if (index != -1) {
          newIndex = index;
        } else {
          _logger.w("Input device not found: $deviceId");
          newIndex = -1;
        }
      }

      // If already running, restart with new device
      // We assume if _audioProcessingController has listener, we are "active"
      // But better to track a _isRecording flag or check _windowsPlayer state if exposed.
      // Since _windowsPlayer doesn't expose isRecording easily, we'll force restart if we are in a call.
      // A simple heuristic: if _isMuted is false, we are recording.
      
      _windowsPlayer.stopRecording();
      _windowsPlayer.setInputDevice(newIndex);
      
      if (!_isMuted) {
         _windowsPlayer.startRecording((data) {
           _audioProcessingController.add(data);
         });
      }
      return;
    }
    // Mobile implementation todo
  }

  @override
  void setOutputDevice(String deviceId) {
    if (Platform.isWindows) {
      // Output device switching for playback
      // Note: FlutterPcmSound doesn't support switching device easily without re-init.
      // WindowsAudioPlayer also has setOutputDevice but that's for waveOut (if used).
      
      int newIndex = -1;
      if (deviceId == "系统默认") {
        newIndex = -1;
      } else {
        final devices = _windowsPlayer.listOutputDevices();
        final index = devices.indexOf(deviceId);
        if (index != -1) {
          newIndex = index;
        } else {
           _logger.w("Output device not found: $deviceId");
           newIndex = -1;
        }
      }
      _windowsPlayer.setOutputDevice(newIndex);
      return;
    }
    // Mobile implementation todo
  }

  @override
  void setMute(bool muted) {
    _isMuted = muted;
    // Do NOT disable tracks, as that cuts off the mic from the system.
    // Instead, we just zero out the data in the processing loop.
    if (_isWebRTC && _webRTCManager != null) {
      _webRTCManager!.mute(muted);
    }
  }

  @override
  void setMicGain(double value) {
    _micGain = value;
  }

  @override
  void setSpeakerMute(bool muted) {
    _isSpeakerMuted = muted;
    // WebRTC Deafen (Mute Output)
    if (_isWebRTC && _webRTCManager != null) {
      _webRTCManager!.muteOutput(muted);
    }
    // TODO: Handle Windows player mute if needed, currently setSpeakerGain(0) is used in CallProvider logic if we kept it coupled, 
    // but now we are decoupling.
    if (Platform.isWindows && !_isWebRTC) {
       // Windows native player doesn't have a dedicated mute, so we might simulate it 
       // or rely on setSpeakerGain logic in UI? 
       // Ideally we should have a separate mute flag in _audioProcessingController or similar if we were playing back locally.
       // But _windowsPlayer seems to handle playback? No, _windowsPlayer is for recording.
       // Playback on Windows usually goes through 'audioplayers' or similar if implemented?
       // Wait, NativeAudioService seems to be recording-focused or WebRTC-focused.
       // WebSocket playback on Windows is not fully clear in this file. 
       // Ah, NativeAudioService seems to lack WebSocket playback logic for Windows?
       // Let's assume WebRTC is the main concern here.
    }
  }

  @override
  void setSpeakerGain(double value) {
    if (_isWebRTC && _webRTCManager != null) {
       _webRTCManager!.setMasterVolume(value);
       // If currently muted, ensure we stay muted (volume 0)
       if (_isSpeakerMuted) {
         _webRTCManager!.muteOutput(true);
       }
    }
  }

  @override
  void setNoiseMode(String mode) {
    _noiseMode = mode;
    _fallbackWarningShown = false;
  }

  @override
  void setGateThreshold(double value) {
    _gateThreshold = value;
  }

  @override
  void setPeerVolume(String uid, double volume) {
    _peerVolumes[uid] = volume;
    if (_isWebRTC && _webRTCManager != null) {
      _webRTCManager!.setPeerVolume(uid, volume);
    }
  }

  @override
  void setPeerMute(String uid, bool muted) {
    if (muted) {
      _mutedPeers.add(uid);
    } else {
      _mutedPeers.remove(uid);
    }
    if (_isWebRTC && _webRTCManager != null) {
      _webRTCManager!.setPeerMute(uid, muted);
    }
  }

  int _mapQualityToSampleRate(int quality, String codec) {
    // quality: 1=16k, 2=64k, 3=128k, 4=192k (matches AudioQualityLevel in Go backend)
    if (codec == 'opus') return 48000;

    // For PCM, we respect the user's requested sample rates exactly
    if (codec != 'opus') {
      switch (quality) {
        case 1: // 16k
          return 16000;
        case 2: // 64k
          return 32000;
        case 3: // 128k
          return 44100;
        case 4: // 192k
          return 48000;
        default:
          return 48000;
      }
    }

    // For Opus, we snap to supported native rates (8, 12, 16, 24, 48)
    // 16k -> 16k
    // 32k -> 24k or 48k
    // 44.1k -> 48k
    // 48k -> 48k
    switch (quality) {
      case 1: // 16k
        return 16000;
      case 2: // 64k
        return 48000;
      case 3: // 128k
        return 48000;
      case 4: // 192k
        return 48000;
      default:
        return 48000;
    }
  }

  int _mapQualityToBitrate(int quality) {
    // quality: 1=16k, 2=64k, 3=128k, 4=192k (matches AudioQualityLevel in Go backend)
    // Bitrate in bits per second

    switch (quality) {
      case 1:
        return 16000;   // 16kbps - Low bandwidth
      case 2:
        return 64000;   // 64kbps - Standard quality (default)
      case 3:
        return 128000;  // 128kbps - High quality
      case 4:
        return 192000;  // 192kbps - Highest quality
      default:
        return 64000;   // Default to standard quality
    }
  }

  @override
  Future<void> setAudioConfig(String codec, int quality) async {
    // codec can be 'opus', 'pcmf32', 'pcm16'
    // quality: 1=16k, 2=64k, 3=128k, 4=192k

    int newSampleRate = _mapQualityToSampleRate(quality, codec);
    int newBitrate = _mapQualityToBitrate(quality);

    bool configChanged =
        (_sampleRate != newSampleRate) ||
        (_targetCodec != codec) ||
        (_targetBitrate != newBitrate);

    _targetCodec = codec;
    _targetBitrate = newBitrate;

    if (configChanged) {
      _logger.i(
        "Audio Config Update: Codec=$codec, SampleRate=$newSampleRate, Bitrate=$newBitrate (quality=$quality)",
      );
      _sampleRate = newSampleRate;
    } else {
      _logger.i(
        "Audio Config Update: Unchanged (Codec=$codec, Rate=$newSampleRate)",
      );
    }
  }

  Future<void> _closeAudioSystem() async {
    if (Platform.isWindows) {
      _windowsPlayer.stopRecording();
      // Note: Windows player playback is kept open but re-inited in _initAudioSystem
    } else {
      _recorder.stop();
      _audioDataSubscription?.cancel();
    }
    _opusEncoder?.destroy();
    _opusEncoder = null;
    // Decoders also need clear because sample rate changed
    for (var d in _opusDecoders.values) {
      d.destroy();
    }
    _opusDecoders.clear();
    _sendBuffer.clear();
  }

  @override
  Future<void> connect(String roomId, String uid) async {
    _myUid = uid;
    _currentRoomId = roomId;

    // Ensure Audio System is initialized (fixes first-time join bug on Desktop)
    await _initAudioSystem();

    // Reset fade volume for smooth entry
    _fadeVolume = 0.0;

    // Build ICE servers from config (may be empty if not yet received)
    final iceServers = _buildIceServers();
    _logger.i("Connecting with ${iceServers.length} ICE servers");

    // Initialize WebRTC Manager for pure WebRTC audio
    _webRTCManager = WebRTCManager(
      myUid: uid,
      label: 'audio',
      iceServers: iceServers.isNotEmpty ? iceServers : null,
      onSignal: (signal) {
        _outboundSignalController.add(signal);
      },
    );

    // Pure WebRTC mode - directly start WebRTC
    _isWebRTC = true;

    _logger.i("Connecting to room $roomId with pure WebRTC audio");

    // Start WebRTC (will receive member UIDs from updateRoomState)
    await _webRTCManager!.start([]);
    _startWebRTCStatsPolling();
  }

  @override
  void updateRoomState(List<dynamic> members) {
    if (_webRTCManager == null || _myUid == null) return;

    // Cast members to RoomMember
    final roomMembers = members.cast<RoomMember>();

    // Pure WebRTC mode - just update peers
    _webRTCManager!.updatePeers(roomMembers.map((e) => e.uid).toList());
  }

  void _startWebRTCStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!_isWebRTC || _webRTCManager == null) {
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

  void _stopWebRTCStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  @override
  void handleSignal(Map<String, dynamic> data) {
    if (_webRTCManager != null && _isWebRTC) {
      // final target = data['target'];
          // final type = data['type'];
          // final payload = data['payload'];
          // final senderUid = data['senderUid']; // Assuming senderUid is added by SignalingService or wrapper?
      // Wait, SignalingService.onMessage gives raw JSON.
      // We need to know WHO sent it.
      // The protocol: {"method": "signal", "params": {...}} from server?
      // No, server forwards signal to target.
      // The payload received usually contains sender info?
      // Let's check server/signal.go or peer.go.
      // Usually signal message from server is: {"method": "signal", "params": {"uid": "sender_uid", "target": "me", "type": "...", "payload": ...}}
      // So data is the 'params' map.

      // Use 'sender' (from server) or 'uid' (legacy/fallback)
      String? sender = data['sender'] ?? data['uid'];
      if (sender != null && data['target'] == 'sfu') {
        sender = 'sfu';
      }

      if (sender != null) {
         _webRTCManager!.handleSignal(sender, data['type'], data['payload']);
      }
    }
  }

  /// Build ICE servers from stored config
  /// If no TURN server is configured, uses current server domain as default TURN
  List<Map<String, dynamic>> _buildIceServers() {
    final servers = <Map<String, dynamic>>[];

    // Add STUN servers
    if (_iceConfig['stun'] != null) {
      final stunList = _iceConfig['stun'];
      if (stunList is List) {
        for (var server in stunList) {
          if (server is String) {
            servers.add({'urls': server});
          } else if (server is Map) {
            servers.add({'urls': server['url'] ?? server['urls']});
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
      // Handle ws://, wss://, http://, https://
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

      // Remove port if present
      final portIndex = normalizedUrl.indexOf(':');
      if (portIndex > 0) {
        normalizedUrl = normalizedUrl.substring(0, portIndex);
      }

      // Remove path if present
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
  void setIceConfig(Map<String, dynamic> config) {
    _iceConfig.clear();
    _iceConfig.addAll(config);
    final servers = _buildIceServers();
    _logger.i("ICE config updated: ${servers.length} servers");
  }

  @override
  Future<void> close() async {
    await _closeAudioSystem();

    _stopWebRTCStatsPolling();
    await _webRTCManager?.stop();
    _webRTCManager = null;
    _isWebRTC = false;
  }

  Future<void> _processAndSendAudioInternal(Uint8List rawData) async {
    // If in WebRTC mode, ignore data from recorder (if any leaks through)
    if (_isWebRTC) return;
    
    if (_isMuted) return;

    Float32List floatList;

    if (Platform.isWindows) {
      // Windows: Int16 -> Float32
      final int16List = rawData.buffer.asInt16List(
        rawData.offsetInBytes,
        rawData.lengthInBytes ~/ 2,
      );
      floatList = Float32List(int16List.length);
      for (var i = 0; i < int16List.length; i++) {
        floatList[i] = int16List[i] / 32768.0;
      }
    } else {
      // Mobile: Float32 -> Float32
      floatList = Float32List(rawData.lengthInBytes ~/ 4);
      final byteData = ByteData.sublistView(rawData);
      for (var i = 0; i < floatList.length; i++) {
        floatList[i] = byteData.getFloat32(i * 4, Endian.little);
      }
    }

    // Apply Gain & Gate
    // Process entire chunk first for volume/gate stats
    // But we need to buffer for Opus framing.

    // Simple implementation: Add to buffer, process when popping
    _sendBuffer.addAll(floatList);

    // _frameSize is samples per channel. Total samples = frameSize * channels
    final totalSamplesPerFrame = _frameSize * _channels;

    while (_sendBuffer.length >= totalSamplesPerFrame) {
      final frame = _sendBuffer.sublist(0, totalSamplesPerFrame);
      _sendBuffer.removeRange(0, totalSamplesPerFrame);
      await _processFrame(frame);
    }
  }

  Future<void> _processFrame(List<double> frame) async {
    // Apply Gain (always apply to ensure consistent volume)
    if (_micGain != 1.0 || true) {  // Always apply for consistent behavior
      for (var i = 0; i < frame.length; i++) {
        frame[i] *= _micGain;
      }
    }

    // Clamp to prevent clipping
    for (var i = 0; i < frame.length; i++) {
      if (frame[i] > 1.0) {
        frame[i] = 1.0;
      } else if (frame[i] < -1.0) {
        frame[i] = -1.0;
      }
    }

    // Calc Volume
    double peak = 0;
    for (var x in frame) {
      if (x.abs() > peak) peak = x.abs();
    }
    _volumeController.add(peak);

    // Determine Effective Mode (Fallback logic)
    String effectiveMode = _noiseMode;
    if (effectiveMode == 'smart' && !DeepFilterNetService().isInitialized) {
      // Try to init if not initialized?
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
         // Should have been inited, but maybe failed.
      }
      
      // Fallback if still not ready
      if (!DeepFilterNetService().isInitialized) {
        effectiveMode = 'gate';
        if (!_fallbackWarningShown) {
          _errorController.add("WARNING: 智能降噪不可用(DFN未就绪)，已切换为门限模式");
          _fallbackWarningShown = true;
        }
      }
    }

    // Smart Noise Reduction (DeepFilterNet)
    if (effectiveMode == "smart") {
      try {
        if (_channels == 1) {
          final floatList = Float32List.fromList(frame);
          final outList = Float32List(floatList.length);
          DeepFilterNetService().processFloat(floatList, outList);
          for(int i=0; i<frame.length; i++) {
             frame[i] = outList[i];
          }
        } else {
          // Stereo: Mix to Mono -> Denoise -> Duplicate
          final int samplesPerChannel = frame.length ~/ _channels;
          final monoFloat = Float32List(samplesPerChannel);
          
          for (int i = 0; i < samplesPerChannel; i++) {
            double sum = 0;
            for (int ch = 0; ch < _channels; ch++) {
              sum += frame[i * _channels + ch];
            }
            monoFloat[i] = sum / _channels;
          }
          
          final outMono = Float32List(samplesPerChannel);
          DeepFilterNetService().processFloat(monoFloat, outMono);
          
          for (int i = 0; i < samplesPerChannel; i++) {
            final val = outMono[i];
            for (int ch = 0; ch < _channels; ch++) {
              frame[i * _channels + ch] = val;
            }
          }
        }
      } catch (e) {
        _logger.w("Smart Denoise Failed (DFN): $e");
        effectiveMode = 'gate'; // Fallback for this frame/session
      }
    }

    // Gate Logic (Soft Gate)
    double targetEnvelope = 0.0;
    
    if (effectiveMode == "gate") {
      if (peak > _gateThreshold) {
        _gateHold = 20; // Hold for ~400ms (20 * 20ms)
        targetEnvelope = 1.0;
      } else {
        if (_gateHold > 0) {
          _gateHold--;
          targetEnvelope = 1.0;
        } else {
          targetEnvelope = 0.0;
        }
      }
    } else {
      // Pass through if not in gate mode
      targetEnvelope = 1.0;
    }

    // Apply Soft Gate & Global Fade
    for (var i = 0; i < frame.length; i++) {
      // 1. Update Gate Envelope per sample (or per frame for efficiency)
      // Per-frame envelope update is usually sufficient and cheaper
    }
    
    // Per-frame envelope smoothing
    if (targetEnvelope > _gateEnvelope) {
       _gateEnvelope += _attackRate;
       if (_gateEnvelope > targetEnvelope) _gateEnvelope = targetEnvelope;
    } else {
       _gateEnvelope -= _releaseRate;
       if (_gateEnvelope < targetEnvelope) _gateEnvelope = targetEnvelope;
    }

    // Per-frame fade-in smoothing
    if (_fadeVolume < 1.0) {
      _fadeVolume += _fadeInRate;
      if (_fadeVolume > 1.0) _fadeVolume = 1.0;
    }

    // Apply envelopes
    final double finalGain = _gateEnvelope * _fadeVolume;
    
    // Optimization: If finalGain is 0, skip processing and set to silence?
    // But we need to keep buffer filled.
    
    if (finalGain < 1.0) {
      for (var i = 0; i < frame.length; i++) {
        frame[i] *= finalGain;
      }
    }
    
    // WebRTC mode: audio is sent via WebRTC data channels, not this path
  }

}
