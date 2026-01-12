import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:opus_dart/opus_dart.dart';
import 'deep_filter_net.dart';
import '../windows_audio_player.dart';
import 'audio_client.dart';
import 'webrtc_manager.dart';
import '../../models/room_model.dart';

/// 默认实现：使用 flutter_recorder + flutter_pcm_sound (Windows下使用 native winmm)
/// 支持 Opus 编码/解码
class AudioService implements AudioClient {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );
  WebSocketChannel? _channel;
  final String baseUrl;

  // Capture
  final Recorder _recorder = Recorder.instance;
  // String? _selectedInputDeviceId;

  // Playback
  // // bool _playbackInitialized = false;
  final _windowsPlayer = WindowsAudioPlayer();

  StreamSubscription? _wsSubscription;
  StreamSubscription? _audioDataSubscription;

  int _seq = 0;
  bool _isMuted = false;
  bool _isSpeakerMuted = false;
  double _micGain = 1.0;
  double _speakerGain = 1.0;
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
  DateTime _lastErrorTime = DateTime.fromMillisecondsSinceEpoch(0);

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
    _speakerGain = value;
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
    if (codec == 'opus') return 48000;

    final n = quality.clamp(1, 10);

    // For PCM, we respect the user's requested sample rates exactly
    if (codec != 'opus') {
      switch (n) {
        case 1:
          return 12000;
        case 2:
          return 16000;
        case 3:
          return 24000;
        case 4:
          return 24000;
        case 5:
          return 32000;
        case 6:
          return 32000;
        case 7:
          return 44100;
        case 8:
          return 44100;
        case 9:
          return 48000;
        case 10:
          return 48000;
        default:
          return 48000;
      }
    }

    // For Opus, we snap to supported native rates (8, 12, 16, 24, 48)
    // 44.1k -> 48k
    // 32k -> 24k (or 48k)
    switch (n) {
      case 1:
        return 12000;
      case 2:
        return 16000;
      case 3:
        return 24000;
      case 4:
        return 24000;
      case 5:
        return 24000; // 32k not supported, use 24k (Super Wideband)
      case 6:
        return 48000; // 32k -> 48k for higher quality
      case 7:
        return 48000; // 44.1k -> 48k
      case 8:
        return 48000; // 44.1k -> 48k
      case 9:
        return 48000;
      case 10:
        return 48000;
      default:
        return 48000;
    }
  }

  int _mapQualityToBitrate(int quality) {
    final n = quality.clamp(1, 10);
    // Base bitrates for Stereo (reduce for Mono?)
    // We assume Stereo here. If Mono, Opus Encoder might handle it or we can halve it.
    // User Recommendations:
    // 10: 512-1024 -> Cap at 256k for Opus (Transparency)
    // 9: 384-512 -> 192k
    // 8: 320-384 -> 160k
    // 7: 256-320 -> 128k
    // 6: 192-256 -> 96k
    // 5: 128-192 -> 64k
    // 4: 96-128 -> 48k
    // 3: 64-96 -> 32k
    // 2: 48-64 -> 24k
    // 1: 32-48 -> 16k

    int bitrate = 64000;
    switch (n) {
      case 1:
        bitrate = 16000;
        break;
      case 2:
        bitrate = 24000;
        break;
      case 3:
        bitrate = 32000;
        break;
      case 4:
        bitrate = 48000;
        break;
      case 5:
        bitrate = 64000;
        break;
      case 6:
        bitrate = 96000;
        break;
      case 7:
        bitrate = 128000;
        break;
      case 8:
        bitrate = 160000;
        break;
      case 9:
        bitrate = 192000;
        break;
      case 10:
        bitrate = 256000;
        break;
    }

    // If Mono, reduce bitrate (heuristic: 60-70% of stereo)
    if (_channels == 1) {
      bitrate = (bitrate * 0.6).floor();
    }
    return bitrate;
  }

  @override
  Future<void> setAudioConfig(String codec, int quality) async {
    // codec can be 'opus', 'pcmf32', 'pcm16'

    int newSampleRate = _mapQualityToSampleRate(quality, codec);
    int newBitrate;

    if (codec == 'opus') {
      // Fix bitrate for Opus to prevent recreation on quality change
      newBitrate = 64000;
    } else {
      newBitrate = _mapQualityToBitrate(quality);
    }

    bool configChanged =
        (_sampleRate != newSampleRate) ||
        (_targetCodec != codec) ||
        (_targetBitrate != newBitrate);

    _targetCodec = codec;
    _targetBitrate = newBitrate;

    if (configChanged) {
      _logger.i(
        "Audio Config Update: Codec=$codec, SampleRate=$newSampleRate, Bitrate=$newBitrate",
      );
      _sampleRate = newSampleRate;

      // If we are already running (channel open), we need to restart audio system
      if (_channel != null) {
        await _closeAudioSystem();
        await _initAudioSystem();

        // Re-start recording (if not in WebRTC mode)
        if (!_isWebRTC) {
          if (Platform.isWindows) {
            await _windowsPlayer.startRecording(
              (data) => _audioProcessingController.add(data),
            );
          } else {
            _recorder.start();
            _recorder.startStreamingData();
            _audioDataSubscription?.cancel();
            _audioDataSubscription = _recorder.uint8ListStream.listen((data) {
              _audioProcessingController.add(data.rawData);
            });
          }
        }
      }
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
    if (_channel != null) close();

    _myUid = uid;
    _currentRoomId = roomId;

    // Ensure Audio System is initialized (fixes first-time join bug on Desktop)
    await _initAudioSystem();
    
    // Reset fade volume for smooth entry
    _fadeVolume = 0.0;

    // Initialize WebRTC Manager
    _webRTCManager = WebRTCManager(
      myUid: uid,
      label: 'audio',
      onSignal: (signal) {
        _outboundSignalController.add(signal);
      },
    );

    final uri = Uri.parse('$baseUrl/ws/audio?uid=$uid&sid=$roomId');
    _logger.i("Connecting Audio WS: $uri");

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _wsSubscription = _channel!.stream.listen(
        (data) {
          if (data is List<int>) {
            // Binary
            _handleAudioData(Uint8List.fromList(data));
          }
        },
        onError: (e) {
          _logger.e("Audio WS Error: $e");
        },
      );

      // Start Recording (Default to WS initially, will update logic via updateRoomState)
      // Actually we should start in WS mode until we get member list and decide to switch.
      _isWebRTC = false;
      await _startWSCapture();
      
    } catch (e) {
      _logger.e("Audio Connect Error: $e");
    }
  }

  Future<void> _startWSCapture() async {
    if (Platform.isWindows) {
      _windowsPlayer.startRecording((data) {
        _audioProcessingController.add(data);
      });
      // _windowsPlayer.startPlayback();
    } else {
      _recorder.start();
      _recorder.startStreamingData();
      _audioDataSubscription = _recorder.uint8ListStream.listen((data) {
        _audioProcessingController.add(data.rawData);
      });
    }
  }

  Future<void> _stopWSCapture() async {
    if (Platform.isWindows) {
      _windowsPlayer.stopRecording();
    } else {
      _recorder.stop();
      _audioDataSubscription?.cancel();
    }
  }

  @override
  void updateRoomState(List<dynamic> members) {
    if (_webRTCManager == null || _myUid == null) return;

    // Cast members to RoomMember
    final roomMembers = members.cast<RoomMember>();
    
    // Logic:
    // 1. If any member (other than me) does NOT support WebRTC, force WS.
    // 2. If room count <= 3, use WebRTC (Mesh).
    // 3. Else use WS.
    
    // Find my member info? Not strictly needed if we assume I support WebRTC (since I'm running this code).

    // Determine target mode
    // Force WS mode (Disable WebRTC for Audio per user request)
    bool shouldBeWebRTC = false; // (roomMembers.length <= 3) && allSupportWebRTC;

    // ignore: dead_code
    if (shouldBeWebRTC) {
      if (!_isWebRTC) {
        _switchToWebRTC(roomMembers.map((e) => e.uid).toList());
      } else {
         // Update peers
         _webRTCManager!.updatePeers(roomMembers.map((e) => e.uid).toList());
      }
    } else {
      if (_isWebRTC) {
        _switchToWS();
      }
    }
  }

  Future<void> _switchToWebRTC(List<String> memberUids) async {
    _logger.i("Switching to WebRTC Mode");
    _isWebRTC = true;
    
    // Stop WS Capture
    await _stopWSCapture();

    // Start WebRTC
    await _webRTCManager!.start(memberUids);
    _startWebRTCStatsPolling();
  }

  Future<void> _switchToWS() async {
    _logger.i("Switching to WS Mode");
    _stopWebRTCStatsPolling();
    _isWebRTC = false;

    // Stop WebRTC
    await _webRTCManager!.stop();

    // Start WS Capture
    await _startWSCapture();
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
      if (sender == null && data['target'] == 'sfu') {
        sender = 'sfu';
      }

      if (sender != null) {
         _webRTCManager!.handleSignal(sender, data['type'], data['payload']);
      }
    }
  }

  @override
  Future<void> close() async {
    await _closeAudioSystem();
    _channel?.sink.close();
    _channel = null;
    _wsSubscription?.cancel();
    
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
    // Apply Gain
    if (_micGain != 1.0) {
      for (var i = 0; i < frame.length; i++) {
        frame[i] *= _micGain;
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
    
    bool pass = finalGain > 0.001; // Cutoff silence

    if (pass && _channel != null) {
      Uint8List payload;

      if (_targetCodec == 'opus') {
        if (_opusEncoder == null) {
          if (DateTime.now().difference(_lastErrorTime).inSeconds > 5) {
            _lastErrorTime = DateTime.now();
            _errorController.add("Opus编码器未就绪，发送失败");
          }
          return;
        }
        // Opus Encode
        final input = Float32List.fromList(frame);
        final opusData = _opusEncoder!.encodeFloat(input: input);

        // [SEQ(2)][HEADER_LEN(1)][CODEC(1)][CH(1)][RATE(4)][DATA]
        const int headerLen = 6;
        payload = Uint8List(2 + 1 + headerLen + opusData.length);
        final view = ByteData.sublistView(payload);
        view.setUint16(0, _seq, Endian.little);
        view.setUint8(2, headerLen);
        view.setUint8(3, 0); // Codec: Opus
        view.setUint8(4, _channels);
        view.setUint32(5, _sampleRate, Endian.little);
        payload.setAll(2 + 1 + headerLen, opusData);
      } else if (_targetCodec == 'pcm16') {
        // PCM Int16
        final bytes = Uint8List(frame.length * 2);
        final view = ByteData.sublistView(bytes);
        for (int i = 0; i < frame.length; i++) {
          final sample = (frame[i] * 32767).toInt().clamp(-32768, 32767);
          view.setInt16(i * 2, sample, Endian.little);
        }

        const int headerLen = 6;
        payload = Uint8List(2 + 1 + headerLen + bytes.length);
        final pv = ByteData.sublistView(payload);
        pv.setUint16(0, _seq, Endian.little);
        pv.setUint8(2, headerLen);
        pv.setUint8(3, 1); // Codec: PCM16
        pv.setUint8(4, _channels);
        pv.setUint32(5, _sampleRate, Endian.little);
        payload.setAll(2 + 1 + headerLen, bytes);
      } else {
        // PCM Float32 (fallback or explicit pcmf32)
        final bytes = Uint8List(frame.length * 4);
        final view = ByteData.sublistView(bytes);
        for (int i = 0; i < frame.length; i++) {
          view.setFloat32(i * 4, frame[i], Endian.little);
        }

        const int headerLen = 6;
        payload = Uint8List(2 + 1 + headerLen + bytes.length);
        final pv = ByteData.sublistView(payload);
        pv.setUint16(0, _seq, Endian.little);
        pv.setUint8(2, headerLen);
        pv.setUint8(3, 2); // Codec: PCMF32
        pv.setUint8(4, _channels);
        pv.setUint32(5, _sampleRate, Endian.little);
        payload.setAll(2 + 1 + headerLen, bytes);
      }

      // Send to WebSocket
      if (!_isWebRTC) {
        try {
          _channel?.sink.add(payload);
          _seq = (_seq + 1) % 65536;
        } catch (e) {
          // ignore
        }
      }
    }
  }

  void _handleAudioData(Uint8List data) {
    if (_isWebRTC) return;

    try {
      if (data.isEmpty) return;

      int uidLen = data[0];
      if (data.length < 1 + uidLen) return;

      String uid = String.fromCharCodes(data.sublist(1, 1 + uidLen));
      Uint8List audioPacket = data.sublist(1 + uidLen);

      if (audioPacket.length < 9) return;

      final view = ByteData.sublistView(audioPacket);
      // int seq = view.getUint16(0, Endian.little);
      int headerLen = view.getUint8(2);
      int codecId = view.getUint8(3); // 0=Opus, 1=PCM16, 2=PCMF32
      int channels = view.getUint8(4);
      int sampleRate = view.getUint32(5, Endian.little);

      int offset = 2 + 1 + headerLen;
      if (offset > audioPacket.length) return;

      Uint8List payload = audioPacket.sublist(offset);

      Float32List pcm;

      if (codecId == 0) {
        // Opus
        if (!_opusDecoders.containsKey(uid)) {
          try {
            _opusDecoders[uid] = SimpleOpusDecoder(
              sampleRate: sampleRate,
              channels: channels,
            );
          } catch (e) {
            _logger.e("Decoder init failed for $uid: $e");
            return;
          }
        }
        final decoder = _opusDecoders[uid]!;
        // Note: If remote params change, we might need to recreate decoder.
        // For now, assume consistent stream parameters.

        try {
          pcm = decoder.decodeFloat(input: payload, loss: 0);
        } catch (e) {
          // Decode failed
          return;
        }
      } else if (codecId == 1) {
        // PCM16
        final int16 = payload.buffer.asInt16List(
          payload.offsetInBytes,
          payload.lengthInBytes ~/ 2,
        );
        pcm = Float32List(int16.length);
        for (int i = 0; i < int16.length; i++) {
          pcm[i] = int16[i] / 32768.0;
        }
      } else {
        // PCM Float32
        final f32 = payload.buffer.asFloat32List(
          payload.offsetInBytes,
          payload.lengthInBytes ~/ 4,
        );
        pcm = f32; // View is fine if we copy or write immediately
      }

      // Calculate volume for UI
      double peak = 0;
      for (var x in pcm) {
        if (x.abs() > peak) peak = x.abs();
      }
      _remoteVolumeController.add(MapEntry(uid, peak));

      // Check Local Mute
      if (_mutedPeers.contains(uid)) {
        return;
      }

      // Check Global Speaker Mute
      if (_isSpeakerMuted) {
        return;
      }

      // Play
      // Convert Float32 to Int16 for playback
      final int16List = Int16List(pcm.length);
      
      double peerVol = _peerVolumes[uid] ?? 1.0;
      
      for (int i = 0; i < pcm.length; i++) {
        double val = pcm[i];
        
        // Master Gain
        if (_speakerGain != 1.0) {
          val *= _speakerGain;
        }
        
        // Peer Gain
        if (peerVol != 1.0) {
          val *= peerVol;
        }

        int16List[i] = (val * 32767).toInt().clamp(-32768, 32767);
      }

      if (Platform.isWindows) {
        _windowsPlayer.feedSafe(int16List);
      } else {
        FlutterPcmSound.feed(PcmArrayInt16.fromList(int16List));
      }
    } catch (e) {
      _logger.e("Handle Audio Error: $e");
    }
  }
}
