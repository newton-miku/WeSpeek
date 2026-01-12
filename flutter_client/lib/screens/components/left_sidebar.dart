import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wespeek_client/services/audio/audio_client.dart'
    show AudioPermissionException;
import 'package:provider/provider.dart';
import '../../providers/call_provider.dart';
import '../../models/room_model.dart';
import '../../theme/app_colors.dart';
import '../admin_status_screen.dart';
import '../connect_screen.dart';

import 'package:flutter/foundation.dart'; // for kIsWeb

import 'audio_control_button.dart';

class LeftSidebar extends StatelessWidget {
  const LeftSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, provider, child) {
        return SizedBox(
          width: 250,
          child: Container(
            color: AppColors.bgSecondary,
            child: Column(
              children: [
                // Top Bar: Logo + Audio Controls + Exit
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.bgSecondary,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      // Logo
                      const Text(
                        "WeSpeek",
                        style: TextStyle(
                          fontFamily: 'Segoe UI', // Fallback
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),

                      // Mic
                      AudioControlButton(
                        icon: provider.isMicMuted ? Icons.mic_off : Icons.mic,
                        isMuted: provider.isMicMuted,
                        onTap: () => provider.toggleMicMute(),
                        items: kIsWeb ? [] : provider.inputDevices,
                        selectedItem: provider.selectedInputDevice,
                        onItemSelected: (val) =>
                            provider.setSelectedInputDevice(val),
                        tooltip: "麦克风: ${provider.isMicMuted ? '已静音' : '开启'}",
                        volume: provider.micGain,
                        onVolumeChanged: (val) => provider.setMicGain(val),
                        noiseModes: kIsWeb 
                            ? const ["none", "gate", "smart"]
                            : const ["none", "gate", "smart", "deepfilter"],
                        currentNoiseMode: provider.noiseMode,
                        onNoiseModeChanged: (val) => provider.setNoiseMode(val),
                      ),
                      const SizedBox(width: 4),

                      // Speaker
                      AudioControlButton(
                        icon: provider.isSpeakerMuted
                            ? Icons.volume_off
                            : Icons.volume_up,
                        isMuted: provider.isSpeakerMuted,
                        onTap: () => provider.toggleSpeakerMute(),
                        items: kIsWeb ? [] : provider.outputDevices,
                        selectedItem: provider.selectedOutputDevice,
                        onItemSelected: (val) =>
                            provider.setSelectedOutputDevice(val),
                        tooltip:
                            "扬声器: ${provider.isSpeakerMuted ? '已静音' : '开启'}",
                        volume: provider.speakerGain,
                        onVolumeChanged: (val) => provider.setSpeakerGain(val),
                      ),
                      const SizedBox(width: 4),

                      // Exit Room (Only visible if in room)
                      if (provider.isInCall)
                        IconButton(
                          icon: const Icon(Icons.exit_to_app, size: 18),
                          color: AppColors.danger,
                          tooltip: "退出房间",
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () => provider.leaveRoom(),
                        ),
                    ],
                  ),
                ),

                // Server Info Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppColors.bgSecondary,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.dns, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          provider.currentServer.isEmpty
                              ? "No Server"
                              : provider.currentServer,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.textSecondary,
                        ),
                        color: AppColors.bgTertiary,
                        onSelected: (value) {
                          if (value == 'admin_status') {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AdminStatusScreen(),
                              ),
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'admin_status',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.admin_panel_settings,
                                  color: AppColors.textPrimary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Server Status',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // User Info
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: AppColors.bgSecondary,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person,
                        color: AppColors.success,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${provider.currentName} (${provider.currentUid})",
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Rooms List
                Expanded(
                  child: provider.rooms.isEmpty
                      ? const Center(
                          child: Text(
                            "No Rooms",
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          itemCount:
                              provider.groups.length +
                              1, // Groups + "Default" (no group)
                          itemBuilder: (context, index) {
                            final sortedGroups = List<String>.from(provider.groups)..sort();
                            
                            if (index < sortedGroups.length) {
                              final group = sortedGroups[index];
                              final groupRooms = provider.rooms
                                  .where((r) => r.group == group)
                                  .toList()
                                ..sort((a, b) => a.id.compareTo(b.id)); // Sort rooms
                                
                              if (groupRooms.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return Theme(
                                data: Theme.of(context).copyWith(
                                  dividerColor: Colors.transparent,
                                  iconTheme: const IconThemeData(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  title: Text(
                                    group.toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  initiallyExpanded: true,
                                  iconColor: AppColors.textSecondary,
                                  collapsedIconColor: AppColors.textSecondary,
                                  shape: const Border(),
                                  collapsedShape: const Border(),
                                  children: groupRooms
                                      .map(
                                        (r) => _buildRoomItem(
                                          context,
                                          r,
                                          provider,
                                        ),
                                      )
                                      .toList(),
                                ),
                              );
                            } else {
                              // Rooms without group
                              final noGroupRooms = provider.rooms
                                  .where((r) => r.group.isEmpty)
                                  .toList()
                                ..sort((a, b) => a.id.compareTo(b.id)); // Sort rooms
                                
                              if (noGroupRooms.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: noGroupRooms
                                    .map(
                                      (r) =>
                                          _buildRoomItem(context, r, provider),
                                    )
                                    .toList(),
                              );
                            }
                          },
                        ),
                ),
                // Connection Status Footer
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppColors.bgSecondary,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        provider.isConnected ? Icons.check_circle : Icons.error,
                        color: provider.isConnected
                            ? AppColors.success
                            : AppColors.danger,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          provider.status,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (provider.isConnected)
                        IconButton(
                          icon: const Icon(
                            Icons.logout,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () {
                            provider.disconnect();
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const ConnectScreen(),
                              ),
                            );
                          },
                          tooltip: "断开连接",
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMemberItem(
    BuildContext context,
    RoomMember member,
    CallProvider provider,
  ) {
    final isMe = member.uid == provider.currentUid;
    final isSpeaking = provider.speakingUsers.contains(member.uid);

    return Container(
      margin: const EdgeInsets.only(left: 20, top: 1, bottom: 1, right: 8),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: isSpeaking
            ? AppColors.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            member.inputDisabled
                ? Icons.mic_off
                : (isSpeaking ? Icons.mic : Icons.mic_none),
            size: 14,
            color: member.inputDisabled
                ? AppColors.danger
                : (isSpeaking ? AppColors.success : AppColors.textTertiary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              member.name,
              style: TextStyle(
                color: isSpeaking
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.outputDisabled)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.headset_off, size: 14, color: AppColors.danger),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomItem(
    BuildContext context,
    Room room,
    CallProvider provider,
  ) {
    final isSelected = room.id == provider.selectedRoomId;
    final isInThisRoom = room.id == provider.currentRoomId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onSecondaryTapDown: (details) async {
            final offset = details.globalPosition;
            final value = await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                offset.dx,
                offset.dy,
                offset.dx,
                offset.dy,
              ),
              items: [
                const PopupMenuItem(
                  value: 'join',
                  child: Row(
                    children: [
                      Icon(Icons.login, size: 16, color: AppColors.textPrimary),
                      SizedBox(width: 8),
                      Text('加入频道', style: TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, size: 16, color: AppColors.textPrimary),
                      SizedBox(width: 8),
                      Text('分享链接', style: TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ],
              color: AppColors.bgTertiary,
              elevation: 8,
            );

            if (value == 'join') {
              if (provider.currentRoomId != room.id) {
                try {
                  await provider.joinRoom(room.id);
                } catch (e) {
                  if (e is AudioPermissionException && context.mounted) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("麦克风权限错误"),
                        content: Text(
                          (e).message == "No microphone found"
                              ? "未检测到麦克风设备，请检查连接。"
                              : "网页没有麦克风权限，请在浏览器设置中允许访问麦克风。",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text("确定"),
                          ),
                        ],
                      ),
                    );
                  }
                }
              }
            } else if (value == 'share') {
              final link = "${provider.httpBaseUrl}/?room=${room.id}";
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("链接已复制到剪贴板")),
                );
              }
            }
          },
          child: InkWell(
            onTap: () {
              // provider.selectRoom(room.id);
            },
          onDoubleTap: () async {
            if (provider.currentRoomId != room.id) {
              try {
                await provider.joinRoom(room.id);
              } catch (e) {
                if (e is AudioPermissionException && context.mounted) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("麦克风权限错误"),
                      content: Text(
                        (e).message == "No microphone found"
                            ? "未检测到麦克风设备，请检查连接。"
                            : "网页没有麦克风权限，请在浏览器设置中允许访问麦克风。",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text("确定"),
                        ),
                      ],
                    ),
                  );
                }
              }
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isInThisRoom
                  ? Border.all(color: AppColors.success.withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  isInThisRoom ? Icons.volume_up : Icons.tag,
                  size: 16,
                  color: isInThisRoom
                      ? AppColors.success
                      : (isSelected
                            ? AppColors.accent
                            : AppColors.textTertiary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    room.id,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (room.members.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bgTertiary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "${room.members.length}",
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        ),
        if (room.members.isNotEmpty)
          Column(
            children: room.members
                .map((m) => _buildMemberItem(context, m, provider))
                .toList(),
          ),
      ],
    );
  }
}
