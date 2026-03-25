// ...existing code... 
import 'dart:convert';
import 'package:uuid/uuid.dart';

class IslandPayload {
  final int v;
  final String msgId;
  final String type;
  final int timestamp;
  final String islandId;
  final Map<String, dynamic> payload;

  IslandPayload({
    this.v = 1,
    String? msgId,
    required this.type,
    int? timestamp,
    required this.islandId,
    required this.payload,
  })  : msgId = msgId ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'v': v,
        'msg_id': msgId,
        'type': type,
        'timestamp': timestamp,
        'island_id': islandId,
        'payload': payload,
      };

  String toJsonString() => jsonEncode(toJson());

  static IslandPayload fromJson(Map<String, dynamic> json) {
    return IslandPayload(
      v: json['v'] ?? 1,
      msgId: json['msg_id'],
      type: json['type'] ?? 'update',
      timestamp: json['timestamp'],
      islandId: json['island_id'] ?? 'island-1',
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
    );
  }
}

class IslandEvent {
  final String name;
  final Map<String, dynamic> payload;

  IslandEvent({required this.name, Map<String, dynamic>? payload}) : payload = payload ?? {};

  Map<String, dynamic> toJson() => {'name': name, 'payload': payload};
}

