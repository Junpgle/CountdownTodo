import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/item_semantics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ItemSemanticsService', () {
    test('pickup codes stay pickup todos', () {
      expect(
        ItemSemanticsService.classifyCaptureIntent('顺丰已到驿站，取件码8866'),
        CaptureIntentKind.todo,
      );
      expect(
        ItemSemanticsService.domainKindForText('KFC A056 已出餐'),
        TodoDomainKind.pickup,
      );
    });

    test('an appointment pickup is a fixed schedule', () {
      expect(
        ItemSemanticsService.classifyCaptureIntent('明天14点预约取证'),
        CaptureIntentKind.fixedSchedule,
      );
    });

    test('an exam is a fixed schedule but exam preparation is a todo', () {
      expect(
        ItemSemanticsService.classifyCaptureIntent('明天14点到16点高数考试'),
        CaptureIntentKind.fixedSchedule,
      );
      expect(
        ItemSemanticsService.classifyCaptureIntent('今晚复习高数考试'),
        CaptureIntentKind.todo,
      );
    });

    test('self-directed work in a range is a plan block intent', () {
      expect(
        ItemSemanticsService.classifyCaptureIntent('今晚19点到21点写论文'),
        CaptureIntentKind.planBlock,
      );
    });

    test('an unknown time range asks for confirmation', () {
      expect(
        ItemSemanticsService.classifyCaptureIntent('明天15点到17点处理事情'),
        CaptureIntentKind.needsConfirmation,
      );
    });

    test('todo remarks can identify a pickup domain', () {
      final todo = TodoItem(title: '顺丰取件', remark: '取件码: 8866');

      expect(
        ItemSemanticsService.domainKindForTodo(todo),
        TodoDomainKind.pickup,
      );
    });

    test('ambiguous Jingdong titles are not treated as pickup todos', () {
      expect(
        ItemSemanticsService.specialTodoTypeForTitle('京东健康减重打卡'),
        'default',
      );
      expect(
        ItemSemanticsService.specialTodoTypeForTitle('京东快递'),
        'delivery',
      );
      expect(
        ItemSemanticsService.specialTodoTypeForTitle('京东取件'),
        'delivery',
      );
    });

    test('pickup codes are masked for exposed surfaces', () {
      expect(
        ItemSemanticsService.maskPickupSensitiveText('顺丰取件码 8866'),
        '顺丰取件码 ••66',
      );
      expect(
        ItemSemanticsService.maskPickupSensitiveText('KFC A056 已出餐'),
        'KFC ••56 已出餐',
      );
      expect(
        ItemSemanticsService.maskPickupSensitiveText('完成报告 A056'),
        '完成报告 A056',
      );
    });
  });
}
