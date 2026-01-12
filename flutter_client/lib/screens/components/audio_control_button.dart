import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_colors.dart';
import '../../providers/call_provider.dart';
import '../../widgets/noise_gate_settings_dialog.dart';

class AudioControlButton extends StatefulWidget {
  final IconData icon;
  final bool isMuted;
  final VoidCallback onTap;
  final List<String> items;
  final String selectedItem;
  final ValueChanged<String> onItemSelected;
  final String tooltip;

  // Volume/Gain
  final double? volume;
  final ValueChanged<double>? onVolumeChanged;

  // Noise Mode
  final List<String>? noiseModes;
  final String? currentNoiseMode;
  final ValueChanged<String>? onNoiseModeChanged;

  const AudioControlButton({
    super.key,
    required this.icon,
    required this.isMuted,
    required this.onTap,
    required this.items,
    required this.selectedItem,
    required this.onItemSelected,
    required this.tooltip,
    this.volume,
    this.onVolumeChanged,
    this.noiseModes,
    this.currentNoiseMode,
    this.onNoiseModeChanged,
  });

  @override
  State<AudioControlButton> createState() => _AudioControlButtonState();
}

class _AudioControlButtonState extends State<AudioControlButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHoveringButton = false;
  bool _isHoveringMenu = false;
  Timer? _closeTimer;

  @override
  void dispose() {
    _closeTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(AudioControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayEntry != null) {
          _overlayEntry!.markNeedsBuild();
        }
      });
    }
  }

  void _showMenu() {
    _closeTimer?.cancel();
    if (_overlayEntry != null) return;

    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideMenu() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_isHoveringButton && !_isHoveringMenu) {
        _removeMenu();
      }
    });
  }

  void _removeMenu() {
    _closeTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: 250,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(
            size.width / 2 - 125,
            size.height + 8,
          ), // Center below button
          child: MouseRegion(
            onEnter: (_) {
              _isHoveringMenu = true;
              _closeTimer?.cancel();
            },
            onExit: (_) {
              _isHoveringMenu = false;
              _hideMenu();
            },
            child: Material(
              elevation: 8,
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(8),
              shadowColor: Colors.black.withValues(alpha: 0.5),
              child: _AudioControlMenuContent(
                widget: widget,
                onRemoveMenu: _removeMenu,
                onHideMenu: _hideMenu,
                onCancelCloseTimer: () => _closeTimer?.cancel(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          _isHoveringButton = true;
          _showMenu();
        },
        onExit: (_) {
          _isHoveringButton = false;
          _hideMenu();
        },
        child: Tooltip(
          message: widget.tooltip,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.isMuted
                    ? AppColors.danger.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: widget.isMuted
                    ? Border.all(color: AppColors.danger)
                    : null,
              ),
              child: Icon(
                widget.icon,
                color: widget.isMuted
                    ? AppColors.danger
                    : AppColors.textPrimary,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioControlMenuContent extends StatefulWidget {
  final AudioControlButton widget;
  final VoidCallback onRemoveMenu;
  final VoidCallback onHideMenu;
  final VoidCallback onCancelCloseTimer;

  const _AudioControlMenuContent({
    required this.widget,
    required this.onRemoveMenu,
    required this.onHideMenu,
    required this.onCancelCloseTimer,
  });

  @override
  State<_AudioControlMenuContent> createState() => _AudioControlMenuContentState();
}

class _AudioControlMenuContentState extends State<_AudioControlMenuContent> {
  bool _isDeviceListExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.bgSecondary,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 1. Gain Slider ---
          if (widget.widget.volume != null &&
              widget.widget.onVolumeChanged != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 8,
              ),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.accent,
                  inactiveTrackColor: AppColors.bgTertiary,
                  thumbColor: AppColors.textPrimary,
                  overlayColor: AppColors.accent.withValues(
                    alpha: 0.2,
                  ),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  trackHeight: 4,
                  showValueIndicator: ShowValueIndicator.onDrag,
                  valueIndicatorTextStyle: const TextStyle(
                    color: AppColors.textPrimary,
                  ),
                  valueIndicatorColor: AppColors.bgTertiary,
                ),
                child: Slider(
                  value: widget.widget.volume!,
                  min: 0.0,
                  max: 2.0,
                  label: "${(widget.widget.volume! * 100).toInt()}%",
                  onChanged: (val) {
                    setState(() {}); // Local update for slider
                    widget.widget.onVolumeChanged!(val);
                  },
                ),
              ),
            ),
            if (widget.widget.items.length > 1 ||
                (widget.widget.noiseModes != null &&
                    widget.widget.onNoiseModeChanged != null))
              const Divider(color: AppColors.border, height: 1),
          ],

          // --- 2. Device Selection (Custom Dropdown) ---
          if (widget.widget.items.length > 1) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                "选择设备",
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgTertiary,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header (Selected Item)
                    InkWell(
                      onTap: () {
                         widget.onCancelCloseTimer();
                         setState(() {
                           _isDeviceListExpanded = !_isDeviceListExpanded;
                         });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (widget.widget.items.length > 1 &&
                                        widget.widget.items.contains(
                                          widget.widget.selectedItem,
                                        ))
                                    ? widget.widget.selectedItem
                                    : (widget.widget.items.isNotEmpty
                                        ? widget.widget.items.first
                                        : ""),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              _isDeviceListExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: AppColors.textSecondary,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // List (Expanded)
                    if (_isDeviceListExpanded)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: const BoxDecoration(
                           border: Border(top: BorderSide(color: AppColors.border)),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: widget.widget.items.toSet().toList().map((item) {
                              final isSelected = item == widget.widget.selectedItem;
                              return InkWell(
                                onTap: () {
                                  widget.widget.onItemSelected(item);
                                  setState(() {
                                    _isDeviceListExpanded = false;
                                  });
                                  widget.onRemoveMenu();
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  color: isSelected ? AppColors.accent.withValues(alpha: 0.1) : null,
                                  child: Text(
                                    item,
                                    style: TextStyle(
                                      color: isSelected ? AppColors.accent : AppColors.textPrimary,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],

          // --- 3. Noise Mode (Radio) ---
          if (widget.widget.noiseModes != null &&
              widget.widget.onNoiseModeChanged != null) ...[
            if (widget.widget.items.length > 1)
              const Divider(color: AppColors.border, height: 1),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                "降噪模式",
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              child: Column(
                children: widget.widget.noiseModes!.map((mode) {
                  final isSelected = mode == widget.widget.currentNoiseMode;
                  return Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            widget.onRemoveMenu();
                            widget.widget.onNoiseModeChanged!(mode);
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.accent
                                          : AppColors.textSecondary,
                                      width: isSelected ? 4 : 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    mode == "none"
                                        ? "关闭"
                                        : (mode == "gate"
                                            ? "噪音门"
                                            : (mode == "smart"
                                                ? "智能降噪"
                                                : (mode == "deepfilter"
                                                    ? "DeepFilterNet"
                                                    : mode))),
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (mode == "gate" && isSelected)
                        InkWell(
                          onTap: () {
                            widget.onRemoveMenu();
                            final provider = context
                                .read<CallProvider>();
                            showDialog(
                              context: context,
                              builder: (context) =>
                                  NoiseGateSettingsDialog(
                                    provider: provider,
                                  ),
                            );
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.settings,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
