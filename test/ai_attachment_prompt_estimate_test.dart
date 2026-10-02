import 'dart:typed_data';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_multimodal_message_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/ai_context_mode.dart';
import 'package:countdown_todo/screens/todo_chat_screen.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:countdown_todo/services/feature_tip_service.dart';

void main() {
  group('pending attachment request text', () {
    test('uses the same fallback prompt for estimation and sending', () {
      final cases = [
        (ChatAttachmentKind.image, 'image/png', 'image.png'),
        (ChatAttachmentKind.audio, 'audio/wav', 'audio.wav'),
        (ChatAttachmentKind.video, 'video/mp4', 'video.mp4'),
        (ChatAttachmentKind.document, 'text/plain', 'notes.txt'),
      ];

      for (final (kind, mimeType, name) in cases) {
        final estimateText = AiMultimodalMessageBuilder.requestTextForAttachment(
          text: '',
          attachmentKind: kind,
        );
        final content = AiMultimodalMessageBuilder.buildContent(
          text: '',
          attachment: ChatImageAttachment(
            path: '/tmp/$name',
            name: name,
            mimeType: mimeType,
            kind: kind,
          ),
          bytes: Uint8List.fromList([1]),
          provider: 'custom',
        );

        expect(estimateText, isNotEmpty, reason: kind.name);
        expect(content.first['text'], estimateText, reason: kind.name);
      }
    });

    test('trims typed text and leaves no-attachment input empty', () {
      expect(
        AiMultimodalMessageBuilder.requestTextForAttachment(
          text: '  查看这些内容  ',
          attachmentKind: ChatAttachmentKind.image,
        ),
        '查看这些内容',
      );
      expect(
        AiMultimodalMessageBuilder.requestTextForAttachment(
          text: '',
          attachmentKind: null,
        ),
        isEmpty,
      );
    });
  });

  testWidgets(
    'expanding context does not lower the estimate for an explicit previous month',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await ChatStorageService.setSmartContextEnabled(true);
      await ChatStorageService.setContextMode(
        AiContextMode.smartContextInjection,
      );
      await ChatStorageService.setInjectMoreContext(false);
      await ChatStorageService.setShowContextPreview(true);
      await FeatureTipService.markTipShown('todo_chat_guide');

      final now = DateTime.now();
      final previousMonthDays = DateTime(now.year, now.month, 0).day;
      final timeLogs = <TimeLogItem>[
        for (var day = 1; day <= previousMonthDays; day++)
          TimeLogItem(
            id: 'previous-month-$day',
            title: '上月专注记录第 $day 天',
            startTime: DateTime(
              now.year,
              now.month - 1,
              day,
              9,
            ).millisecondsSinceEpoch,
            endTime: DateTime(
              now.year,
              now.month - 1,
              day,
              10,
            ).millisecondsSinceEpoch,
          ),
        for (var offset in [2, 6, 10, 14, 18, 22])
          TimeLogItem(
            id: 'future-$offset',
            title: '未来专注记录第 $offset 天',
            startTime: DateTime(
              now.year,
              now.month,
              now.day + offset,
              9,
            ).millisecondsSinceEpoch,
            endTime: DateTime(
              now.year,
              now.month,
              now.day + offset,
              10,
            ).millisecondsSinceEpoch,
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: TodoChatScreen(
            username: 'token-estimate-test',
            todos: const [],
            timeLogs: timeLogs,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField).first, '分析我上个月的效率');
      await tester.pump(const Duration(milliseconds: 500));

      int currentEstimate() {
        final estimateLabel = find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data?.startsWith('预计Token：~') == true,
        );
        expect(estimateLabel, findsOneWidget);
        return int.parse(
          tester.widget<SelectableText>(estimateLabel).data!.split('~').last,
        );
      }

      String currentContextPreview() {
        final preview = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((widget) => widget.data ?? '')
            .firstWhere((data) => data.startsWith('将注入：'));
        return preview;
      }

      final before = currentEstimate();
      final contextBefore = currentContextPreview();
      expect(before, greaterThan(0));
      expect(contextBefore, contains('专注记录'));
      await tester.tap(find.text('注入更多'));
      await tester.pump();
      expect(find.text('注入更多: 开'), findsOneWidget);

      expect(currentEstimate(), before);
      expect(currentContextPreview(), contextBefore);
    },
  );

  testWidgets('expanding context preserves a selected custom range', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await ChatStorageService.setSmartContextEnabled(true);
    await ChatStorageService.setContextMode(
      AiContextMode.smartContextInjection,
    );
    await ChatStorageService.setInjectMoreContext(false);
    await ChatStorageService.setShowContextPreview(true);
    await FeatureTipService.markTipShown('todo_chat_guide');

    final now = DateTime.now();
    final customStart = DateTime(now.year, now.month - 2, 1);
    final customEnd = DateTime(now.year, now.month, 0);
    final timeLogs = <TimeLogItem>[
      for (
        var day = 1;
        day <= DateTime(customStart.year, customStart.month + 1, 0).day;
        day++
      )
        TimeLogItem(
          id: 'custom-$day',
          title: '自定义范围专注记录第 $day 天，持续专注完成重要工作',
          startTime: DateTime(
            customStart.year,
            customStart.month,
            day,
            9,
          ).millisecondsSinceEpoch,
          endTime: DateTime(
            customStart.year,
            customStart.month,
            day,
            10,
          ).millisecondsSinceEpoch,
        ),
      for (var day in [1, 2])
        TimeLogItem(
          id: 'previous-$day',
          title: '上个月专注记录第 $day 天',
          startTime: DateTime(
            customEnd.year,
            customEnd.month,
            day,
            9,
          ).millisecondsSinceEpoch,
          endTime: DateTime(
            customEnd.year,
            customEnd.month,
            day,
            10,
          ).millisecondsSinceEpoch,
        ),
      for (var offset in [5, 10, 15])
        TimeLogItem(
          id: 'future-$offset',
          title: '未来专注记录第 $offset 天',
          startTime: DateTime(
            now.year,
            now.month,
            now.day + offset,
            9,
          ).millisecondsSinceEpoch,
          endTime: DateTime(
            now.year,
            now.month,
            now.day + offset,
            10,
          ).millisecondsSinceEpoch,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: TodoChatScreen(
          username: 'custom-range-token-estimate-test',
          todos: const [],
          timeLogs: timeLogs,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField).first, '分析我上个月的效率');
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.textContaining('不含附件、财务/习惯明细或原生工具定义'),
      findsOneWidget,
    );

    int currentEstimate() {
      final estimateLabel = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data?.startsWith('预计Token：~') == true,
      );
      expect(estimateLabel, findsOneWidget);
      return int.parse(
        tester.widget<SelectableText>(estimateLabel).data!.split('~').last,
      );
    }

    await tester.tap(find.text('自定义注入'));
    await tester.pump(const Duration(milliseconds: 500));
    Finder inputModeButton() =>
        find.byIcon(Icons.edit_outlined).evaluate().isNotEmpty
        ? find.byIcon(Icons.edit_outlined)
        : find.byIcon(Icons.edit);

    await tester.tap(inputModeButton().last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byType(TextField).last,
      '${customStart.month}/${customStart.day}/${customStart.year}',
    );
    await tester.pump();
    await tester.tap(find.text('OK').last);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(inputModeButton().last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byType(TextField).last,
      '${customEnd.month}/${customEnd.day}/${customEnd.year}',
    );
    await tester.pump();
    await tester.tap(find.text('OK').last);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('自定义注入: 开'), findsOneWidget);
    final before = currentEstimate();
    await tester.tap(find.text('注入更多'));
    await tester.pump();

    expect(find.text('自定义注入: 开'), findsOneWidget);
    expect(find.text('注入更多: 开'), findsOneWidget);
    expect(currentEstimate(), greaterThan(before));
  });
}
