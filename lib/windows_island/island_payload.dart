// IslandPayload DTO
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

    int toInt(dynamic v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) {
        return int.tryParse(v) ?? fallback;
      }
      return fallback;
    }

    bool toBool(dynamic v, [bool fallback = false]) {
      if (v is bool) return v;
      if (v is int) return v != 0;
      if (v is String) return v.toLowerCase() == 'true';
      return fallback;
    }

    String toStr(dynamic v) => (v == null) ? '' : v.toString();

    List<String> toStrList(dynamic v) {
      if (v is List) return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      return <String>[];
    }

    List<Map<String, String>> toReminderList(dynamic v) {
      if (v is List) {
        final out = <Map<String, String>>[];
        for (final item in v) {
          if (item is Map) {
            final mapped = <String, String>{};
            item.forEach((k, val) { mapped[k.toString()] = val?.toString() ?? ''; });
            out.add(mapped);
          }
        }
        return out;
      }
      return <Map<String, String>>[];
    }

    return IslandPayload(
      endMs: toInt(m['endMs'], 0),
      title: toStr(m['title']),
      tags: toStrList(m['tags']),
      isLocal: toBool(m['isLocal'], true),
      mode: toInt(m['mode'], 0),
      style: toInt(m['style'], 0),
      left: toStr(m['left']),
      right: toStr(m['right']),
      forceReset: toBool(m['forceReset'], false),
      topBarLeft: toStr(m['topBarLeft']),
      topBarRight: toStr(m['topBarRight']),
      reminderQueue: toReminderList(m['reminderQueue']),
      detailType: toStr(m['detail_type']),
      detailTitle: toStr(m['detail_title']),
      detailSubtitle: toStr(m['detail_subtitle']),
      detailLocation: toStr(m['detail_location']),
      detailTime: toStr(m['detail_time']),
      detailNote: toStr(m['detail_note']),
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
}

