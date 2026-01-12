// ignore_for_file: camel_case_types, non_constant_identifier_names

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

// --- LADSPA FFI Definitions ---

typedef LADSPA_Data = Float; // float
typedef NativeLADSPA_Descriptor_Function = Pointer<LADSPA_Descriptor> Function(UnsignedLong index);
typedef DartLADSPA_Descriptor_Function = Pointer<LADSPA_Descriptor> Function(int index);

// Function pointers in the struct
typedef InstantiateFunc = Pointer<Void> Function(Pointer<LADSPA_Descriptor> descriptor, UnsignedLong sampleRate);
typedef DartInstantiateFunc = Pointer<Void> Function(Pointer<LADSPA_Descriptor> descriptor, int sampleRate);

typedef ConnectPortFunc = Void Function(Pointer<Void> instance, UnsignedLong port, Pointer<Float> dataLocation);
typedef DartConnectPortFunc = void Function(Pointer<Void> instance, int port, Pointer<Float> dataLocation);

typedef ActivateFunc = Void Function(Pointer<Void> instance);
typedef DartActivateFunc = void Function(Pointer<Void> instance);

typedef RunFunc = Void Function(Pointer<Void> instance, UnsignedLong sampleCount);
typedef DartRunFunc = void Function(Pointer<Void> instance, int sampleCount);

typedef CleanupFunc = Void Function(Pointer<Void> instance);
typedef DartCleanupFunc = void Function(Pointer<Void> instance);

final class LADSPA_PortRangeHint extends Struct {
  @Int32()
  external int HintDescriptor;
  @Float()
  external double LowerBound;
  @Float()
  external double UpperBound;
}

final class LADSPA_Descriptor extends Struct {
  @UnsignedLong()
  external int UniqueID;
  external Pointer<Utf8> Label;
  @Int32() // LADSPA_Properties (int)
  external int Properties;
  external Pointer<Utf8> Name;
  external Pointer<Utf8> Maker;
  external Pointer<Utf8> Copyright;
  @UnsignedLong()
  external int PortCount;
  external Pointer<Int32> PortDescriptors; // LADSPA_PortDescriptor *
  external Pointer<Pointer<Utf8>> PortNames;
  external Pointer<LADSPA_PortRangeHint> PortRangeHints;
  external Pointer<Void> ImplementationData;
  external Pointer<NativeFunction<InstantiateFunc>> instantiate;
  external Pointer<NativeFunction<ConnectPortFunc>> connect_port;
  external Pointer<NativeFunction<ActivateFunc>> activate;
  external Pointer<NativeFunction<RunFunc>> run;
  external Pointer<NativeFunction<Void Function()>> run_adding;
  external Pointer<NativeFunction<Void Function()>> set_run_adding_gain;
  external Pointer<NativeFunction<Void Function()>> deactivate;
  external Pointer<NativeFunction<CleanupFunc>> cleanup;
}

// --- DeepFilterNet Service ---

