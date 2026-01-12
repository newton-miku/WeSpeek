import 'package:flutter/material.dart';
import 'package:wespeek_client/screens/components/user_info_dialog.dart';
import 'package:provider/provider.dart';
import '../../providers/call_provider.dart';
import '../../theme/app_colors.dart';
import '../../models/room_model.dart';

class MembersList extends StatelessWidget {
  final bool isVertical;

  const MembersList({super.key, this.isVertical = false});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, provider, child) {
        final room = provider.getRoomById(provider.currentRoomId);
        if (room == null || !provider.isInCall) {
          if (isVertical) {
             return const Center(
               child: Text("未连接", style: TextStyle(color: AppColors.textSecondary)),
             );
          }
          return const SizedBox(
            height: 120,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.meeting_room_outlined,
                    color: AppColors.textSecondary,
                    size: 32,
                  ),
                  SizedBox(height: 8),
                  Text(
                    "双击频道以加入",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        if (isVertical) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: room.members.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final m = room.members[index];
              final isSpeaking = provider.speakingUsers.contains(m.uid);
              final isMe = m.uid == provider.currentUid;

              return _MemberCard(
                member: m,
                isSpeaking: isSpeaking,
                isMe: isMe,
                provider: provider,
                isVertical: true,
              );
            },
          );
        }

        return SizedBox(
          height: 140, // Slightly taller for better spacing
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            itemCount: room.members.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final m = room.members[index];
              final isSpeaking = provider.speakingUsers.contains(m.uid);
              final isMe = m.uid == provider.currentUid;

              return _MemberCard(
                member: m,
                isSpeaking: isSpeaking,
                isMe: isMe,
                provider: provider,
              );
            },
          ),
        );
      },
    );
  }
}

class _MemberCard extends StatefulWidget {
  final RoomMember member;
  final bool isSpeaking;
  final bool isMe;
  final CallProvider provider;
  final bool isVertical;

  const _MemberCard({
    required this.member,
    required this.isSpeaking,
    required this.isMe,
    required this.provider,
    this.isVertical = false,
  });

