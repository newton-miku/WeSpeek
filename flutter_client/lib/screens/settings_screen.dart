import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../services/audio_service.dart';
import '../theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedIndex = 0;

  final List<(String, IconData)> _tabs = [
    ("音频设置", Icons.volume_up),
    ("服务器状态", Icons.dns),
    ("关于 WeSpeek", Icons.info_outline),
  ];

  @override
  Widget build(BuildContext context) {
    // Get screen width to determine layout
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768; // Consider mobile if width < 768px

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppColors.bgSecondary,
              title: const Text(
                "设置",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              elevation: 0,
            )
          : null,
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Sidebar
        Container(
          width: 250,
          color: AppColors.bgSecondary,
          child: Column(
            children: [
              // Title Area
              Container(
                height: 60,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: const Text(
                  "设置",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              // Navigation Items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: _tabs.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedIndex == index;
                    final (label, icon) = _tabs[index];
                    return InkWell(
                      onTap: () => setState(() => _selectedIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accent.withAlpha(25)
                              : Colors.transparent,
                          border: Border(
                            left: BorderSide(
                              color: isSelected
                                  ? AppColors.accent
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              label,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Back Button (Bottom of Sidebar)
              const Divider(height: 1, color: AppColors.border),
              ListTile(
                leading: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textSecondary,
                ),
                title: const Text(
                  "返回",
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        // Vertical Divider
        Container(width: 1, color: AppColors.border),
        // Right Content Area
        Expanded(
          child: Container(
            color: AppColors.bgPrimary,
            child: Column(
              children: [
                // Content Header (matches sidebar header height)
                Container(
                  height: 60,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                    color: AppColors.bgPrimary,
                  ),
                  child: Text(
                    _tabs[_selectedIndex].$1,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // Content Body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: _buildContent(_selectedIndex),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Mobile Navigation Tabs
        Container(
          color: AppColors.bgSecondary,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_tabs.length, (index) {
                final isSelected = _selectedIndex == index;
                final (label, icon) = _tabs[index];
                return InkWell(
                  onTap: () => setState(() => _selectedIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.border,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        // Mobile Content Area
        Expanded(
          child: Container(
            color: AppColors.bgPrimary,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildContent(_selectedIndex),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(int index) {
    switch (index) {
      case 0:
        return const AudioSettingsView();
      case 1:
        return const ServerStatusView();
      case 2:
        return const AboutSettingsView();
      default:
        return const SizedBox();
    }
  }
}

class ServerStatusView extends StatefulWidget {
  const ServerStatusView({super.key});

  @override
  State<ServerStatusView> createState() => _ServerStatusViewState();
}

class _ServerStatusViewState extends State<ServerStatusView> {
  final _passwordController = TextEditingController();
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CallProvider>();

    // Attempt to get latency if in a room
    int latency = -1;
    if (provider.isInCall) {
      final room = provider.getRoomById(provider.currentRoomId);
      if (room != null) {
        try {
          final me = room.members.firstWhere(
            (m) => m.uid == provider.currentUid,
          );
          latency = me.latency;
        } catch (_) {}
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connection Info Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.dns,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "连接概览",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: provider.isConnected
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: provider.isConnected
                            ? AppColors.success.withValues(alpha: 0.3)
                            : AppColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: provider.isConnected
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          provider.isConnected ? "已连接" : "断开",
                          style: TextStyle(
                            fontSize: 12,
                            color: provider.isConnected
                                ? AppColors.success
                                : AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1, color: AppColors.border),
              ),
              // Info Grid
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildCompactInfoItem(
                      "服务器地址",
                      provider.currentServer.isEmpty
                          ? "-"
                          : provider.currentServer,
                      Icons.link,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildCompactInfoItem(
                      "网络延迟",
                      latency > 0
                          ? "$latency ms"
                          : (provider.isConnected ? "测速中..." : "-"),
                      Icons.speed,
                      valueColor: latency > 100 ? AppColors.warning : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildCompactInfoItem(
                      "当前身份",
                      "${provider.currentName} (${provider.currentUid})",
                      Icons.person_outline,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildCompactInfoItem(
                      "所在位置",
                      provider.isInCall
                          ? "房间: ${provider.currentRoomId}"
                          : "大厅 (未加入房间)",
                      Icons.meeting_room_outlined,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Admin Management Section
        _buildSectionTitle("管理员控制台"),

        if (provider.isAdmin) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Text(
                      provider.adminRole == 'owner'
                          ? "超级管理员 (Owner)"
                          : "普通管理员 (Admin)",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  "您已拥有此服务器的管理权限。",
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      provider.logoutAdmin();
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text("退出管理员身份"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Login Form
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "登录以管理服务器",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: "管理员密码",
                    hintText: "请输入服务器管理员密码",
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: AppColors.textSecondary,
                    ),
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_passwordController.text.isNotEmpty) {
                        provider.loginAdminWithPassword(
                          _passwordController.text,
                        );
                        _passwordController.clear();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text("登录"),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Setup Token (Collapsible)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text(
                "初始设置 (使用 Setup Token)",
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              children: [
                const SizedBox(height: 8),
                const Text(
                  "如果是首次设置服务器，请使用控制台输出的 Setup Token 获取 Owner 权限。",
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tokenController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: "Setup Token",
                          isDense: true,
                          labelStyle: TextStyle(color: AppColors.textSecondary),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.accent),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (_tokenController.text.isNotEmpty) {
                          final errorMsg = await provider.claimAdmin(
                            _tokenController.text,
                          );
                          if (errorMsg == null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("权限获取成功！")),
                            );
                            _tokenController.clear();
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("验证失败: $errorMsg")),
                            );
                          }
                        }
                      },
                      child: const Text("获取权限"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactInfoItem(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamilyFallback: const [
              'Microsoft YaHei',
              'Segoe UI Emoji',
              'Segoe UI Symbol',
              'Noto Color Emoji',
            ],
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class AudioSettingsView extends StatefulWidget {
  const AudioSettingsView({super.key});

  @override
  State<AudioSettingsView> createState() => _AudioSettingsViewState();
}

class _AudioSettingsViewState extends State<AudioSettingsView> {
  // Local state for sliders to ensure smooth UI
  late double _micGain;
  late double _speakerGain;
  late double _gateThreshold;

  // Calibration State
  double _currentLevel = 0.0;
  String _calibState = 'idle'; // idle, noise, speech
  double _calibNoiseMax = 0.0;
  double _calibSpeechMax = 0.0;
  StreamSubscription<double>? _volumeSub;
  AudioClient?
  _tempAudioClient; // Temporary audio client for calibration when not in call

  @override
  void initState() {
    super.initState();
    final provider = context.read<CallProvider>();
    _micGain = provider.micGain;
    _speakerGain = provider.speakerGain;
    _gateThreshold = provider.gateThreshold;

    // Try to use existing volume stream if available (user is in call)
    if (provider.onVolume != null) {
      _volumeSub = provider.onVolume!.listen((vol) {
        _updateVolume(vol);
      });
    }
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    _stopTempAudio();
    super.dispose();
  }

  void _updateVolume(double vol) {
    if (!mounted) return;
    setState(() {
      _currentLevel = vol;
      if (_calibState == 'noise') {
        if (vol > _calibNoiseMax) _calibNoiseMax = vol;
      } else if (_calibState == 'speech') {
        if (vol > _calibSpeechMax) _calibSpeechMax = vol;
      }
    });
  }

  Future<void> _startTempAudio() async {
    final provider = context.read<CallProvider>();

    // Only start temporary audio if not in call and no existing temp audio
    if (provider.isInCall || _tempAudioClient != null) return;

    try {
      // Initialize temporary audio client
      _tempAudioClient = AudioService(provider.currentServer);
      await _tempAudioClient!.init();

      // Configure audio settings
      if (provider.selectedInputDevice != "系统默认") {
        _tempAudioClient!.setInputDevice(provider.selectedInputDevice);
      }
      if (provider.selectedOutputDevice != "系统默认") {
        _tempAudioClient!.setOutputDevice(provider.selectedOutputDevice);
      }
      _tempAudioClient!.setMicGain(provider.micGain);
      _tempAudioClient!.setSpeakerMute(provider.isSpeakerMuted);
      _tempAudioClient!.setSpeakerGain(provider.speakerGain);
      _tempAudioClient!.setNoiseMode(provider.noiseMode);
      _tempAudioClient!.setGateThreshold(provider.gateThreshold);

      // Start listening to volume
      _volumeSub?.cancel();
      _volumeSub = _tempAudioClient!.onVolume.listen((vol) {
        _updateVolume(vol);
      });
    } catch (e) {
      // Ignore errors (e.g. no mic, permission denied)
      _tempAudioClient = null;
    }
  }

  Future<void> _stopTempAudio() async {
    if (_tempAudioClient != null) {
      await _tempAudioClient!.close();
      _tempAudioClient = null;
    }
  }

  Future<void> _startNoiseCalib() async {
    // Start temporary audio if not in call
    await _startTempAudio();

    setState(() {
      _calibState = 'noise';
      _calibNoiseMax = 0.0;
    });

    // 3 seconds timer
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _calibState != 'noise') return;
      _stopCalib();

      // Auto set threshold: noise max + 50% or at least +0.01
      // Using a slightly more aggressive multiplier to be safe
      double newThreshold = _calibNoiseMax * 1.5;
      if (newThreshold < _calibNoiseMax + 0.01) {
        newThreshold = _calibNoiseMax + 0.01;
      }
      // Clamp to range
      if (newThreshold > 0.2) newThreshold = 0.2;

      setState(() {
        _gateThreshold = newThreshold;
      });
      // Apply immediately
      context.read<CallProvider>().setGateThreshold(_gateThreshold);
    });
  }

  Future<void> _startSpeechCalib() async {
    // Start temporary audio if not in call
    await _startTempAudio();

    setState(() {
      _calibState = 'speech';
      _calibSpeechMax = 0.0;
    });
  }

  Future<void> _stopCalib() async {
    // Get provider early to avoid context issues after await
    final provider = context.read<CallProvider>();
    bool applyThreshold = false;
    double newThreshold = _gateThreshold;

    if (_calibState == 'speech' && _calibSpeechMax > 0) {
      // Auto set threshold based on speech
      // Ideally, threshold should be well below speech peak (e.g. 20-30%)
      // but above noise floor.
      newThreshold = _calibSpeechMax * 0.25;

      // If we have noise data, ensure we are above it
      if (_calibNoiseMax > 0) {
        double noiseSafe = _calibNoiseMax * 1.5;
        if (newThreshold < noiseSafe) {
          newThreshold = noiseSafe;
        }
      }

      // Ensure minimum
      if (newThreshold < 0.01) newThreshold = 0.01;
      // Clamp to range
      if (newThreshold > 0.2) newThreshold = 0.2;

      applyThreshold = true;
    }

    setState(() {
      if (applyThreshold) {
        _gateThreshold = newThreshold;
      }
      _calibState = 'idle';
    });

    // Apply threshold if changed
    if (applyThreshold) {
      provider.setGateThreshold(newThreshold);
    }

    // Stop temporary audio if it was started
    await _stopTempAudio();

    // Restore volume subscription if user is in call - check mounted first
    if (!mounted) return;
    if (provider.isInCall && provider.onVolume != null) {
      _volumeSub?.cancel();
      _volumeSub = provider.onVolume!.listen((vol) {
        _updateVolume(vol);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CallProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input Device
        if (!kIsWeb && provider.inputDevices.length > 1) ...[
          _buildSectionTitle("输入设备"),
          const SizedBox(height: 8),
          _buildDropdown(
            value: provider.inputDevices.contains(provider.selectedInputDevice)
                ? provider.selectedInputDevice
                : null,
            items: provider.inputDevices,
            onChanged: (v) {
              if (v != null) provider.setSelectedInputDevice(v);
            },
          ),
          const SizedBox(height: 24),
        ],

        // Output Device
        if (!kIsWeb && provider.outputDevices.length > 1) ...[
          _buildSectionTitle("输出设备"),
          const SizedBox(height: 8),
          _buildDropdown(
            value:
                provider.outputDevices.contains(provider.selectedOutputDevice)
                ? provider.selectedOutputDevice
                : null,
            items: provider.outputDevices,
            onChanged: (v) {
              if (v != null) provider.setSelectedOutputDevice(v);
            },
          ),
          const SizedBox(height: 24),
        ],

        // Noise Mode
        _buildSectionTitle("降噪模式"),
        const SizedBox(height: 8),
        _buildDropdown(
          value: provider.noiseMode,
          items: const ["none", "gate", "smart", "deepfilter"],
          itemLabelBuilder: (item) {
            switch (item) {
              case "none":
                return "关闭";
              case "gate":
                return "噪音门";
              case "smart":
                return "智能降噪";
              case "deepfilter":
                return "深度降噪";
              default:
                return item;
            }
          },
          onChanged: (v) {
            if (v != null) provider.setNoiseMode(v);
          },
        ),
        const SizedBox(height: 24),

        // Gate Threshold (only if gate mode)
        if (provider.noiseMode == "gate") ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle("噪音门限阈值"),
              Text(
                "${(_gateThreshold * 100).toStringAsFixed(1)}%",
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          Slider(
            value: _gateThreshold,
            min: 0.0,
            max: 0.2,
            divisions: 200,
            label: "${(_gateThreshold * 100).toStringAsFixed(1)}%",
            onChanged: (v) => setState(() => _gateThreshold = v),
            onChangeEnd: (v) => provider.setGateThreshold(v),
            activeColor: AppColors.accent,
            inactiveColor: AppColors.bgHover,
          ),

          // Level Meter
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _currentLevel.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                _currentLevel > _gateThreshold ? Colors.green : Colors.red,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Calibration Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_calibState == 'idle') ...[
                OutlinedButton.icon(
                  onPressed: () async => await _startNoiseCalib(),
                  icon: const Icon(Icons.mic_none, size: 18),
                  label: const Text("采集噪音(3s)"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async => await _startSpeechCalib(),
                  icon: const Icon(Icons.record_voice_over, size: 18),
                  label: const Text("采集语音"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ] else ...[
                Text(
                  _calibState == 'noise' ? "保持安静..." : "请说话...",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
                ElevatedButton(
                  onPressed: () async => await _stopCalib(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("完成"),
                ),
              ],
              if (_calibState == 'idle')
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: Text(
                      "噪音峰值: ${(_calibNoiseMax * 100).toStringAsFixed(1)}%, 语音峰值: ${(_calibSpeechMax * 100).toStringAsFixed(1)}%",
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        // Mic Gain
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle("麦克风音量"),
            Text(
              _micGain.toStringAsFixed(2),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        Slider(
          value: _micGain,
          min: 0,
          max: 2,
          divisions: 40,
          label: _micGain.toStringAsFixed(2),
          onChanged: (v) => setState(() => _micGain = v),
          onChangeEnd: (v) => provider.setMicGain(v),
          activeColor: AppColors.accent,
          inactiveColor: AppColors.bgHover,
        ),
        const SizedBox(height: 16),

        // Speaker Gain
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle("扬声器音量"),
            Text(
              _speakerGain.toStringAsFixed(2),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        Slider(
          value: _speakerGain,
          min: 0,
          max: 2,
          divisions: 40,
          label: _speakerGain.toStringAsFixed(2),
          onChanged: (v) => setState(() => _speakerGain = v),
          onChangeEnd: (v) => provider.setSpeakerGain(v),
          activeColor: AppColors.accent,
          inactiveColor: AppColors.bgHover,
        ),
        const SizedBox(height: 16),

        // Close to Tray
        if (!kIsWeb)
          SwitchListTile(
            title: const Text(
              "关闭时最小化到托盘",
              style: TextStyle(color: AppColors.textPrimary),
            ),
            value: provider.closeToTray,
            onChanged: (v) => provider.setCloseToTray(v),
            contentPadding: EdgeInsets.zero,
            activeTrackColor: AppColors.accent,
            thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return Colors.grey;
            }),
          ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    String Function(T)? itemLabelBuilder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.bgSecondary,
          icon: const Icon(
            Icons.arrow_drop_down,
            color: AppColors.textSecondary,
          ),
          style: const TextStyle(color: AppColors.textPrimary),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(
                itemLabelBuilder != null
                    ? itemLabelBuilder(item)
                    : item.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class AboutSettingsView extends StatelessWidget {
  const AboutSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "WeSpeek Client",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 16),
        Text(
          "Version: 1.0.0 (Alpha)",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        SizedBox(height: 24),
        Text(
          "A modern, low-latency voice chat application built with Go and Flutter.",
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
