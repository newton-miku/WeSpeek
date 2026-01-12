import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:typed_data';
// import 'dart:math' as math;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:opus_dart/opus_dart.dart';
// import 'package:flutter_nnnoiseless/flutter_nnnoiseless.dart'; // Disable FFI on Web
import 'audio_client.dart';
import 'webrtc_manager.dart';

@JS('rnnoiseBridge')
external RNNoiseBridge get rnnoiseBridge;

extension type RNNoiseBridge._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> init(JSString wasmUrl);
  external JSFloat32Array process(JSFloat32Array input);
}

class AudioService implements AudioClient {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );
  WebSocketChannel? _channel;
  final String baseUrl;

  web.AudioContext? _audioCtx;
  web.MediaStream? _localStream;
  web.ScriptProcessorNode? _recorderNode;
  web.GainNode? _micGainNode;
  web.GainNode? _masterGainNode; // For playback volume

  // Opus
  // Note: For Web support, you must download 'opus.wasm' and place it in the 'web/' directory.
  final Map<String, SimpleOpusDecoder> _opusDecoders = {};
  SimpleOpusEncoder? _opusEncoder;
  bool _opusInitialized = false;
  String _targetCodec = 'opus';
  int _sampleRate = 48000;
  int _targetBitrate = 64000;
  int _channels = 2;
  int get _frameSize => (_sampleRate * 0.02).floor();
  final List<double> _sendBuffer = [];

  // Playback state
  final Map<String, double> _nextStartTime = {}; // uid -> time

  // Smart Denoise
  // final _noiseless = Noiseless.instance; // Disable FFI on Web
  bool _rnnoiseReady = false;
  final _audioProcessingController = StreamController<List<double>>();
  final _outboundSignalController =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription? _wsSubscription;
  int _seq = 0;
  bool _isWebRTC = false;
  WebRTCManager? _webRTCManager;
  Timer? _statsTimer;
  String? _myUid;
  bool _isMuted = false;
  bool _isSpeakerMuted = false;
  double _micGain = 1.0;
  double _speakerGain = 1.0;
  String _noiseMode = "gate"; // 'none', 'gate', 'smart'
  double _gateThreshold = 0.015;
  int _gateHold = 0;

  final _volumeController = StreamController<double>.broadcast();
  final _remoteVolumeController =
      StreamController<MapEntry<String, double>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  DateTime _lastErrorTime = DateTime.fromMillisecondsSinceEpoch(0);

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
    _logger.i("Initializing Web Audio (${_sampleRate}Hz, ${_channels}ch)...");
    try {
      final options = web.AudioContextOptions(
        sampleRate: _sampleRate.toDouble(),
      );
      _audioCtx = web.AudioContext(options);
      _masterGainNode = _audioCtx!.createGain();
      _masterGainNode!.connect(_audioCtx!.destination);

      // Init Opus
      if (_targetCodec == 'opus') {
        try {
          _opusEncoder?.destroy();
          _opusEncoder = SimpleOpusEncoder(
            sampleRate: _sampleRate,
            channels: _channels,
            application: Application.voip,
          );
          _opusInitialized = true;
        } catch (e) {
          _opusInitialized = false;
          _logger.e("Opus init failed: $e");
        }
      } else {
        _opusEncoder?.destroy();
        _opusEncoder = null;
        _opusInitialized = false;
      }
    } catch (e) {
      _logger.e("Web Audio Init Error: $e");
    }
  }

  Future<void> _ensureAudioContext() async {
    if (_audioCtx == null) {
      final options = web.AudioContextOptions(
        sampleRate: _sampleRate.toDouble(),
      );
      _audioCtx = web.AudioContext(options);
      _masterGainNode = _audioCtx!.createGain();
      _masterGainNode!.connect(_audioCtx!.destination);
    }
    if (_audioCtx!.state == 'suspended') {
      await _audioCtx!.resume().toDart;
    }
  }

  // Device Management
  final Map<String, String> _inputDeviceMap = {};
  String? _currentInputDeviceId;

  @override
  Future<List<String>> listInputDevices() async {
    try {
      final devices = await web.window.navigator.mediaDevices
          .enumerateDevices()
          .toDart;
      final deviceList = devices.toDart;

      _inputDeviceMap.clear();
      final result = <String>[];

      int genericCount = 0;
      for (var i = 0; i < deviceList.length; i++) {
        final d = deviceList[i];
        if (d.kind == 'audioinput') {
          String label = d.label;
          if (label.isEmpty) {
            genericCount++;
            label = "Microphone $genericCount";
          }

          // Ensure unique name
          if (_inputDeviceMap.containsKey(label)) {
            int suffix = 2;
            while (_inputDeviceMap.containsKey("$label ($suffix)")) {
              suffix++;
            }
            label = "$label ($suffix)";
          }

          _inputDeviceMap[label] = d.deviceId;
          result.add(label);
        }
      }

      if (result.isEmpty) {
        return ["Default"];
      }
      return result;
    } catch (e) {
      _logger.e("Error listing devices: $e");
      return ["Default"];
    }
  }

  @override
  Future<List<String>> listOutputDevices() async {
    // User requested to hide output devices on Web
    return ["Default"];
  }

  @override
  void setInputDevice(String deviceId) {
    // deviceId is the Name/Label from the list
    final actualId = _inputDeviceMap[deviceId];
    if (actualId != null) {
      _logger.i("Switching Input Device to: $deviceId ($actualId)");
      _currentInputDeviceId = actualId;

      // Restart recording if active (we are connected)
      if (_localStream != null) {
        _startRecording();
      }
    } else {
      _logger.w("Input device not found in map: $deviceId");
    }
  }

  @override
  void setOutputDevice(String deviceId) {
    // Not supported/Hidden on Web
  }

  @override
  void setMute(bool muted) {
    _isMuted = muted;
    // Do NOT disable tracks, as that cuts off the mic from the system.
    // Instead, we just zero out the data in the processing loop.
    // if (_localStream != null) {
    //   final tracks = _localStream!.getAudioTracks().toDart;
    //   for (var i = 0; i < tracks.length; i++) {
    //     (tracks[i]).enabled = !muted;
    //   }
    // }
    
    // Also mute via GainNode if available (this is safe soft-mute)
    if (_micGainNode != null) {
      _micGainNode!.gain.value = muted ? 0.0 : _micGain;
    }
  }

  @override
  void setMicGain(double value) {
    _micGain = value;
    if (_micGainNode != null) {
      _micGainNode!.gain.value = value;
    }
  }

  @override
  void setSpeakerMute(bool muted) {
    _isSpeakerMuted = muted;
    if (_masterGainNode != null) {
      _masterGainNode!.gain.value = muted ? 0.0 : _speakerGain;
    }
    if (_isWebRTC && _webRTCManager != null) {
      _webRTCManager!.muteOutput(muted);
    }
  }

  @override
  void setSpeakerGain(double value) {
    _speakerGain = value;
    if (_masterGainNode != null && !_isSpeakerMuted) {
      _masterGainNode!.gain.value = value;
    }
  }

  @override
  void setNoiseMode(String mode) {
    _noiseMode = mode;
    if (mode == 'smart') {
      _initRNNoise();
    }
    _applyConstraints();
  }

  Future<void> _initRNNoise() async {
    if (_rnnoiseReady) return;
    try {
      // Assuming assets are served from root/assets/
      final success = await rnnoiseBridge
          .init('assets/js/rnnoise/rnnoise.wasm'.toJS)
          .toDart;
      _rnnoiseReady = success.toDart;
      if (_rnnoiseReady) {
        _logger.i("RNNoise (WASM) Initialized");
      } else {
        _logger.w("RNNoise (WASM) Init returned false");
      }
    } catch (e) {
      _logger.e("RNNoise Init Error: $e");
    }
  }

  @override
  void setGateThreshold(double value) {
    _gateThreshold = value;
  }

  @override
  void setPeerVolume(String uid, double volume) {
    // Web implementation pending
    _logger.w("setPeerVolume not implemented for Web");
  }

  @override
  void setPeerMute(String uid, bool muted) {
    // Web implementation pending
    _logger.w("setPeerMute not implemented for Web");
  }

  Future<void> _applyConstraints() async {
    if (_localStream == null) return;

    // We use software processing (RNNoise) for 'smart' -> Browser NS OFF.
    // We use software gate + Browser Native NS for 'gate' -> Browser NS ON.
    // 'none' -> Browser NS OFF.
    // Fix: On Web, RNNoise (ffi) causes freeze. Map 'smart' to Browser NS.
    final bool useBrowserSuppression =
        (_noiseMode == 'gate' || _noiseMode == 'smart');

    final track = _localStream!.getAudioTracks().toDart.first;
    try {
      await track
          .applyConstraints(
            {
                  'noiseSuppression': useBrowserSuppression,
                  'echoCancellation': true,
                  'autoGainControl': false,
                }.jsify()
                as web.MediaTrackConstraints,
          )
          .toDart;
      _logger.i(
        "Applied Web Constraints: NoiseSuppression=$useBrowserSuppression (Mode: $_noiseMode)",
      );
    } catch (e) {
      _logger.w("Failed to apply constraints: $e");
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

    // For Opus, we usually snap to standard Opus rates: 8, 12, 16, 24, 48 kHz
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
        return 24000; // 32k not standard opus, snap to 24 or 48? usually 48 is safe for >24
      case 6:
        return 48000;
      case 7:
        return 48000;
      case 8:
        return 48000;
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

    // Reduce bitrate for mono
    if (_channels == 1) {
      bitrate = (bitrate * 0.6).floor();
    }
    return bitrate;
  }

  @override
  Future<void> setAudioConfig(String codec, int quality) async {
    // codec can be 'opus', 'pcmf32', 'pcm16'

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
        "Audio Config Update: Codec=$codec, SampleRate=$newSampleRate, Bitrate=$newBitrate",
      );
      _sampleRate = newSampleRate;

      if (_channel != null) {
        await _closeAudioSystem();
        await init(); // Recreate context
        if (_channel != null) {
          await _startRecording();
        }
      }
    } else {
      _logger.i("Audio Config Update: Unchanged");
    }
  }

  Future<void> _closeAudioSystem() async {
    if (_localStream != null) {
      _localStream!.getTracks().toDart.forEach((t) => (t).stop());
      _localStream = null;
    }
    _recorderNode?.disconnect();
    _recorderNode = null;
    _micGainNode?.disconnect();
    _micGainNode = null;
    await _audioCtx?.close().toDart;
    _audioCtx = null;

    _opusEncoder?.destroy();
    _opusEncoder = null;
    // Decoders
    for (var d in _opusDecoders.values) {
      d.destroy();
    }
    _opusDecoders.clear();
    _sendBuffer.clear();
  }

  @override
  void handleSignal(Map<String, dynamic> data) {
    if (_webRTCManager != null && _isWebRTC) {
      String? sender = data['sender'] ?? data['uid'];
      if (sender == null && data['target'] == 'sfu') {
        sender = 'sfu';
      }

      if (sender != null) {
        _webRTCManager!
            .handleSignal(sender, data['type'], data['payload']);
      }
    }
  }

  @override
  void updateRoomState(List<dynamic> members) {
    if (_myUid == null) return;

    // Check if we should use WebRTC
    // Criteria: <= 3 members, ALL support WebRTC
    final activeMemberUids = <String>[];

    for (final m in members) {
      final uid = (m as dynamic).uid;
      activeMemberUids.add(uid);
    }

    // Force WS mode (Disable WebRTC for Audio per user request)
    bool shouldBeWebRTC = false; // (count <= 3) && allSupportWebRTC;

    // ignore: dead_code
    if (shouldBeWebRTC) {
      _switchToWebRTC(activeMemberUids);
    } else {
      _switchToWS();
    }
  }

  Future<void> _switchToWebRTC(List<String> memberUids) async {
    if (_isWebRTC) {
      _webRTCManager?.updatePeers(memberUids);
      return;
    }

    _logger.i("Switching to WebRTC Mode");
    // Stop WS Audio
    await _closeAudioSystem();

    _isWebRTC = true;
    _webRTCManager = WebRTCManager(
      myUid: _myUid!,
      label: 'audio',
      onSignal: (data) => _outboundSignalController.add(data),
    );
    await _webRTCManager!.start(memberUids);
    _startWebRTCStatsPolling();
  }

  Future<void> _switchToWS() async {
    if (!_isWebRTC) return;

    _logger.i("Switching to WS Mode");
    _stopWebRTCStatsPolling();
    _isWebRTC = false;

    if (_webRTCManager != null) {
      await _webRTCManager!.stop();
      _webRTCManager = null;
    }

    // Restart WS Audio
    await init();
    if (_channel != null) {
      await _startRecording();
    }
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
  Future<void> connect(String roomId, String uid) async {
    _myUid = uid;
    if (_channel != null) close();

    await _ensureAudioContext();

    // Setup WebSocket
    final uri = Uri.parse('$baseUrl/ws/audio?uid=$uid&sid=$roomId');
    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _wsSubscription = _channel!.stream.listen((data) {
        if (data is ByteBuffer) {
          _handleAudioData(data.asUint8List());
        } else if (data is List<int>) {
          _handleAudioData(Uint8List.fromList(data));
        }
      });

      // Start Recording
      await _startRecording();
    } catch (e) {
      if (e is AudioPermissionException) rethrow;
      _logger.e("Web Audio Connect Error: $e");
      rethrow;
    }
  }

  Future<void> _startRecording() async {
    // Cleanup previous if exists
    if (_localStream != null) {
      _localStream!.getTracks().toDart.forEach((t) => (t).stop());
      _localStream = null;
    }
    _recorderNode?.disconnect();
    _recorderNode = null;
    _micGainNode?.disconnect();
    _micGainNode = null;

    try {
      // Start processing loop
      if (!_audioProcessingController.hasListener) {
        _audioProcessingController.stream
            .asyncMap((data) async {
              await _bufferAudio(data);
            })
            .listen(null, onError: (e) => _logger.e("Audio Proc Error: $e"));
      }

      // Auto-detect channels: Prefer Stereo (2), fallback to Mono (1)
      final constraintsMap = {
        'echoCancellation': true,
        'noiseSuppression':
            _noiseMode ==
            'gate', // Enable for gate, Disable for smart/none (Smart uses WASM)
        'autoGainControl': false,
        'channelCount': {'ideal': 2},
      };

      if (_currentInputDeviceId != null) {
        constraintsMap['deviceId'] = {'exact': _currentInputDeviceId!};
      }

      final constraints = web.MediaStreamConstraints(
        audio: constraintsMap.jsify() as JSAny,
      );

      _localStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;

      // Detect actual channels
      int actualChannels = 1;
      final source = _audioCtx!.createMediaStreamSource(_localStream!);

      if (source.channelCount >= 2) {
        actualChannels = 2;
      }

      bool needOpusInit =
          (_targetCodec == 'opus' &&
          (!_opusInitialized || _opusEncoder == null));

      if (_channels != actualChannels || needOpusInit) {
        if (_channels != actualChannels) {
          _logger.i("Auto-detected channels: $actualChannels (was $_channels)");
          _channels = actualChannels;
        }

        if (_targetCodec == 'opus') {
          try {
            _opusEncoder?.destroy();
            _opusEncoder = SimpleOpusEncoder(
              sampleRate: _sampleRate,
              channels: _channels,
              application: Application.voip,
            );
            _opusInitialized = true;
            _logger.i(
              "Opus Encoder initialized (Web): ${_sampleRate}Hz, ${_channels}ch",
            );
          } catch (e) {
            _logger.e("Opus init failed in startRecording: $e");
            _opusInitialized = false;
            // Fallback to PCM16 if Opus fails
            final msg = "Opus init failed, falling back to PCM16 codec: $e";
            // print(msg); // Ensure visibility in console
            _logger.w(msg);
            _targetCodec = 'pcm16';
            _targetBitrate = 32000; // Lower bitrate for fallback
          }
        }
      }

      _micGainNode = _audioCtx!.createGain();
      _micGainNode!.gain.value = _micGain;

      // Use ScriptProcessor
      // bufferSize: 4096 is standard.
      _recorderNode = _audioCtx!.createScriptProcessor(4096, _channels, 1);
      _recorderNode!.onaudioprocess = (web.AudioProcessingEvent e) {
        _onAudioProcess(e);
      }.toJS;

      source.connect(_micGainNode!);
      _micGainNode!.connect(_recorderNode!);
      _recorderNode!.connect(_audioCtx!.destination);
    } catch (e) {
      if (e.toString().contains("NotAllowedError") ||
          e.toString().contains("PermissionDeniedError")) {
        throw AudioPermissionException("Microphone permission denied");
      }
      if (e.toString().contains("NotFoundError")) {
        throw AudioPermissionException("No microphone found");
      }
      _logger.e("Start Recording Error: $e");
      rethrow; // Rethrow other errors too so connect() fails
    }
  }

  void _onAudioProcess(web.AudioProcessingEvent e) {
    final inputBuffer = e.inputBuffer;
    final channel0 = inputBuffer.getChannelData(0).toDart;

    // Zero out output to prevent feedback
    final outputBuffer = e.outputBuffer;
    final out0 = outputBuffer.getChannelData(0).toDart;
    for (int i = 0; i < out0.length; i++) {
      out0[i] = 0;
    }

    if (_isMuted) return;

    Float32List processedData;

    if (_channels == 2) {
      Float32List channel1;
      if (inputBuffer.numberOfChannels > 1) {
        channel1 = inputBuffer.getChannelData(1).toDart;
      } else {
        channel1 = channel0; // Duplicate mono
      }

      // Interleave
      processedData = Float32List(channel0.length * 2);
      for (int i = 0; i < channel0.length; i++) {
        processedData[i * 2] = channel0[i];
        processedData[i * 2 + 1] = channel1[i];
      }
    } else {
      // Mono
      processedData = Float32List.fromList(channel0);
    }

    _audioProcessingController.add(processedData);
  }

  Future<void> _bufferAudio(List<double> samples) async {
    // Safety: prevent buffer explosion (cap at ~2 seconds @ 48kHz)
    if (_sendBuffer.length > 96000) {
      _sendBuffer.clear();
      _logger.w("Audio buffer full/lagging, clearing to prevent freeze");
    }

    _sendBuffer.addAll(samples);
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

    // Smart Denoise (RNNoise via WASM)
    if (_noiseMode == "smart" && _rnnoiseReady && _sampleRate == 48000) {
      if (_channels == 1) {
        // Mono
        try {
          final inputJS = Float32List.fromList(frame).toJS;
          final outputJS = rnnoiseBridge.process(inputJS);
          final output = outputJS.toDart;

          for (int i = 0; i < frame.length; i++) {
            if (i < output.length) {
              frame[i] = output[i];
            }
          }
        } catch (e) {
          _logger.w("RNNoise WASM Error: $e");
        }
      } else {
        // Stereo: Mix -> Denoise -> Duplicate
        final int samplesPerChannel = frame.length ~/ _channels;
        final monoList = Float32List(samplesPerChannel);

        for (int i = 0; i < samplesPerChannel; i++) {
          double sum = 0;
          for (int ch = 0; ch < _channels; ch++) {
            sum += frame[i * _channels + ch];
          }
          monoList[i] = sum / _channels;
        }

        try {
          final outputJS = rnnoiseBridge.process(monoList.toJS);
          final output = outputJS.toDart;

          for (int i = 0; i < samplesPerChannel; i++) {
            double val = 0;
            if (i < output.length) {
              val = output[i];
            }
            for (int ch = 0; ch < _channels; ch++) {
              frame[i * _channels + ch] = val;
            }
          }
        } catch (e) {
          _logger.w("RNNoise WASM Stereo Error: $e");
        }
      }
    }

    // Calc Volume
    double peak = 0;
    for (var x in frame) {
      if (x.abs() > peak) peak = x.abs();
    }
    _volumeController.add(peak);

    // Gate
    bool pass = true;
    if (_noiseMode == "gate") {
      if (peak > _gateThreshold) {
        _gateHold = 10;
      } else {
        if (_gateHold > 0) {
          _gateHold--;
        } else {
          pass = false;
        }
      }
    }

    if (pass && _channel != null) {
      Uint8List dataBytes;
      int codecId = 0; // 0: Opus, 1: PCM16, 2: PCMF32

      if (_targetCodec == 'opus') {
        if (!_opusInitialized || _opusEncoder == null) {
          if (DateTime.now().difference(_lastErrorTime).inSeconds > 5) {
            _lastErrorTime = DateTime.now();
            _errorController.add("Opus编码器未就绪(Web)，发送失败");
          }
          return;
        }
        // Opus Encode
        final input = Float32List.fromList(frame);
        dataBytes = _opusEncoder!.encodeFloat(input: input);
        codecId = 0;
      } else if (_targetCodec == 'pcm16') {
        // PCM Int16
        final floatList = Float32List.fromList(frame);
        dataBytes = Uint8List(floatList.length * 2);
        final view = ByteData.sublistView(dataBytes);
        for (int i = 0; i < floatList.length; i++) {
          final sample = (floatList[i] * 32767).toInt().clamp(-32768, 32767);
          view.setInt16(i * 2, sample, Endian.little);
        }
        codecId = 1;
      } else {
        // PCM Fallback or pcmf32
        final floatList = Float32List.fromList(frame);
        dataBytes = Uint8List(floatList.length * 4);
        final view = floatList.buffer.asByteData();
        dataBytes = view.buffer.asUint8List();
        codecId = 2;
      }

      // Packet Format: [SEQ(2)][HEADER_LEN(1)][CODEC(1)][CH(1)][RATE(4)][DATA]
      // Header Len = 6 (Codec + Ch + Rate)
      const int headerLen = 6;
      final payload = Uint8List(2 + 1 + headerLen + dataBytes.length);
      final view = ByteData.sublistView(payload);

      view.setUint16(0, _seq, Endian.little);
      view.setUint8(2, headerLen);
      view.setUint8(3, codecId);
      view.setUint8(4, _channels);
      view.setUint32(5, _sampleRate, Endian.little);

      payload.setAll(2 + 1 + headerLen, dataBytes);

      _channel?.sink.add(payload);
      _seq = (_seq + 1) % 65536;
    }
  }

  void _handleAudioData(Uint8List data) {
    if (_isWebRTC) return; // Ignore WS audio in WebRTC mode

    // Protocol from server: [UID_LEN][UID][SEQ(2)][PAYLOAD]
    // New PAYLOAD: [HEADER_LEN(1)][CODEC(1)][CH(1)][RATE(4)][DATA]

    if (data.length < 3) return;

    final uidLen = data[0];
    if (data.length < 1 + uidLen + 2) return;

    final uidBytes = data.sublist(1, 1 + uidLen);
    final uid = String.fromCharCodes(uidBytes);

    // Skip UID_LEN(1) + UID + SEQ(2) to get to PAYLOAD
    final payloadWithHeader = data.sublist(1 + uidLen + 2);

    if (payloadWithHeader.isEmpty) return;

    // Parse Header
    int headerLen = payloadWithHeader[0];

    // Basic validation: Header len should be reasonable (e.g. 6)
    if (payloadWithHeader.length < 1 + headerLen) return;

    final view = ByteData.sublistView(payloadWithHeader);
    int codecId = view.getUint8(1);
    int channels = view.getUint8(2);
    int sampleRate = view.getUint32(3, Endian.little);

    final audioData = payloadWithHeader.sublist(1 + headerLen);

    Float32List pcmOutput;

    if (codecId == 0) {
      // Opus
      if (!_opusInitialized) return; // Can't decode if no WASM loaded
      try {
        SimpleOpusDecoder? decoder = _opusDecoders[uid];
        // Re-create decoder if params changed
        if (decoder == null ||
            decoder.sampleRate != sampleRate ||
            decoder.channels != channels) {
          decoder?.destroy();
          decoder = SimpleOpusDecoder(
            sampleRate: sampleRate,
            channels: channels,
          );
          _opusDecoders[uid] = decoder;
        }
        pcmOutput = decoder.decodeFloat(input: audioData, loss: 0);
      } catch (e) {
        return;
      }
    } else if (codecId == 1) {
      // PCM16
      final int16View = audioData.buffer.asInt16List(
        audioData.offsetInBytes,
        audioData.lengthInBytes ~/ 2,
      );
      pcmOutput = Float32List(int16View.length);
      for (int i = 0; i < int16View.length; i++) {
        pcmOutput[i] = int16View[i] / 32768.0;
      }
    } else {
      // PCMF32 (codecId == 2)
      pcmOutput = Float32List(audioData.length ~/ 4);
      final dView = ByteData.sublistView(audioData);
      for (int i = 0; i < pcmOutput.length; i++) {
        pcmOutput[i] = dView.getFloat32(i * 4, Endian.little);
      }
    }

    _playAudio(uid, pcmOutput, sampleRate, channels);
  }

  void _playAudio(
    String uid,
    Float32List pcmData,
    int sampleRate,
    int channels,
  ) {
    if (_audioCtx == null) return;

    // Calc Remote Volume
    double peak = 0;
    for (var x in pcmData) {
      if (x.abs() > peak) peak = x.abs();
    }
    _remoteVolumeController.add(MapEntry(uid, peak));

    // Playback
    // pcmData is interleaved
    final frameCount = pcmData.length ~/ channels;
    if (frameCount == 0) return;

    final buffer = _audioCtx!.createBuffer(channels, frameCount, sampleRate);

    for (int ch = 0; ch < channels; ch++) {
      final channelData = Float32List(frameCount);
      for (int i = 0; i < frameCount; i++) {
        if (i * channels + ch < pcmData.length) {
          channelData[i] = pcmData[i * channels + ch];
        }
      }
      buffer.copyToChannel(channelData.toJS, ch);
    }

    final source = _audioCtx!.createBufferSource();
    source.buffer = buffer;
    source.connect(_masterGainNode!);

    // Jitter Buffer / Scheduling
    double now = _audioCtx!.currentTime;
    double start = _nextStartTime[uid] ?? 0;

    if (start < now) {
      start = now + 0.05;
    } else if (start > now + 1.0) {
      start = now + 0.05;
    }

    source.start(start);
    _nextStartTime[uid] = start + buffer.duration;
  }

  @override
  Future<void> close() async {
    try {
      await _channel?.sink.close();
    } catch (e) {
      _logger.w("Error closing audio channel: $e");
    }
    _channel = null;
    await _wsSubscription?.cancel();

    _stopWebRTCStatsPolling();
    if (_webRTCManager != null) {
      await _webRTCManager!.stop();
      _webRTCManager = null;
    }

    // Stop recording
    _recorderNode?.disconnect();
    _micGainNode?.disconnect();

    if (_localStream != null) {
      final tracks = _localStream!.getTracks().toDart;
      for (var i = 0; i < tracks.length; i++) {
        (tracks[i]).stop();
      }
      _localStream = null;
    }

    _audioCtx?.close();
    _audioCtx = null;

    // _errorController is broadcast, so we don't strictly need to close it,
    // but we can if we want to ensure no more events.
    // _errorController.close();

    try {
      _opusEncoder?.destroy();
      _opusEncoder = null;
      for (var d in _opusDecoders.values) {
        d.destroy();
      }
      _opusDecoders.clear();
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}
