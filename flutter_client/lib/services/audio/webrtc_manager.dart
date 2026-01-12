import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';

class WebRTCManager {
  final _logger = Logger(
    level: kReleaseMode ? Level.warning : Level.all,
  );
  final Map<String, RTCPeerConnection> _pcs = {};
  MediaStream? _localStream;
  final Function(Map<String, dynamic>) onSignal;
  final String myUid;
  final String label;
  final Future<MediaStream> Function()? streamProvider;
  final Function(MediaStream stream, String uid)? onRemoteStream;
  final Function(String uid)? onRemoteStreamRemoved;
  
  bool _isActive = false;

  bool get isActive => _isActive;
  MediaStream? get localStream => _localStream;

  final Map<String, MediaStream> _remoteStreams = {}; // Cache remote streams
  double _masterVolume = 1.0;

  // ICE Servers (Should be configurable)
  final Map<String, dynamic> _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
      {'urls': 'stun:turn.cloud-rtc.com:80'},
      {'urls': 'stun:stun.hitv.com'},
      {'urls': 'stun:stun.douyucdn.cn:18000'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  WebRTCManager({
    required this.myUid,
    required this.onSignal,
    this.label = 'audio',
    this.streamProvider,
    this.onRemoteStream,
    this.onRemoteStreamRemoved,
  });

  Future<void> start(List<String> memberUids, {bool captureMedia = true, bool initiator = false, MediaStream? stream}) async {
    _logger.i("Starting WebRTC Mesh ($label) for members: $memberUids, capture: $captureMedia");
    
    if (!_isActive) {
      _isActive = true;
    }

    // Handle Local Stream Acquisition
    if (captureMedia) {
      if (stream != null) {
        _localStream = stream;
      }
      
      if (_localStream == null) {
        try {
          if (streamProvider != null) {
            _localStream = await streamProvider!();
          } else {
            _localStream = await navigator.mediaDevices.getUserMedia({
              'audio': true,
              'video': false,
            });
          }
        } catch (e) {
          _logger.e("Failed to get user media: $e");
          if (_pcs.isEmpty) stop();
          return;
        }
      }
      
      // If we have existing peers (e.g. we were receiving), add tracks and renegotiate
      for (var uid in _pcs.keys) {
        _logger.i("Adding local stream to existing peer $uid");
        var pc = _pcs[uid]!;
        _localStream!.getTracks().forEach((track) {
          pc.addTrack(track, _localStream!);
        });
        
        // Renegotiate
        try {
          RTCSessionDescription offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          _sendSignal(uid, 'offer', offer.toMap());
        } catch (e) {
           _logger.e("Renegotiate error: $e");
        }
      }
    }

    await updatePeers(memberUids, initiator: initiator);
  }

  Future<void> stopLocalCapture() async {
    if (_localStream == null) return;
    _logger.i("Stopping local capture ($label)");

    // Stop tracks immediately
    _localStream!.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (e) {
        _logger.w("Error stopping track: $e");
      }
    });

    // Remove tracks from all peers and renegotiate concurrently
    final renegotiationFutures = <Future>[];
    for (var uid in _pcs.keys) {
      renegotiationFutures.add(_removeLocalTracksAndRenegotiate(uid));
    }
    
    // We don't necessarily need to wait for renegotiation to finish before cleaning up local stream object
    // But it's safer to let them run.
    
    try {
      await _localStream!.dispose();
    } catch (e) {
      _logger.w("Error disposing local stream: $e");
    }
    _localStream = null;
    
