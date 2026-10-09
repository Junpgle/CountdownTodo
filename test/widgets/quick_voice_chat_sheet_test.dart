import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/mimo_asr_service.dart';
import 'package:countdown_todo/services/quick_voice_recorder.dart';
import 'package:countdown_todo/widgets/quick_voice_chat_sheet.dart';
import 'package:countdown_todo/widgets/home_bottom_navigation_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Recorder implements QuickVoiceRecorder {
  Completer<void>? startup;
  Object? startError;
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  @override
  Future<void> start() async {
    starts++;
    await startup?.future;
    if (startError != null) throw startError!;
  }

  @override
  Future<Uint8List> stop() async {
    stops++;
    return encodePcmWav(Uint8List(32000), sampleRate: 16000);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

Future<void> _openSheet(
  WidgetTester tester,
  _Recorder recorder,
  MimoAsrService service,
  ValueChanged<String?> result, {
  ValueChanged<ChatUsageSummary>? onUsageSummary,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result(
              await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => QuickVoiceChatSheet(
                  apiKey: 'test-key',
                  recorder: recorder,
                  asrService: service,
                  onUsageSummary: onUsageSummary,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

MimoAsrService asr(Future<http.Response> Function(http.Request) handler) =>
    MimoAsrService(
      client: MockClient(handler),
      authorize: () async => true,
      recordUsage: (_) async => null,
    );
http.Response transcript() => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'choices': [
        {
          'message': {'content': '明天买牛奶'},
        },
      ],
    }),
  ),
  200,
);

void main() {
  testWidgets('recognized text forwards incurred ASR cost exactly once', (
    tester,
  ) async {
    final recorder = _Recorder();
    const summary = ChatUsageSummary(
      provider: 'mimo',
      model: MimoAsrService.model,
      audioSeconds: 4,
      costMicros: 556,
    );
    var usageWrites = 0;
    final forwarded = <ChatUsageSummary>[];
    String? result;
    final service = MimoAsrService(
      client: MockClient((_) async => transcript()),
      authorize: () async => true,
      recordUsage: (_) async {
        usageWrites++;
        return summary;
      },
    );
    await _openSheet(
      tester,
      recorder,
      service,
      (value) => result = value,
      onUsageSummary: forwarded.add,
    );
    await tester.tap(find.text('结束录音并发送'));
    await tester.pumpAndSettle();
    expect(result, '明天买牛奶');
    expect(usageWrites, 1);
    expect(forwarded, [summary]);
    expect(tester.takeException(), null);
  });

  testWidgets('record stop transcribes once and returns recognized text', (
    tester,
  ) async {
    final recorder = _Recorder();
    var requests = 0;
    String? result;
    await _openSheet(
      tester,
      recorder,
      asr((_) async {
        requests++;
        return transcript();
      }),
      (value) => result = value,
    );
    expect(find.textContaining('正在聆听'), findsOneWidget);
    await tester.tap(find.text('结束录音并发送'));
    await tester.pumpAndSettle();
    expect(result, '明天买牛奶');
    expect(recorder.stops, 1);
    expect(recorder.disposed, true);
    expect(requests, 1);
  });

  testWidgets(
    'cancel during microphone permission startup releases late recorder without sending',
    (tester) async {
      final recorder = _Recorder()..startup = Completer<void>();
      var requests = 0;
      String? result = 'pending';
      await _openSheet(
        tester,
        recorder,
        asr((_) async {
          requests++;
          return transcript();
        }),
        (value) => result = value,
      );
      await tester.tap(find.byTooltip('取消录音'));
      await tester.pumpAndSettle();
      expect(result, null);
      expect(recorder.disposed, false);
      recorder.startup!.complete();
      await tester.pump();
      expect(recorder.disposed, true);
      expect(requests, 0);
      expect(tester.takeException(), null);
    },
  );

  testWidgets('permission denial offers settings and never uploads', (
    tester,
  ) async {
    final recorder = _Recorder()..startError = MicrophoneAccessDenied();
    var requests = 0;
    await _openSheet(
      tester,
      recorder,
      asr((_) async {
        requests++;
        return transcript();
      }),
      (_) {},
    );
    expect(find.text('打开系统设置'), findsOneWidget);
    expect(find.text('重新录音'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(find.byTooltip('取消录音'));
    await tester.pumpAndSettle();
    expect(recorder.disposed, true);
  });

  testWidgets(
    'failed recognition retries same audio without starting a new recording',
    (tester) async {
      final recorder = _Recorder();
      var requests = 0;
      String? result;
      await _openSheet(
        tester,
        recorder,
        asr((_) async {
          requests++;
          return requests == 1 ? http.Response('', 500) : transcript();
        }),
        (value) => result = value,
      );
      await tester.tap(find.text('结束录音并发送'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      await tester.tap(find.text('重试识别'));
      await tester.pumpAndSettle();
      expect(result, '明天买牛奶');
      expect(recorder.starts, 1);
      expect(recorder.stops, 1);
      expect(requests, 2);
    },
  );

  testWidgets('60 second limit stops and submits automatically', (
    tester,
  ) async {
    final recorder = _Recorder();
    String? result;
    await _openSheet(
      tester,
      recorder,
      asr((_) async => transcript()),
      (value) => result = value,
    );
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(recorder.stops, 1);
    expect(result, '明天买牛奶');
  });

  testWidgets(
    'going into background cancels recording and returns no transcript',
    (tester) async {
      final recorder = _Recorder();
      var requests = 0;
      String? result = 'pending';
      await _openSheet(
        tester,
        recorder,
        asr((_) async {
          requests++;
          return transcript();
        }),
        (value) => result = value,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(result, null);
      expect(recorder.disposed, true);
      expect(requests, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  for (final lens in [true, false]) {
    testWidgets(
      'plus long press fires once without tap in ${lens ? 'phone' : 'wide'} bar',
      (tester) async {
        var taps = 0;
        var voices = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 60,
                  child: FloatingBottomNavigationContent(
                    items: [
                      const FloatingBottomNavigationItem(
                        label: '首页',
                        icon: Icons.home,
                      ),
                      FloatingBottomNavigationItem(
                        label: '新增',
                        icon: Icons.add,
                        selectable: false,
                        onPressed: () => taps++,
                        onLongPress: () => voices++,
                      ),
                      const FloatingBottomNavigationItem(
                        label: '专注',
                        icon: Icons.timer,
                      ),
                    ],
                    selectedIndex: 0,
                    primaryColor: Colors.blue,
                    inactiveColor: Colors.grey,
                    selectedBackgroundColor: Colors.white,
                    onTabSelected: (_) {},
                    showSelectionLens: lens,
                  ),
                ),
              ),
            ),
          ),
        );
        final bar = find.byKey(
          const ValueKey('floating-bottom-navigation-gesture-layer'),
        );
        await tester.longPressAt(tester.getCenter(bar));
        await tester.pump();
        expect(voices, 1);
        expect(taps, 0);
        await tester.tapAt(tester.getCenter(bar));
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(voices, 1);
      },
    );
  }
}
