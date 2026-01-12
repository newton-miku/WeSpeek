class RoomMember {
  final String uid;
  final String name;
  final String role; // "user", "admin", "owner"
  final bool inputDisabled;
  final bool outputDisabled;
  int latency;
  final bool webrtc; // Add webrtc field

  RoomMember({
    required this.uid,
    required this.name,
    this.role = 'user',
    this.inputDisabled = false,
    this.outputDisabled = false,
    this.latency = 0,
    this.webrtc = false, // Default false
  });

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      uid: json['uid'] ?? '',
      name: json['name'] ?? 'Unknown',
      role: json['role'] ?? 'user',
      inputDisabled: json['inputDisabled'] ?? false,
      outputDisabled: json['outputDisabled'] ?? false,
      latency: json['latency'] ?? 0,
      webrtc: json['webrtc'] ?? false, // Parse webrtc
    );
  }
}

class Room {
  final String id;
  final String group;
  final int order;
  final bool permanent;
  final String audioCodec;
  final int audioQuality;
  List<RoomMember> members;

  Room({
    required this.id,
    this.group = '',
    this.order = 0,
    this.permanent = false,
    this.audioCodec = 'opus',
    this.audioQuality = 6,
    List<RoomMember>? members,
  }) : members = members ?? [];

  factory Room.fromJson(Map<String, dynamic> json) {
    var membersList = <RoomMember>[];
    if (json['members'] != null) {
      json['members'].forEach((v) {
        membersList.add(RoomMember.fromJson(v));
      });
    }

    return Room(
      id: json['id'],
      group: json['group'] ?? '',
      order: json['order'] ?? 0,
      permanent: json['permanent'] ?? false,
      audioCodec: json['audioCodec'] ?? 'opus',
      audioQuality: json['audioQuality'] ?? 6,
      members: membersList,
    );
  }
}
