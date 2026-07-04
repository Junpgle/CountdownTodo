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
  final String note;
  final bool isPaused;
  final int accumulatedMs;
  final int pauseStartMs;

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
    required this.note,
    this.isPaused = false,
    this.accumulatedMs = 0,
    this.pauseStartMs = 0,
  });

  factory IslandPayload.fromMap(Map? m) {
    if (m == null) return IslandPayload.empty();

    return IslandPayload(
      endMs: _toInt(m['endMs']),
      title: _toStr(m['title']),
      tags: _toStrList(m['tags']),
      isLocal: _toBool(m['isLocal'], true),
      mode: _toInt(m['mode']),
      style: _toInt(m['style']),
      left: _toStr(m['left']),
      right: _toStr(m['right']),
      forceReset: _toBool(m['forceReset']),
      topBarLeft: _toStr(m['topBarLeft']),
      topBarRight: _toStr(m['topBarRight']),
      reminderQueue: _toReminderList(m['reminderQueue']),
      detailType: _toStr(m['detail_type']),
      detailTitle: _toStr(m['detail_title']),
      detailSubtitle: _toStr(m['detail_subtitle']),
      detailLocation: _toStr(m['detail_location']),
      detailTime: _toStr(m['detail_time']),
      detailNote: _toStr(m['detail_note']),
      note: _toStr(m['note']),
      isPaused: _toBool(m['isPaused']),
      accumulatedMs: _toInt(m['accumulatedMs']),
      pauseStartMs: _toInt(m['pauseStartMs']),
    );
  }

  factory IslandPayload.empty() {
    return IslandPayload(
      endMs: 0,
      title: '',
      tags: const <String>[],
      isLocal: true,
      mode: 0,
      style: 0,
      left: '',
      right: '',
      forceReset: false,
      topBarLeft: '',
      topBarRight: '',
      reminderQueue: const <Map<String, String>>[],
      detailType: '',
      detailTitle: '',
      detailSubtitle: '',
      detailLocation: '',
      detailTime: '',
      detailNote: '',
      note: '',
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
      'note': note,
      'isPaused': isPaused,
      'accumulatedMs': accumulatedMs,
      'pauseStartMs': pauseStartMs,
    };
  }

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

  static String _toStr(dynamic v) => v?.toString() ?? '';

  static List<String> _toStrList(dynamic v) {
    if (v is! List) return const <String>[];
    return v
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static List<Map<String, String>> _toReminderList(dynamic v) {
    if (v is! List) return const <Map<String, String>>[];
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
}
