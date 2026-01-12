import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// 信令客户端抽象，便于替换实现（如原生/第三方/Mock）
abstract class SignalingClient {
  Stream<Map<String, dynamic>> get onMessage;
  Stream<dynamic> get onLatencyUpdate;
  Stream<void> get onClosed;
  Future<void> connect();
  void subscribe();
  void subscribeLatency();
  void unsubscribeLatency();
  void join(String roomId, String uid, String name);
  void leave();
  void sendPublicChat(String uid, String name, String text);
  void sendRoomChat(String roomId, String uid, String name, String text);
  void rename(String uid, String name);
  void setIOSet(bool? inputDisabled, bool? outputDisabled);
  void getUserInfo(String uid, {String? auth});
  void adminLogin(String password);
  void adminKick(String uid, String key);
  void adminMute(String uid, bool mute, String key);
  void adminGrant(String uid, String key);
  void adminRevoke(String uid, String key);
  void sendRevoke(String uid, int msgId, {String? auth});
  void sendSignal(String target, String type, dynamic payload);
  void close();
}

/// 基于 WebSocket 的信令实现
class SignalingService implements SignalingClient {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );
  WebSocketChannel? _channel;
  final String baseUrl;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  final _latencyController = StreamController<dynamic>.broadcast();
  @override
  Stream<dynamic> get onLatencyUpdate => _latencyController.stream;

  final _closedController = StreamController<void>.broadcast();
  @override
  Stream<void> get onClosed => _closedController.stream;

  SignalingService(this.baseUrl);

  @override
  Future<void> connect() async {
    final uri = Uri.parse('$baseUrl/ws');
    _logger.i("Connecting to Signaling: $uri");
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;
    _logger.i("Signaling Connected");

    _channel!.stream.listen(
      (event) {
        try {
          final data = jsonDecode(event);
          if (data is Map<String, dynamic>) {
            if (data['method'] == 'latency.update') {
               _latencyController.add(data['params']);
            } else if (data['method'] == 'ping') {
               _send({
                 "method": "pong",
                 "params": data['params']
               });
            } else {
               _messageController.add(data);
            }
          }
        } catch (e) {
          _logger.e("Signaling decode error: $e");
        }
      },
      onError: (e) {
        _logger.e("Signaling Error: $e");
        _closedController.add(null);
      },
      onDone: () {
        _logger.i("信令连接已关闭");
        _closedController.add(null);
      },
    );
  }

  @override
  void subscribe() {
    _send({"method": "subscribe"});
  }

  @override
  void subscribeLatency() {
    _send({"method": "latency.subscribe"});
  }

  @override
  void unsubscribeLatency() {
    _send({"method": "latency.unsubscribe"});
  }

  @override
  void join(String roomId, String uid, String name) {
    _send({
      "method": "join",
      "params": {
        "sid": roomId,
        "uid": uid,
        "name": name,
        "webrtc": true, // Enable WebRTC support flag
      },
    });
  }

  @override
  void leave() {
    _send({"method": "leave"});
  }

  @override
  void sendSignal(String target, String type, dynamic payload) {
    _send({
      "method": "signal",
      "params": {
        "target": target,
        "type": type,
        "payload": payload,
      },
    });
  }

  @override
  void sendPublicChat(String uid, String name, String text) {
    _send({
      "method": "chat.public",
      "params": {"uid": uid, "name": name, "text": text},
    });
  }

  @override
  void sendRoomChat(String roomId, String uid, String name, String text) {
    _send({
      "method": "chat.room",
      "params": {"sid": roomId, "uid": uid, "name": name, "text": text},
    });
  }

  @override
  void rename(String uid, String name) {
    _send({
      "method": "rename",
      "params": {"uid": uid},
    });
    // name update is separate
    _send({
      "method": "name",
      "params": {"uid": uid, "name": name},
    });
  }

  void _send(Map<String, dynamic> msg) {
    if (_channel == null) return;
    _logger.d("Sending: $msg");
    _channel!.sink.add(jsonEncode(msg));
  }

  @override
  void setIOSet(bool? inputDisabled, bool? outputDisabled) {
    final params = <String, dynamic>{};
    if (inputDisabled != null) params['inputDisabled'] = inputDisabled;
    if (outputDisabled != null) params['outputDisabled'] = outputDisabled;
    _send({"method": "io.set", "params": params});
  }

  @override
  void getUserInfo(String uid, {String? auth}) {
    final params = {"uid": uid};
    if (auth != null) {
      params["auth"] = auth;
    }
    _send({
      "method": "admin.get_user_info",
      "params": params,
    });
  }

  @override
  void adminLogin(String password) {
    _send({
      "method": "admin.login",
      "params": {"password": password},
    });
  }

  @override
  void adminKick(String uid, String key) {
    _send({
      "method": "admin.kick",
      "params": {"uid": uid, "auth": key},
    });
  }

  @override
  void adminMute(String uid, bool mute, String key) {
    _send({
      "method": "admin.mute",
      "params": {"uid": uid, "mute": mute, "auth": key},
    });
  }

  @override
  void adminGrant(String uid, String key) {
    _send({
      "method": "admin.grant",
      "params": {"uid": uid, "auth": key},
    });
  }

  @override
  void adminRevoke(String uid, String key) {
    _send({
      "method": "admin.revoke",
      "params": {"uid": uid, "auth": key},
    });
  }

  @override
  void sendRevoke(String uid, int msgId, {String? auth}) {
    final params = {
      "uid": uid,
      "msgId": msgId,
    };
    if (auth != null) {
      params["auth"] = auth;
    }
    _send({
      "method": "chat.revoke",
      "params": params,
    });
  }

  @override
  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}
