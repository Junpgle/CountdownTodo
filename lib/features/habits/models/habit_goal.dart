import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../../../utils/json_value_parser.dart';

/// 习惯的数据来源类型。
///
/// - [recurringTodo]：完成型，绑定循环待办系列；
/// - [pomodoroTag]：时长型，绑定一个或多个专注标签；
/// - [durationCheckIn]：时长型，使用独立打卡事件累计时长；
/// - [quantityCheckIn]：数量型，使用独立打卡事件累计数量；
/// - [timeCheckIn]：时间点型，使用独立打卡事件记录实际发生时间。
enum HabitSourceType {
  recurringTodo,
  pomodoroTag,
  quantityCheckIn,
  timeCheckIn,
  durationCheckIn,
}

/// 首页展示位置。
///
/// 只影响首页展示，不影响待办自身和提醒。
enum HabitDisplayMode {
  habitOnly,
  todoOnly,
  both,
}

/// 习惯目标：表示习惯的身份、来源和展示设置。
///
/// 遵循项目通用同步模型：uuid、version、createdAt/updatedAt（UTC 毫秒）、
/// isDeleted 逻辑删除、hasConflict/conflictData 冲突快照。
class HabitGoal {
  String uuid;
  String name;
  String icon;
  HabitSourceType sourceType;

  /// 来源标识（JSON 数组）：
  /// - 完成型：一个循环待办系列 ID（recurrenceSeriesId）；
  /// - 时长型：多个专注标签 UUID；
  /// - 数量型 / 时间点型 / 独立时长型：可为空。
  List<String> sourceIds;

  /// 当前生效的规则版本 UUID。
  String? currentRuleUuid;

  HabitDisplayMode displayMode;

  /// 时长型：点击「开始专注」时的默认专注时长（分钟）；为空时使用专注设置默认值。
  int? defaultFocusMinutes;

  int sortOrder;
  bool isArchived;
  bool isDeleted;
  int version;
  String? deviceId;
  int createdAt;
  int updatedAt;
  bool hasConflict;
  Map<String, dynamic>? conflictData;

  HabitGoal({
    String? uuid,
    required this.name,
    this.icon = '🎯',
    this.sourceType = HabitSourceType.quantityCheckIn,
    List<String>? sourceIds,
    this.currentRuleUuid,
    this.displayMode = HabitDisplayMode.habitOnly,
    this.defaultFocusMinutes,
    this.sortOrder = 0,
    this.isArchived = false,
    this.isDeleted = false,
    this.version = 1,
    this.deviceId,
    int? createdAt,
    int? updatedAt,
    this.hasConflict = false,
    this.conflictData,
  })  : uuid = uuid ?? const Uuid().v4(),
        sourceIds = sourceIds ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 每次本地修改都必须调用，用于并发版本控制。
  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'icon': icon,
        'source_type': sourceType.index,
        'source_ids': jsonEncode(sourceIds),
        'current_rule_uuid': currentRuleUuid,
        'display_mode': displayMode.index,
        'default_focus_minutes': defaultFocusMinutes,
        'sort_order': sortOrder,
        'is_archived': isArchived ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'has_conflict': hasConflict ? 1 : 0,
        'conflict_data': conflictData != null ? jsonEncode(conflictData) : null,
      };

  factory HabitGoal.fromJson(Map<String, dynamic> json) {
    return HabitGoal(
      uuid: json['uuid']?.toString() ?? const Uuid().v4(),
      name: json['name']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '🎯',
      sourceType: HabitSourceType
          .values[int.tryParse(json['source_type']?.toString() ?? '') ?? 2],
      sourceIds: _parseStringList(json['source_ids']),
      currentRuleUuid: json['current_rule_uuid']?.toString(),
      displayMode: HabitDisplayMode
          .values[int.tryParse(json['display_mode']?.toString() ?? '') ?? 0],
      defaultFocusMinutes:
          int.tryParse(json['default_focus_minutes']?.toString() ?? ''),
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
      isArchived: json['is_archived'] == 1 || json['is_archived'] == true,
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
      deviceId: json['device_id']?.toString(),
      createdAt: _parseMs(json['created_at']),
      updatedAt: _parseMs(json['updated_at']),
      hasConflict: json['has_conflict'] == 1 || json['has_conflict'] == true,
      conflictData: _mapOrNull(json['conflict_data']),
    );
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  static Map<String, dynamic>? _mapOrNull(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static int _parseMs(dynamic v) {
    return JsonValueParser.epochMillisOrNow(v);
  }
}
