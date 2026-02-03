import 'dart:typed_data';

/// Web stub for DeepFilterNetService
class DeepFilterNetService {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  Future<void> init({required int sampleRate, required int frameSize}) async {
    _initialized = false;
  }

  void processFloat(Float32List input, Float32List output) {
    // No-op for web
    output.setAll(0, input);
  }
}
