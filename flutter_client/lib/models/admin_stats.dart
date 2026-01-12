class ServerStats {
  final int peerCount;
  final int roomCount;
  final double avgPing;
  final double avgQueueSize;
  final int totalPacketsSent;
  final int totalPacketsLost;
  final int totalBytesSent;
  final int totalBytesReceived;
  final List<RoomStats> rooms;
  final int goroutineCount;
  final int allocMemory;
  final int totalAllocMemory;
  final int sysMemory;
  final int uptime;

  ServerStats({
    required this.peerCount,
    required this.roomCount,
    required this.avgPing,
    required this.avgQueueSize,
    required this.totalPacketsSent,
    required this.totalPacketsLost,
    required this.totalBytesSent,
    required this.totalBytesReceived,
    required this.rooms,
    required this.goroutineCount,
    required this.allocMemory,
    required this.totalAllocMemory,
    required this.sysMemory,
    required this.uptime,
  });

  factory ServerStats.fromJson(Map<String, dynamic> json) {
    return ServerStats(
      peerCount: json['peerCount'] ?? 0,
      roomCount: json['roomCount'] ?? 0,
      avgPing: (json['avgPing'] ?? 0).toDouble(),
      avgQueueSize: (json['avgQueueSize'] ?? 0).toDouble(),
      totalPacketsSent: json['totalPacketsSent'] ?? 0,
      totalPacketsLost: json['totalPacketsLost'] ?? 0,
      totalBytesSent: json['totalBytesSent'] ?? 0,
      totalBytesReceived: json['totalBytesReceived'] ?? 0,
      rooms:
          (json['rooms'] as List<dynamic>?)
              ?.map((e) => RoomStats.fromJson(e))
              .toList() ??
          [],
      goroutineCount: json['goroutineCount'] ?? 0,
      allocMemory: json['allocMemory'] ?? 0,
      totalAllocMemory: json['totalAllocMemory'] ?? 0,
      sysMemory: json['sysMemory'] ?? 0,
      uptime: json['uptime'] ?? 0,
    );
  }
}

class RoomStats {
  final String id;
  final String name;
  final int peerCount;
  final double avgPing;
  final int bytesSent;
  final int bytesReceived;

  RoomStats({
    required this.id,
    required this.name,
    required this.peerCount,
    required this.avgPing,
    required this.bytesSent,
    required this.bytesReceived,
  });

  factory RoomStats.fromJson(Map<String, dynamic> json) {
    return RoomStats(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      peerCount: json['peerCount'] ?? 0,
      avgPing: (json['avgPing'] ?? 0).toDouble(),
      bytesSent: json['bytesSent'] ?? 0,
      bytesReceived: json['bytesReceived'] ?? 0,
    );
  }
}
