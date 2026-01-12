import 'dart:math';
import 'dart:typed_data';

class SoundGenerator {
  static const int sampleRate = 44100;

  /// Generates a WAV file byte array for the "Join" sound.
  /// Web: 440Hz -> 880Hz, 0.3s, Gain 0.1 -> 0.01
  static Uint8List generateJoinSound() {
    return _generateSweep(
      startFreq: 440,
      endFreq: 880,
      duration: 0.3,
      startGain: 0.5,
      endGain: 0.05,
    );
  }

  static Int16List generateJoinSoundPCM() {
    return _generateSweepPCM(
      startFreq: 440,
      endFreq: 880,
      duration: 0.3,
      startGain: 0.5,
      endGain: 0.05,
    );
  }

  /// Generates a WAV file byte array for the "Leave" sound.
  /// Web: 440Hz -> 220Hz, 0.3s, Gain 0.1 -> 0.01
  static Uint8List generateLeaveSound() {
    return _generateSweep(
      startFreq: 440,
      endFreq: 220,
      duration: 0.3,
      startGain: 0.5,
      endGain: 0.05,
    );
  }

  static Int16List generateLeaveSoundPCM() {
    return _generateSweepPCM(
      startFreq: 440,
      endFreq: 220,
      duration: 0.3,
      startGain: 0.5,
      endGain: 0.05,
    );
  }

  static Uint8List generateJoinSoundWav() {
    return _generateSweep(
      startFreq: 440,
      endFreq: 880,
      duration: 0.3,
      startGain: 0.05,
      endGain: 0.5,
    );
  }

  static Uint8List generateLeaveSoundWav() {
    return _generateSweep(
      startFreq: 440,
      endFreq: 220,
      duration: 0.3,
      startGain: 0.5,
      endGain: 0.05,
    );
  }

  static Uint8List generateWarningSoundWav() {
    // "Error" sound: Lower pitch, descending
    return _generateSweep(
      startFreq: 200,
      endFreq: 100,
      duration: 0.4,
      startGain: 0.5,
      endGain: 0.1,
    );
  }

  static Uint8List generateSuccessSoundWav() {
    // "Success" sound: Higher pitch, ascending, crisp
    return _generateSweep(
      startFreq: 880,
      endFreq: 1760,
      duration: 0.2,
      startGain: 0.1,
      endGain: 0.3,
    );
  }

  static Uint8List _generateSweep({
    required double startFreq,
    required double endFreq,
    required double duration,
    required double startGain,
    required double endGain,
  }) {
    final pcm = _generateSweepPCM(
      startFreq: startFreq,
      endFreq: endFreq,
      duration: duration,
      startGain: startGain,
      endGain: endGain,
    );

    final numSamples = pcm.length;
    final dataSize = numSamples * 2; // 16-bit
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);

    // WAV Header
    // RIFF chunk
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57); // W
    buffer.setUint8(9, 0x41); // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E

    // fmt chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6d); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // space
    buffer.setUint32(16, 16, Endian.little); // Chunk size
    buffer.setUint16(20, 1, Endian.little); // Audio format (1 = PCM)
    buffer.setUint16(22, 1, Endian.little); // Num channels (1 = Mono)
    buffer.setUint32(24, sampleRate, Endian.little); // Sample rate
    buffer.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    buffer.setUint16(32, 2, Endian.little); // Block align
    buffer.setUint16(34, 16, Endian.little); // Bits per sample

    // data chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);

    // Copy PCM data
    for (int i = 0; i < numSamples; i++) {
      buffer.setInt16(44 + i * 2, pcm[i], Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  static Int16List _generateSweepPCM({
    required double startFreq,
    required double endFreq,
    required double duration,
    required double startGain,
    required double endGain,
  }) {
    final numSamples = (duration * sampleRate).toInt();
    final pcmData = Int16List(numSamples);

    double phase = 0;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final progress = t / duration;

      // Exponential frequency ramp
      final currentFreq = startFreq * pow(endFreq / startFreq, progress);

      // Exponential gain ramp
      final currentGain = startGain * pow(endGain / startGain, progress);

      // Update phase
      phase += 2 * pi * currentFreq / sampleRate;
      if (phase > 2 * pi) {
        phase -= 2 * pi;
      }

      // Generate sample
      final sampleValue = sin(phase) * currentGain;

      // Convert to 16-bit integer
      int pcm = (sampleValue * 32767).toInt();
      if (pcm > 32767) pcm = 32767;
      if (pcm < -32768) pcm = -32768;

      pcmData[i] = pcm;
    }
    return pcmData;
  }
}
