import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../theme/app_colors.dart';

class ScreenSelectDialog extends StatefulWidget {
  const ScreenSelectDialog({super.key});

  @override
  State<ScreenSelectDialog> createState() => _ScreenSelectDialogState();
}

class _ScreenSelectDialogState extends State<ScreenSelectDialog> {
  List<DesktopCapturerSource> _screens = [];
  List<DesktopCapturerSource> _windows = [];
  bool _loading = true;
  String? _selectedSourceId;
  bool _shareAudio = false;
  Timer? _thumbnailTimer;

  @override
  void initState() {
    super.initState();
    _loadSources();
    // Refresh thumbnails periodically to provide a low-fps preview
    _thumbnailTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _loadSources(isRefresh: true);
    });
  }

  @override
  void dispose() {
    _thumbnailTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSources({bool isRefresh = false}) async {
    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(640, 360), // Request reasonable quality for preview
      );
      
      if (mounted) {
        // If refreshing and we got no sources, it might be a glitch or empty return.
        // Don't clear existing list immediately unless we are sure.
        if (isRefresh && sources.isEmpty) {
           debugPrint("Warning: getSources returned empty list during refresh");
           return;
        }

        setState(() {
          _screens = sources.where((s) => s.type == SourceType.Screen).toList();
          _windows = sources.where((s) => s.type == SourceType.Window).toList();
          if (!isRefresh) _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Error getting sources: $e");
      if (mounted && !isRefresh) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _selectSource(DesktopCapturerSource source) {
    if (_selectedSourceId == source.id) return;
    setState(() {
      _selectedSourceId = source.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgSecondary,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 900,
        height: 600,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Text(
                    "选择共享内容",
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          Container(
                            color: AppColors.bgTertiary,
                            child: const TabBar(
                              labelColor: AppColors.accent,
                              unselectedLabelColor: AppColors.textSecondary,
                              indicatorColor: AppColors.accent,
                              tabs: [
                                Tab(text: "屏幕"),
                                Tab(text: "窗口"),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                // Source List
                                Expanded(
                                  flex: 4,
                                  child: TabBarView(
                                    physics: const NeverScrollableScrollPhysics(),
                                    children: [
                                      _buildGrid(_screens),
                                      _buildGrid(_windows),
                                    ],
                                  ),
                                ),
                                const VerticalDivider(width: 1, color: AppColors.border),
                                // Preview Area
                                Expanded(
                                  flex: 6,
                                  child: Container(
                                    color: AppColors.bgPrimary,
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "预览",
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black,
                                              border: Border.all(color: AppColors.border),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: _selectedSourceId == null
                                                  ? const Center(
                                                      child: Text(
                                                        "请选择左侧内容进行预览",
                                                        style: TextStyle(color: AppColors.textSecondary),
                                                      ),
                                                    )
                                                  : _buildPreview(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Checkbox(
                                              value: _shareAudio,
                                              onChanged: (val) {
                                                setState(() {
                                                  _shareAudio = val ?? false;
                                                });
                                              },
                                              activeColor: AppColors.accent,
                                            ),
                                            const Text(
                                              "共享系统音频 (实验性)",
                                              style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(),
                                              child: const Text("取消", style: TextStyle(color: AppColors.textSecondary)),
                                            ),
                                            const SizedBox(width: 16),
                                            ElevatedButton(
                                              onPressed: _selectedSourceId == null
                                                  ? null
                                                  : () {
                                                      Navigator.of(context).pop({
                                                        'sourceId': _selectedSourceId,
                                                        'shareAudio': _shareAudio,
                                                      });
                                                    },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.accent,
                                                disabledBackgroundColor: AppColors.bgTertiary,
                                              ),
                                              child: const Text("开始共享", style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    DesktopCapturerSource? source;
    try {
      source = [..._screens, ..._windows].firstWhere((s) => s.id == _selectedSourceId);
    } catch (_) {
      return const Center(child: Text("源不可用", style: TextStyle(color: AppColors.textSecondary)));
    }

    if (source.thumbnail != null) {
      return Image.memory(
        source.thumbnail!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else {
      return const Center(
        child: Icon(Icons.monitor, size: 64, color: AppColors.textSecondary),
      );
    }
  }

  Widget _buildGrid(List<DesktopCapturerSource> sources) {
    if (sources.isEmpty) {
      return const Center(
        child: Text(
          "无可用内容",
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        final isSelected = _selectedSourceId == source.id;
        
        return InkWell(
          onTap: () => _selectSource(source),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? AppColors.accent : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: isSelected ? AppColors.accent.withValues(alpha: 0.1) : AppColors.bgTertiary,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: source.thumbnail != null
                        ? Image.memory(
                            source.thumbnail!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : const Icon(
                            Icons.monitor,
                            size: 40,
                            color: AppColors.textSecondary,
                          ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accent : AppColors.bgSecondary,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                  ),
                  child: Text(
                    source.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
