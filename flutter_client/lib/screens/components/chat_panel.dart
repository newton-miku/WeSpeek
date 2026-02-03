import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../providers/call_provider.dart';
import '../../models/chat_message.dart';
import '../../theme/app_colors.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  bool _isPublic = true;
  bool _showEmoji = false;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() => _showEmoji = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (publicVer, roomVer, rosterVer, isInCall, currentRoomId) = context
        .select<CallProvider, (int, int, int, bool, String)>(
          (p) => (
            p.publicChatVersion,
            p.roomChatVersion,
            p.rosterVersion,
            p.isInCall,
            p.currentRoomId,
          ),
        );

    // If we are no longer in a call or have no room ID, force switch to public chat
    if ((!isInCall || currentRoomId.isEmpty) && !_isPublic) {
      _isPublic = true;
    }

    final provider = context.read<CallProvider>();
    final messages = _isPublic
        ? provider.publicMessages
        : provider.roomMessages;

    // Auto scroll to bottom when messages change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (_scrollController.offset < 100) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });

    return Column(
      children: [
        // Tabs
        Container(
          height: 48,
          decoration: const BoxDecoration(
            color: AppColors.bgSecondary,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              _TabButton(
                text: "服务器大厅聊天",
                isActive: _isPublic,
                onTap: () => setState(() => _isPublic = true),
              ),
              if (isInCall && currentRoomId.isNotEmpty)
                _TabButton(
                  text: currentRoomId,
                  isActive: !_isPublic,
                  onTap: () => setState(() => _isPublic = false),
                ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: Container(
            color: AppColors.bgPrimary,
            child: ListView.builder(
              reverse: true, // Anchor to bottom
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                // Reverse index to get correct message order (Newest at 0)
                final msg = messages[messages.length - 1 - index];

                // Get display name (prefer current room member name if available)
                final displayName = provider.getUserName(msg.uid) ?? msg.name;

                final time = DateTime.fromMillisecondsSinceEpoch(
                  msg.time * 1000,
                );
                final now = DateTime.now();
                final isToday =
                    time.year == now.year &&
                    time.month == now.month &&
                    time.day == now.day;

                String timeStr;
                if (isToday) {
                  timeStr =
                      "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
                } else {
                  timeStr =
                      "${time.year}年${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              Colors.primaries[getStableHashCode(displayName) %
                                  Colors.primaries.length],
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : "?",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Name + Time
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    timeStr,
                                    style: const TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Message Body
                            _MessageContent(
                              msg: msg,
                              provider: provider,
                              baseUrl: provider.httpBaseUrl,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        // Input
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.bgSecondary,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.bgTertiary,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _pickImage(provider),
                  color: AppColors.textSecondary,
                  tooltip: "发送图片",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.keyV,
                        control: true,
                      ): () =>
                          _handlePaste(provider),
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
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
                        hintText:
                            "发送消息到 ${_isPublic ? '服务器大厅' : (currentRoomId.isNotEmpty ? currentRoomId : '频道')}...",
                        hintStyle: const TextStyle(
                          color: AppColors.textTertiary,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(provider),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  onPressed: () {
                    setState(() {
                      _showEmoji = !_showEmoji;
                      if (_showEmoji) {
                        _focusNode.unfocus();
                      }
                    });
                  },
                  color: _showEmoji
                      ? AppColors.accent
                      : AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () => _sendMessage(provider),
                  color: AppColors.accent,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showEmoji)
          SizedBox(
            height: 250,
            child: EmojiPicker(
              textEditingController: _controller,
              config: Config(
                height: 250,
                checkPlatformCompatibility: true,
                emojiViewConfig: const EmojiViewConfig(
                  emojiSizeMax: 28,
                  backgroundColor: AppColors.bgSecondary,
                  columns: 7,
                ),
                categoryViewConfig: const CategoryViewConfig(
                  backgroundColor: AppColors.bgSecondary,
                  indicatorColor: AppColors.accent,
                  iconColor: AppColors.textTertiary,
                  iconColorSelected: AppColors.accent,
                ),
                bottomActionBarConfig: const BottomActionBarConfig(
                  backgroundColor: AppColors.bgSecondary,
                  buttonColor: AppColors.bgSecondary,
                  buttonIconColor: AppColors.textTertiary,
                ),
                searchViewConfig: const SearchViewConfig(
                  backgroundColor: AppColors.bgSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _sendMessage(CallProvider provider) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (_isPublic) {
      provider.sendPublicChat(text);
    } else {
      provider.sendRoomChat(text);
    }
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _pickImage(CallProvider provider) async {
    try {
      FilePickerResult? result;

      // file_picker 8.x API: use FilePicker.platform
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;

        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        if (bytes != null) {
          final base64Image = base64Encode(bytes);
          final extension = file.extension ?? "png";
          final mimeType = lookupMimeType(file.name) ?? "image/$extension";
          final msg = "data:$mimeType;base64,$base64Image";

          if (_isPublic) {
            provider.sendPublicChat(msg);
          } else {
            provider.sendRoomChat(msg);
          }
        }
      }
    } catch (e) {
      debugPrint("Pick image error: $e");
    }
  }

  Future<void> _handlePaste(CallProvider provider) async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        if (!mounted) return;
        final shouldSend = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF333333),
            title: const Text(
              "发送剪贴板图片?",
              style: TextStyle(color: Colors.white),
            ),
            content: Image.memory(imageBytes, height: 200, fit: BoxFit.contain),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("取消"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("发送"),
              ),
            ],
          ),
        );

        if (shouldSend == true) {
          final base64Image = base64Encode(imageBytes);
          final msg = "data:image/png;base64,$base64Image";
          if (_isPublic) {
            provider.sendPublicChat(msg);
          } else {
            provider.sendRoomChat(msg);
          }
        }
        return;
      }
    } catch (e) {
      debugPrint("Paste image error: $e");
    }

    // Fallback to text paste
    final text = await Clipboard.getData(Clipboard.kTextPlain);
    if (text != null && text.text != null && text.text!.isNotEmpty) {
      final content = text.text!;
      final selection = _controller.selection;
      if (selection.isValid) {
        final newText = _controller.text.replaceRange(
          selection.start,
          selection.end,
          content,
        );
        _controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
            offset: selection.start + content.length,
          ),
        );
      } else {
        _controller.text += content;
      }
    }
  }
}