  @override
  State<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<_MemberCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void didUpdateWidget(_MemberCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpeaking && !oldWidget.isSpeaking) {
      _controller.repeat();
    } else if (!widget.isSpeaking && oldWidget.isSpeaking) {
      _controller.stop();
      _controller.reset();
    }
    // Ensure animation is running if speaking (e.g. after rebuild)
    if (widget.isSpeaking && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, details),
      child: Container(
        width: widget.isVertical ? double.infinity : 100,
        height: widget.isVertical ? 80 : null, // Fixed height for vertical list items
        decoration: BoxDecoration(
          color: widget.isMe
              ? AppColors.bgTertiary.withValues(alpha: 0.8)
              : AppColors.bgTertiary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isMe
                ? AppColors.selfHighlight.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: widget.isMe
              ? [
                  BoxShadow(
                    color: AppColors.selfHighlight.withValues(alpha: 0.1),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: widget.isVertical
            ? Row(
                children: [
                  const SizedBox(width: 12),
                  _buildAvatar(small: true),
                  const SizedBox(width: 12),
                  Expanded(child: _buildName(alignLeft: true)),
                  if (widget.member.inputDisabled)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.mic_off, size: 16, color: AppColors.danger),
                    ),
                  if (widget.member.outputDisabled)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child:
                          Icon(Icons.headset_off, size: 16, color: AppColors.danger),
                    ),
                  // Local Mute Indicator
                  if (!widget.isMe && widget.provider.isPeerMuted(widget.member.uid))
                     const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.volume_off, size: 16, color: AppColors.warning),
                    ),
                  // Screen Share Indicator
                  if (widget.provider.remoteScreenStreams.containsKey(widget.member.uid))
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GestureDetector(
                        onTap: () {
                          widget.provider.setViewingScreenShare(widget.member.uid);
                        },
                        child: Icon(
                          Icons.screen_share,
                          size: 16,
                          color: widget.provider.viewingScreenShareUid == widget.member.uid
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAvatar(),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildName(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAvatar({bool small = false}) {
    final size = small ? 48.0 : 64.0;
    final radius = small ? 20.0 : 22.0;
    final fontSize = small ? 16.0 : 18.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Speaking Ripple Animation (Halo Effect)
          if (widget.isSpeaking)
            Positioned(
              left: -10,
              right: -10,
              top: -10,
              bottom: -10,
              child: CustomPaint(
                painter: _RipplePainter(
                  animation: _controller,
                  color: AppColors.success,
                ),
              ),
            ),

          // Avatar Circle
          Container(
            padding: const EdgeInsets.all(2), // Border space
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: widget.isSpeaking
                  ? Border.all(color: AppColors.success, width: 2)
                  : null,
            ),
            child: CircleAvatar(
              radius: radius,
              backgroundColor: Colors.primaries[widget.member.uid.hashCode %
                  Colors.primaries.length],
              child: Text(
                widget.member.name.isNotEmpty
                    ? widget.member.name[0].toUpperCase()
                    : "?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Status Icons (Muted/Deafened/LocalMuted)
          if (!widget.isVertical &&
              (widget.member.inputDisabled || widget.member.outputDisabled || (!widget.isMe && widget.provider.isPeerMuted(widget.member.uid))))
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.bgPrimary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.member.inputDisabled)
                      const Icon(
                        Icons.mic_off,
                        size: 14,
                        color: AppColors.danger,
                      ),
                    if (widget.member.inputDisabled && (widget.member.outputDisabled || (!widget.isMe && widget.provider.isPeerMuted(widget.member.uid))))
                      const SizedBox(width: 2),
                    if (widget.member.outputDisabled)
                      const Icon(
                        Icons.headset_off,
                        size: 14,
                        color: AppColors.danger,
                      ),
                    if (widget.member.outputDisabled && (!widget.isMe && widget.provider.isPeerMuted(widget.member.uid)))
                       const SizedBox(width: 2),
                    if (!widget.isMe && widget.provider.isPeerMuted(widget.member.uid))
                       const Icon(
                        Icons.volume_off,
                        size: 14,
                        color: AppColors.warning,
                      ),
                    if (widget.provider.remoteScreenStreams.containsKey(widget.member.uid)) ...[
                       const SizedBox(width: 2),
                       GestureDetector(
                         onTap: () => widget.provider.setViewingScreenShare(widget.member.uid),
                         child: Icon(
                            Icons.screen_share,
                            size: 14,
                            color: widget.provider.viewingScreenShareUid == widget.member.uid
                                 ? AppColors.accent
                                 : AppColors.textSecondary,
                          ),
                       ),
                     ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildName({bool alignLeft = false}) {
    final latency = widget.member.latency;
    // Treat invalid latency as -1
    final displayLatency = latency <= 0 ? -1 : latency;
    
    Color latencyColor = AppColors.success;
    IconData latencyIcon = Icons.signal_cellular_alt;
    
    if (displayLatency > 200 && displayLatency != -1) {
      latencyColor = AppColors.danger;
      latencyIcon = Icons.signal_cellular_connected_no_internet_4_bar;
    } else if (displayLatency > 100 && displayLatency != -1) {
      latencyColor = AppColors.warning;
      latencyIcon = Icons.signal_cellular_alt_2_bar;
    }

    // Only show icon if latency is bad (Yellow/Red)
    // If Green (<=100) or Unknown (-1), hide icon.
    final bool showIcon = (displayLatency > 100 && displayLatency != -1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignLeft ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            widget.member.name,
            style: TextStyle(
              color: widget.isMe ? AppColors.selfHighlight : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: widget.isMe ? FontWeight.w600 : FontWeight.normal,
              fontFamilyFallback: const [
                'Microsoft YaHei',
                'Segoe UI Emoji',
                'Segoe UI Symbol',
                'Noto Color Emoji',
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showIcon) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: "${displayLatency}ms",
            child: Icon(
              latencyIcon,
              size: 12,
              color: latencyColor,
            ),
          ),
        ],
      ],
    );
  }

  void _showContextMenu(BuildContext context, TapDownDetails details) {
    final items = <PopupMenuEntry<String>>[];

    if (widget.isMe) {
      items.add(
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
        ),
      );
    } else {
       final isMuted = widget.provider.isPeerMuted(widget.member.uid);
       items.add(
         PopupMenuItem(
           value: 'mute',
           child: Row(
             children: [
               Icon(isMuted ? Icons.volume_off : Icons.volume_up, size: 16, color: isMuted ? AppColors.warning : null),
               SizedBox(width: 8),
               Text(isMuted ? 'Unmute' : 'Mute'),
             ],
           ),
         ),
       );
       items.add(
         const PopupMenuItem(
           value: 'volume',
           child: Row(
             children: [
               Icon(Icons.tune, size: 16),
               SizedBox(width: 8),
               Text('Volume'),
             ],
           ),
         ),
       );
    }

    items.add(
      const PopupMenuItem(
        value: 'info',
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16),
            SizedBox(width: 8),
            Text('Info'),
          ],
        ),
      ),
    );

    if (widget.provider.isAdmin && !widget.isMe) {
       items.add(const PopupMenuDivider());
       items.add(
         const PopupMenuItem(
           value: 'admin_kick',
           child: Row(
             children: [
               Icon(Icons.remove_circle, size: 16, color: AppColors.danger),
               SizedBox(width: 8),
               Text('Kick User', style: TextStyle(color: AppColors.danger)),
             ],
           ),
         ),
       );
       items.add(
         PopupMenuItem(
           value: 'admin_mute',
           child: Row(
             children: [
               Icon(widget.member.inputDisabled ? Icons.mic : Icons.mic_off, size: 16, color: AppColors.warning),
               SizedBox(width: 8),
               Text(widget.member.inputDisabled ? 'Admin Unmute' : 'Admin Mute', style: TextStyle(color: AppColors.warning)),
             ],
           ),
         ),
       );

       if (widget.provider.adminRole == 'owner') {
         if (widget.member.role == 'admin' || widget.member.role == 'owner') {
           items.add(
             const PopupMenuItem(
               value: 'admin_revoke',
               child: Row(
                 children: [
                   Icon(Icons.remove_moderator, size: 16, color: AppColors.danger),
                   SizedBox(width: 8),
                   Text('Revoke Admin', style: TextStyle(color: AppColors.danger)),
                 ],
               ),
             ),
           );
         } else {
           items.add(
             const PopupMenuItem(
               value: 'admin_grant',
               child: Row(
                 children: [
                   Icon(Icons.admin_panel_settings, size: 16, color: AppColors.accent),
                   SizedBox(width: 8),
                   Text('Grant Admin', style: TextStyle(color: AppColors.accent)),
                 ],
               ),
             ),
           );
         }
       }
    }

    showMenu(
      context: context,
      color: AppColors.bgTertiary,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: items,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).then((value) {
      if (!context.mounted) return;
      if (value == 'rename') {
        _showRenameDialog(context);
      } else if (value == 'info') {
        showDialog(
          context: context,
          builder: (context) =>
              UserInfoDialog(uid: widget.member.uid, name: widget.member.name),
        );
      } else if (value == 'mute') {
        widget.provider.togglePeerMute(widget.member.uid);
      } else if (value == 'volume') {
        _showVolumeDialog(context);
      } else if (value == 'admin_kick') {
         widget.provider.adminKick(widget.member.uid);
      } else if (value == 'admin_mute') {
         widget.provider.adminMute(widget.member.uid, !widget.member.inputDisabled);
      } else if (value == 'admin_grant') {
         widget.provider.adminGrantUser(widget.member.uid);
      } else if (value == 'admin_revoke') {
         widget.provider.adminRevokeUser(widget.member.uid);
      }
    });
  }

  void _showVolumeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        double currentVol = widget.provider.getPeerVolume(widget.member.uid);
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.bgSecondary,
              title: Text(
                "Adjust Volume: ${widget.member.name}",
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                       const Icon(Icons.volume_down, size: 16, color: AppColors.textSecondary),
                       Expanded(
                         child: SliderTheme(
                           data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.accent,
                              inactiveTrackColor: AppColors.bgTertiary,
                              thumbColor: AppColors.textPrimary,
                           ),
                           child: Slider(
                            value: currentVol,
                            min: 0.0,
                            max: 2.0, // Up to 200%
                            divisions: 20,
                            label: "${(currentVol * 100).toInt()}%",
                            onChanged: (val) {
                              setState(() {
                                currentVol = val;
                              });
                              widget.provider.setPeerVolume(widget.member.uid, val);
                            },
                           ),
                         ),
                       ),
                       const Icon(Icons.volume_up, size: 16, color: AppColors.textSecondary),
                    ],
                  ),
                  Text(
                    "${(currentVol * 100).toInt()}%",
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Done", style: TextStyle(color: AppColors.accent)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.provider.currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          "Rename",
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontFamilyFallback: [
              'Microsoft YaHei',
              'Segoe UI Emoji',
              'Segoe UI Symbol',
              'Noto Color Emoji',
            ],
          ),
          decoration: InputDecoration(
            hintText: "Enter new name",
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.bgPrimary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text(
              "Cancel",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              "Save",
              style: TextStyle(color: AppColors.accent),
            ),
            onPressed: () {
              widget.provider.rename(controller.text.trim());
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;

  _RipplePainter({required this.animation, required this.color})
    : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Adjust radius for the larger canvas (since we expanded the stack item)
    // The avatar radius is ~32 (for large). 
    // We want ripple to start around 32 and go out to 40+.
    // Size here is the size of the CustomPaint area (size + 20 padding).
    
    final radius = (size.width / 2) * 0.6; // Approx match inner avatar
    final maxRadius = size.width / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw 3 expanding rings
    for (int i = 0; i < 3; i++) {
      final double waveOffset = i * 0.33;
      double progress = (animation.value + waveOffset) % 1.0;

      // Calculate current radius and opacity
      final currentRadius = radius + (maxRadius - radius) * progress;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      // Use a gradient-like effect or just solid color with opacity
      paint.color = color.withValues(alpha: opacity * 0.8);
      paint.strokeWidth =
          2.0 + (2.0 * (1.0 - progress)); // Thinner as it expands

      canvas.drawCircle(center, currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
