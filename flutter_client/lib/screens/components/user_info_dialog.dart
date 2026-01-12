import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/call_provider.dart';
import '../../theme/app_colors.dart';

class UserInfoDialog extends StatefulWidget {
  final String uid;
  final String name;

  const UserInfoDialog({super.key, required this.uid, required this.name});

  @override
  State<UserInfoDialog> createState() => _UserInfoDialogState();
}

class _UserInfoDialogState extends State<UserInfoDialog> {
  Timer? _refreshTimer;
  Map<String, dynamic>? _lastStatsData;
  DateTime? _lastStatsTime;

  // Rate calculation state
  double _rxRate = 0;
  double _txRate = 0;

  // Loss calculation history (1-minute window)
  final List<Map<String, dynamic>> _statsHistory = [];

  @override
  void initState() {
    super.initState();
    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });

    // Poll every 1 second
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _fetchData();
    });
  }

  void _fetchData() {
    if (!mounted) return;
    final provider = Provider.of<CallProvider>(context, listen: false);
    provider.fetchUserInfo(widget.uid);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _formatBytes(num bytes) {
    if (bytes > 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    if (bytes > 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${bytes.toStringAsFixed(1)} B';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, provider, child) {
        // Get Latency from member list (real-time)
        int latency = 0;
        final room = provider.getRoomById(provider.currentRoomId);
        if (room != null) {
          final member = room.members.firstWhere(
            (m) => m.uid == widget.uid,
            orElse: () => room
                .members
                .first, // Fallback, though unlikely if list didn't change
          );
          if (member.uid == widget.uid) {
            latency = member.latency;
          }
        }

        // Get Extended Info (IP, Stats)
        final info = provider.lastUserInfo;
        final isCurrentInfo = info['uid'] == widget.uid;

        String ip = "Unknown";
        Map<String, dynamic>? stats;

        if (isCurrentInfo) {
          ip = info['ip'] ?? "Unknown";
          stats = info['stats'];

          if (stats != null) {
            _updateRates(stats);
          }
        }

        // Parse Stats
        // Server Perspective:
        // packetsReceived = Upload (from client)
        // packetsSent = Download (to client)
        final rx = stats?['packetsSent'] ?? 0;
        final tx = stats?['packetsReceived'] ?? 0;
        final rxBytes = stats?['bytesSent'] ?? 0;
        final txBytes = stats?['bytesReceived'] ?? 0;

        // Loss Calculation
        String lossText = "0.00%";
        if (stats != null) {
          lossText = _calculateLoss(stats);
        }

        return AlertDialog(
          backgroundColor: AppColors.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.bgPrimary, width: 1),
              ),
            ),
            padding: const EdgeInsets.only(bottom: 8),
            child: const Text(
              "客户端连接信息",
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 550
                ? 500
                : MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection("基本信息", [
                    _buildRow("用户", widget.name),
                    _buildRow("UID", widget.uid),
                    _buildRow("延迟 (RTT)", "$latency ms"),
                    if (isCurrentInfo && provider.isAdmin) _buildRow("IP 地址", ip),
                  ]),
                  const SizedBox(height: 16),
                  if (stats != null)
                    _buildSection("网络统计", [
                      _buildRow("接收", "$rx pkts (${_formatBytes(rxBytes)})"),
                      _buildRow("下载速率", "${_formatBytes(_rxRate)}/s"),
                      _buildRow("发送", "$tx pkts (${_formatBytes(txBytes)})"),
                      _buildRow("上传速率", "${_formatBytes(_txRate)}/s"),
                      _buildRow("丢包率 (下行)", lossText),
                    ]),
                  if (!isCurrentInfo)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "关闭",
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  void _updateRates(Map<String, dynamic> currentStats) {
    final now = DateTime.now();
    if (_lastStatsData != null && _lastStatsTime != null) {
      final dt = now.difference(_lastStatsTime!).inMilliseconds / 1000.0;
      if (dt > 0 && dt < 10) {
        final prevRx = _lastStatsData!['bytesSent'] ?? 0;
        final prevTx = _lastStatsData!['bytesReceived'] ?? 0;
        final curRx = currentStats['bytesSent'] ?? 0;
        final curTx = currentStats['bytesReceived'] ?? 0;

        if (curRx >= prevRx) {
          _rxRate = (curRx - prevRx) / dt;
        }
        if (curTx >= prevTx) {
          _txRate = (curTx - prevTx) / dt;
        }
      }
    }
    _lastStatsData = currentStats;
    _lastStatsTime = now;
  }

  String _calculateLoss(Map<String, dynamic> currentStats) {
    final now = DateTime.now();
    _statsHistory.add({'time': now, 'stats': currentStats});

    // Keep 60 seconds history
    _statsHistory.removeWhere(
      (item) => now.difference(item['time'] as DateTime).inSeconds > 60,
    );

    if (_statsHistory.length > 1) {
      final newest = _statsHistory.last['stats'];
      final oldest = _statsHistory.first['stats'];

      final windowRx =
          (newest['packetsSent'] ?? 0) - (oldest['packetsSent'] ?? 0);
      final windowLost =
          (newest['sentPacketsLost'] ?? 0) - (oldest['sentPacketsLost'] ?? 0);

      if (windowRx + windowLost > 0) {
        return "${((windowLost / (windowRx + windowLost)) * 100).toStringAsFixed(2)}%";
      }
    } else {
      // Fallback to cumulative
      final rx = currentStats['packetsSent'] ?? 0;
      final lost = currentStats['sentPacketsLost'] ?? 0;
      if (rx + lost > 0) {
        return "${((lost / (rx + lost)) * 100).toStringAsFixed(2)}%";
      }
    }
    return "0.00%";
  }

  Widget _buildSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const Divider(color: AppColors.bgPrimary, height: 8),
        ...rows,
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              "$label:",
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
