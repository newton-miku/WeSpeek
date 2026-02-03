import 'dart:async';

class AudioPermissionException implements Exception {
  final String message;
  AudioPermissionException(this.message);
  @override
  String toString() => "语音权限异常: $message";
}

/// 音频客户端抽象，封装采集与播放的职责，便于替换实现
abstract class AudioClient {
  Future<void> init();
  Future<void> connect(String roomId, String uid);
  Future<List<String>> listInputDevices();
  Future<List<String>> listOutputDevices();
  void setInputDevice(String deviceId);
  void setOutputDevice(String deviceId);
  void setMute(bool muted);
  void setMicGain(double value);
  void setSpeakerMute(bool muted);
  void setSpeakerGain(double value);
  void setNoiseMode(String mode);
  void setGateThreshold(double value);
  void setPeerVolume(String uid, double volume);
  void setPeerMute(String uid, bool muted);
  Future<void> setAudioConfig(String codec, int quality);
  void updateRoomState(List<dynamic> members); // dynamic to avoid circular import if RoomMember is not available here, or import it.
  void handleSignal(Map<String, dynamic> data);
  /// Set ICE configuration from server (STUN/TURN servers)
  void setIceConfig(Map<String, dynamic> config);
  Stream<Map<String, dynamic>> get outboundSignal;
  Stream<double> get onVolume;
  Stream<MapEntry<String, double>> get onRemoteVolume;
  Stream<String> get onError;
  Future<void> close();
}