class _TabButton extends StatelessWidget {
  final String text;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.text,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? AppColors.accent : AppColors.textTertiary,
            fontWeight: FontWeight.bold,
            fontFamilyFallback: const [
              'Microsoft YaHei',
              'Segoe UI Emoji',
              'Segoe UI Symbol',
              'Noto Color Emoji',
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  final ChatMessage msg;
  final CallProvider provider;
  final String baseUrl;

  const _MessageContent({
    required this.msg,
    required this.provider,
    required this.baseUrl,
  });

  bool get _canRevoke {
    if (provider.isAdmin) return true;
    if (msg.uid == provider.currentUid) {
      final msgTime = DateTime.fromMillisecondsSinceEpoch(msg.time * 1000);
      return DateTime.now().difference(msgTime).inMinutes < 2;
    }
    return false;
  }

  void _handleRevoke(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("撤回消息", style: TextStyle(color: Colors.white)),
        content: const Text(
          "确定要撤回这条消息吗？",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.revokeMessage(msg.id);
            },
            child: const Text("撤回", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = msg.text;
    if (text.startsWith("image:")) {
      final path = text.substring(6);
      final cleanBase = baseUrl.endsWith("/")
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final cleanPath = path.startsWith("/") ? path : "/$path";
      final fullUrl = "$cleanBase$cleanPath";

      return GestureDetector(
        onTap: () => _showFullScreenImage(context, Image.network(fullUrl)),
        onSecondaryTapUp: (details) {
          _showImageMenu(context, details.globalPosition, fullUrl);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            fullUrl,
            width: 200,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => _buildError(),
          ),
        ),
      );
    } else if (text.startsWith("data:image/")) {
      try {
        final commaIndex = text.indexOf(',');
        if (commaIndex > 0) {
          final base64Str = text.substring(commaIndex + 1);
          final bytes = base64Decode(base64Str);
          return GestureDetector(
            onTap: () => _showFullScreenImage(context, Image.memory(bytes)),
            onSecondaryTapUp: (details) {
              _showImageMenu(
                context,
                details.globalPosition,
                null,
                bytes: bytes,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                width: 200,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => _buildError(),
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint("Image decode error: $e");
      }
    }

    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showTextMenu(context, details.globalPosition, text);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgTertiary,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SelectableText(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            height: 1.4,
          ),
          contextMenuBuilder: (context, editableTextState) {
            final List<ContextMenuButtonItem> buttonItems =
                editableTextState.contextMenuButtonItems;
            // Remove "Share" etc if needed
            buttonItems.removeWhere(
              (item) =>
                  item.type != ContextMenuButtonType.copy &&
                  item.type != ContextMenuButtonType.selectAll,
            );

            if (_canRevoke) {
              buttonItems.add(
                ContextMenuButtonItem(
                  onPressed: () {
                    editableTextState.hideToolbar();
                    _handleRevoke(context);
                  },
                  type: ContextMenuButtonType.custom,
                  label: '撤回',
                ),
              );
            }
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: buttonItems,
            );
          },
        ),
      ),
    );
  }

  Widget _buildError() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.broken_image, color: AppColors.textTertiary),
        Text(
          "图片加载失败",
          style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
        ),
      ],
    );
  }

  void _showFullScreenImage(BuildContext context, Widget imageWidget) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(minScale: 0.5, maxScale: 4.0, child: imageWidget),
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTextMenu(BuildContext context, Offset position, String text) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: const Text('复制'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已复制到剪贴板'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        if (_canRevoke)
          PopupMenuItem(
            value: 'revoke',
            child: const Text('撤回消息', style: TextStyle(color: Colors.red)),
            onTap: () {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (context.mounted) _handleRevoke(context);
              });
            },
          ),
      ],
    );
  }

  void _showImageMenu(
    BuildContext context,
    Offset position,
    String? url, {
    Uint8List? bytes,
  }) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (url != null)
          PopupMenuItem(
            value: 'copy_link',
            child: const Text('复制图片链接'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('链接已复制'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        PopupMenuItem(
          value: 'copy_image',
          child: const Text('复制图片'),
          onTap: () async {
            try {
              Uint8List? imageBytes = bytes;
              if (imageBytes == null && url != null) {
                final response = await http.get(Uri.parse(url));
                if (response.statusCode == 200) {
                  imageBytes = response.bodyBytes;
                }
              }

              if (imageBytes != null) {
                await Pasteboard.writeImage(imageBytes);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('图片已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              }
            } catch (e) {
              debugPrint("Copy image error: $e");
            }
          },
        ),
        if (_canRevoke)
          PopupMenuItem(
            value: 'revoke',
            child: const Text('撤回消息', style: TextStyle(color: Colors.red)),
            onTap: () {
              // Delay slightly to allow menu to close
              Future.delayed(const Duration(milliseconds: 100), () {
                if (context.mounted) _handleRevoke(context);
              });
            },
          ),
      ],
    );
  }
}

// 跨平台一致的简单哈希函数
int getStableHashCode(String str) {
  int hash = 0;
  for (var code in str.codeUnits) {
    hash += code;
  }
  return hash;
}
