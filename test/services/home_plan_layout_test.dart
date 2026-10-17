import 'package:countdown_todo/services/home_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const a = HomeLayoutTarget.mobileHome, b = HomeLayoutTarget.mobileFocus;
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'current_login_user': 'layout-test',
    }),
  );
  test('new home and wide layouts contain the real plan module once', () {
    expect(
      HomeLayoutService.defaultOrder(a).where((k) => k == 'agenda').length,
      1,
    );
    expect(HomeLayoutService.defaultOrder(b).contains('agenda'), isFalse);
    expect(
      HomeLayoutService.defaultOrder(HomeLayoutTarget.wideRight)
          .contains('agenda'),
      isTrue,
    );
  });
  test(
    'old custom order is preserved and missing module is added only once',
    () {
      final p = HomeLayoutService.normalizePair(
        firstTarget: a,
        secondTarget: b,
        firstOrder: ['todos', 'agenda'],
        secondOrder: ['pomodoro'],
      );
      expect(p.first.take(2), ['todos', 'agenda']);
      expect(
        [...p.first, ...p.second].where((k) => k == 'agenda').length,
        1,
      );
    },
  );
  test(
    'cross-tab move and explicit hidden setting survive persistence',
    () async {
      await HomeLayoutService.savePair(
        firstTarget: a,
        secondTarget: b,
        firstOrder: ['todos'],
        secondOrder: ['agenda', 'pomodoro'],
      );
      await HomeLayoutService.saveVisibility(
        firstTarget: a,
        secondTarget: b,
        visibility: {'agenda': false},
      );
      final pair = await HomeLayoutService.loadPair(a, b);
      expect(pair.first.contains('agenda'), isFalse);
      expect(pair.second.first, 'agenda');
      expect(
        (await HomeLayoutService.loadVisibility(a, b))['agenda'],
        isFalse,
      );
    },
  );
  test('duplicated plan module in old preferences is normalized', () {
    final p = HomeLayoutService.normalizePair(
      firstTarget: a,
      secondTarget: b,
      firstOrder: ['agenda', 'agenda', 'bad'],
      secondOrder: ['agenda'],
    );
    expect([...p.first, ...p.second].where((k) => k == 'agenda').length, 1);
    expect(p.first.contains('bad'), isFalse);
  });
}
