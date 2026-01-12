class ChatMessage {
  final int id;
  final String uid;
  final String name;
  final String text;
  final int time;

  ChatMessage({
    this.id = 0,
    required this.uid,
    required this.name,
    required this.text,
    required this.time,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['ID'] ?? json['id'] ?? 0,
      uid: json['uid'] ?? '',
      name: json['name'] ?? '',
      text: json['text'] ?? '',
      time: json['time'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }
}
