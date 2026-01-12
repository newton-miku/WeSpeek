import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling_service.dart';
import '../services/audio_service.dart';
import '../services/audio/webrtc_manager.dart';

import '../models/room_model.dart';
import '../models/chat_message.dart';
import '../services/sfx_service.dart';

/// CallProvider serves as the Application Service (in DDD terms) for the client.
/// It orchestrates:
/// 1. Infrastructure Services: Signaling (WebSocket) and Audio (WebRTC/UDP).
/// 2. Domain State: Room management, User presence, Chat messages.
/// 3. UI State: Connection status, Selected devices, Mute status.
///
/// It acts as a Facade to the complex underlying systems, exposing a simple
/// state-based API to the UI layer (Flutter Widgets).
class CallProvider extends ChangeNotifier {
  // Dependencies (Infrastructure Services)
  SignalingClient? _signaling;
  AudioClient? _audio;

  bool _isConnected = false;
  bool _isInCall = false;
  // bool _isMuted = false; // Removed unused
  String _status = "Disconnected";
  String _lastError = "";

  String _currentServer = "";
  String _currentUid = "";
  String _currentName = "";
  String _currentRoomId = "";
  List<String> _serverCandidates = [];
  bool _reconnecting = false;
  int _retryAttempt = 0;
  String _selectedRoomId = "";
  bool _isIntentionalDisconnect = false;
  int _connectionGeneration = 0;

  final List<Room> _rooms = [];
  final List<String> _logs = [];

  // Audio player for sound effects
  final SfxService _sfxService = SfxService.instance;

  // Screen Sharing
  WebRTCManager? _screenShareManager;
  bool _isScreenSharing = false;
  bool _stoppingScreenShare = false;
  final Map<String, MediaStream> _remoteScreenStreams = {};

  // Screen Share Viewing State
  String? _viewingScreenShareUid;
  bool _isScreenShareAudioMuted = false;

  final List<ChatMessage> _publicMessages = [];
  final List<ChatMessage> _roomMessages = [];
  // Chat versioning for optimized updates
  int _publicChatVersion = 0;
  int _roomChatVersion = 0;
  int _rosterVersion = 0;
  List<String> _groups = [];
  List<String> _inputDevices = ["系统默认"];
  List<String> _outputDevices = ["系统默认"];
  String _selectedInputDevice = "系统默认";
  String _selectedOutputDevice = "系统默认";
  double _micGain = 1.0;
  double _speakerGain = 1.0;
  String _noiseMode = "gate"; // none, gate
  double _gateThreshold = 0.05; // 0.0 ~ 1.0
  bool _isMicMuted = false;
  bool _isSpeakerMuted = false;
  bool _closeToTray = false;
  final Set<String> _speakingUsers = {};

  // Local Peer Controls
  final Map<String, double> _peerVolumes = {};
  final Set<String> _mutedPeers = {};

  // Admin State
  String? _adminKey;
  String? _adminRole;
  bool _isAdmin = false;

  // Public getters for Admin State
  String? get adminKey => _adminKey;
  String? get adminRole => _adminRole;
  bool get isAdmin => _isAdmin;

  // Keys for SharedPreferences
  static const String _kServerUrl = 'server_url';
  static const String _kUserName = 'user_name';
  static const String _kUserUid = 'user_uid';
  static const String _kInputDevice = 'input_device';
  static const String _kOutputDevice = 'output_device';
  static const String _kNoiseMode = 'noise_mode';
  static const String _kGateThreshold = 'gate_threshold';
  static const String _kMicGain = 'mic_gain';
  static const String _kSpeakerGain = 'speaker_gain';
  static const String _kCloseToTray = 'close_to_tray';

  bool get isConnected => _isConnected;
  bool get isInCall => _isInCall;
  bool get isMicMuted => _isMicMuted;
  bool get isSpeakerMuted => _isSpeakerMuted;
  bool get closeToTray => _closeToTray;
  bool get isScreenSharing => _isScreenSharing;
  MediaStream? get localScreenStream => _screenShareManager?.localStream;
  Map<String, MediaStream> get remoteScreenStreams => _remoteScreenStreams;
  String? get viewingScreenShareUid => _viewingScreenShareUid;
  bool get isScreenShareAudioMuted => _isScreenShareAudioMuted;

  Stream<double>? get onVolume => _audio?.onVolume;
  Set<String> get speakingUsers => _speakingUsers;
  String get status => _status;
  List<Room> get rooms => _rooms;
  List<String> get logs => _logs;
  List<ChatMessage> get publicMessages => _publicMessages;
  List<ChatMessage> get roomMessages => _roomMessages;
  int get publicChatVersion => _publicChatVersion;
  int get roomChatVersion => _roomChatVersion;
  int get rosterVersion => _rosterVersion;
  String get currentRoomId => _currentRoomId;
  String get currentUid => _currentUid;
  String get currentName => _currentName; // Add getter for currentName
  String get currentServer =>
      _sanitizeServerUrl(_currentServer); // Return sanitized server address
  String get httpBaseUrl {
    String url = _currentServer;
    if (url.startsWith("wss://")) {
      url = url.replaceFirst("wss://", "https://");
    } else if (url.startsWith("ws://")) {
      url = url.replaceFirst("ws://", "http://");
    } else {
      url = "https://$url";
    }

    // Remove /ws suffix if present, assuming static files are served from root
    if (url.endsWith("/ws")) {
      url = url.substring(0, url.length - 3);
    }
    return url;
  }

  String get lastError => _lastError;
  List<String> get groups => _groups;
  List<String> get inputDevices => _inputDevices;
  List<String> get outputDevices => _outputDevices;
  String get selectedInputDevice => _selectedInputDevice;
  String get selectedOutputDevice => _selectedOutputDevice;
  double get micGain => _micGain;
  double get gateThreshold => _gateThreshold;
  double get speakerGain => _speakerGain;
  String get noiseMode => _noiseMode;

