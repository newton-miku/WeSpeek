import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../services/admin_service.dart';
import '../models/admin_stats.dart';

class AdminStatusScreen extends StatefulWidget {
  const AdminStatusScreen({super.key});

  @override
  State<AdminStatusScreen> createState() => _AdminStatusScreenState();
}

class _AdminStatusScreenState extends State<AdminStatusScreen> {
  String? _lastAdminKey;
  ServerStats? _stats;
  bool _isLoading = false;
  String _error = '';
  Timer? _timer;
  AdminService? _adminService;
  final TextEditingController _keyController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<CallProvider>(context);

    if (_adminService == null ||
        _adminService!.baseUrl != provider.httpBaseUrl) {
      _adminService = AdminService(provider.httpBaseUrl);
    }

    if (provider.adminKey != _lastAdminKey) {
      _lastAdminKey = provider.adminKey;
      if (_lastAdminKey != null) {
        _startAutoRefresh();
      } else {
        _timer?.cancel();
        _timer = null;
        if (mounted) {
          setState(() {
            _stats = null;
            _error = '';
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _fetchStats() async {
    if (_lastAdminKey == null || _lastAdminKey!.isEmpty) return;
    if (_adminService == null) return;

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final stats = await _adminService!.fetchServerStats(_lastAdminKey!);
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          if (e.toString().contains("Unauthorized")) {
            _timer?.cancel();
            _timer = null;
          }
        });
      }
    }
  }

  void _startAutoRefresh() {
    _timer?.cancel();
    _fetchStats();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_lastAdminKey != null) {
        _fetchStatsSilently();
      }
    });
  }

  Future<void> _fetchStatsSilently() async {
    if (_adminService == null || _lastAdminKey == null) return;
    try {
      final stats = await _adminService!.fetchServerStats(_lastAdminKey!);
      if (mounted) {
        setState(() {
          _stats = stats;
        });
      }
    } catch (e) {
      // silently fail
    }
  }

  void _onLogin() {
    if (_keyController.text.isEmpty) return;
    Provider.of<CallProvider>(
      context,
      listen: false,
    ).setAdminIdentity(_keyController.text);
    // didChangeDependencies will trigger refresh
  }

  void _onLogout() {
    Provider.of<CallProvider>(context, listen: false).logoutAdmin();
    // didChangeDependencies will trigger cleanup
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(1)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final secs = duration.inSeconds % 60;
    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h ${minutes}m ${secs}s';
    return '${minutes}m ${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Status'),
        actions: [
          if (_lastAdminKey != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _onLogout,
              tooltip: "修改管理员密钥",
            ),
        ],
      ),
      body: _lastAdminKey == null ? _buildLogin() : _buildDashboard(),
    );
  }

  Widget _buildLogin() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "管理员访问",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _keyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "管理员密钥",
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _onLogin(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onLogin,
                    child: const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Text("连接"),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    if (_isLoading && _stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty && _stats == null) {
      return Center(
        child: Text(
          "Error: $_error",
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (_stats == null) {
      return const Center(child: Text("暂无数据"));
    }

    final s = _stats!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGridSummary(s),
          const SizedBox(height: 24),
          const Text(
            "系统资源",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildSystemStats(s),
          const SizedBox(height: 24),
          const Text(
            "活跃房间",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildRoomList(s),
        ],
      ),
    );
  }

  Widget _buildGridSummary(ServerStats s) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildInfoCard("在线用户", "${s.peerCount}", Icons.people, Colors.blue),
        _buildInfoCard(
          "房间",
          "${s.roomCount}",
          Icons.meeting_room,
          Colors.green,
        ),
        _buildInfoCard(
          "运行时间",
          _formatDuration(s.uptime),
          Icons.timer,
          Colors.orange,
        ),
        _buildInfoCard(
          "平均延迟",
          "${s.avgPing.toStringAsFixed(1)} ms",
          Icons.network_check,
          Colors.purple,
        ),
        _buildInfoCard(
          "入站流量",
          _formatBytes(s.totalBytesReceived),
          Icons.download,
          Colors.teal,
        ),
        _buildInfoCard(
          "出站流量",
          _formatBytes(s.totalBytesSent),
          Icons.upload,
          Colors.teal,
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(title, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemStats(ServerStats s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildRow("协程数", "${s.goroutineCount}"),
            const Divider(),
            _buildRow("已分配内存", _formatBytes(s.allocMemory)),
            const Divider(),
            _buildRow("总分配内存", _formatBytes(s.totalAllocMemory)),
            const Divider(),
            _buildRow("系统内存", _formatBytes(s.sysMemory)),
            const Divider(),
            _buildRow("发送数据包", "${s.totalPacketsSent}"),
            const Divider(),
            _buildRow("丢失数据包", "${s.totalPacketsLost}"),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRoomList(ServerStats s) {
    if (s.rooms.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text("暂无活跃房间")),
      );
    }
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: s.rooms.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final r = s.rooms[index];
          return ListTile(
            title: Text(r.name.isEmpty ? r.id : r.name),
            subtitle: Text("ID: ${r.id}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${r.peerCount} peers"),
                Text("${r.avgPing.toStringAsFixed(1)} ms"),
              ],
            ),
          );
        },
      ),
    );
  }
}
