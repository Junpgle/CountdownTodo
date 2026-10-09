import 'dart:convert';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/models/ai_context_mode.dart';
import 'package:countdown_todo/screens/todo_chat_screen.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:countdown_todo/services/llm_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'plan_availability_fixture.dart';

void runVoiceChatEntryTest({required bool sendImmediately}) {
  testWidgets(
    'voice transcript preserves old chat and cost: autoSend=$sendImmediately',
    (tester) async {
      final fixture = PlanAvailabilityFixture();
      await tester.runAsync(fixture.initialize);
      debugDefaultTargetPlatformOverride = fixture.previousPlatform;
      addTearDown(() async => await tester.runAsync(fixture.dispose));
      FlutterSecureStorage.setMockInitialValues({});
      await ChatStorageService.setContextMode(AiContextMode.functionCalling);
      await LLMService.saveConfig(
        LLMConfig(
          provider: 'mimo',
          model: 'mimo-v2.6-flash',
          apiKey: 'synthetic-key',
          apiUrl: '${AiChatService.mimoApiBaseUrl}/chat/completions',
        ),
      );
      final old = await ChatStorageService.createSession(title: '已有对话');
      await ChatStorageService.saveHistory([
        ChatMessage(role: ChatRole.user, content: '之前的话题'),
      ], old.id);
      final requests = <Map<String, dynamic>>[];
      http.Client makeClient() => MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['model'] == 'mimo-v2.6-flash' && body['stream'] == true) {
          requests.add(body);
          return http.Response(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': '好的，我来帮你安排'},
                  'finish_reason': 'stop',
                },
              ],
            })}\n\ndata: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '语音提醒'},
              },
            ],
          }),
          200,
        );
      });
      const initialVoiceText = '明天九点提醒我交报告';
      const editedVoiceDraft = '我改成后天交报告';
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: TodoChatScreen(
              username: PlanAvailabilityFixture.username,
              todos: [],
              initialMessage: initialVoiceText,
              sendInitialMessage: sendImmediately,
              initialVoiceUsageSummary: const ChatUsageSummary(
                provider: 'mimo',
                model: 'mimo-v2.5-asr',
                audioSeconds: 4,
                costMicros: 556,
              ),
            ),
          ),
        );
        if (!sendImmediately) {
          await tester.enterText(
            find.byKey(const ValueKey('ai-chat-input')),
            editedVoiceDraft,
          );
          await tester.pump();
        }
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        if (!sendImmediately) {
          expect(requests, isEmpty);
          final draftSession = await ChatStorageService.getActiveSessionId();
          expect(await ChatStorageService.loadHistory(draftSession), isEmpty);
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('ai-chat-input')))
                .controller!
                .text,
            editedVoiceDraft,
          );
          final send = tester.widget<IconButton>(
            find.byKey(const ValueKey('ai-chat-send')),
          );
          expect(send.onPressed, isNotNull);
          // Invoke inside runWithClient's zone, as engine pointer dispatch
          // otherwise escapes the mocked HTTP client zone.
          await tester.runAsync(
            () => http.runWithClient(() async {
              send.onPressed!();
            }, makeClient),
          );
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
          }
        }
        expect(requests, hasLength(1));
        expect(requests.single['model'], 'mimo-v2.6-flash');
        final messages = requests.single['messages'] as List;
        final expectedMessage = sendImmediately
            ? initialVoiceText
            : editedVoiceDraft;
        expect(messages.last['content'], contains(expectedMessage));
        expect(jsonEncode(messages), isNot(contains('之前的话题')));
        expect(requests.single['tools'], isNotEmpty);
        final active = await ChatStorageService.getActiveSessionId();
        expect(active, isNot(old.id));
        final history = await ChatStorageService.loadHistory(active);
        expect(
          history.where((m) => m.role == ChatRole.user).single.content,
          expectedMessage,
        );
        expect(history.last.content, contains('好的，我来帮你安排'));
        expect(history.first.usageSummary?.costMicros, 556);
        expect(history.first.usageSummary?.audioSeconds, 4);
        expect(find.text('语音识别 ¥0.0006 · 录音 4 秒'), findsOneWidget);
        expect(
          (await ChatStorageService.loadHistory(old.id)).single.content,
          '之前的话题',
        );
        await tester.pump(const Duration(seconds: 1));
        expect(requests, hasLength(1));
        expect(find.byTooltip('语音对话'), findsOneWidget);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
      }, makeClient);
    },
  );
}