  double getPeerVolume(String uid) => _peerVolumes[uid] ?? 1.0;
  bool isPeerMuted(String uid) => _mutedPeers.contains(uid);

  String get selectedRoomId => _selectedRoomId;
  Room? get selectedRoom {
    final idx = _rooms.indexWhere((r) => r.id == _selectedRoomId);
    return idx >= 0 ? _rooms[idx] : null;
  }

  Room? getRoomById(String id) {
    final idx = _rooms.indexWhere((r) => r.id == id);
    return idx >= 0 ? _rooms[idx] : null;
  }

  String? getUserName(String uid) {
    if (uid == _currentUid) return _currentName;
    for (var room in _rooms) {
      for (var member in room.members) {
        if (member.uid == uid) {
          return member.name;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _lastUserInfo = {};
  Map<String, dynamic> get lastUserInfo => _lastUserInfo;

  CallProvider() {
    _loadSettings();
    _loadDevices();
    _sfxService.init();
  }

  Future<void> reloadDevices() async {
    await _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      // Use a temporary AudioService to list devices
      // We don't need a real server URL for device listing
      final tempAudio = AudioService("");

      final inputs = await tempAudio.listInputDevices();
      _inputDevices = ["系统默认", ...inputs];

      final outputs = await tempAudio.listOutputDevices();
      _outputDevices = ["系统默认", ...outputs];

      notifyListeners();
    } catch (e) {
      _addLog("Error loading devices: $e");
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentServer = prefs.getString(_kServerUrl) ?? "";
      _currentName = prefs.getString(_kUserName) ?? "";

      _currentUid = prefs.getString(_kUserUid) ?? "";
      if (_currentUid.isEmpty) {
        _currentUid = const Uuid().v4();
        await prefs.setString(_kUserUid, _currentUid);
      }

      _selectedInputDevice = prefs.getString(_kInputDevice) ?? "系统默认";
      _selectedOutputDevice = prefs.getString(_kOutputDevice) ?? "系统默认";
      _noiseMode = prefs.getString(_kNoiseMode) ?? "gate";
      _gateThreshold = prefs.getDouble(_kGateThreshold) ?? 0.05;
      _micGain = prefs.getDouble(_kMicGain) ?? 1.0;
      _speakerGain = prefs.getDouble(_kSpeakerGain) ?? 1.0;
      _closeToTray = prefs.getBool(_kCloseToTray) ?? false;

      await _loadAdminState();

      _addLog(
        "Loaded settings: Server=$_currentServer, Name=$_currentName, In=$_selectedInputDevice, Out=$_selectedOutputDevice",
      );
      notifyListeners();
    } catch (e) {
      _addLog("Error loading settings: $e");
    }
  }

  Future<void> _saveString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      _addLog("Error saving setting $key: $e");
    }
  }

  Future<void> _saveDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (e) {
      _addLog("Error saving setting $key: $e");
    }
  }

  // Connect to Signaling Server
  Future<void> connectServer(String serverUrl, String name, String uid) async {
    // Save connection settings (Sanitized)
    await _saveString(_kServerUrl, _sanitizeServerUrl(serverUrl));
    await _saveString(_kUserName, name);

    try {
      _connectionGeneration++;
      final currentGen = _connectionGeneration;
      _isIntentionalDisconnect = false;
      _status = "Connecting to server...";
      notifyListeners();

      // Ensure previous connection is closed
      if (_signaling != null) {
        _signaling?.close();
        _signaling = null;
      }

      final candidates = _resolveBaseUrls(serverUrl);
      _serverCandidates = candidates;

      _currentName = name;
      _currentUid = uid;
      _lastError = "";

      bool connected = false;
      for (final base in candidates) {
        try {
          // 默认使用 WebSocket 实现，也可在外部注入不同实现
          _signaling = SignalingService(base);
          await _signaling!.connect();
          _currentServer = base;
          connected = true;
          break;
        } catch (e) {
          _lastError = "$e";
        }
      }
      if (!connected) {
        _status = "无法连接到服务器";
        _addLog("连接失败");
        notifyListeners();
        return;
      }

      _setupSignalingListeners(currentGen);

      // Subscribe to room updates
      _signaling!.subscribe();
      // _signaling!.subscribeLatency(); // Latency subscription is now on-demand (e.g. in settings/info panel)

      _isConnected = true;
      _status = "Connected to server";
      await _loadAdminState();
      _addLog("Connected to $_currentServer");
      notifyListeners();
    } catch (e) {
      if (e is AudioPermissionException) {
        _addLog("Permission Error: ${e.message}");
        rethrow;
      }
      _lastError = "$e";
      _status = "无法连接到服务器";
      _addLog("连接失败");
      notifyListeners();
    }
  }

