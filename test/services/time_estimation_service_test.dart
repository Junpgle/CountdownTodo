import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/services/time_estimation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;
  final now = DateTime.now().subtract(const Duration(days: 1));

  Future<void> record(String id, String todo, String title, int minutes) async {
    await fixture.db.insert('pomodoro_records', {
      'uuid': id,
      'todo_uuid': todo,
      'todo_title': title,
      'start_time': now
          .subtract(Duration(minutes: minutes))
          .millisecondsSinceEpoch,
      'end_time': now.millisecondsSinceEpoch,
      'actual_duration': minutes * 60,
      'planned_duration': 25 * 60,
      'status': 'completed',
      'tag_uuids': '[]',
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
  }

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.dispose());

  test('一项任务三轮25分钟汇总为75分钟，不用最近单轮代替', () async {
    for (var i = 0; i < 3; i++) {
      await fixture.todo('done-$i', '复习高数', done: true);
      for (var j = 0; j < 3; j++) {
        await record('record-$i-$j', 'done-$i', '复习高数', 25);
      }
    }
    expect((await TimeEstimationService.estimate('复习高数')).estimatedMinutes, 75);
  });
  test('同名的不同完成任务分别保留，50、60、65分钟中位数为60', () async {
    final minutes = [50, 60, 65];
    for (var i = 0; i < 3; i++) {
      await fixture.todo('done-$i', '复习高数', done: true);
      await record('record-$i', 'done-$i', '复习高数', minutes[i]);
    }
    expect((await TimeEstimationService.estimate('复习高数')).estimatedMinutes, 60);
  });
  test('未执行规划不能反向污染估时', () async {
    for (var i = 0; i < 3; i++) {
      final title = '复习数学${['甲', '乙', '丙'][i]}';
      await fixture.todo('done-$i', title, done: true);
      await record('record-$i', 'done-$i', title, 60);
    }
    final before = await TimeEstimationService.estimate('复习数学');
    for (var i = 0; i < 20; i++) {
      await fixture.block(
        TodoPlanBlock(
          id: 'unused-$i',
          todoId: 'todo-target',
          titleSnapshot: '复习数学第$i章',
          startTime: now.millisecondsSinceEpoch,
          endTime: now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
          plannedMinutes: 180,
        ),
      );
    }
    expect(
      (await TimeEstimationService.estimate('复习数学')).estimatedMinutes,
      before.estimatedMinutes,
    );
  });
  test('没有匹配的历史层不能以零或无关平均值参与估算', () async {
    for (var i = 0; i < 3; i++) {
      final title = ['晨间瑜伽', '烘焙蛋糕', '跑步运动'][i];
      await fixture.todo('done-$i', title, done: true);
      await record('record-$i', 'done-$i', title, 120);
    }
    expect((await TimeEstimationService.estimate('打印资料')).estimatedMinutes, 15);
  });

  TimeEstimationHistory history(
    List<int> durations, {
    String title = '复习高数',
    int days = 1,
    String? group,
    Set<String> tags = const {},
  }) => TimeEstimationHistory([
    for (var i = 0; i < durations.length; i++)
      TimeEstimationSample(
        todoId: 'done-$i',
        title: title,
        actualSeconds: durations[i] * 60,
        endedAt: now.subtract(Duration(days: days)).millisecondsSinceEpoch,
        groupId: group,
        tagIds: tags,
      ),
  ]);
  TimeEstimationResult calculate(
    TimeEstimationHistory h, {
    String title = '复习高数',
    String? group,
    String? tag,
  }) => TimeEstimationService.estimateFromHistory(
    title,
    h,
    now: now,
    groupId: group,
    categoryTagId: tag,
  );
  for (final count in [0, 1, 2, 3, 4, 5]) {
    test('参考程度锁定样本边界$count，不把分数当准确率', () {
      final result = calculate(history(List.filled(count, 60)));
      expect(result.samples.length, count);
      expect(
        result.reference,
        count >= 5
            ? TimeEstimationReference.sufficient
            : count >= 3
            ? TimeEstimationReference.moderate
            : TimeEstimationReference.limited,
      );
      expect(result.referenceLabel, isNot(contains('%')));
    });
  }
  test('无相似层时同分组层归一化，不被零值压低', () {
    final result = calculate(
      history([120, 120, 120], title: '晨间瑜伽', group: 'group-a'),
      title: '打印资料',
      group: 'group-a',
    );
    expect(result.estimatedMinutes, 120);
    expect(result.reason, contains('同分组'));
    expect(result.similarTitles, isEmpty);
  });
  test('标签精确匹配，不把tag-1当成tag-10', () {
    final data = history([120, 120, 120], title: '晨间瑜伽', tags: {'tag-10'});
    expect(calculate(data, title: '打印资料', tag: 'tag-1').samples, isEmpty);
    expect(calculate(data, title: '打印资料', tag: 'tag-10').estimatedMinutes, 120);
  });
  test('离群值不拉到数小时，分布差异明显降低参考程度', () {
    final result = calculate(history([50, 60, 65, 600]));
    expect(result.estimatedMinutes, lessThanOrEqualTo(90));
    expect(result.reference, TimeEstimationReference.limited);
    expect(result.reason, contains('差异较大'));
  });
  test('过久历史、弱相似、未来与无效数据不获得较充分', () {
    expect(
      calculate(history(List.filled(8, 60), days: 400)).reference,
      TimeEstimationReference.limited,
    );
    expect(
      calculate(history(List.filled(8, 60), title: '复习高数第二册')).reference,
      isNot(TimeEstimationReference.sufficient),
    );
    expect(calculate(history([60], days: -1)).samples, isEmpty);
    expect(calculate(history([0, -1])).samples, isEmpty);
  });
  test('英文标准化匹配；仅展示实际使用的有界样本和前三标题', () {
    final result = calculate(
      history(List.filled(30, 75), title: 'Review, CODE!'),
      title: 'review code',
    );
    expect(result.estimatedMinutes, 75);
    expect(result.samples.length, TimeEstimationService.maxSimilarSamples);
    expect(result.similarTitles, ['Review, CODE!']);
    expect(() => result.samples.clear(), throwsUnsupportedError);
    expect(() => result.similarTitles.clear(), throwsUnsupportedError);
  });
  test('近期同组任务不能使久远的相似任务获得较充分参考', () {
    final old = history([60, 60, 60, 60, 60], days: 120, group: 'study');
    final recent = history(List.filled(20, 60), title: '打印资料', group: 'study');
    final combined = TimeEstimationHistory([
      ...old.samples,
      for (final s in recent.samples)
        TimeEstimationSample(
          todoId: 'recent-${s.todoId}',
          title: s.title,
          actualSeconds: s.actualSeconds,
          endedAt: s.endedAt,
          groupId: s.groupId,
        ),
    ]);
    expect(
      calculate(combined, group: 'study').reference,
      isNot(TimeEstimationReference.sufficient),
    );
  });

  test('空标题不匹配历史，返回明确空状态', () {
    final result = calculate(history([60, 60, 60]), title: '   ');
    expect(result.source, TimeEstimationSource.empty);
    expect(result.samples, isEmpty);
  });
}
