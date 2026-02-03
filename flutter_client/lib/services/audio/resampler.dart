import 'dart:math' as math;
import 'dart:typed_data';

/// 简单的重采样器
/// 用于在不同采样率之间转换音频数据
class AudioResampler {
  /// 将音频从 srcSampleRate 重采样到 dstSampleRate
  /// @param pcmData 输入的 PCM 浮点数据 (范围 -1.0 到 1.0)
  /// @param srcSampleRate 源采样率
  /// @param dstSampleRate 目标采样率
  /// @return 重采样后的 PCM 数据
  static List<double> resample(
    List<double> pcmData,
    int srcSampleRate,
    int dstSampleRate,
  ) {
    if (srcSampleRate == dstSampleRate) {
      return pcmData;
    }

    // 计算重采样比例
    final ratio = srcSampleRate / dstSampleRate;

    // 计算输出长度
    final outputLength = (pcmData.length / ratio).ceil();

    // 使用线性插值进行重采样
    // 注意：这是一个简单的实现，对于高质量音频应该使用更复杂的算法（如 sinc 插值）
    final result = List<double>.filled(outputLength, 0.0);

    for (int i = 0; i < outputLength; i++) {
      final srcPos = i * ratio;

      // 获取整数部分索引
      final srcIndex0 = srcPos.floor();
      final srcIndex1 = math.min(srcIndex0 + 1, pcmData.length - 1);

      // 获取小数部分（用于线性插值）
      final frac = srcPos - srcIndex0;

      // 线性插值
      result[i] = pcmData[srcIndex0] * (1 - frac) + pcmData[srcIndex1] * frac;
    }

    return result;
  }

  /// 将 Int16 PCM 数据从 srcSampleRate 重采样到 dstSampleRate
  static List<int> resampleInt16(
    List<int> pcmData,
    int srcSampleRate,
    int dstSampleRate,
  ) {
    if (srcSampleRate == dstSampleRate) {
      return pcmData;
    }

    // 先转换为浮点
    final floatData = pcmData.map((v) => v / 32768.0).toList();

    // 重采样
    final resampled = resample(floatData, srcSampleRate, dstSampleRate);

    // 转换回 Int16
    return resampled.map((v) => (v * 32768).round().clamp(-32768, 32767)).toList();
  }

  /// 将 Float32List 从 srcSampleRate 重采样到 dstSampleRate
  static Float32List resampleFloat32(
    Float32List pcmData,
    int srcSampleRate,
    int dstSampleRate,
  ) {
    if (srcSampleRate == dstSampleRate) {
      return pcmData;
    }

    final ratio = srcSampleRate / dstSampleRate;
    final outputLength = (pcmData.length / ratio).ceil();

    final result = Float32List(outputLength);

    for (int i = 0; i < outputLength; i++) {
      final srcPos = i * ratio;
      final srcIndex0 = srcPos.floor();
      final srcIndex1 = math.min(srcIndex0 + 1, pcmData.length - 1);
      final frac = srcPos - srcIndex0;

      result[i] = pcmData[srcIndex0] * (1 - frac) + pcmData[srcIndex1] * frac;
    }

    return result;
  }
}
