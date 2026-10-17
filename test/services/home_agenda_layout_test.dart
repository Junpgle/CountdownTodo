import 'dart:convert';

import 'package:countdown_todo/services/home_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const a = HomeLayoutTarget.mobileHome, b = HomeLayoutTarget.mobileFocus;
  test(
    'old visible schedule is anchor across groups; unrelated order is stable',
    () {
      final pair = HomeLayoutService.normalizePair(
        firstTarget: a,
        secondTarget: b,
        firstOrder: ['todos', 'planBlocks', 'finance'],
        secondOrder: ['pomodoro', 'courses', 'math'],
      );
      expect(pair.first.take(2), ['todos', 'finance']);
      expect(pair.second.take(3), ['pomodoro', 'agenda', 'math']);
      expect(
        [...pair.first, ...pair.second].where((k) => k == 'agenda'),
        hasLength(1),
      );
    },
  );
  test(
    'hidden schedule uses visible planning position and sources stay opt-in',
    () {
      final pair = HomeLayoutService.normalizePair(
        firstTarget: a,
        secondTarget: b,
        firstOrder: ['todos', 'planBlocks'],
        secondOrder: ['courses'],
        visibility: {'courses': false},
      );
      expect(pair.first.take(2), ['todos', 'agenda']);
      expect(pair.second.contains('agenda'), isFalse);
      final visibility = HomeLayoutService.normalizeVisibility(
        firstTarget: a,
        secondTarget: b,
        raw: {'courses': false},
      );
      expect(visibility['agenda'], isTrue);
      expect(visibility['agendaSchedules'], isFalse);
      expect(visibility['agendaPlans'], isTrue);
    },
  );
  test(
    'both hidden stay hidden, and new layout does not resurrect old keys',
    () {
      final visibility = HomeLayoutService.normalizeVisibility(
        firstTarget: a,
        secondTarget: b,
        raw: {'courses': false, 'planBlocks': false},
      );
      expect(visibility['agenda'], isFalse);
      final pair = HomeLayoutService.normalizePair(
        firstTarget: a,
        secondTarget: b,
        firstOrder: ['courses', 'todos'],
        secondOrder: ['agenda', 'planBlocks'],
      );
      expect(pair.second.first, 'agenda');
      expect(pair.first.contains('courses'), isFalse);
    },
  );
  test('persisted legacy visibility determines migration and new settings survive reload', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'agenda-layout',
      'home_layout_mobile_home_agenda-layout': jsonEncode([
        'todos',
        'planBlocks',
      ]),
      'home_layout_mobile_focus_agenda-layout': jsonEncode([
        'courses',
        'pomodoro',
      ]),
      'home_layout_visibility_mobile_agenda-layout': jsonEncode({
        'courses': false,
        'planBlocks': true,
      }),
    });
    final pair = await HomeLayoutService.loadPair(a, b),
        v = await HomeLayoutService.loadVisibility(a, b);
    expect(pair.first.take(2), ['todos', 'agenda']);
    expect(v['agendaSchedules'], isFalse);
    await HomeLayoutService.savePair(
      firstTarget: a,
      secondTarget: b,
      firstOrder: ['todos'],
      secondOrder: ['agenda'],
    );
    await HomeLayoutService.saveVisibility(
      firstTarget: a,
      secondTarget: b,
      visibility: {...v, 'agenda': false},
    );
    expect((await HomeLayoutService.loadPair(a, b)).second.first, 'agenda');
    expect((await HomeLayoutService.loadVisibility(a, b))['agenda'], isFalse);
  });
}
