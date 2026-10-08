import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/utils/semester_week_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      StorageService.keyCurrentUser: 'semester-week-test',
    });
  });

  test(
    'loads the selected semester calendar while today is outside it',
    () async {
      final start = DateTime.now().subtract(const Duration(days: 240));
      final semester = SemesterInfo(
        id: 'fall-term',
        name: '秋季学期',
        startDate: start,
        endDate: start.add(const Duration(days: 120)),
        isCurrent: true,
      );
      await StorageService.saveSemesters([semester]);
      await StorageService.setActiveSemesterId(semester.id);

      final context = await SemesterWeekContext.loadForToday();

      expect(context, isNotNull);
      expect(context!.weekForDate(start), 1);
      expect(context.appendWeekLabel(start, '日期'), '日期 · 第1周');
      expect(context.weekForDate(DateTime.now()), isNull);
    },
  );
}
