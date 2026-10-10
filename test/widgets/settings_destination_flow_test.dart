import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/widgets/ai_settings_navigation_card.dart';
import 'package:countdown_todo/screens/settings/llm_config_page.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/utils/ai_settings_navigation.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpDestination(WidgetTester tester, String target) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      home: AiSettingsNavigation.pageFor(target, username: 'test'),
    ),
  );
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    if (find
        .byKey(const ValueKey('settings-focus-highlight'))
        .evaluate()
        .isNotEmpty) {
      break;
    }
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'enable_animations': false});
    PageTransitions.setPowerSaveMode(false);
    await PageTransitions.init();
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorage,
          (call) async => switch (call.method) {
            'readAll' => <String, String>{},
            'containsKey' => false,
            _ => null,
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  testWidgets(
    'semester date opens current semester editor and cancel preserves data',
    (tester) async {
      final semester = SemesterInfo(
        id: 'current',
        name: '测试学期',
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2027, 1, 18),
        isCurrent: true,
      );
      await StorageService.saveSemesters([semester]);
      await StorageService.setActiveSemesterId(semester.id);
      final before = (await StorageService.getSemesters())
          .map((s) => s.toJson())
          .toList();
      await pumpDestination(tester, 'semester_end');
      expect(find.text('编辑学期'), findsOneWidget);
      expect(find.text('放假日期: 2027/01/18').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-focus-highlight')),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        (await StorageService.getSemesters()).map((s) => s.toJson()).toList(),
        before,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('animated card enters page before opening semester editor', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_animations', true);
    await PageTransitions.init();
    await StorageService.saveSemesters([
      SemesterInfo(
        id: 'current',
        name: '动画测试',
        startDate: DateTime(2026, 9, 7),
        isCurrent: true,
      ),
    ]);
    await StorageService.setActiveSemesterId('current');
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        home: const Scaffold(
          body: AiSettingsNavigationCard(
            target: 'semester_start',
            username: 'test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('一键直达'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      if (find
          .byKey(const ValueKey('settings-focus-highlight'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(find.text('编辑学期'), findsOneWidget);
    expect(find.text('开学日期: 2026/09/07').hitTestable(), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('一键直达'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty semester list opens an unsaved creation editor', (
    tester,
  ) async {
    await StorageService.saveSemesters([]);
    await pumpDestination(tester, 'semester_start');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('选择开学日期').hitTestable(), findsOneWidget);
    expect(await StorageService.getSemesters(), isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recognition prompt opens model step and expands advanced settings',
    (tester) async {
      await pumpDestination(tester, 'llm_vision_prompt');
      final page = tester.widget<LLMConfigPage>(find.byType(LLMConfigPage));
      expect(page.initialStep, 2);
      expect(
        find.text('图片识别 Prompt（可用变量: {now}）').hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-focus-highlight')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in {
    'math_result_max': '结果最大值',
    'ai_context_mode': '上下文获取方式',
  }.entries) {
    testWidgets('${entry.key} locates the actual control after async loading', (
      tester,
    ) async {
      final before = await StorageService.getSettings();
      await pumpDestination(tester, entry.key);
      expect(find.text(entry.value).hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-focus-highlight')),
        findsOneWidget,
      );
      expect(await StorageService.getSettings(), before);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