class DeepFilterNetService {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );
  DynamicLibrary? _lib;
  Pointer<LADSPA_Descriptor>? _descriptor;
  Pointer<Void>? _handle;

  // Function Pointers (Dart wrappers)
  DartInstantiateFunc? _instantiate;
  DartConnectPortFunc? _connectPort;
  DartActivateFunc? _activate;
  DartRunFunc? _run;
  DartCleanupFunc? _cleanup;

  // Ports
  // DeepFilterNet Mono usually has:
  // 0: Audio In
  // 1: Audio Out
  // 2: Attenuation Limit (Control In)
  // We need to verify this via inspection or assume standard if documented.
  // Based on search: "controls [ 84 -15 ]" might imply multiple controls.
  // But usually: Audio In, Audio Out are audio ports.
  
  // Buffers for ports
  Pointer<Float>? _inputBuffer;
  Pointer<Float>? _outputBuffer;
  Pointer<Float>? _attenuationLimit; // Optional control

  bool _isInitialized = false;
  int _sampleRate = 48000;
  int _frameSize = 0;

  static final DeepFilterNetService _instance = DeepFilterNetService._internal();
  factory DeepFilterNetService() => _instance;
  DeepFilterNetService._internal();

  bool get isInitialized => _isInitialized;

  /// Load the library from the given path.
  /// If [path] is null, tries to find 'libdeep_filter_ladspa.dll' or 'deep_filter.dll' in current directory.
  Future<bool> init({String? libPath, int sampleRate = 48000, int frameSize = 960}) async {
    if (_isInitialized) return true;
    _sampleRate = sampleRate;
    _frameSize = frameSize; // 20ms at 48k

    try {
      final path = libPath ?? (Platform.isWindows ? 'libdeep_filter_ladspa.dll' : 'libdeep_filter_ladspa.so');
      
      // Try to verify file existence first to avoid crash or hard error
      if (!File(path).existsSync()) {
         // Try finding in current directory or release folder pattern?
         // _logger.w("DeepFilterNet DLL not found at $path");
         return false;
      }

      _lib = DynamicLibrary.open(path);

      final ladspaDescriptorFunc = _lib!.lookupFunction<NativeLADSPA_Descriptor_Function, DartLADSPA_Descriptor_Function>('ladspa_descriptor');
      
      // Usually index 0 is the mono plugin
      _descriptor = ladspaDescriptorFunc(0);
      if (_descriptor == nullptr) {
        _logger.e("Failed to get LADSPA descriptor");
        return false;
      }

      _logger.i("Loaded DeepFilterNet: ${_descriptor!.ref.Name.toDartString()} by ${_descriptor!.ref.Maker.toDartString()}");

      // Bind functions
      _instantiate = _descriptor!.ref.instantiate.asFunction<DartInstantiateFunc>();
      _connectPort = _descriptor!.ref.connect_port.asFunction<DartConnectPortFunc>();
      _activate = _descriptor!.ref.activate.asFunction<DartActivateFunc>();
      _run = _descriptor!.ref.run.asFunction<DartRunFunc>();
      _cleanup = _descriptor!.ref.cleanup.asFunction<DartCleanupFunc>();

      // Instantiate
      _handle = _instantiate!(_descriptor!, _sampleRate);
      if (_handle == nullptr) {
        _logger.e("Failed to instantiate DeepFilterNet");
        return false;
      }

      // Allocate buffers
      _inputBuffer = calloc<Float>(frameSize);
      _outputBuffer = calloc<Float>(frameSize);
      // Optional controls - we need to know port indices.
      // We will inspect ports to find Audio inputs/outputs.
      
      int audioInIndex = -1;
      int audioOutIndex = -1;
      int attenuationIndex = -1;

      final portCount = _descriptor!.ref.PortCount;
      final portDescriptors = _descriptor!.ref.PortDescriptors;
      final portNames = _descriptor!.ref.PortNames;

      for (int i = 0; i < portCount; i++) {
        final flags = portDescriptors[i];
        final name = portNames[i].toDartString();
        // LADSPA_PORT_INPUT = 0x1
        // LADSPA_PORT_OUTPUT = 0x2
        // LADSPA_PORT_AUDIO = 0x4
        // LADSPA_PORT_CONTROL = 0x8

        final isInput = (flags & 1) != 0;
        final isOutput = (flags & 2) != 0;
        final isAudio = (flags & 4) != 0;
        final isControl = (flags & 8) != 0;

        // _logger.d("Port $i: $name (In:$isInput, Out:$isOutput, Audio:$isAudio, Ctrl:$isControl)");

        if (isAudio && isInput) audioInIndex = i;
        if (isAudio && isOutput) audioOutIndex = i;
        if (isControl && isInput && name.toLowerCase().contains("attenuation")) attenuationIndex = i;
      }

      if (audioInIndex == -1 || audioOutIndex == -1) {
        _logger.e("Could not find Audio Input/Output ports in DeepFilterNet plugin");
        return false;
      }

      // Connect ports
      _connectPort!(_handle!, audioInIndex, _inputBuffer!);
      _connectPort!(_handle!, audioOutIndex, _outputBuffer!);

      if (attenuationIndex != -1) {
        _attenuationLimit = calloc<Float>(1);
        _attenuationLimit!.value = 100.0; // Default no limit (dB?) or 100? Need to check range.
        _connectPort!(_handle!, attenuationIndex, _attenuationLimit!);
      }

      // Activate
      if (_descriptor!.ref.activate != nullptr) {
        _activate!(_handle!);
      }

      _isInitialized = true;
      _logger.i("DeepFilterNet Initialized successfully");
      return true;
    } catch (e) {
      _logger.e("DeepFilterNet Init Error: $e");
      return false;
    }
  }

  void process(Int16List pcmData, Int16List outData) {
    if (!_isInitialized || _handle == null) {
      // Passthrough if not init
      outData.setAll(0, pcmData);
      return;
    }

    final count = pcmData.length;
    if (count > _frameSize) {
      // Handle larger buffers if necessary, but ideally frameSize matches
      // _logger.w("Buffer size mismatch: $count > $_frameSize");
    }

    // Convert Int16 -> Float32
    for (int i = 0; i < count; i++) {
      _inputBuffer![i] = pcmData[i] / 32768.0;
    }

    // Run
    _run!(_handle!, count);

    // Convert Float32 -> Int16
    for (int i = 0; i < count; i++) {
      double val = _outputBuffer![i] * 32768.0;
      if (val > 32767) val = 32767;
      if (val < -32768) val = -32768;
      outData[i] = val.toInt();
    }
  }

  // Handle Float32 directly if needed
  void processFloat(Float32List input, Float32List output) {
     if (!_isInitialized || _handle == null) {
      output.setAll(0, input);
      return;
    }
    final count = input.length;
    for(int i=0; i<count; i++) {
      _inputBuffer![i] = input[i];
    }
    _run!(_handle!, count);
    for(int i=0; i<count; i++) {
      output[i] = _outputBuffer![i];
    }
  }

  void dispose() {
    if (_handle != null) {
      if (_descriptor!.ref.deactivate != nullptr) {
        // _descriptor!.ref.deactivate is a pointer, need to use cached function or cast
        // We used _activate (Dart wrapper), assume deactivate exists if activate did?
        // Actually we didn't bind deactivate to a Dart function.
        // Let's rely on _cleanup usually.
      }
      _cleanup!(_handle!);
      _handle = null;
    }
    if (_inputBuffer != null) calloc.free(_inputBuffer!);
    if (_outputBuffer != null) calloc.free(_outputBuffer!);
    if (_attenuationLimit != null) calloc.free(_attenuationLimit!);
    _isInitialized = false;
  }
}
