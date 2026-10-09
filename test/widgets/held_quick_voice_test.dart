import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/mimo_asr_service.dart';
import 'package:countdown_todo/services/quick_voice_recorder.dart';
import 'package:countdown_todo/widgets/home_bottom_navigation_content.dart';
import 'package:countdown_todo/widgets/quick_voice_chat_sheet.dart';
import 'package:countdown_todo/widgets/quick_voice_gesture.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:countdown_todo/widgets/quick_voice_container_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Recorder implements QuickVoiceRecorder {
  Completer<void>? startup;
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  @override
  Future<void> start() async {
    starts++;
    await startup?.future;
  }

  @override
  Future<Uint8List> stop() async {
    stops++;
    return encodePcmWav(Uint8List(32000), sampleRate: 16000);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _Harness {
  final addKey = GlobalKey();
  final recorder = _Recorder();
  QuickVoiceGestureController? gesture;
  HeldQuickVoiceResult? result;
  int requests = 0;
  int completions = 0;
  int taps = 0;
  int tabChanges = 0;

  Future<void> pump(
    WidgetTester tester, {
    bool lens = true,
    bool reduceMotion = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 320,
                  height: 64,
                  child: FloatingBottomNavigationContent(
                    items: [
                      const FloatingBottomNavigationItem(
                        label: '首页',
                        icon: Icons.home,
                      ),
                      FloatingBottomNavigationItem(
                        key: addKey,
                        label: '新增',
                        icon: Icons.add,
                        selectable: false,
                        onPressed: () => taps++,
                        onLongPressStart: (details) {
                          gesture = QuickVoiceGestureController(
                            details.globalPosition,
                          );
                          unawaited(
                            showHeldQuickVoiceChat(
                              context: context,
                              apiKey: 'synthetic-key',
                              gesture: gesture!,
                              sourceKey: addKey,
                              recorder: recorder,
                              asrService: MimoAsrService(
                                authorize: () async => true,
                                recordUsage: (_) async =>
                                    const ChatUsageSummary(
                                      provider: 'mimo',
                                      model: MimoAsrService.model,
                                      audioSeconds: 4,
                                      costMicros: 556,
                                    ),
                                client: MockClient((_) async {
                                  requests++;
                                  return http.Response.bytes(
                                    utf8.encode(
                                      jsonEncode({
                                        'choices': [
                                          {
                                            'message': {'content': '明天交报告'},
                                          },
                                        ],
                                      }),
                                    ),
                                    200,
                                  );
                                }),
                              ),
                            ).then((value) {
                              result = value;
                              completions++;
                            }),
                          );
                        },
                        onLongPressMoveUpdate: (details) =>
                            gesture?.move(details.globalPosition),
                        onLongPressEnd: (details) {
                          gesture?.move(details.globalPosition);
                          gesture?.release();
                        },
                        onLongPressCancel: () => gesture?.release(cancel: true),
                      ),
                      const FloatingBottomNavigationItem(
                        label: '专注',
                        icon: Icons.timer,
                      ),
                    ],
                    selectedIndex: 0,
                    primaryColor: Theme.of(context).colorScheme.primary,
                    inactiveColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    selectedBackgroundColor: Theme.of(context)
                        .colorScheme
                        .surface,
                    onTabSelected: (_) => tabChanges++,
                    showSelectionLens: lens,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    addTearDown(() => gesture?.dispose());
  }

  Future<TestGesture> hold(WidgetTester tester) async {
    final bar = find.byKey(
      const ValueKey('floating-bottom-navigation-gesture-layer'),
    );
    final pointer = await tester.startGesture(tester.getCenter(bar));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(recorder.starts, 1);
    expect(requests, 0);
    return pointer;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PageTransitions.setPowerSaveMode(false);
  });

  Rect containerBounds(WidgetTester tester) {
    final clip = tester.widget<ClipPath>(
      find.byKey(const ValueKey('quick-voice-container-transform')),
    );
    return clip.clipper!.getClip(const Size(800, 600)).getBounds();
  }

  testWidgets(
    'container expands from actual plus and returns on cancellation',
    (tester) async {
      SharedPreferences.setMockInitialValues({'animation_duration': 800});
      final harness = _Harness();
      await harness.pump(tester);
      final source = tester.getRect(find.byKey(harness.addKey));
      final pointer = await tester.startGesture(source.center);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      final transition = tester.widget<QuickVoiceContainerTransition>(
        find.byType(QuickVoiceContainerTransition),
      );
      expect(transition.sourceRect, source);
      final initial = containerBounds(tester);
      expect(initial.left, closeTo(source.left, 0.001));
      expect(initial.top, closeTo(source.top, 0.001));
      expect(initial.width, closeTo(source.width, 0.001));
      expect(initial.height, closeTo(source.height, 0.001));
      await tester.pump(const Duration(milliseconds: 200));
      final middle = containerBounds(tester);
      expect(middle.width, greaterThan(source.width));
      expect(middle.width, lessThan(520));
      await tester.pump(const Duration(milliseconds: 600));
      final expanded = containerBounds(tester);
      expect(expanded.width, 520);
      expect(expanded.bottom, 600);
      await pointer.cancel();
      await tester.pump();
      expect(harness.recorder.disposed, true);
      expect(harness.completions, 0);
      await tester.pump(const Duration(milliseconds: 200));
      final shrinking = containerBounds(tester);
      expect(shrinking.width, lessThan(expanded.width));
      expect(shrinking.width, greaterThan(source.width));
      await tester.pumpAndSettle();
      expect(harness.completions, 1);
      expect(harness.requests, 0);
      expect(find.byType(QuickVoiceContainerTransition), findsNothing);
    },
  );

  for (final policy in ['disabled', 'reduced', 'powerSaver']) {
    testWidgets('container respects $policy motion policy', (tester) async {
      SharedPreferences.setMockInitialValues({
        'enable_animations': policy != 'disabled',
        'animation_duration': 2000,
      });
      PageTransitions.setPowerSaveMode(policy == 'powerSaver');
      final harness = _Harness();
      await harness.pump(tester, reduceMotion: policy == 'reduced');
      final pointer = await harness.hold(tester);
      expect(containerBounds(tester).width, 520);
      await pointer.cancel();
      await tester.pump();
      expect(harness.completions, 1);
      expect(harness.requests, 0);
      await tester.pumpAndSettle();
      expect(find.byType(QuickVoiceContainerTransition), findsNothing);
    });
  }
  for (final lens in [true, false]) {
    for (final target in QuickVoiceTarget.values) {
      testWidgets(
        'held plus ${target.name} in ${lens ? 'phone' : 'wide'} bar',
        (tester) async {
          final harness = _Harness();
          await harness.pump(tester, lens: lens);
          final pointer = await harness.hold(tester);
          expect(find.text('松手发送'), findsOneWidget);
          if (target != QuickVoiceTarget.send) {
            final delta = Offset(
              target == QuickVoiceTarget.openAi ? -85 : 85,
              -110,
            );
            await pointer.moveTo(harness.gesture!.origin + delta);
            await tester.pump(const Duration(milliseconds: 250));
            expect(harness.gesture!.target, target);
            expect(
              find.text(
                target == QuickVoiceTarget.cancel ? '松手取消' : '松手进入 AI · 保留草稿',
              ),
              findsOneWidget,
            );
            final chip = tester.widget<AnimatedContainer>(
              find.byKey(ValueKey('voice-target-${target.name}')),
            );
            final colors = Theme.of(
              tester.element(find.byType(QuickVoiceChatSheet)),
            ).colorScheme;
            expect(
              (chip.decoration as BoxDecoration).color,
              target == QuickVoiceTarget.cancel ? colors.error : colors.primary,
            );
          }
          await pointer.up();
          await tester.pumpAndSettle();
          expect(harness.completions, 1);
          expect(harness.recorder.disposed, true);
          expect(harness.taps, 0);
          expect(harness.tabChanges, 0);
          if (target == QuickVoiceTarget.cancel) {
            expect(harness.result, null);
            expect(harness.requests, 0);
            expect(harness.recorder.stops, 0);
          } else {
            expect(harness.requests, 1);
            expect(harness.recorder.stops, 1);
            expect(harness.result?.text, '明天交报告');
            expect(
              harness.result?.sendImmediately,
              target == QuickVoiceTarget.send,
            );
            expect(harness.result?.usageSummary?.costMicros, 556);
          }
          expect(tester.takeException(), null);
        },
      );
    }
  }

  testWidgets(
    'drag back restores send and pointer cancellation never uploads',
    (tester) async {
      final harness = _Harness();
      await harness.pump(tester);
      final pointer = await harness.hold(tester);
      await pointer.moveTo(harness.gesture!.origin + const Offset(90, -120));
      await tester.pump(const Duration(milliseconds: 200));
      expect(harness.gesture!.target, QuickVoiceTarget.cancel);
      await pointer.moveTo(harness.gesture!.origin);
      await tester.pump(const Duration(milliseconds: 200));
      expect(harness.gesture!.target, QuickVoiceTarget.send);
      await pointer.cancel();
      await tester.pumpAndSettle();
      expect(harness.requests, 0);
      expect(harness.recorder.disposed, true);
    },
  );

  testWidgets(
    'release during pending permission closes and cleans up late recorder',
    (tester) async {
      final harness = _Harness();
      harness.recorder.startup = Completer<void>();
      await harness.pump(tester);
      final pointer = await harness.hold(tester);
      await pointer.up();
      await tester.pumpAndSettle();
      expect(harness.completions, 1);
      expect(harness.requests, 0);
      expect(harness.recorder.disposed, false);
      harness.recorder.startup!.complete();
      await tester.pump();
      expect(harness.recorder.disposed, true);
    },
  );

  testWidgets('system back cancels held recording without leaving page', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.pump(tester);
    final pointer = await harness.hold(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(harness.requests, 0);
    expect(harness.completions, 1);
    expect(find.byType(FloatingBottomNavigationContent), findsOneWidget);
    await pointer.up();
  });

  testWidgets('reduced motion and large text keep hold targets usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness();
    await harness.pump(tester, reduceMotion: true, textScale: 2);
    final pointer = await harness.hold(tester);
    expect(find.text('进入 AI'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });
}
