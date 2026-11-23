import 'package:uuid/uuid.dart';

import '../../../utils/json_value_parser.dart';

/// 戒饮/控糖类习惯的常用饮品图标选项（支持自定义与云同步）。
class HabitDrinkOption {
  String uuid;
  String icon;
  String label;
  int sortOrder;
  bool isDeleted;
  int version;
  String? deviceId;
  int createdAt;
  int updatedAt;

  HabitDrinkOption({
    String? uuid,
    required this.icon,
    required this.label,
    this.sortOrder = 0,
    this.isDeleted = false,
    this.version = 1,
    this.deviceId,
    int? createdAt,
    int? updatedAt,
  }) : uuid = uuid ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 兼容旧调用的只读标识别名。
  String get id => uuid;

  /// 写入 [HabitCheckIn.note] 的标准可读标记。
  String get noteText => '$icon $label';

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
  }

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'icon': icon,
    'label': label,
    'sort_order': sortOrder,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory HabitDrinkOption.fromJson(Map<String, dynamic> json) {
    return HabitDrinkOption(
      uuid: json['uuid']?.toString() ?? const Uuid().v4(),
      icon: json['icon']?.toString() ?? '🥤',
      label: json['label']?.toString() ?? '',
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
      deviceId: json['device_id']?.toString(),
      createdAt: JsonValueParser.epochMillisOrNow(json['created_at']),
      updatedAt: JsonValueParser.epochMillisOrNow(json['updated_at']),
    );
  }
}
