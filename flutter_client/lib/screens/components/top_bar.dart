import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../providers/call_provider.dart';
import '../../theme/app_colors.dart';
import '../settings_screen.dart';
import '../../widgets/screen_select_dialog.dart';

class TopBar extends StatelessWidget {
  final VoidCallback? onToggleMembers;
  final bool isMembersVisible;
  final VoidCallback? onToggleSidebar;

  const TopBar({
    super.key,
    this.onToggleMembers,
    this.isMembersVisible = true,
    this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    // Select specific properties to avoid unnecessary rebuilds (e.g. on speaking status change)
    final (isInCall, currentRoomId, isScreenSharing, canShareScreen) = context
        .select<CallProvider, (bool, String, bool, bool)>(
          (p) => (p.isInCall, p.currentRoomId, p.isScreenSharing, p.canShareScreen),
        );

    // We need the provider for callbacks

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Mobile sidebar toggle button - only show on small screens
          if (MediaQuery.of(context).size.width < 768) ...[
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.textPrimary),
              onPressed: onToggleSidebar,
              tooltip: "切换侧边栏",
            ),
            const SizedBox(width: 8),
          ],
          // On desktop, always show WeSpeek logo when not in a call
          if (MediaQuery.of(context).size.width >= 768 && !isInCall) ...[
            const Text(
              "WeSpeek",
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 16),
          ],

          if (isInCall && currentRoomId.isNotEmpty) ...[
            const Icon(Icons.volume_up, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              currentRoomId,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const Spacer(),

          // Screen Share Button - Always show when in call, but disable if WebRTC not supported
          if (isInCall) ...[
            IconButton(
              icon: Icon(
                isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
              ),
              color: isScreenSharing
                  ? AppColors.accent
                  : (canShareScreen ? AppColors.textPrimary : AppColors.textTertiary),
              onPressed: canShareScreen
                  ? () async {
                      final provider = context.read<CallProvider>();
                      if (isScreenSharing) {
                        provider.stopScreenShare();
                      } else {
                        String? sourceId;
                        bool shareAudio = false;
                        if (!kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.windows ||
                                defaultTargetPlatform == TargetPlatform.linux ||
                                defaultTargetPlatform == TargetPlatform.macOS)) {
                          final result = await showDialog<Map<String, dynamic>>(
                            context: context,
                            builder: (context) => const ScreenSelectDialog(),
                          );
                          if (result == null) return; // User cancelled
                          sourceId = result['sourceId'];
                          shareAudio = result['shareAudio'] ?? false;
                        }
                        provider.startScreenShare(
                          sourceId: sourceId,
                          shareAudio: shareAudio,
                        );
                      }
                    }
                  : null,
              tooltip: isScreenSharing
                  ? "停止共享"
                  : (canShareScreen ? "屏幕共享" : "屏幕共享（需要 WebRTC 支持）"),
            ),
            const SizedBox(width: 8),
          ],

          // Settings Button - Only show if NOT desktop (because desktop has it in custom title bar)
          if (kIsWeb ||
              (defaultTargetPlatform != TargetPlatform.windows &&
                  defaultTargetPlatform != TargetPlatform.linux &&
                  defaultTargetPlatform != TargetPlatform.macOS)) ...[
            IconButton(
              icon: const Icon(
                Icons.settings,
              ), // Use Settings icon for consistency
              color: AppColors.textPrimary,
              tooltip: "设置",
              onPressed: () {
                // final provider = context.read<CallProvider>();
                // showSettingsDialog(context, provider);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(width: 8),
          ],

          // Toggle Members List
          if (isInCall)
            IconButton(
              icon: Icon(isMembersVisible ? Icons.group : Icons.group_outlined),
              color: isMembersVisible
                  ? AppColors.accent
                  : AppColors.textPrimary,
              onPressed: onToggleMembers,
              tooltip: isMembersVisible ? "隐藏成员列表" : "显示成员列表",
            ),
        ],
      ),
    );
  }
}
