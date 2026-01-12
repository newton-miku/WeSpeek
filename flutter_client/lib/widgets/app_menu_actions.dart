import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../screens/settings_screen.dart';
import '../theme/app_colors.dart';

class AppMenuActions {
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev-debug',
  );

  static List<Widget> buildActions(BuildContext context) {
    final provider = Provider.of<CallProvider>(context);
    
    return [
      if (provider.isConnected)
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.redAccent),
          tooltip: "断开服务器",
          onPressed: () => provider.disconnect(),
        ),
      IconButton(
        icon: const Icon(Icons.settings, color: AppColors.textPrimary),
        tooltip: "设置",
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        },
      ),
    ];
  }
}
