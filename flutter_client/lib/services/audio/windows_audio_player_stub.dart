import 'dart:typed_data';

/// Web stub for WindowsAudioPlayer
class WindowsAudioPlayer {
  int actualSampleRate = 48000;

  Future<void> init({int sampleRate = 16000, int channels = 1}) async {
    actualSampleRate = sampleRate;
  }

  List<String> listInputDevices() => ["Default Microphone"];

  List<String> listOutputDevices() => ["Default Speaker"];

  void setInputDevice(int index) {}

  void setOutputDevice(int index) {}

  void setNoiseMode(String mode) {}

  void setVolumeCallback(Function(double) callback) {}

  Future<void> startRecording(Function(Uint8List) onData) async {}

  void stopRecording() {}

  void feedSafe(Int16List pcmData) {}

  void dispose() {}
}
