import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

// FFI definitions for winmm.dll

typedef NativeWaveOutOpen =
    Int32 Function(
      Pointer<IntPtr> phwo,
      Uint32 uDeviceID,
      Pointer<WAVEFORMATEX> pwfx,
      IntPtr dwCallback,
      IntPtr dwInstance,
      Uint32 fdwOpen,
    );
typedef DartWaveOutOpen =
    int Function(
      Pointer<IntPtr> phwo,
      int uDeviceID,
      Pointer<WAVEFORMATEX> pwfx,
      int dwCallback,
      int dwInstance,
      int fdwOpen,
    );

typedef NativeWaveOutPrepareHeader =
    Int32 Function(IntPtr hwo, Pointer<WAVEHDR> pwh, Uint32 cbwh);
typedef DartWaveOutPrepareHeader =
    int Function(int hwo, Pointer<WAVEHDR> pwh, int cbwh);

typedef NativeWaveOutWrite =
    Int32 Function(IntPtr hwo, Pointer<WAVEHDR> pwh, Uint32 cbwh);
typedef DartWaveOutWrite =
    int Function(int hwo, Pointer<WAVEHDR> pwh, int cbwh);

typedef NativeWaveOutUnprepareHeader =
    Int32 Function(IntPtr hwo, Pointer<WAVEHDR> pwh, Uint32 cbwh);
typedef DartWaveOutUnprepareHeader =
    int Function(int hwo, Pointer<WAVEHDR> pwh, int cbwh);

typedef NativeWaveOutClose = Int32 Function(IntPtr hwo);
typedef DartWaveOutClose = int Function(int hwo);

typedef NativeWaveOutReset = Int32 Function(IntPtr hwo);
typedef DartWaveOutReset = int Function(int hwo);

typedef NativeWaveOutGetNumDevs = Uint32 Function();
typedef DartWaveOutGetNumDevs = int Function();

typedef NativeWaveOutGetDevCapsW =
    Int32 Function(UintPtr uDeviceID, Pointer<WAVEOUTCAPSW> pwoc, Uint32 cbwoc);
typedef DartWaveOutGetDevCapsW =
    int Function(int uDeviceID, Pointer<WAVEOUTCAPSW> pwoc, int cbwoc);

// WaveIn

typedef NativeWaveInOpen =
    Int32 Function(
      Pointer<IntPtr> phwi,
      Uint32 uDeviceID,
      Pointer<WAVEFORMATEX> pwfx,
      IntPtr dwCallback,
      IntPtr dwInstance,
      Uint32 fdwOpen,
    );
typedef DartWaveInOpen =
    int Function(
      Pointer<IntPtr> phwi,
      int uDeviceID,
      Pointer<WAVEFORMATEX> pwfx,
      int dwCallback,
      int dwInstance,
      int fdwOpen,
    );

typedef NativeWaveInPrepareHeader =
    Int32 Function(IntPtr hwi, Pointer<WAVEHDR> pwh, Uint32 cbwh);
typedef DartWaveInPrepareHeader =
    int Function(int hwi, Pointer<WAVEHDR> pwh, int cbwh);

typedef NativeWaveInAddBuffer =
    Int32 Function(IntPtr hwi, Pointer<WAVEHDR> pwh, Uint32 cbwh);
typedef DartWaveInAddBuffer =
    int Function(int hwi, Pointer<WAVEHDR> pwh, int cbwh);

typedef NativeWaveInStart = Int32 Function(IntPtr hwi);
typedef DartWaveInStart = int Function(int hwi);

typedef NativeWaveInStop = Int32 Function(IntPtr hwi);
typedef DartWaveInStop = int Function(int hwi);

typedef NativeWaveInReset = Int32 Function(IntPtr hwi);
typedef DartWaveInReset = int Function(int hwi);

typedef NativeWaveInClose = Int32 Function(IntPtr hwi);
typedef DartWaveInClose = int Function(int hwi);

