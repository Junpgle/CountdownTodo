import 'package:countdown_todo/features/habits/services/habit_sync_conflict_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('忽略同步元数据后，相同习惯内容不再被视为冲突', () {
    final local = <String, dynamic>{
      'uuid': 'habit-1',
      'name': '阅读',
      'icon': '📖',
      'source_type': 1,
      'source_ids': '["tag-1"]',
      'current_rule_uuid': 'rule-1',
      'display_mode': 0,
      'version': 2,
      'device_id': 'device-local',
      'created_at': 100,
      'updated_at': 200,
      'has_conflict': 1,
      'conflict_data': '{}',
    };
    final remote = <String, dynamic>{
      'uuid': 'habit-1',
      'user_id': 1,
      'name': '阅读',
      'icon': '📖',
      'sourceType': 1,
      'sourceIds': ['tag-1'],
      'currentRuleUuid': 'rule-1',
      'displayMode': 0,
      'version': 9,
      'device_id': 'device-server',
      'created_at': 300,
      'updated_at': 400,
      'has_conflict': 1,
    };

    expect(
      HabitSyncConflictService.hasSameBusinessContent(local, remote),
      isTrue,
    );
  });

  test('首页展示位置不同仍然保留为真实冲突', () {
    final local = <String, dynamic>{
      'name': '阅读',
      'display_mode': 0,
      'source_ids': '[]',
    };
    final remote = <String, dynamic>{
      'name': '阅读',
      'display_mode': 2,
      'source_ids': '[]',
    };

    expect(
      HabitSyncConflictService.hasSameBusinessContent(local, remote),
      isFalse,
    );
  });
}