  void _handleSignalingMessage(Map<String, dynamic> msg) {
    final method = msg['method'];
    final params = msg['params'];

    if (method == 'rooms.update') {
      _handleRoomsUpdate(params);
    } else if (method == 'room.update') {
      _handleRoomUpdate(params);
    } else if (method == 'latency.update') {
      _handleLatencyUpdate(params);
    } else if (method == 'chat.public') {
      final msg = ChatMessage.fromJson(params);
      _publicMessages.add(msg);
      _publicChatVersion++;
      // _addLog("Public Chat: ${msg.name}: ${msg.text}");
    } else if (method == 'chat.room') {
      final msg = ChatMessage.fromJson(params);
      _roomMessages.add(msg);
      _roomChatVersion++;
      // _addLog("Room Chat: ${msg.name}: ${msg.text}");
    } else if (method == 'chat.public.history') {
      if (params is List) {
        _publicMessages.clear();
        for (var p in params) {
          _publicMessages.add(ChatMessage.fromJson(p));
        }
        _publicChatVersion++;
      }
    } else if (method == 'chat.room.history') {
      if (params is List) {
        _roomMessages.clear();
        for (var p in params) {
          _roomMessages.add(ChatMessage.fromJson(p));
        }
        _roomChatVersion++;
      }
    } else if (method == 'admin.user_info') {
      _lastUserInfo = params;
    } else if (method == 'admin.login') {
      final secret = params['secret'];
      final role =
          params['role'] ??
          "owner"; // Default to owner if logging in directly? Or admin?
      if (secret != null) {
        _setAdminKey(secret, role: role);
        _addLog("管理员登录成功");
        _sfxService.playSuccess();
      }
    } else if (method == 'admin.granted') {
      final secret = params['secret'];
      final role = params['role'] ?? "admin";
      if (secret != null) {
        _setAdminKey(secret, role: role);
        _addLog("您已被授予管理员权限");
        _sfxService.playSuccess();
      }
    } else if (method == 'admin.revoked') {
      logoutAdmin();
      _addLog("您的管理员权限已被撤销");
    } else if (method == 'chat.revoke') {
      final msgId = params['msgId'];
      if (msgId != null) {
        _publicMessages.removeWhere((m) => m.id == msgId);
        _roomMessages.removeWhere((m) => m.id == msgId);
        _publicChatVersion++;
        _roomChatVersion++;
      }
    } else if (method == 'signal') {
      final payload = params['payload'];
      if (payload is Map && payload['label'] == 'screen') {
        _ensureScreenShareManager();
        // Start receiving (captureMedia: false) if not active
        if (!_screenShareManager!.isActive) {
          _screenShareManager!.start([], captureMedia: false);
        }

        String? sender = params['sender'] ?? params['uid'];
        if (sender == null && params['target'] == 'sfu') {
          sender = 'sfu';
        }

        _screenShareManager?.handleSignal(sender!, params['type'], payload);

        // Force cleanup after 1s if not already removed (User request)
        if (params['type'] == 'bye') {
          Future.delayed(const Duration(seconds: 1), () {
            if (_remoteScreenStreams.containsKey(sender)) {
              _remoteScreenStreams.remove(sender);

              if (_viewingScreenShareUid == sender) {
                if (_remoteScreenStreams.isNotEmpty) {
                  _viewingScreenShareUid = _remoteScreenStreams.keys.first;
                } else {
                  _viewingScreenShareUid = null;
                }
              }

              _updateScreenShareAudio();
              notifyListeners();
            }
          });
        }
      } else {
        if (_isInCall && _audio != null) {
          _audio!.handleSignal(params);
        }
      }
    }
    notifyListeners();
  }

  void sendPublicChat(String text) {
    if (_signaling != null && _isConnected) {
      _signaling!.sendPublicChat(_currentUid, _currentName, text);
    }
  }

  void sendRoomChat(String text) {
    if (_signaling != null && _isConnected && _currentRoomId.isNotEmpty) {
      _signaling!.sendRoomChat(_currentRoomId, _currentUid, _currentName, text);
    }
  }

  void revokeMessage(int msgId) {
    if (_signaling != null && _isConnected) {
      String? auth;
      if (_isAdmin && _adminKey != null) {
        // Use stored role or default to 'admin'
        // Note: rpc.go VerifyAdmin expects 'secret:role'
        auth = "$_adminKey:${_adminRole ?? 'admin'}";
      }
      _signaling!.sendRevoke(_currentUid, msgId, auth: auth);
    }
  }

  void fetchUserInfo(String uid) {
    if (_signaling != null && _isConnected) {
      if (_isAdmin && _adminKey != null) {
        _signaling!.getUserInfo(uid, auth: "$_adminKey:x");
      } else {
        _signaling!.getUserInfo(uid);
      }
    }
  }

  void subscribeLatency() {
    if (_signaling != null && _isConnected) {
      _signaling!.subscribeLatency();
    }
  }

  void unsubscribeLatency() {
    if (_signaling != null && _isConnected) {
      _signaling!.unsubscribeLatency();
    }
  }

  void rename(String name) {
    if (_signaling != null && _isConnected) {
      _signaling!.rename(_currentUid, name);
      _currentName = name;
      notifyListeners();
    }
  }

  void setMicGain(double value) {
    _micGain = value;
    _saveDouble(_kMicGain, value);
    if (_audio != null) {
      _audio!.setMicGain(value);
    }
    notifyListeners();
  }

  void setSpeakerGain(double value) {
    _speakerGain = value;
    _saveDouble(_kSpeakerGain, value);
    if (_audio != null) {
      _audio!.setSpeakerGain(value);
    }
    notifyListeners();
  }

  void setNoiseMode(String value) {
    _noiseMode = value;
    _saveString(_kNoiseMode, value);
    _audio?.setNoiseMode(value);
    _addLog("设置降噪模式: $value");
    notifyListeners();
  }

  void setGateThreshold(double value) {
    _gateThreshold = value;
    _saveDouble(_kGateThreshold, value);
    _audio?.setGateThreshold(value);
    notifyListeners();
  }

  void setPeerVolume(String uid, double value) {
    _peerVolumes[uid] = value;
    _audio?.setPeerVolume(uid, value);
    notifyListeners();
  }

  void togglePeerMute(String uid) {
    final isMuted = _mutedPeers.contains(uid);
    if (isMuted) {
      _mutedPeers.remove(uid);
    } else {
      _mutedPeers.add(uid);
    }
    _audio?.setPeerMute(uid, !isMuted);
    notifyListeners();
  }

  void setViewingScreenShare(String? uid) {
    if (_viewingScreenShareUid != uid) {
      _viewingScreenShareUid = uid;
      _updateScreenShareAudio();
      notifyListeners();
    }
  }