typedef NativeWaveInUnprepareHeader =
    Int32 Function(IntPtr hwi, Pointer<WAVEHDR> pwh, Uint32 cbwh);
typedef DartWaveInUnprepareHeader =
    int Function(int hwi, Pointer<WAVEHDR> pwh, int cbwh);

typedef NativeWaveInGetNumDevs = Uint32 Function();
typedef DartWaveInGetNumDevs = int Function();

typedef NativeWaveInGetDevCapsW =
    Int32 Function(UintPtr uDeviceID, Pointer<WAVEINCAPSW> pwic, Uint32 cbwic);
typedef DartWaveInGetDevCapsW =
    int Function(int uDeviceID, Pointer<WAVEINCAPSW> pwic, int cbwic);

final class WAVEFORMATEX extends Struct {
  @Uint16()
  external int wFormatTag;
  @Uint16()
  external int nChannels;
  @Uint32()
  external int nSamplesPerSec;
  @Uint32()
  external int nAvgBytesPerSec;
  @Uint16()
  external int nBlockAlign;
  @Uint16()
  external int wBitsPerSample;
  @Uint16()
  external int cbSize;
}

final class WAVEHDR extends Struct {
  external Pointer<Uint8> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  @IntPtr()
  external int dwUser;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwLoops;
  external Pointer<WAVEHDR> lpNext;
  @IntPtr()
  external int reserved;
}

final class WAVEOUTCAPSW extends Struct {
  @Uint16()
  external int wMid;
  @Uint16()
  external int wPid;
  @Uint32()
  external int vDriverVersion;
  @Array(32)
  external Array<Uint16> szPname;
  @Uint32()
  external int dwFormats;
  @Uint16()
  external int wChannels;
  @Uint16()
  external int wReserved1;
  @Uint32()
  external int dwSupport;
}

final class WAVEINCAPSW extends Struct {
  @Uint16()
  external int wMid;
  @Uint16()
  external int wPid;
  @Uint32()
  external int vDriverVersion;
  @Array(32)
  external Array<Uint16> szPname;
  @Uint32()
  external int dwFormats;
  @Uint16()
  external int wChannels;
  @Uint16()
  external int wReserved1;
}

const int waveFormatPcm = 1;
const int callbackNull = 0;
const int whdrDone = 1;

