// Island Payload Data Transfer Objects
// Consolidated from payload.dart and island_payload.dart
import 'dart:convert';
import 'package:uuid/uuid.dart';

/// DTO for island focus/payload data with legacy compatibility.
class IslandPayload {
  final int endMs;
  final String title;
  final List<String> tags;
  final bool isLocal;
  final int mode;
  final int style;
  final String left;
  final String right;
  final bool forceReset;
  final String topBarLeft;
  final String topBarRight;
  final List<Map<String, String>> reminderQueue;
  final String detailType;
  final String detailTitle;
  final String detailSubtitle;
  final String detailLocation;
  final String detailTime;
  final String detailNote;

  IslandPayload({
    required this.endMs,
    required this.title,
    required this.tags,
    required this.isLocal,
    required this.mode,
    required this.style,
    required this.left,
    required this.right,
    required this.forceReset,
    required this.topBarLeft,
    required this.topBarRight,
    required this.reminderQueue,
    required this.detailType,
    required this.detailTitle,
    required this.detailSubtitle,
    required this.detailLocation,
    required this.detailTime,
    required this.detailNote,
  });

  factory IslandPayload.fromMap(Map? m) {
    if (m == null) {
      return IslandPayload.empty();
    }

    return IslandPayload(
      endMs: _toInt(m['endMs'], 0),
      title: _toStr(m['title']),
      tags: _toStrList(m['tags']),
      isLocal: _toBool(m['isLocal'], true),
      mode: _toInt(m['mode'], 0),
      style: _toInt(m['style'], 0),
      left: _toStr(m['left']),
      right: _toStr(m['right']),
      forceReset: _toBool(m['forceReset'], false),
      topBarLeft: _toStr(m['topBarLeft']),
      topBarRight: _toStr(m['topBarRight']),
      reminderQueue: _toReminderList(m['reminderQueue']),
      detailType: _toStr(m['detail_type']),
      detailTitle: _toStr(m['detail_title']),
      detailSubtitle: _toStr(m['detail_subtitle']),
      detailLocation: _toStr(m['detail_location']),
      detailTime: _toStr(m['detail_time']),
      detailNote: _toStr(m['detail_note']),
    );
  }

  /// Create an empty/default payload
  factory IslandPayload.empty() {
    return IslandPayload(
      endMs: 0,
      title: '',
      tags: <String>[],
      isLocal: true,
      mode: 0,
      style: 0,
      left: '',
      right: '',
      forceReset: false,
      topBarLeft: '',
      topBarRight: '',
      reminderQueue: <Map<String, String>>[],
      detailType: '',
      detailTitle: '',
      detailSubtitle: '',
      detailLocation: '',
      detailTime: '',
      detailNote: '',
    );
  }

  Map<String, Object> toMap() {
    return {
      'endMs': endMs,
      'title': title,
      'tags': tags,
      'isLocal': isLocal,
      'mode': mode,
      'style': style,
      'left': left,
      'right': right,
      'forceReset': forceReset,
      'topBarLeft': topBarLeft,
      'topBarRight': topBarRight,
      'reminderQueue': reminderQueue,
      'detail_type': detailType,
      'detail_title': detailTitle,
      'detail_subtitle': detailSubtitle,
      'detail_location': detailLocation,
      'detail_time': detailTime,
      'detail_note': detailNote,
    };
  }

  // ── Type conversion helpers ────────────────────────────────────────────

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static bool _toBool(dynamic v, [bool fallback = false]) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v.toLowerCase() == 'true';
    return fallback;
  }

  static String _toStr(dynamic v) => (v == null) ? '' : v.toString();

  static List<String> _toStrList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  static List<Map<String, String>> _toReminderList(dynamic v) {
    if (v is List) {
      final out = <Map<String, String>>[];
      for (final item in v) {
        if (item is Map) {
          final mapped = <String, String>{};
          item.forEach((k, val) {
            mapped[k.toString()] = val?.toString() ?? '';
          });
          out.add(mapped);
        }
      }
      return out;
    }
    return <Map<String, String>>[];
  }
}

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
