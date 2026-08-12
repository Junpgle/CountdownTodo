import 'package:countdown_todo/features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('搜索习惯和设置时返回对应结果', () async {
    final habitResults = await SearchService.instance.search('习惯');
    final habitEntry = habitResults.firstWhere(
      (result) => result.id == 'feature_habit_center',
    );
    expect(habitEntry.type, SearchResultType.habit);
    expect(habitEntry.extraData?['route'], '/habits');

    final settingResults = await SearchService.instance.search('数据导出');
    final exportEntry = settingResults.firstWhere(
      (result) => result.id == 'setting_data_export',
    );
    expect(exportEntry.type, SearchResultType.setting);
    expect(exportEntry.extraData, {
      'route': '/settings',
      'target': 'data_export',
    });

    final sidebarResults = await SearchService.instance.search('侧边栏排序');
    final sidebarEntry = sidebarResults.firstWhere(
      (result) => result.id == 'setting_sidebar_menu',
    );
    expect(sidebarEntry.extraData, {
      'route': '/settings',
      'target': 'sidebar_menu',
    });
  });

  test('搜索自定义挑战中的任务名称', () async {
    await ThirtyDayChallengeRepository.startNewChallenge(
      title: '我的夏日挑战',
      taskTitles: ['整理房间', '去公园散步'],
    );

    final results = await SearchService.instance.search('整理房间');
    final challengeEntry = results.firstWhere(
      (result) => result.id == 'db_challenge_current',
    );

    expect(challengeEntry.type, SearchResultType.challenge);
    expect(challengeEntry.title, '我的夏日挑战');
    expect(challengeEntry.subtitle, contains('整理房间'));
    expect(challengeEntry.extraData?['route'], '/challenge');
  });
}
