import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../theme/app_colors.dart';

import '../widgets/app_menu_actions.dart';
import 'main_screen.dart';
import 'components/custom_title_bar.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _serverController;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<CallProvider>(context, listen: false);

    // Initialize with provider values if available, otherwise default
    String initServer = provider.currentServer;

    if (initServer.isEmpty) {
      if (kIsWeb) {
        final uri = Uri.base;
        if (uri.host.isNotEmpty) {
          initServer = uri.host;
          if (uri.hasPort && uri.port != 80 && uri.port != 443) {
            initServer = "$initServer:${uri.port}";
          }
        }
      }

      if (initServer.isEmpty) {
        const envServer = String.fromEnvironment('DEFAULT_SERVER');
        if (envServer.isNotEmpty) {
          initServer = envServer;
        } else {
          initServer = "127.0.0.1";
        }
      }
    }

    String initName = provider.currentName;
    if (initName.isEmpty) initName = "User";

    _serverController = TextEditingController(text: initServer);
    _nameController = TextEditingController(text: initName);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CallProvider>(context);
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);

    // Auto-navigate if connected
    if (provider.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Use pushReplacement to replace ConnectScreen with MainScreen
        // Check if we are already navigating to avoid loop (though postFrameCallback usually safe)
        if (ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text(
                "WeSpeek Connect",
                style: TextStyle(color: AppColors.textPrimary),
              ),
              backgroundColor: AppColors.bgSecondary,
              iconTheme: const IconThemeData(color: AppColors.textPrimary),
              actions: AppMenuActions.buildActions(context),
            ),
      body: Column(
        children: [
          if (isDesktop) const CustomTitleBar(),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo-universal.png',
                      height: 80,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.headset,
                        size: 80,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildTextField(
                      controller: _serverController,
                      label: "Server Address",
                      hint: "example.com:7000",
                      icon: Icons.dns,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _nameController,
                      label: "Nickname",
                      hint: "Your Name",
                      icon: Icons.person,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          String uid = provider.currentUid;
                          if (uid.isEmpty) {
                            // 使用uuid生成持久化的uid
                            uid = const Uuid().v4();
                          }
                          provider.connectServer(
                            _serverController.text,
                            _nameController.text,
                            uid,
                          );
                        },
                        child: const Text(
                          "Connect",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (provider.status == "Connecting to server...")
                      const SizedBox(
                        height: 24,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accent,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              "正在连接服务器...",
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    if (provider.status == "无法连接到服务器")
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "无法连接到服务器",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.danger,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "请检查以下事项：",
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            _buildErrorItem(
                              "• 确认地址格式，如 ws://主机:端口 或 wss://主机 或者直接输入 域名（IP）",
                            ),
                            _buildErrorItem("• 后端服务已启动且端口开放"),
                            _buildErrorItem("• 设备与服务器在同一网络，或使用公网可达地址"),
                            _buildErrorItem("• 若使用 HTTPS/WSS，证书已正确配置"),
                            _buildErrorItem(
                                "• Windows 防火墙可能阻止连接，请允许应用访问网络"),
                            const SizedBox(height: 8),
                            Theme(
                              data: Theme.of(
                                context,
                              ).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text(
                                  "查看详细错误",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.accent,
                                  ),
                                ),
                                iconColor: AppColors.accent,
                                collapsedIconColor: AppColors.accent,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.bgTertiary,
                                      border: Border.all(
                                        color: AppColors.danger.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      Provider.of<CallProvider>(
                                        context,
                                        listen: false,
                                      ).lastError,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.bgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }

  Widget _buildErrorItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}
