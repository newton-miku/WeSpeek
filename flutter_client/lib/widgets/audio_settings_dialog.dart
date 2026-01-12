import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:async';
import '../providers/call_provider.dart';

class AudioSettingsDialog extends StatefulWidget {
  final CallProvider provider;
  const AudioSettingsDialog({super.key, required this.provider});

  @override
  State<AudioSettingsDialog> createState() => _AudioSettingsDialogState();
}

class _AudioSettingsDialogState extends State<AudioSettingsDialog> {
  late double micGain;
  late double speakerGain;
  late String inputSel;
  late String outputSel;
  late String noiseMode;
  late bool closeToTray;
  late double gateThreshold;

  // Calibration State
  double _currentLevel = 0.0;
  String _calibState = 'idle'; // idle, noise, speech
  double _calibNoiseMax = 0.0;
  double _calibSpeechMax = 0.0;
  StreamSubscription<double>? _volumeSub;

  @override
  void initState() {
    super.initState();
    micGain = widget.provider.micGain;
    speakerGain = widget.provider.speakerGain;
    inputSel = widget.provider.selectedInputDevice;
    outputSel = widget.provider.selectedOutputDevice;
    noiseMode = widget.provider.noiseMode;
    closeToTray = widget.provider.closeToTray;
    gateThreshold = widget.provider.gateThreshold;

    _volumeSub = widget.provider.onVolume?.listen((vol) {
      if (!mounted) return;
      setState(() {
        _currentLevel = vol;
        if (_calibState == 'noise') {
          if (vol > _calibNoiseMax) _calibNoiseMax = vol;
        } else if (_calibState == 'speech') {
          if (vol > _calibSpeechMax) _calibSpeechMax = vol;
        }
      });
    });
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    super.dispose();
  }

  void _startNoiseCalib() {
    setState(() {
      _calibState = 'noise';
      _calibNoiseMax = 0.0;
    });

    // 3 seconds timer
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _calibState != 'noise') return;
      _stopCalib();

      // Auto set threshold: noise max + 50% or at least +0.01
      // Using a slightly more aggressive multiplier to be safe
      double newThreshold = _calibNoiseMax * 1.5;
      if (newThreshold < _calibNoiseMax + 0.01) {
        newThreshold = _calibNoiseMax + 0.01;
      }
      // Clamp to range
      if (newThreshold > 0.2) newThreshold = 0.2;

      setState(() {
        gateThreshold = newThreshold;
      });
    });
  }

  void _startSpeechCalib() {
    setState(() {
      _calibState = 'speech';
      _calibSpeechMax = 0.0;
    });
  }

  void _stopCalib() {
    if (_calibState == 'speech' && _calibSpeechMax > 0) {
      // Auto set threshold based on speech
      // Ideally, threshold should be well below speech peak (e.g. 20-30%)
      // but above noise floor.
      double newThreshold = _calibSpeechMax * 0.25;

      // If we have noise data, ensure we are above it
      if (_calibNoiseMax > 0) {
        double noiseSafe = _calibNoiseMax * 1.5;
        if (newThreshold < noiseSafe) {
          newThreshold = noiseSafe;
        }
      }

      // Ensure minimum
      if (newThreshold < 0.01) newThreshold = 0.01;
      // Clamp to range
      if (newThreshold > 0.2) newThreshold = 0.2;

      setState(() {
        gateThreshold = newThreshold;
      });
    }
    setState(() {
      _calibState = 'idle';
    });
  }

  @override
  void didUpdateWidget(AudioSettingsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.provider.inputDevices.contains(inputSel)) {
      if (widget.provider.inputDevices.isNotEmpty) {
        inputSel = widget.provider.inputDevices[0];
      } else {
        inputSel = "系统默认";
      }
    }
    if (!widget.provider.outputDevices.contains(outputSel)) {
      if (widget.provider.outputDevices.isNotEmpty) {
        outputSel = widget.provider.outputDevices[0];
      } else {
        outputSel = "系统默认";
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("音频设置"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb && widget.provider.inputDevices.length > 1) ...[
              Row(
                children: [
                  const Text("输入设备"),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          widget.provider.inputDevices.contains(inputSel)
                          ? inputSel
                          : null,
                      items: widget.provider.inputDevices
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => inputSel = v);
                        }
                      },
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (!kIsWeb && widget.provider.outputDevices.length > 1) ...[
              Row(
                children: [
                  const Text("输出设备"),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          widget.provider.outputDevices.contains(outputSel)
                          ? outputSel
                          : null,
                      items: widget.provider.outputDevices
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => outputSel = v);
                        }
                      },
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                const Text("降噪模式"),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: noiseMode,
                    items: const [
                      DropdownMenuItem(value: "none", child: Text("关闭")),
                      DropdownMenuItem(value: "gate", child: Text("噪音门")),
                      DropdownMenuItem(value: "smart", child: Text("智能降噪")),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => noiseMode = v);
                      }
                    },
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (noiseMode == "gate") ...[
              const Text(
                "噪音门限阈值 (自动/手动)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
                  Text("${(gateThreshold * 100).toStringAsFixed(1)}%"),
                ],
              ),
              // Level Meter
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _currentLevel.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _currentLevel > gateThreshold ? Colors.green : Colors.red,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_calibState == 'idle') ...[
                    OutlinedButton(
                      onPressed: _startNoiseCalib,
                      child: const Text("采集噪音(3秒)"),
                    ),
                    OutlinedButton(
                      onPressed: _startSpeechCalib,
                      child: const Text("采集语音"),
                    ),
                  ] else ...[
                    Text(_calibState == 'noise' ? "保持安静..." : "请说话..."),
                    ElevatedButton(
                      onPressed: _stopCalib,
                      child: const Text("完成"),
                    ),
                  ],
                ],
              ),
              if (_calibState == 'idle')
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    "噪音峰值: ${(_calibNoiseMax * 100).toStringAsFixed(1)}%, 语音峰值: ${(_calibSpeechMax * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [const Text("麦克风音量"), Text(micGain.toStringAsFixed(2))],
            ),
            Slider(
              value: micGain,
              min: 0,
              max: 2,
              divisions: 30,
              label: micGain.toStringAsFixed(2),
              onChanged: (v) => setState(() => micGain = v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("扬声器音量"),
                Text(speakerGain.toStringAsFixed(2)),
              ],
            ),
            Slider(
              value: speakerGain,
              min: 0,
              max: 2,
              divisions: 30,
              label: speakerGain.toStringAsFixed(2),
              onChanged: (v) => setState(() => speakerGain = v),
            ),
            const SizedBox(height: 8),
            if (!kIsWeb)
              CheckboxListTile(
                title: const Text("关闭时最小化到托盘"),
                value: closeToTray,
                onChanged: (v) => setState(() => closeToTray = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("取消"),
        ),
        ElevatedButton(
          onPressed: () {
            widget.provider.setMicGain(micGain);
            widget.provider.setSpeakerGain(speakerGain);
            widget.provider.setSelectedInputDevice(inputSel);
            widget.provider.setSelectedOutputDevice(outputSel);
            widget.provider.setNoiseMode(noiseMode);
            if (noiseMode == 'gate') {
              widget.provider.setGateThreshold(gateThreshold);
            }
            widget.provider.setCloseToTray(closeToTray);
            Navigator.pop(context);
          },
          child: const Text("保存"),
        ),
      ],
    );
  }
}
