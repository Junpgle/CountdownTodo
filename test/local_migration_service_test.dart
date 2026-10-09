import 'package:countdown_todo/services/local_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('迁移有失败记录时保留待处理标记和旧数据', () async {
    SharedPreferences.setMockInitialValues({
      'todo_list': ['broken legacy JSON'],
    });

    await LocalMigrationService.persistCompletionIfSuccessful(['待办解析失败']);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(LocalMigrationService.keyMigrationCompletedV4), isNull);
    expect(prefs.getStringList('todo_list'), ['broken legacy JSON']);
    expect(await LocalMigrationService.needsMigration(), isTrue);
  });

  test('所有本地记录成功迁移后才清除待处理标记', () async {
    SharedPreferences.setMockInitialValues({'todo_list': ['valid legacy row']});

    await LocalMigrationService.persistCompletionIfSuccessful([]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(LocalMigrationService.keyMigrationCompletedV4), isTrue);
    expect(await LocalMigrationService.needsMigration(), isFalse);
  });
}
