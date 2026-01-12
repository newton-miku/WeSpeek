import 'dart:async';
import 'package:flutter/material.dart';
import '../providers/call_provider.dart';

class NoiseGateSettingsDialog extends StatefulWidget {
  final CallProvider provider;

  const NoiseGateSettingsDialog({super.key, required this.provider});

  @override
  State<NoiseGateSettingsDialog> createState() =>
      _NoiseGateSettingsDialogState();
}

class _NoiseGateSettingsDialogState extends State<NoiseGateSettingsDialog> {
  late double gateThreshold;

  // Calibration State
  double _currentLevel = 0.0;
  String _calibState = 'idle'; // idle, recording
  double _calibNoiseMax = 0.0;
  StreamSubscription<double>? _volumeSub;
  Timer? _calibTimer;
  int _lastUpdate = 0;

  @override
  void initState() {
    super.initState();
    gateThreshold = widget.provider.gateThreshold;

    _volumeSub = widget.provider.onVolume?.listen((vol) {
      if (!mounted) return;

      // Always update calibration data to capture peaks accurately
      _currentLevel = vol;
      if (_calibState == 'recording') {
        if (vol > _calibNoiseMax) _calibNoiseMax = vol;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      // Throttle UI updates to ~15 FPS (66ms) to prevent UI freeze
      if (now - _lastUpdate < 66) return;
      _lastUpdate = now;

      setState(() {
        // UI rebuild will reflect the latest _currentLevel
      });
    });
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    _calibTimer?.cancel();
    super.dispose();
  }

  void _startCalib() {
    setState(() {
      _calibState = 'recording';
      _calibNoiseMax = 0.0;
    });

    // 5 seconds timer for calibration
    _calibTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _calibState != 'recording') return;
      _stopCalib();
    });
  }

  void _stopCalib() {
    _calibTimer?.cancel();
    if (!mounted) return;

    // Auto set threshold: noise max + 50% or at least +0.01
    // Using a slightly more aggressive multiplier to be safe
    double newThreshold = _calibNoiseMax * 1.5;
    if (newThreshold < _calibNoiseMax + 0.01) {
      newThreshold = _calibNoiseMax + 0.01;
    }
    // Clamp to range
    if (newThreshold > 0.2) newThreshold = 0.2;
    if (newThreshold < 0.01) newThreshold = 0.01; // Minimum floor

    setState(() {
      gateThreshold = newThreshold;
      _calibState = 'idle';
    });
  }

  void _save() {
    if (!mounted) return;
    widget.provider.setGateThreshold(gateThreshold);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("噪音门限设置"),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("实时音量", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _currentLevel.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _currentLevel > gateThreshold ? Colors.green : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("当前音量: ${(_currentLevel * 100).toStringAsFixed(1)}%"),
                if (_calibState == 'recording')
                  const Text(
                    "正在录制背景噪音...",
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "自动设置",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_calibState == 'idle')
                  TextButton.icon(
                    onPressed: _startCalib,
                    icon: const Icon(Icons.mic, size: 16),
                    label: const Text("开始录制 (5秒)"),
                  )
                else
                  TextButton.icon(
                    onPressed: _stopCalib,
                    icon: const Icon(Icons.stop, size: 16, color: Colors.red),
                    label: const Text(
                      "停止录制",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
            const Text(
              "请在不说话时点击录制，系统将自动检测背景噪音并设置阈值。",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 20),
            const Text("手动微调阈值", style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: gateThreshold,
                    min: 0.0,
                    max: 0.2,
                    divisions: 200,
                    label: "${(gateThreshold * 100).toStringAsFixed(1)}%",
                    onChanged: (v) => setState(() => gateThreshold = v),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    "${(gateThreshold * 100).toStringAsFixed(1)}%",
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("取消"),
        ),
        ElevatedButton(onPressed: _save, child: const Text("确定")),
      ],
    );
  }
}