  void toggleScreenShareAudioMute() {
    _isScreenShareAudioMuted = !_isScreenShareAudioMuted;
    _updateScreenShareAudio();
    notifyListeners();
  }

  void _updateScreenShareAudio() {
    // Logic:
    // If global mute is true -> Mute ALL.
    // Else -> Unmute ONLY viewingUid, mute others.

    _remoteScreenStreams.forEach((uid, stream) {
      bool shouldPlay =
          !_isScreenShareAudioMuted && (uid == _viewingScreenShareUid);
      stream.getAudioTracks().forEach((track) {
        track.enabled = shouldPlay;
      });
    });
  }

  void _ensureScreenShareManager({String? sourceId, bool shareAudio = false}) {
    if (_screenShareManager != null) return;

    _screenShareManager = WebRTCManager(
      myUid: _currentUid,
      label: 'screen',
      onSignal: (data) {
        _signaling?.sendSignal(data['target'], data['type'], data['payload']);
      },
      streamProvider: () async {
        Map<String, dynamic> mediaConstraints = {
          'audio': kIsWeb || shareAudio,
          'video': true,
        };

        if (sourceId != null) {
          mediaConstraints['video'] = {
            'deviceId': {'exact': sourceId},
            'width': 1920,
            'height': 1080,
            'frameRate': 30,
          };

          if (shareAudio && !kIsWeb) {
            // For desktop, we try to request audio.
            // Note: Windows/macOS/Linux support varies.
            mediaConstraints['audio'] = true;
          }
        }

        return await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      },
      onRemoteStream: (stream, uid) {
        _remoteScreenStreams[uid] = stream;

        // Auto-view if first one
        _viewingScreenShareUid ??= uid;

        _updateScreenShareAudio();
        notifyListeners();
      },
      onRemoteStreamRemoved: (uid) {
        _remoteScreenStreams.remove(uid);

        if (_viewingScreenShareUid == uid) {
          if (_remoteScreenStreams.isNotEmpty) {
            _viewingScreenShareUid = _remoteScreenStreams.keys.first;
          } else {
            _viewingScreenShareUid = null;
          }
        }

        _updateScreenShareAudio();
        notifyListeners();
      },
    );
  }

  Future<void> startScreenShare({
    String? sourceId,
    bool shareAudio = false,
  }) async {
    if (!_isInCall || _signaling == null) return;
    if (_isScreenSharing) return;

    try {
      _ensureScreenShareManager(sourceId: sourceId, shareAudio: shareAudio);

      final room = getRoomById(_currentRoomId);
      final members = room?.members.map((m) => m.uid).toList() ?? [];

      await _screenShareManager!.start(
        members,
        captureMedia: true,
        initiator: true,
      );
      _isScreenSharing = true;
      notifyListeners();

      // Listen for system stop (Only video track matters for stopping screen share)
      _screenShareManager?.localStream?.getVideoTracks().forEach((track) {
        track.onEnded = () {
          stopScreenShare();
        };
      });
    } catch (e) {
      _addLog("Failed to start screen share: $e");
      _screenShareManager?.stop();
      _screenShareManager = null;
      _isScreenSharing = false;
      notifyListeners();
    }
  }

  Future<void> stopScreenShare() async {
    if (!_isScreenSharing || _stoppingScreenShare) return;
    _stoppingScreenShare = true;

    try {
      // Send bye signal to all members for immediate UI update
      if (_currentRoomId.isNotEmpty) {
        final room = getRoomById(_currentRoomId);
        if (room != null) {
          for (var member in room.members) {
            if (member.uid != _currentUid) {
              _signaling?.sendSignal(member.uid, 'bye', {'label': 'screen'});
            }
          }
        }
      }

      await _screenShareManager?.stopLocalCapture();
      _isScreenSharing = false;

      // Only destroy manager if we are not receiving any streams
      if (_remoteScreenStreams.isEmpty) {
        await _screenShareManager?.stop();
        _screenShareManager = null;
      }

      notifyListeners();
    } finally {
      _stoppingScreenShare = false;
    }
  }

  // Admin Actions

  /// Allows setting admin identity from external sources (e.g. AdminStatusScreen)
  void setAdminIdentity(String key, {String role = "admin"}) {
    _setAdminKey(key, role: role);
  }

  void _setAdminKey(String key, {String role = "admin"}) {
    _adminKey = key;
    _adminRole = role;
    _isAdmin = true;
    _saveAdminState(key, role);
    notifyListeners();
  }

  void logoutAdmin() {
    _adminKey = null;
    _adminRole = null;
    _isAdmin = false;
    _clearAdminState();
    notifyListeners();
  }

  void loginAdminWithPassword(String password) {
    if (_signaling != null && _isConnected) {
      _signaling!.adminLogin(password);
    }
  }

  void adminKick(String uid) {
    if (_signaling != null && _isConnected && _isAdmin && _adminKey != null) {
      _signaling!.adminKick(uid, "$_adminKey:x");
    }
  }

  void adminMute(String uid, bool mute) {
    if (_signaling != null && _isConnected && _isAdmin && _adminKey != null) {
      _signaling!.adminMute(uid, mute, "$_adminKey:x");
    }
  }

