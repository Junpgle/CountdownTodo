import 'package:countdown_todo/course_import/widgets/course_import_shared_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'CourseLoadingDialogController shows once, closes only its route, and disposes safely',
    (tester) async {
      final controller = CourseLoadingDialogController();
      late BuildContext hostContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      controller.show(hostContext, '正在导入课表...');
      // Second call while open must coalesce cleanly.
      controller.show(hostContext, '重复弹窗');
      await tester.pump();

      expect(controller.isOpen, isTrue);
      expect(find.text('正在导入课表...'), findsOneWidget);
      expect(find.text('重复弹窗'), findsNothing);

      // Push an unrelated dialog on top; closing controller must remove only its own route.
      showDialog<void>(
        context: hostContext,
        builder: (_) => const AlertDialog(content: Text('上层确认弹窗')),
      );
      await tester.pump();
      expect(find.text('上层确认弹窗'), findsOneWidget);

      await controller.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.isOpen, isFalse);
      expect(find.text('正在导入课表...'), findsNothing);
      expect(find.text('上层确认弹窗'), findsOneWidget);

      Navigator.of(hostContext, rootNavigator: true).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Calling dispose while open must remove active route without throwing.
      controller.show(hostContext, '销毁测试');
      await tester.pump();
      expect(find.text('销毁测试'), findsOneWidget);

      controller.dispose();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.isOpen, isFalse);
      expect(find.text('销毁测试'), findsNothing);
    },
  );

  testWidgets('CourseImportOptionCard renders copy and triggers onTap', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseImportOptionCard(
            icon: Icons.merge_rounded,
            title: '与现有课表共存',
            subtitle: '保留其他学期数据',
            accentColor: Colors.teal,
            highlighted: true,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('与现有课表共存'), findsOneWidget);
    expect(find.text('保留其他学期数据'), findsOneWidget);
    await tester.tap(find.text('与现有课表共存'));
    expect(tapped, isTrue);
  });
}
