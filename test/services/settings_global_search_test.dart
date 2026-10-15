import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/search_scope.dart';
import 'package:countdown_todo/services/app_settings_catalog.dart';
import 'package:countdown_todo/services/search_service.dart';
import 'package:countdown_todo/utils/app_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/search_scope_fixture.dart';

Future<List<SearchResult>> settings(String query) => SearchService.instance
    .search(query, scope: SearchScope.settings, recordHistory: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'every available directory item can be found through real settings search',
    () async {
      final sources = <String>[];
      for (final item in AppSettingsCatalog.available) {
        final results = await SearchService.instance.search(
          item.title,
          scope: SearchScope.settings,
          recordHistory: false,
          onSourceQueried: sources.add,
        );
        final matches = results.where(
          (result) =>
              result.extraData?['route'] == '/settings' &&
              result.extraData?['target'] == item.id,
        );
        expect(matches, hasLength(1), reason: item.id);
        expect(matches.single.breadcrumb, item.path);
        expect(
          results.every((result) => SearchScope.settings.includes(result.type)),
          isTrue,
        );
      }
      // Looking up settings does not read private business records.
      expect(sources, isEmpty);
    },
  );

  test('aliases, case-insensitive English and cross-field terms find specific controls', () async {
    for (final entry in {
      '液态玻璃透明度': 'liquid_glass_transparency',
      '玻璃 透明度': 'liquid_glass_transparency',
      'liquid GLASS': 'liquid_glass',
      '液态玻璃 模式': 'liquid_glass_mode',
      '番茄钟 休息': 'pomodoro_break',
      '通知 预算': 'notification_budget',
      '上下文 获取': 'ai_context_mode',
      '深色模式': 'theme',
      '课程导入': 'smart_import',
      '同步间隔': 'sync_interval',
    }.entries) {
      expect(
        (await settings(entry.key))
            .map((result) => result.extraData?['target']),
        contains(entry.value),
        reason: entry.key,
      );
    }
  });

  test('search has one result per destination and omits stale or unavailable controls', () async {
    for (final query in ['设置', '通知', '记账', '更新', '壁纸']) {
      final results = await settings(query);
      final targets = results
          .where((result) => result.extraData?['route'] == '/settings')
          .map((result) => result.extraData!['target'] as String)
          .toList();
      expect(targets.toSet(), hasLength(targets.length));
      expect(targets, isNot(contains('test_notification')));
      final available = AppSettingsCatalog.available
          .map((item) => item.id)
          .toSet();
      expect(targets.every(available.contains), isTrue);
    }
    if (!AppPlatform.isWindows) {
      expect(
        (await settings('Tai'))
            .where((result) => result.extraData?['target'] == 'tai_db'),
        isEmpty,
      );
    }
    if (!AppPlatform.isAndroid) {
      expect(
        (await settings('手环'))
            .where((result) => result.extraData?['target'] == 'band_sync'),
        isEmpty,
      );
    }
  });

  test('all scope also finds settings while business scope keeps its original results', () async {
    final fixture = SearchScopeFixture();
    await fixture.initialize();
    try {
      final all = await SearchService.instance.search(
        '液态玻璃透明度',
        recordHistory: false,
      );
      expect(
        all.map((result) => result.id),
        contains('setting_liquid_glass_transparency'),
      );
      final finance = await SearchService.instance.search(
        '预算提醒',
        scope: SearchScope.finance,
        recordHistory: false,
      );
      expect(
        finance.where((result) => SearchScope.settings.includes(result.type)),
        isEmpty,
      );
    } finally {
      await fixture.dispose();
    }
  });
}
