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

      final before = currentEstimate();
      await tester.tap(find.text('注入更多'));
      await tester.pump();
      expect(find.text('注入更多: 开'), findsOneWidget);

      expect(currentEstimate(), before);
    },
  );
}
