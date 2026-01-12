import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'sfx_service.dart';

SfxService createSfxService() => WebSfxService();

class WebSfxService implements SfxService {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );
  web.AudioContext? _audioCtx;

  @override
  Future<void> init() async {
    // Lazy init on first play to avoid autoplay policy issues
  }

  void _ensureCtx() {
    _audioCtx ??= web.AudioContext();
    if (_audioCtx!.state == 'suspended') {
      _audioCtx!.resume();
    }
  }

  @override
  Future<void> playJoin() async {
    try {
      _ensureCtx();
      final ctx = _audioCtx!;
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();

      osc.connect(gain);
      gain.connect(ctx.destination);

      final now = ctx.currentTime;
      // 440 -> 880 Hz
      osc.frequency.setValueAtTime(440, now);
      osc.frequency.exponentialRampToValueAtTime(880, now + 0.1);

      // Gain 0.1 -> 0.01
      gain.gain.setValueAtTime(0.1, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.3);

      osc.start(now);
      osc.stop(now + 0.3);
    } catch (e) {
      _logger.w('WebSfx playJoin error: $e');
    }
  }

  @override
  Future<void> playLeave() async {
    try {
      _ensureCtx();
      final ctx = _audioCtx!;
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();

      osc.connect(gain);
      gain.connect(ctx.destination);

      final now = ctx.currentTime;
      // 440 -> 220 Hz
      osc.frequency.setValueAtTime(440, now);
      osc.frequency.exponentialRampToValueAtTime(220, now + 0.1);

      // Gain 0.1 -> 0.01
      gain.gain.setValueAtTime(0.1, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.3);

      osc.start(now);
      osc.stop(now + 0.3);
    } catch (e) {
      _logger.w('WebSfx playLeave error: $e');
    }
  }

  @override
  Future<void> playWarning() async {
    try {
      _ensureCtx();
      final ctx = _audioCtx!;
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();

      osc.connect(gain);
      gain.connect(ctx.destination);

      final now = ctx.currentTime;
      // 200 -> 100 Hz (Error sound)
      osc.frequency.setValueAtTime(200, now);
      osc.frequency.exponentialRampToValueAtTime(100, now + 0.2);

      // Gain 0.1 -> 0.01
      gain.gain.setValueAtTime(0.1, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.4);

      osc.start(now);
      osc.stop(now + 0.4);
    } catch (e) {
      _logger.w('WebSfx playWarning error: $e');
    }
  }

  @override
  Future<void> playSuccess() async {
    try {
      _ensureCtx();
      final ctx = _audioCtx!;
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();

      osc.connect(gain);
      gain.connect(ctx.destination);

      final now = ctx.currentTime;
      // 880 -> 1760 Hz
      osc.frequency.setValueAtTime(880, now);
      osc.frequency.exponentialRampToValueAtTime(1760, now + 0.2);

      // Gain 0.1 -> 0.01
      gain.gain.setValueAtTime(0.1, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.3);

      osc.start(now);
      osc.stop(now + 0.3);
    } catch (e) {
      _logger.w('WebSfx playSuccess error: $e');
    }
  }

  @override
  void dispose() {
    _audioCtx?.close();
    _audioCtx = null;
  }
}
