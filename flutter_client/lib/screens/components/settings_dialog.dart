import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../providers/call_provider.dart';
import '../../theme/app_colors.dart';

class SettingsDialog extends StatelessWidget {
  final CallProvider provider;

  const SettingsDialog({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: provider,
      builder: (context, child) {
        return AlertDialog(
          backgroundColor: AppColors.bgSecondary,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("设置", style: TextStyle(color: AppColors.textPrimary)),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
                onPressed: () {
                  provider.reloadDevices();
                },
                tooltip: "刷新设备列表",
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!kIsWeb) ...[
                  // Input Device
                  _buildDropdown(
                    "输入设备",
                    provider.inputDevices,
                    provider.selectedInputDevice,
                    (v) => provider.setSelectedInputDevice(v!),
                  ),
                  const SizedBox(height: 16),
                  // Output Device
                  _buildDropdown(
                    "输出设备",
                    provider.outputDevices,
                    provider.selectedOutputDevice,
                    (v) => provider.setSelectedOutputDevice(v!),
                  ),
                  const SizedBox(height: 16),
                ],
                // Mic Gain
                Row(
                  children: [
                    const Text(
                      "麦克风增益",
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    Expanded(
                      child: Slider(
                        value: provider.micGain,
                        min: 0.0,
                        max: 2.0,
                        activeColor: AppColors.accent,
                        inactiveColor: AppColors.bgHover,
                        onChanged: (v) => provider.setMicGain(v),
                      ),
                    ),
                    Text(
                      provider.micGain.toStringAsFixed(1),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                // Speaker Gain
                Row(
                  children: [
                    const Text(
                      "扬声器增益",
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    Expanded(
                      child: Slider(
                        value: provider.speakerGain,
                        min: 0.0,
                        max: 2.0,
                        activeColor: AppColors.accent,
                        inactiveColor: AppColors.bgHover,
                        onChanged: (v) => provider.setSpeakerGain(v),
                      ),
                    ),
                    Text(
                      provider.speakerGain.toStringAsFixed(1),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Noise Suppression
                _buildDropdown(
                  "降噪模式",
                  ["off", "auto", "gate"],
                  provider.noiseMode,
                  (v) => provider.setNoiseMode(v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("关闭", style: TextStyle(color: AppColors.accent)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String value,
    Function(String?) onChanged,
  ) {
    if (!items.contains(value) && items.isNotEmpty) {
      // value = items.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.bgTertiary,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : null,
              isExpanded: true,
              dropdownColor: AppColors.bgSecondary,
              style: const TextStyle(color: AppColors.textPrimary),
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: onChanged,
              hint: Text(
                value,
                style: const TextStyle(color: AppColors.textTertiary),
              ),
              icon: const Icon(
                Icons.arrow_drop_down,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void showSettingsDialog(BuildContext context, CallProvider provider) {
  showDialog(
    context: context,
    builder: (context) => SettingsDialog(provider: provider),
  );
}
