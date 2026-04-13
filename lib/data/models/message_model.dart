import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, song, system }

class MessageModel {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final MessageType type;
  final String? linkedSongId;
  final String? linkedSongName;
  final DateTime timestamp;

  const MessageModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    this.type = MessageType.text,
    this.linkedSongId,
    this.linkedSongName,
    required this.timestamp,
  });

  bool get hasSong => linkedSongId != null;

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'text': text,
      'type': type.name,
      'linkedSongId': linkedSongId,
      'linkedSongName': linkedSongName,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory MessageModel.fromFirestore(Map<String, dynamic> data) {
    return MessageModel(
      id: data['id'] as String,
      userId: data['userId'] as String,
      userName: data['userName'] as String,
      text: data['text'] as String,
      type: MessageType.values.firstWhere(
        (t) => t.name == (data['type'] as String? ?? 'text'),
        orElse: () => MessageType.text,
      ),
      linkedSongId: data['linkedSongId'] as String?,
      linkedSongName: data['linkedSongName'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
