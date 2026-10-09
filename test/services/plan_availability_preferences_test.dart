import 'dart:convert';

import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_availability_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('首次使用保留三个默认时段，默认不避让', () async {
    final loaded = await PlanAvailabilityPreferences.load('first');
    expect(loaded.options.map((w) => w.label), ['午休', '午餐', '晚餐']);
    expect(loaded.options.first.startMinutes, 720);
    expect(loaded.options.first.endMinutes, 840);
    expect(loaded.selectedIndices, isEmpty);
  });

  test('按账号保存勾选、调整的预设和自定义时段', () async {
    final windows = [
      const PlanDailyTimeWindow('午休', 750, 810),
      ...PlanAvailabilityPreferences.defaultWindows.skip(1),
      const PlanDailyTimeWindow('自定义', 900, 960),
    ];
    await PlanAvailabilityPreferences.save('a', windows, {
      windows[0],
      windows[3],
    });
    final a = await PlanAvailabilityPreferences.load('a');
    expect(a.selectedIndices, {0, 3});
    expect(a.options.first.startMinutes, 750);
    expect(a.options.first.endMinutes, 810);
    expect(a.options.last.startMinutes, 900);
    final b = await PlanAvailabilityPreferences.load('b');
    expect(b.options, hasLength(3));
    expect(b.selectedIndices, isEmpty);
  });

  test('全部取消和移除自定义也会保存，不恢复旧选项', () async {
    final windows = [
      ...PlanAvailabilityPreferences.defaultWindows,
      const PlanDailyTimeWindow('自定义', 900, 960),
    ];
    await PlanAvailabilityPreferences.save('a', windows, windows.toSet());
    await PlanAvailabilityPreferences.save(
      'a',
      PlanAvailabilityPreferences.defaultWindows,
      {},
    );
    final loaded = await PlanAvailabilityPreferences.load('a');
    expect(loaded.options, hasLength(3));
    expect(loaded.selectedIndices, isEmpty);
  });

  test('快速更新按顺序落盘，立即重开等到最后一次写入且快照不随草稿变化', () async {
    final windows = List.of(PlanAvailabilityPreferences.defaultWindows);
    final selected = {windows.first};
    final first = PlanAvailabilityPreferences.save('a', windows, selected);
    selected
      ..clear()
      ..add(windows.last);
    final last = PlanAvailabilityPreferences.save('a', windows, selected);
    windows.clear();
    selected.clear();
    final loaded = await PlanAvailabilityPreferences.load('a');
    await Future.wait([first, last]);
    expect(loaded.options, hasLength(3));
    expect(loaded.selectedIndices, {2});
  });

  test('损坏、类型错误或不支持版本的偏好退回默认值', () async {
    for (final raw in [
      '{',
      123,
      'null',
      '[]',
      jsonEncode({'version': 2, 'windows': []}),
      jsonEncode({'version': 1, 'windows': 'invalid'}),
    ]) {
      SharedPreferences.setMockInitialValues({
        'plan_availability_avoidance_a': raw,
      });
      final loaded = await PlanAvailabilityPreferences.load('a');
      expect(loaded.options, hasLength(3));
      expect(loaded.selectedIndices, isEmpty);
    }
  });

  test('非法时段不加载，后续有效自定义的勾选索引正确', () async {
    SharedPreferences.setMockInitialValues({
      'plan_availability_avoidance_a': jsonEncode({
        'version': 1,
        'windows': [
          null,
          {'label': '午餐', 'start': -1, 'end': 750, 'enabled': true},
          {'label': '晚餐', 'start': 1080, 'end': 1500, 'enabled': true},
          {'label': ' ', 'start': 900, 'end': 960, 'enabled': true},
          {'label': '自定义', 'start': 900, 'end': 960, 'enabled': true},
        ],
      }),
    });
    final loaded = await PlanAvailabilityPreferences.load('a');
    expect(loaded.options, hasLength(4));
    expect(loaded.options.first.label, '午休');
    expect(loaded.selectedIndices, {3});
    expect(loaded.options[3].label, '自定义');
  });
}