    await Future.wait(renegotiationFutures);
  }

  Future<void> _removeLocalTracksAndRenegotiate(String uid) async {
    var pc = _pcs[uid];
    if (pc == null) return;
    
    try {
      var senders = await pc.getSenders();
      for (var sender in senders) {
        await pc.removeTrack(sender);
      }

      // Renegotiate
      RTCSessionDescription offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sendSignal(uid, 'offer', offer.toMap());
    } catch (e) {
      _logger.w("Error removing tracks for $uid: $e");
    }
  }

  Future<void> stop() async {
    _logger.i("Stopping WebRTC Mesh");
    _isActive = false;
    
    // Stop local stream immediately
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        try {
          track.stop();
        } catch (e) {
          _logger.w("Error stopping track: $e");
        }
      });
      try {
        await _localStream!.dispose();
      } catch (e) {
        _logger.w("Error disposing local stream: $e");
      }
      _localStream = null;
    }

    // Close all peer connections concurrently
    final closeFutures = <Future>[];
    for (var pc in _pcs.values) {
      closeFutures.add(pc.close().catchError((e) {
        _logger.w("Error closing peer connection: $e");
      }));
    }
    await Future.wait(closeFutures);
    _pcs.clear();
  }

  void mute(bool muted) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !muted;
      });
    }
  }

  Future<void> muteOutput(bool muted) async {
    // 1. Iterate over cached remote streams (Preferred)
    for (var stream in _remoteStreams.values) {
      for (var track in stream.getAudioTracks()) {
        track.enabled = !muted;
        Helper.setVolume(muted ? 0.0 : _masterVolume, track);
      }
    }

    // 2. Fallback: Iterate over receivers
    for (var pc in _pcs.values) {
      var receivers = await pc.getReceivers();
      for (var receiver in receivers) {
        if (receiver.track != null && receiver.track!.kind == 'audio') {
          receiver.track!.enabled = !muted;
          // Helper.setVolume might not work on receiver.track directly if it's not same ref as stream track
          // but we try anyway or rely on streams loop above.
        }
      }
    }
  }

  void setMasterVolume(double volume) {
    _masterVolume = volume;
    for (var stream in _remoteStreams.values) {
      for (var track in stream.getAudioTracks()) {
        // If track is disabled (muted), we might keep it 0 or set it to volume but enabled=false handles it?
        // Usually volume applies when enabled. 
        // But if we are muted, we shouldn't unmute by setting volume.
        // We need to know if we are currently globally muted. 
        // But this method just sets the target volume.
        // If we want to support changing volume while muted without unmuting, we need _isMuted state.
        // For simplicity, we assume this is called when not muted or it updates the 'potential' volume.
        // Let's just set it. If track.enabled is false, no sound anyway.
        Helper.setVolume(volume, track);
      }
    }
  }

  void setPeerMute(String uid, bool muted) {
    // 1. Try cached stream
    if (_remoteStreams.containsKey(uid)) {
      var stream = _remoteStreams[uid];
      if (stream != null) {
        for (var track in stream.getAudioTracks()) {
          track.enabled = !muted;
          Helper.setVolume(muted ? 0.0 : _masterVolume, track);
        }
      }
    }

    // 2. Fallback: Receivers
    if (_pcs.containsKey(uid)) {
      _pcs[uid]?.getReceivers().then((receivers) {
        for (var receiver in receivers) {
          if (receiver.track != null && receiver.track!.kind == 'audio') {
            receiver.track!.enabled = !muted;
          }
        }
      });
    }
  }

  void setPeerVolume(String uid, double volume) {
    if (_pcs.containsKey(uid)) {
      var streams = _pcs[uid]?.getRemoteStreams();
      if (streams != null) {
        for (var stream in streams) {
          // ignore: unnecessary_null_checks
          if (stream == null) continue;
          for (var track in stream.getAudioTracks()) {
            Helper.setVolume(volume, track);
          }
        }
      }
    }
  }

  Future<void> updatePeers(List<String> activeMemberUids, {bool initiator = false}) async {
    if (!_isActive) return;
    _logger.i("Updating peers: $activeMemberUids");

    // Remove inactive peers
    final toRemove = <String>[];
    _pcs.forEach((uid, pc) {
      if (!activeMemberUids.contains(uid)) {
        toRemove.add(uid);
      }
    });

    for (var uid in toRemove) {
      _logger.i("Closing PeerConnection for $uid");
      await _pcs[uid]?.close();
      _pcs.remove(uid);
      if (onRemoteStreamRemoved != null) {
        onRemoteStreamRemoved!(uid);
      }
    }

    // Add new peers
    for (var uid in activeMemberUids) {
      if (uid != myUid && !_pcs.containsKey(uid)) {
        await _createPeer(uid, initiator: initiator);
      }
    }
  }

  Future<void> _sendSignal(String uid, String type, Map<String, dynamic> payload) async {
    final wrappedPayload = Map<String, dynamic>.from(payload);
    wrappedPayload['label'] = label;
    onSignal({
      'target': uid,
      'type': type,
      'payload': wrappedPayload,
    });
  }

  Future<void> _createPeer(String uid, {bool initiator = false}) async {
    _logger.i("Creating PeerConnection for $uid");
    RTCPeerConnection pc = await createPeerConnection(_config);
    _pcs[uid] = pc;

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    pc.onIceCandidate = (candidate) {
      _sendSignal(uid, 'candidate', candidate.toMap());
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'audio') {
        _logger.i("Received remote audio track from $uid");
        if (event.streams.isNotEmpty) {
          _remoteStreams[uid] = event.streams[0];
          
          // Ensure audio output is routed to speaker (mobile/desktop consistency)
          if (!kIsWeb) {
            Helper.setSpeakerphoneOn(true); 
          }
          
          // Force enable track
          event.track.enabled = true;
          Helper.setVolume(_masterVolume, event.track);
        }
      }
      if (onRemoteStream != null) {
        onRemoteStream!(event.streams[0], uid);
      }
    };

    pc.onRemoveTrack = (stream, track) {
      _logger.i("Remote track removed from $uid");
      if (stream.getTracks().isEmpty) {
        _remoteStreams.remove(uid);
        if (onRemoteStreamRemoved != null) {
          onRemoteStreamRemoved!(uid);
        }
      }
    };

    // If I am "smaller" UID (or some rule), I offer?
    // Web client uses: if (myUid < uid) createOffer
    // Let's mimic that to avoid glare.
    // If initiator is true, I force offer (e.g. screen sharer waking up viewers)
    if (initiator || myUid.compareTo(uid) < 0) {
      RTCSessionDescription offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sendSignal(uid, 'offer', offer.toMap());
    }
  }

  Future<void> handleSignal(String senderUid, String type, dynamic payload) async {
    if (!_isActive) return;

    // Check label if present in payload (backward compatibility: if no label, assume 'audio' if this is 'audio')
    // Actually, caller should filter. But we can check too.
    if (payload is Map && payload.containsKey('label')) {
      if (payload['label'] != label) return;
    }

    // In Mesh mode, we expect signals from specific UIDs.
    if (!_pcs.containsKey(senderUid)) {
       // Might be a new peer that initiated connection before updatePeers called?
       // Or we are the callee (myUid > senderUid).
       // We should create PC if not exists.
       if (myUid.compareTo(senderUid) > 0) { // Only if I am supposed to be answerer?
          // Actually, if they sent offer, I must answer regardless of ID comparison, 
          // but usually ID comparison decides who initiates.
          // If I receive offer, I must create PC.
          await _createPeer(senderUid);
       } else {
         // I should have initiated. If I didn't, maybe race condition.
         // Let's create anyway.
         await _createPeer(senderUid);
       }
    }

    RTCPeerConnection? pc = _pcs[senderUid];
    if (pc == null) return;

    try {
      if (type == 'offer') {
        final description = RTCSessionDescription(payload['sdp'], payload['type']);
        await pc.setRemoteDescription(description);
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _sendSignal(senderUid, 'answer', answer.toMap());
      } else if (type == 'answer') {
        final description = RTCSessionDescription(payload['sdp'], payload['type']);
        await pc.setRemoteDescription(description);
      } else if (type == 'candidate') {
        final candidate = RTCIceCandidate(
          payload['candidate'],
          payload['sdpMid'],
          payload['sdpMLineIndex'],
        );
        await pc.addCandidate(candidate);
      } else if (type == 'bye') {
        _logger.i("Received bye from $senderUid");
        await pc.close();
        _pcs.remove(senderUid);
        if (onRemoteStreamRemoved != null) {
          onRemoteStreamRemoved!(senderUid);
        }
      }
    } catch (e) {
      _logger.e("Error handling signal from $senderUid: $e");
    }
  }

  Future<Map<String, double>> getAudioLevels() async {
    final levels = <String, double>{};

    // 1. Local Level (try media-source or track)
    if (_localStream != null && _pcs.isNotEmpty) {
       try {
         final pc = _pcs.values.first;
         final stats = await pc.getStats();
         for (var report in stats) {
           // Standard: media-source
           if (report.type == 'media-source' && report.values['kind'] == 'audio') {
              final level = report.values['audioLevel'];
              if (level != null) {
                levels[myUid] = (level is num) ? level.toDouble() : 0.0;
              }
           }
           // Some implementations: track (if remoteSource is false/missing, implies local)
           // But 'track' usually means sender/receiver track.
         }
       } catch (e) {
         // ignore
       }
    }

    // 2. Remote Levels
    for (var entry in _pcs.entries) {
      final uid = entry.key;
      final pc = entry.value;
      try {
        final stats = await pc.getStats();
        for (var report in stats) {
          // Standard: inbound-rtp
          if (report.type == 'inbound-rtp' && report.values['kind'] == 'audio') {
             final level = report.values['audioLevel'];
             if (level != null) {
               levels[uid] = (level is num) ? level.toDouble() : 0.0;
             }
          }
          // Fallback: track (for remote tracks)
          if (report.type == 'track' && 
              report.values['kind'] == 'audio' && 
              report.values['remoteSource'] == true) {
              final level = report.values['audioLevel'];
              if (level != null) {
                levels[uid] = (level is num) ? level.toDouble() : 0.0;
              }
          }
          // Fallback 2: ssrc (sometimes contains audioLevel)
          if (report.type == 'ssrc' && report.values['audioOutputLevel'] != null) {
              final level = report.values['audioOutputLevel'];
               // Native sometimes uses 0-32768 or similar? No, standard is 0-1.
               // If it's big number, normalize.
               double dLevel = (level is num) ? level.toDouble() : 0.0;
               if (dLevel > 1.0) dLevel = dLevel / 32768.0; 
               levels[uid] = dLevel;
          }
        }
      } catch (e) {
        // ignore
      }
    }
    return levels;
  }
}