class WindowsAudioPlayer {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );
  DynamicLibrary? _winmm;
  int _hWaveOut = 0;
  int _hWaveIn = 0;
  bool _isInitialized = false;

  // WaveOut
  DartWaveOutOpen? _waveOutOpen;
  DartWaveOutPrepareHeader? _waveOutPrepareHeader;
  DartWaveOutWrite? _waveOutWrite;
  DartWaveOutUnprepareHeader? _waveOutUnprepareHeader;
  DartWaveOutClose? _waveOutClose;
  DartWaveOutReset? _waveOutReset;
  DartWaveOutGetNumDevs? _waveOutGetNumDevs;
  DartWaveOutGetDevCapsW? _waveOutGetDevCapsW;

  // WaveIn
  DartWaveInOpen? _waveInOpen;
  DartWaveInPrepareHeader? _waveInPrepareHeader;
  DartWaveInAddBuffer? _waveInAddBuffer;
  DartWaveInStart? _waveInStart;
  DartWaveInStop? _waveInStop;
  DartWaveInReset? _waveInReset;
  DartWaveInClose? _waveInClose;
  DartWaveInUnprepareHeader? _waveInUnprepareHeader;
  DartWaveInGetNumDevs? _waveInGetNumDevs;
  DartWaveInGetDevCapsW? _waveInGetDevCapsW;

  int _inputDeviceId = -1; // WAVE_MAPPER
  int _outputDeviceId = -1; // WAVE_MAPPER
  int _sampleRate = 16000;
  int _channels = 1;

  bool _recording = false;
  final List<Pointer<WAVEHDR>> _recordBuffers = [];
  Function(Uint8List)? _onAudioData;
  Function(double)? _onVolume;
  Timer? _recordTimer;

  String _noiseMode = "gate";
  int _gateHold = 0;
  final int _gateThreshold = 500; // ~ -36dB

  void setNoiseMode(String mode) {
    _noiseMode = mode;
  }

  void setVolumeCallback(Function(double) callback) {
    _onVolume = callback;
  }

  bool _functionsLoaded = false;

  void _loadNativeFunctions() {
    if (_functionsLoaded) return;
    if (!Platform.isWindows) return;

    try {
      _winmm ??= DynamicLibrary.open('winmm.dll');

      // Load WaveOut
      _waveOutOpen = _winmm!.lookupFunction<NativeWaveOutOpen, DartWaveOutOpen>(
        'waveOutOpen',
      );
      _waveOutPrepareHeader = _winmm!
          .lookupFunction<NativeWaveOutPrepareHeader, DartWaveOutPrepareHeader>(
            'waveOutPrepareHeader',
          );
      _waveOutWrite = _winmm!
          .lookupFunction<NativeWaveOutWrite, DartWaveOutWrite>('waveOutWrite');
      _waveOutUnprepareHeader = _winmm!
          .lookupFunction<
            NativeWaveOutUnprepareHeader,
            DartWaveOutUnprepareHeader
          >('waveOutUnprepareHeader');
      _waveOutClose = _winmm!
          .lookupFunction<NativeWaveOutClose, DartWaveOutClose>('waveOutClose');
      _waveOutReset = _winmm!
          .lookupFunction<NativeWaveOutReset, DartWaveOutReset>('waveOutReset');
      _waveOutGetNumDevs = _winmm!
          .lookupFunction<NativeWaveOutGetNumDevs, DartWaveOutGetNumDevs>(
            'waveOutGetNumDevs',
          );
      _waveOutGetDevCapsW = _winmm!
          .lookupFunction<NativeWaveOutGetDevCapsW, DartWaveOutGetDevCapsW>(
            'waveOutGetDevCapsW',
          );

      // Load WaveIn
      _waveInOpen = _winmm!.lookupFunction<NativeWaveInOpen, DartWaveInOpen>(
        'waveInOpen',
      );
      _waveInPrepareHeader = _winmm!
          .lookupFunction<NativeWaveInPrepareHeader, DartWaveInPrepareHeader>(
            'waveInPrepareHeader',
          );
      _waveInAddBuffer = _winmm!
          .lookupFunction<NativeWaveInAddBuffer, DartWaveInAddBuffer>(
            'waveInAddBuffer',
          );
      _waveInStart = _winmm!.lookupFunction<NativeWaveInStart, DartWaveInStart>(
        'waveInStart',
      );
      _waveInStop = _winmm!.lookupFunction<NativeWaveInStop, DartWaveInStop>(
        'waveInStop',
      );
      _waveInReset = _winmm!.lookupFunction<NativeWaveInReset, DartWaveInReset>(
        'waveInReset',
      );
      _waveInClose = _winmm!.lookupFunction<NativeWaveInClose, DartWaveInClose>(
        'waveInClose',
      );
      _waveInUnprepareHeader = _winmm!
          .lookupFunction<
            NativeWaveInUnprepareHeader,
            DartWaveInUnprepareHeader
          >('waveInUnprepareHeader');
      _waveInGetNumDevs = _winmm!
          .lookupFunction<NativeWaveInGetNumDevs, DartWaveInGetNumDevs>(
            'waveInGetNumDevs',
          );
      _waveInGetDevCapsW = _winmm!
          .lookupFunction<NativeWaveInGetDevCapsW, DartWaveInGetDevCapsW>(
            'waveInGetDevCapsW',
          );

      _functionsLoaded = true;
    } catch (e) {
      _logger.e('WindowsAudioPlayer load functions error: $e');
    }
  }

  Future<void> init({int sampleRate = 16000, int channels = 1}) async {
    if (!Platform.isWindows) return;
    if (_isInitialized) return;

    _sampleRate = sampleRate;
    _channels = channels;

    _loadNativeFunctions();

    try {
      await _initWaveOut(sampleRate, channels);
      _isInitialized = true;
    } catch (e) {
      // print('WindowsAudioPlayer init error: $e');
    }
  }

  Future<void> _initWaveOut(int sampleRate, int channels) async {
    if (_hWaveOut != 0) {
      _waveOutReset!(_hWaveOut);
      _waveOutClose!(_hWaveOut);
      _hWaveOut = 0;
    }

    final pWaveFmt = calloc<WAVEFORMATEX>();
    pWaveFmt.ref.wFormatTag = waveFormatPcm;
    pWaveFmt.ref.nChannels = channels;
    pWaveFmt.ref.nSamplesPerSec = sampleRate;
    pWaveFmt.ref.wBitsPerSample = 16;
    pWaveFmt.ref.nBlockAlign = (channels * 16) ~/ 8;
    pWaveFmt.ref.nAvgBytesPerSec = sampleRate * pWaveFmt.ref.nBlockAlign;
    pWaveFmt.ref.cbSize = 0;

    final phWaveOut = calloc<IntPtr>();
    // Use selected device ID
    // Casting to unsigned 32-bit to ensure -1 becomes 0xFFFFFFFF
    final uDevId = _outputDeviceId == -1 ? 0xFFFFFFFF : _outputDeviceId;

    final result = _waveOutOpen!(
      phWaveOut,
      uDevId,
      pWaveFmt,
      0,
      0,
      callbackNull,
    );

    if (result == 0) {
      _hWaveOut = phWaveOut.value;
      // print('waveOutOpen success. DeviceID: $_outputDeviceId');
    } else {
      // print('waveOutOpen failed: $result');
      throw Exception('waveOutOpen failed: $result');
    }

    calloc.free(pWaveFmt);
    calloc.free(phWaveOut);
  }

  List<String> listOutputDevices() {
    _loadNativeFunctions();
    if (_waveOutGetNumDevs == null) return [];
    final count = _waveOutGetNumDevs!();
    final List<String> devices = [];

    final caps = calloc<WAVEOUTCAPSW>();
    for (int i = 0; i < count; i++) {
      if (_waveOutGetDevCapsW!(i, caps, sizeOf<WAVEOUTCAPSW>()) == 0) {
        final charCodes = <int>[];
        for (int j = 0; j < 32; j++) {
          if (caps.ref.szPname[j] == 0) break;
          charCodes.add(caps.ref.szPname[j]);
        }
        devices.add(String.fromCharCodes(charCodes));
      }
    }
    calloc.free(caps);
    return devices;
  }

  List<String> listInputDevices() {
    _loadNativeFunctions();
    if (_waveInGetNumDevs == null) return [];
    final count = _waveInGetNumDevs!();
    final List<String> devices = [];

    final caps = calloc<WAVEINCAPSW>();
    for (int i = 0; i < count; i++) {
      if (_waveInGetDevCapsW!(i, caps, sizeOf<WAVEINCAPSW>()) == 0) {
        final charCodes = <int>[];
        for (int j = 0; j < 32; j++) {
          if (caps.ref.szPname[j] == 0) break;
          charCodes.add(caps.ref.szPname[j]);
        }
        devices.add(String.fromCharCodes(charCodes));
      }
    }
    calloc.free(caps);
    return devices;
  }

  void setOutputDevice(int index) {
    // index -1 means WAVE_MAPPER (Default)
    // index >= 0 means specific device ID
    _outputDeviceId = (index < 0) ? -1 : index;

    // Re-init output if initialized
    if (_isInitialized) {
      _initWaveOut(_sampleRate, _channels);
    }
  }

  void setInputDevice(int index) {
    final newId = (index < 0) ? -1 : index;
    if (_inputDeviceId == newId) return;

    _inputDeviceId = newId;

    if (_recording && _onAudioData != null) {
      final callback = _onAudioData!;
      stopRecording();
      startRecording(callback);
    }
  }

  // --- Recording ---

  Future<void> startRecording(Function(Uint8List) onData) async {
    if (_recording) return;
    if (_waveInOpen == null) return;

    _onAudioData = onData;
    _recording = true;

    final pWaveFmt = calloc<WAVEFORMATEX>();
    pWaveFmt.ref.wFormatTag = waveFormatPcm;
    pWaveFmt.ref.nChannels = _channels;
    pWaveFmt.ref.nSamplesPerSec = _sampleRate;
    pWaveFmt.ref.wBitsPerSample = 16;
    pWaveFmt.ref.nBlockAlign = (_channels * 16) ~/ 8;
    pWaveFmt.ref.nAvgBytesPerSec = _sampleRate * pWaveFmt.ref.nBlockAlign;
    pWaveFmt.ref.cbSize = 0;

    final phWaveIn = calloc<IntPtr>();
    final uDevId = _inputDeviceId == -1 ? 0xFFFFFFFF : _inputDeviceId;
    final result = _waveInOpen!(phWaveIn, uDevId, pWaveFmt, 0, 0, callbackNull);

    if (result != 0) {
      // print("waveInOpen failed: $result");
      calloc.free(pWaveFmt);
      calloc.free(phWaveIn);
      _recording = false;
      throw Exception('waveInOpen failed: $result');
    }
    // print("waveInOpen success. DeviceID: $_inputDeviceId, Rate: $_sampleRate, Ch: $_channels");

    _hWaveIn = phWaveIn.value;
    calloc.free(pWaveFmt);
    calloc.free(phWaveIn);

    // Prepare buffers
    // 20ms buffer size
    final bytesPerSample = 2; // 16-bit
    final bufferSize = (_sampleRate * _channels * bytesPerSample * 20) ~/ 1000;
    for (int i = 0; i < 10; i++) {
      final pBuffer = calloc<Uint8>(bufferSize);
      final pHeader = calloc<WAVEHDR>();
      pHeader.ref.lpData = pBuffer;
      pHeader.ref.dwBufferLength = bufferSize;
      pHeader.ref.dwFlags = 0;

      _waveInPrepareHeader!(_hWaveIn, pHeader, sizeOf<WAVEHDR>());
      final addResult = _waveInAddBuffer!(_hWaveIn, pHeader, sizeOf<WAVEHDR>());
      if (addResult != 0) {
        // print("Initial waveInAddBuffer failed: $addResult");
      }
      _recordBuffers.add(pHeader);
    }

    final startResult = _waveInStart!(_hWaveIn);
    if (startResult != 0) {
      // print("waveInStart failed: $startResult");
    } else {
      // print("waveInStart success");
    }

    // Poll for data frequently
    _recordTimer = Timer.periodic(const Duration(milliseconds: 5), (timer) {
      _pollRecording();
    });
  }

  void _pollRecording() {
    if (!_recording || _hWaveIn == 0) return;

    for (final pHeader in _recordBuffers) {
      if ((pHeader.ref.dwFlags & whdrDone) != 0) {
        // Data ready
        final bytesRecorded = pHeader.ref.dwBytesRecorded;
        if (bytesRecorded > 0) {
          final data = pHeader.ref.lpData.asTypedList(bytesRecorded);
          final copy = Uint8List.fromList(
            data,
          ); // Copy because we recycle buffer

          // Process noise gate / volume
          bool isSilent = false;
          if (_noiseMode == "gate") {
            final int16View = copy.buffer.asInt16List();
            int maxAmp = 0;
            for (var s in int16View) {
              if (s.abs() > maxAmp) maxAmp = s.abs();
            }

            // Calculate volume for UI (0.0 - 1.0)
            // 16-bit PCM max is 32768
            double vol = maxAmp / 32768.0;
            _onVolume?.call(vol);

            if (maxAmp > _gateThreshold) {
              _gateHold =
                  20; // Hold for 20 frames (400ms) - Increased for better stability
            } else {
              if (_gateHold > 0) {
                _gateHold--;
              } else {
                isSilent = true;
              }
            }
          } else {
            // Calculate volume even if noise gate is off
            final int16View = copy.buffer.asInt16List();
            int maxAmp = 0;
            for (var s in int16View) {
              if (s.abs() > maxAmp) maxAmp = s.abs();
            }
            double vol = maxAmp / 32768.0;
            _onVolume?.call(vol);
          }

          if (!isSilent) {
            _onAudioData?.call(copy);
          }
        }

        // Recycle
        // Note: Do NOT set dwFlags to 0, as it clears WHDR_PREPARED (value 2).
        // waveInAddBuffer requires the header to be prepared.
        // The driver will clear WHDR_DONE and set WHDR_INQUEUE when added.

        pHeader.ref.dwBytesRecorded = 0;
        final addResult = _waveInAddBuffer!(
          _hWaveIn,
          pHeader,
          sizeOf<WAVEHDR>(),
        );
        if (addResult != 0) {
          // print("waveInAddBuffer failed: $addResult");
        }
      }
    }
  }

  void stopRecording() {
    if (!_recording) return;
    _recording = false;
    _recordTimer?.cancel();

    if (_hWaveIn != 0) {
      _waveInStop!(_hWaveIn);
      _waveInReset!(_hWaveIn);

      for (final pHeader in _recordBuffers) {
        _waveInUnprepareHeader!(_hWaveIn, pHeader, sizeOf<WAVEHDR>());
        calloc.free(pHeader.ref.lpData);
        calloc.free(pHeader);
      }
      _recordBuffers.clear();

      _waveInClose!(_hWaveIn);
      _hWaveIn = 0;
    }
  }

  // --- Playback ---

  final List<Pointer<WAVEHDR>> _pendingHeaders = [];

  void cleanup() {
    if (!_isInitialized) return;
    _pendingHeaders.removeWhere((pHeader) {
      if ((pHeader.ref.dwFlags & whdrDone) != 0) {
        _waveOutUnprepareHeader!(_hWaveOut, pHeader, sizeOf<WAVEHDR>());
        calloc.free(pHeader.ref.lpData);
        calloc.free(pHeader);
        return true;
      }
      return false;
    });
  }

  void feedSafe(Int16List pcmData) {
    if (!_isInitialized || _hWaveOut == 0) return;
    cleanup();

    final byteCount = pcmData.length * 2;
    final pBuffer = calloc<Uint8>(byteCount);

    final view = pBuffer.asTypedList(byteCount);
    final srcView = pcmData.buffer.asUint8List(
      pcmData.offsetInBytes,
      byteCount,
    );
    view.setAll(0, srcView);

    final pHeader = calloc<WAVEHDR>();
    pHeader.ref.lpData = pBuffer;
    pHeader.ref.dwBufferLength = byteCount;
    pHeader.ref.dwFlags = 0;

    _waveOutPrepareHeader!(_hWaveOut, pHeader, sizeOf<WAVEHDR>());
    _waveOutWrite!(_hWaveOut, pHeader, sizeOf<WAVEHDR>());

    _pendingHeaders.add(pHeader);
  }

  void dispose() {
    stopRecording();
    if (_isInitialized) {
      if (_hWaveOut != 0) {
        _waveOutReset!(_hWaveOut);
        for (var pHeader in _pendingHeaders) {
          _waveOutUnprepareHeader!(_hWaveOut, pHeader, sizeOf<WAVEHDR>());
          calloc.free(pHeader.ref.lpData);
          calloc.free(pHeader);
        }
        _pendingHeaders.clear();
        _waveOutClose!(_hWaveOut);
        _hWaveOut = 0;
      }
      _isInitialized = false;
    }
  }
}
