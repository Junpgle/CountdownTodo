// Island Payload Data Transfer Objects
// Consolidated from payload.dart and island_payload.dart
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../services/island_payload_model.dart' as common;

typedef IslandPayload = common.IslandPayload;

/// Message envelope for island IPC communication.
class IslandMessage {
  final int v;
  final String msgId;
  final String type;
  final int timestamp;
  final String islandId;
  final Map<String, dynamic> payload;

  IslandMessage({
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

  static IslandMessage fromJson(Map<String, dynamic> json) {
    return IslandMessage(
      v: json['v'] ?? 1,
      msgId: json['msg_id'],
      type: json['type'] ?? 'update',
      timestamp: json['timestamp'],
      islandId: json['island_id'] ?? 'island-1',
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
    );
  }
}

/// Simple event for island state changes.
class IslandEvent {
  final String name;
  final Map<String, dynamic> payload;

  IslandEvent({required this.name, Map<String, dynamic>? payload})
      : payload = payload ?? {};

  Map<String, dynamic> toJson() => {'name': name, 'payload': payload};
}
