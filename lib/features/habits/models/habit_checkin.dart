import 'package:uuid/uuid.dart';

/// 打卡来源。
enum HabitCheckInSource {
  manual,
  notification,
  widget,
  import,
  health,
  wearable,
}

/// 习惯打卡事件：只用于数量型和时间点型习惯。
///
/// 打卡记录保存 UTC 时间、当时的时区偏移和已计算出的逻辑日期，
/// 用户旅行或切换时区后历史打卡不会自动移动到其他日期。
class HabitCheckIn {
  String uuid;
  String habitUuid;
  String? ruleRevisionUuid;

  /// 实际发生时间（UTC 毫秒）。
  int occurredAt;

  /// 逻辑日期（'yyyy-MM-dd'），由发生时本地的日期分界规则计算。
  String logicalDate;

  /// 发生时的时区偏移（分钟）。
  int timezoneOffsetMinutes;

  /// 数量型为本次增加值；时间点型为 0（实际时间看 [occurredAt]）。
  double value;

  String? note;
  HabitCheckInSource source;

  /// 防重复键：通知按钮或小组件重复提交时用于去重。
  String? dedupeKey;

  bool isDeleted;
  int version;
  String? deviceId;
  int createdAt;
  int updatedAt;

  HabitCheckIn({
    String? uuid,
    required this.habitUuid,
    this.ruleRevisionUuid,
    required this.occurredAt,
    required this.logicalDate,
    this.timezoneOffsetMinutes = 0,
    this.value = 0,
    this.note,
    this.source = HabitCheckInSource.manual,
    this.dedupeKey,
    this.isDeleted = false,
    this.version = 1,
    this.deviceId,
    int? createdAt,
    int? updatedAt,
  })  : uuid = uuid ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
  }

  /// 本地时间（由 UTC 毫秒 + 保存时的时区偏移还原）。
  DateTime get localOccurredAt {
    final utc = DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true);
    return utc.add(Duration(minutes: timezoneOffsetMinutes));
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'habit_uuid': habitUuid,
        'rule_revision_uuid': ruleRevisionUuid,
        'occurred_at': occurredAt,
        'logical_date': logicalDate,
        'timezone_offset_minutes': timezoneOffsetMinutes,
        'value': value,
        'note': note,
        'source': source.name,
        'dedupe_key': dedupeKey,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory HabitCheckIn.fromJson(Map<String, dynamic> json) {
    return HabitCheckIn(
      uuid: json['uuid']?.toString() ?? const Uuid().v4(),
      habitUuid: json['habit_uuid']?.toString() ?? '',
      ruleRevisionUuid: json['rule_revision_uuid']?.toString(),
      occurredAt: _parseMs(json['occurred_at']),
      logicalDate: json['logical_date']?.toString() ?? '',
      timezoneOffsetMinutes:
          int.tryParse(json['timezone_offset_minutes']?.toString() ?? '') ?? 0,
      value: double.tryParse(json['value']?.toString() ?? '') ?? 0,
      note: json['note']?.toString(),
      source: _parseSource(json['source']),
      dedupeKey: json['dedupe_key']?.toString(),
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
      deviceId: json['device_id']?.toString(),
      createdAt: _parseMs(json['created_at']),
      updatedAt: _parseMs(json['updated_at']),
    );
  }

  static HabitCheckInSource _parseSource(dynamic raw) {
    final name = raw?.toString();
    if (name == null) return HabitCheckInSource.manual;
    for (final source in HabitCheckInSource.values) {
      if (source.name == name) return source;
    }
    return HabitCheckInSource.manual;
  }

  static int _parseMs(dynamic v) {
    if (v == null) return DateTime.now().millisecondsSinceEpoch;
    final n = int.tryParse(v.toString());
    return n ?? DateTime.now().millisecondsSinceEpoch;
  }

  /// 生成稳定去重键，例如通知按钮重复提交。
  static String? buildDedupeKey(String habitUuid, String slot) =>
      'habit-checkin/$habitUuid/$slot';
}