  Future<String?> claimAdmin(String token) async {
    if (_currentServer.isEmpty) return "No server connected";

    try {
      String urlStr = _currentServer;
      if (urlStr.startsWith("wss://")) {
        urlStr = urlStr.replaceFirst("wss://", "https://");
      } else if (urlStr.startsWith("ws://")) {
        urlStr = urlStr.replaceFirst("ws://", "http://");
      } else {
        urlStr = urlStr.replaceFirst("ws", "http");
      }

      final uri = Uri.parse(urlStr).replace(path: '/api/admin/setup');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"token": token}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final secret = data['secret'] ?? data['key'];
        final role = data['role'] ?? "owner"; // Setup usually grants owner
        if (secret != null) {
          _setAdminKey(secret, role: role);
          return null; // Success
        }
        return "Invalid response: missing secret";
      } else {
        // Try to parse error message from body
        try {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data['error'] != null) {
            return "Server Error: ${data['error']}";
          }
        } catch (_) {}
        return "HTTP Error: ${response.statusCode}";
      }
    } catch (e) {
      _addLog("Admin Claim Error: $e");
      return "Exception: $e";
    }
  }

  // Audio & Room Actions

  void adminKickUser(String uid) {
    if (_isAdmin && _adminKey != null) {
      _signaling?.adminKick(uid, "$_adminKey:x");
    }
  }

  void adminMuteUser(String uid, bool mute) {
    if (_isAdmin && _adminKey != null) {
      _signaling?.adminMute(uid, mute, "$_adminKey:x");
    }
  }

  void adminGrantUser(String uid) {
    if (_isAdmin && _adminKey != null) {
      _signaling?.adminGrant(uid, "$_adminKey:x");
    }
  }

  void adminRevokeUser(String uid) {
    if (_isAdmin && _adminKey != null) {
      _signaling?.adminRevoke(uid, "$_adminKey:x");
    }
  }

  void _setupSignalingListeners(int generation) {
    _signaling!.onMessage.listen(_handleSignalingMessage);
    _signaling!.onLatencyUpdate.listen(_handleLatencyUpdate);
    _signaling!.onClosed.listen((_) {
      if (_connectionGeneration == generation &&
          !_reconnecting &&
          !_isIntentionalDisconnect) {
        _handleDisconnectAndRetry();
      }
    });
  }

  void _handleDisconnectAndRetry() {
    _isConnected = false;
    _status = "连接丢失，正在重试...";
    _addLog("连接丢失，开始重试");
    notifyListeners();
    _reconnecting = true;
    _retryAttempt = 0;
    _reconnectLoop(_connectionGeneration);
  }

  Future<void> _reconnectLoop(int generation) async {
    while (!_isConnected &&
        !_isIntentionalDisconnect &&
        _connectionGeneration == generation) {
      final delayMs = _computeBackoffDelay(_retryAttempt);
      await Future.delayed(Duration(milliseconds: delayMs));
      _retryAttempt++;
      for (final base in _serverCandidates) {
        if (_isIntentionalDisconnect || _connectionGeneration != generation)
          // ignore: curly_braces_in_flow_control_structures
          break;
        try {
          final sc = SignalingService(base);
          await sc.connect();

          if (_isIntentionalDisconnect || _connectionGeneration != generation) {
            sc.close();
            return;
          }

          _signaling = sc;
          _currentServer = base;
          _setupSignalingListeners(generation);
          _signaling!.subscribe();
          _signaling!.subscribeLatency();
          _isConnected = true;
          _status = "Connected to server";
          _addLog("重连成功: $_currentServer");
          // 恢复通话状态
          if (_isInCall && _currentRoomId.isNotEmpty) {
            _signaling!.join(_currentRoomId, _currentUid, _currentName);
            _audio?.close();
            _audio = AudioService(_currentServer);
            if (_selectedInputDevice != "系统默认") {
              _audio!.setInputDevice(_selectedInputDevice);
            }
            if (_selectedOutputDevice != "系统默认") {
              _audio!.setOutputDevice(_selectedOutputDevice);
            }
            _audio!.setMicGain(_micGain);
            _audio!.setSpeakerGain(_speakerGain);
            _audio!.setNoiseMode(_noiseMode);
            _audio!.setGateThreshold(_gateThreshold);

            // Restore peer settings
            for (var entry in _peerVolumes.entries) {
              _audio!.setPeerVolume(entry.key, entry.value);
            }
            for (var uid in _mutedPeers) {
              _audio!.setPeerMute(uid, true);
            }

            await _audio!.connect(_currentRoomId, _currentUid);
            _setupAudioSubscriptions();
            _addLog("音频通道已恢复");
          }
          _reconnecting = false;
          notifyListeners();
          return;
        } catch (e) {
          _lastError = "$e";
          _addLog("重试失败: $base");
          // continue to next candidate
        }
      }
    }
    _reconnecting = false;
  }

  int _computeBackoffDelay(int attempt) {
    // 线性+指数退避，附带少量抖动
    final baseMs = 1000; // 1s
    final maxMs = 30000; // 30s
    int ms = baseMs * (1 << (attempt.clamp(0, 5))); // 1s,2s,4s,8s,16s,32s
    if (ms > maxMs) ms = maxMs;
    final jitter = (DateTime.now().millisecondsSinceEpoch % 500);
    return ms + jitter;
  }

  void _handleRoomsUpdate(dynamic params) {
    if (params['rooms'] != null) {
      _rooms.clear();
      params['rooms'].forEach((v) {
        _rooms.add(Room.fromJson(v));
      });
      _addLog("Rooms updated: ${_rooms.length} rooms found.");

      // Check if current room config changed
      if (_isInCall && _currentRoomId.isNotEmpty) {
        final room = getRoomById(_currentRoomId);
        if (room != null && _audio != null) {
          _audio!.setAudioConfig(room.audioCodec, room.audioQuality);
        }
      }
    }
    if (params['groups'] != null) {
      _groups = List<String>.from(params['groups']);
    }
    _rosterVersion++;
    notifyListeners();
  }

  void _handleRoomUpdate(dynamic params) {
    final roomId = params['id'];
    final roomIndex = _rooms.indexWhere((r) => r.id == roomId);
    if (roomIndex != -1) {
      // Create a temporary room to parse members
      // The params for room.update are {id: "...", members: [...]}
      // which matches Room.fromJson structure partially
      var updatedMembers = <RoomMember>[];
      if (params['members'] != null) {
        params['members'].forEach((v) {
          updatedMembers.add(RoomMember.fromJson(v));
        });
      }

      // Check for member join/leave if we are in this room
      if (_currentRoomId == roomId) {
        final oldMembers = _rooms[roomIndex].members.map((m) => m.uid).toSet();
        final newMembers = updatedMembers.map((m) => m.uid).toSet();

        // Someone joined (in new but not in old)
        final joined = newMembers.difference(oldMembers);
        // Someone left (in old but not in new)
        final left = oldMembers.difference(newMembers);

        if (joined.isNotEmpty) {
          if (!joined.contains(_currentUid)) {
            _playJoinSound();
          }
        }

        if (left.isNotEmpty) {
          if (!left.contains(_currentUid)) {
            _playLeaveSound();
          }
        }
      }

      _rooms[roomIndex].members = updatedMembers;
      // _addLog("Room $roomId updated.");

      // Update Audio Service Room State
      if (_isInCall && _currentRoomId == roomId && _audio != null) {
        _audio!.updateRoomState(updatedMembers);
      }

      // Update Screen Share State
      if (_screenShareManager != null) {
        final memberUids = updatedMembers.map((m) => m.uid).toList();
        // If we are sharing, we might be initiator for new peers.
        // If we are just receiving, we are not initiator usually, but updatePeers handles that.
        _screenShareManager!.updatePeers(
          memberUids,
          initiator: _isScreenSharing,
        );
      }

      _rosterVersion++;
      notifyListeners();
    }
  }

  void _handleLatencyUpdate(dynamic params) {
    if (params is Map<String, dynamic>) {
      bool changed = false;
      params.forEach((uid, latency) {
        for (var room in _rooms) {
          for (var member in room.members) {
            if (member.uid == uid) {
              member.latency = latency is int
                  ? latency
                  : (latency as num).toInt();
              changed = true;
            }
          }
        }
      });
      if (changed) {
        notifyListeners();
      }
    }
  }

  Future<void> loadAudioDevices() async {
    final tempAudio = _audio ?? AudioService("");
    try {
      final inputs = await tempAudio.listInputDevices();
      final outputs = await tempAudio.listOutputDevices();

      final Set<String> inSet = {"系统默认"};
      inSet.addAll(inputs);
      _inputDevices = inSet.toList();

      // Validate selected input device
      if (!_inputDevices.contains(_selectedInputDevice)) {
        _selectedInputDevice = "系统默认";
        _saveString(_kInputDevice, "系统默认");
      }

      final Set<String> outSet = {"系统默认"};
      outSet.addAll(outputs);
      _outputDevices = outSet.toList();

      // Validate selected output device
      if (!_outputDevices.contains(_selectedOutputDevice)) {
        _selectedOutputDevice = "系统默认";
        _saveString(_kOutputDevice, "系统默认");
      }

      notifyListeners();
    } catch (e) {
      _addLog("Failed to load audio devices: $e");
    }
  }

  Future<void> joinRoom(String roomId) async {
    if (!_isConnected) return;

    // Check permissions before joining audio, but don't force it
    bool hasMicPermission = true;
    bool micAvailable = true;

    try {
      if (!await Permission.microphone.isGranted) {
        await Permission.microphone.request();
      }

      hasMicPermission = await Permission.microphone.isGranted;
    } catch (e) {
      _addLog("麦克风权限检查失败: $e");
      hasMicPermission = false;
      micAvailable = false;
    }

    // If already in a call, close existing audio connection first
    if (_isInCall) {
      _addLog("Switching rooms: Closing previous audio session...");
      await _playLeaveSound(); // Play leave sound when switching
      _audio?.close();
      _audio = null;
      // Note: We don't necessarily need to send signaling leave if the server
      // handles room switching on join, but cleaning up client resources is must.
      _roomMessages.clear();

      // Stop screen share if active
      if (_isScreenSharing) {
        await stopScreenShare();
      }
    }

    try {
      _status = "Joining room $roomId...";
      _addLog("Joining room $roomId...");
      notifyListeners();

      _signaling!.join(roomId, _currentUid, _currentName);

      // Subscribe to latency updates
      _signaling!.subscribeLatency();

      // Update local state to server immediately after joining
      // If no mic, ensure mic is muted
      if (!hasMicPermission || !micAvailable) {
        _isMicMuted = true;
      }
      _signaling!.setIOSet(_isMicMuted, _isSpeakerMuted);

      bool audioInitialized = false;

      try {
        // 默认使用本地音频实现，也可在外部注入不同实现
        _audio = AudioService(_currentServer);
        if (_selectedInputDevice != "系统默认") {
          _audio!.setInputDevice(_selectedInputDevice);
        }
        if (_selectedOutputDevice != "系统默认") {
          _audio!.setOutputDevice(_selectedOutputDevice);
        }
        _audio!.setMicGain(_micGain);
        _audio!.setSpeakerMute(_isSpeakerMuted);
        _audio!.setSpeakerGain(_speakerGain);
        _audio!.setNoiseMode(_noiseMode);
        _audio!.setGateThreshold(_gateThreshold);

        final room = getRoomById(roomId);
        if (room != null) {
          await _audio!.setAudioConfig(room.audioCodec, room.audioQuality);
        }

        try {
          await _audio!.connect(
            roomId,
            _currentUid,
          ); // connect sends init internally now
          audioInitialized = true;

          // Listen to volume for speaking indication
          _setupAudioSubscriptions();
        } catch (audioError) {
          if (audioError is AudioPermissionException) {
            _addLog("音频连接失败 (无麦克风): ${audioError.message}");
            // Allow joining without audio
            _isMicMuted = true;
            _signaling!.setIOSet(true, _isSpeakerMuted);
          } else {
            _addLog("音频连接失败: $audioError");
          }
          // Don't rethrow, allow joining without audio
        }
      } catch (audioInitError) {
        _addLog("音频初始化失败: $audioInitError");
        // Don't rethrow, allow joining without audio
      }

      _isInCall = true;
      _currentRoomId = roomId;
      _status = "In Room: $roomId";
      _addLog("Joined audio channel.");

      if (!audioInitialized) {
        _addLog("注意: 音频功能不可用，可能是由于缺少麦克风权限或没有麦克风设备");
        _errorEventController.add("WARNING: 音频功能不可用，您可以听但无法说话");
      }

      // Ensure Audio Service has correct room state (switch to WebRTC if needed)
      final currentRoom = getRoomById(roomId);
      if (currentRoom != null && _audio != null) {
        _audio!.updateRoomState(currentRoom.members);
      }

      _playJoinSound(); // Play join sound for self

      notifyListeners();
    } catch (e) {
      _lastError = "$e";
      _status = "加入房间失败";
      _addLog("加入房间失败: $e");
      notifyListeners();
    }
  }

  final Map<String, Timer> _speakingTimers = {};
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription? _remoteVolumeSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _signalSubscription;

  final _errorEventController = StreamController<String>.broadcast();
  Stream<String> get errorEvents => _errorEventController.stream;

  void toggleMicMute() {
    _isMicMuted = !_isMicMuted;
    if (_audio != null) {
      _audio!.setMute(_isMicMuted);
    }
    _addLog("麦克风静音: $_isMicMuted");

    // Immediately clear speaking status if muted
    if (_isMicMuted && _speakingUsers.contains(_currentUid)) {
      _speakingUsers.remove(_currentUid);
    }
    _signaling?.setIOSet(_isMicMuted, null);
    notifyListeners();
  }

  void toggleSpeakerMute() {
    _isSpeakerMuted = !_isSpeakerMuted;
    if (_audio != null) {
      _audio!.setSpeakerMute(_isSpeakerMuted);
    }
    _addLog("扬声器静音: $_isSpeakerMuted");
    _signaling?.setIOSet(null, _isSpeakerMuted);
    notifyListeners();
  }

  void startLatencyUpdates() {
    if (_isConnected && _signaling != null) {
      _signaling!.subscribeLatency();
    }
  }

  void stopLatencyUpdates() {
    if (_isConnected && _signaling != null) {
      _signaling!.unsubscribeLatency();
    }
  }

  void selectRoom(String roomId) {
    _selectedRoomId = roomId;
    _addLog("选择房间: $roomId");
    notifyListeners();
  }

  void setSelectedInputDevice(String value) {
    _selectedInputDevice = value;
    // Always update audio service, even for "系统默认"
    _audio?.setInputDevice(value);
    _addLog("选择输入设备: $value");
    _saveString(_kInputDevice, value);
    notifyListeners();
  }

  void setSelectedOutputDevice(String value) {
    _selectedOutputDevice = value;
    // Always update audio service, even for "系统默认"
    _audio?.setOutputDevice(value);
    _addLog("选择输出设备: $value");
    _saveString(_kOutputDevice, value);
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    _volumeSubscription?.cancel();
    _volumeSubscription = null;
    _remoteVolumeSubscription?.cancel();
    _remoteVolumeSubscription = null;
    _errorSubscription?.cancel();
    _errorSubscription = null;
    _signalSubscription?.cancel();
    _signalSubscription = null;
    _speakingUsers.clear();
    for (var t in _speakingTimers.values) {
      t.cancel();
    }
    _speakingTimers.clear();

    if (_signaling != null && _isInCall) {
      _signaling!.leave();
    }

    // Play leave sound for self
    if (_isInCall) {
      await _playLeaveSound();
    }

    if (_audio != null) {
      await _audio!.close();
    }
    _audio = null;
    _isInCall = false;
    _currentRoomId = "";
    _roomMessages.clear();
    _status = "Connected to server";
    _addLog("Left audio channel.");
    notifyListeners();
  }

  void _setupAudioSubscriptions() {
    _volumeSubscription?.cancel();
    _volumeSubscription = _audio!.onVolume.listen(_handleVolume);

    _remoteVolumeSubscription?.cancel();
    _remoteVolumeSubscription = _audio!.onRemoteVolume.listen(
      _handleRemoteVolume,
    );

    _errorSubscription?.cancel();
    _errorSubscription = _audio!.onError.listen(_handleAudioError);

    _signalSubscription?.cancel();
    _signalSubscription = _audio!.outboundSignal.listen((data) {
      if (_signaling != null) {
        _signaling!.sendSignal(data['target'], data['type'], data['payload']);
      }
    });
  }

  void _handleVolume(double vol) {
    if (_isMicMuted) return;
    _updateSpeakingStatus(_currentUid, vol);
  }

  void _handleRemoteVolume(MapEntry<String, double> entry) {
    _updateSpeakingStatus(entry.key, entry.value);
  }

  void _handleAudioError(String error) {
    _addLog("Audio Error: $error");
    _lastError = error;
    _sfxService.playWarning();
    _errorEventController.add(error);
    notifyListeners();
  }

  void _updateSpeakingStatus(String uid, double vol) {
    // Threshold for "speaking" (0.01 is roughly -40dB)
    const double speakThr = 0.01;

    if (vol > speakThr) {
      bool changed = false;
      if (!_speakingUsers.contains(uid)) {
        _speakingUsers.add(uid);
        changed = true;
      }

      // Reset timer
      _speakingTimers[uid]?.cancel();
      _speakingTimers[uid] = Timer(const Duration(milliseconds: 300), () {
        if (_speakingUsers.contains(uid)) {
          _speakingUsers.remove(uid);
          _speakingTimers.remove(uid);
          notifyListeners();
        }
      });

      if (changed) notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _isIntentionalDisconnect = true;
    await leaveRoom();
    _signaling?.close();
    _signaling = null;
    _isConnected = false;
    _rooms.clear();
    _publicMessages.clear();
    _roomMessages.clear();
    _status = "Disconnected";
    notifyListeners();
  }

  void setCloseToTray(bool value) {
    _closeToTray = value;
    _saveBool(_kCloseToTray, value);
    notifyListeners();
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _addLog(String log) {
    final time = DateTime.now().toLocal().toString().split('.')[0];
    _logs.insert(0, "[$time] $log");
    if (_logs.length > 100) _logs.removeLast();
  }

  List<String> _resolveBaseUrls(String input) {
    String s = input.trim();
    if (s.isEmpty) return [];
    final hasScheme = s.contains("://");
    final hasPort = RegExp(r":[0-9]+$").hasMatch(s);
    if (hasScheme && hasPort) {
      if (s.startsWith("http")) {
        s = s.replaceFirst("http", "ws");
      }
      return [s];
    }
    if (hasScheme && !hasPort) {
      if (s.startsWith("https://")) {
        return ["wss://${s.substring(8)}:443"];
      }
      if (s.startsWith("http://")) {
        final host = s.substring(7);
        return ["wss://$host:443", "ws://$host:80", "ws://$host:7000"];
      }
      if (s.startsWith("wss://")) {
        final host = s.substring(6);
        return ["wss://$host:443"];
      }
      if (s.startsWith("ws://")) {
        final host = s.substring(5);
        return ["wss://$host:443", "ws://$host:80", "ws://$host:7000"];
      }
      return [s];
    }
    if (!hasScheme && hasPort) {
      return ["wss://$s", "ws://$s"];
    }
    final host = s;
    return ["wss://$host:443", "ws://$host:80", "ws://$host:7000"];
  }

  String _sanitizeServerUrl(String url) {
    var s = url.trim();
    // Remove schemes
    if (s.startsWith("ws://")) {
      s = s.substring(5);
    } else if (s.startsWith("wss://")) {
      s = s.substring(6);
    } else if (s.startsWith("http://")) {
      s = s.substring(7);
    } else if (s.startsWith("https://")) {
      s = s.substring(8);
    }

    // Remove default ports
    if (s.endsWith(":7000")) {
      s = s.substring(0, s.length - 5);
    } else if (s.endsWith(":80")) {
      s = s.substring(0, s.length - 3);
    } else if (s.endsWith(":443")) {
      s = s.substring(0, s.length - 4);
    }

    return s;
  }

  Future<void> handleDeepLink(String server, String? roomId) async {
    if (server.isEmpty) return;

    // Check if we need to reconnect
    bool needConnect =
        !_isConnected ||
        _sanitizeServerUrl(_currentServer) != _sanitizeServerUrl(server);

    if (needConnect) {
      // Disconnect if connected to another server
      if (_isConnected) {
        disconnect();
      }

      String name = _currentName;
      if (name.isEmpty) name = "User";

      String uid = _currentUid;
      if (uid.isEmpty) uid = "User_${DateTime.now().millisecondsSinceEpoch}";

      await connectServer(server, name, uid);
    }

    if (_isConnected && roomId != null && roomId.isNotEmpty) {
      joinRoom(roomId);
    }
  }

  Future<void> handleSetupLink(
    String server,
    String token, {
    String? roomId,
  }) async {
    if (server.isNotEmpty) {
      await handleDeepLink(server, roomId);
    }

    // Attempt to claim admin if we have a server URL (even if not fully connected via WS, HTTP might work)
    if (_currentServer.isNotEmpty) {
      final error = await claimAdmin(token);
      if (error == null) {
        _addLog("Admin setup successful via link");
      } else {
        _addLog("Admin setup via link failed: $error");
      }
    }
  }

  Future<void> _loadAdminState() async {
    final prefs = await SharedPreferences.getInstance();
    final keyBase = _sanitizeServerUrl(_currentServer);
    if (keyBase.isEmpty) return;

    final savedAdminKey = prefs.getString("admin_key_$keyBase");
    if (savedAdminKey != null && savedAdminKey.isNotEmpty) {
      _adminKey = savedAdminKey;
      _adminRole = prefs.getString("admin_role_$keyBase") ?? "admin";
      _isAdmin = true;
    } else {
      _adminKey = null;
      _adminRole = null;
      _isAdmin = false;
    }
    // No notifyListeners here to avoid redundant builds during loadSettings/connect
  }

  Future<void> _saveAdminState(String key, String role) async {
    final prefs = await SharedPreferences.getInstance();
    final keyBase = _sanitizeServerUrl(_currentServer);
    if (keyBase.isNotEmpty) {
      await prefs.setString("admin_key_$keyBase", key);
      await prefs.setString("admin_role_$keyBase", role);
    }
  }

  Future<void> _clearAdminState() async {
    final prefs = await SharedPreferences.getInstance();
    final keyBase = _sanitizeServerUrl(_currentServer);
    if (keyBase.isNotEmpty) {
      await prefs.remove("admin_key_$keyBase");
      await prefs.remove("admin_role_$keyBase");
    }
  }

  /// Clean up resources (Audio, Signaling) before app exit
  Future<void> disposeResources() async {
    _signaling?.close();
    _audio?.close();
  }

  Future<void> _playJoinSound() async {
    try {
      await _sfxService.playJoin();
      _addLog("Played Join SFX");
    } catch (e) {
      _addLog("Failed to play join sfx: $e");
    }
  }

  Future<void> _playLeaveSound() async {
    try {
      await _sfxService.playLeave();
      _addLog("Played Leave SFX");
    } catch (e) {
      _addLog("Failed to play leave sfx: $e");
    }
  }
}
