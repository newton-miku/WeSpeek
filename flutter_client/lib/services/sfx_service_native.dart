import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../utils/sound_generator.dart';
import 'sfx_service.dart';

SfxService createSfxService() => NativeSfxService();

class NativeSfxService implements SfxService {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );
  final AudioPlayer _player = AudioPlayer();
  Uint8List? _joinWav;
  Uint8List? _leaveWav;
  Uint8List? _warningWav;
  Uint8List? _successWav;

  @override
  Future<void> init() async {
    // Pre-generate WAV data
    _joinWav = SoundGenerator.generateJoinSoundWav();
    _leaveWav = SoundGenerator.generateLeaveSoundWav();
    _warningWav = SoundGenerator.generateWarningSoundWav();
    _successWav = SoundGenerator.generateSuccessSoundWav();

    // Set to low latency mode if possible
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> _playWav(Uint8List wavData) async {
    try {
      // Source must be set each time for BytesSource or we can keep it?
      // BytesSource might be efficient.
      await _player.play(BytesSource(wavData));
    } catch (e) {
      _logger.w('NativeSfx play error: $e');
    }
  }

  @override
  Future<void> playJoin() async {
    if (_joinWav == null) await init();
    if (_joinWav != null) {
      await _playWav(_joinWav!);
    }
  }

  @override
  Future<void> playLeave() async {
    if (_leaveWav == null) await init();
    if (_leaveWav != null) {
      await _playWav(_leaveWav!);
    }
  }

  @override
  Future<void> playWarning() async {
    if (_warningWav == null) await init();
    if (_warningWav != null) {
      await _playWav(_warningWav!);
    }
  }

  @override
  Future<void> playSuccess() async {
    if (_successWav == null) await init();
    if (_successWav != null) {
      await _playWav(_successWav!);
    }
  }

  @override
  void dispose() {
    _player.dispose();
  }
}
