import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/utils/app_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LiquidGlassEffectService.setEnabled(true);
  });

  tearDown(() async {
    await LiquidGlassEffectService.setEnabled(false);
    GlassPerformanceMonitor.stop();
  });

  testWidgets('glass snack bar uses the calling widget overlay', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    AppSnackBars.showSnackBar(
      pageContext,
      const SnackBar(content: Text('保存成功')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('保存成功'), findsOneWidget);
    AppSnackBars.clear(ScaffoldMessenger.of(pageContext));
  });

  testWidgets('saved messenger shows a message without overlay context', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppSnackBars.showSnackBarFromMessenger(
      messengerKey.currentState!,
      const SnackBar(content: Text('操作已完成')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('操作已完成'), findsOneWidget);
  });

  testWidgets('glass sheet keeps content height when the keyboard opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showAppModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (sheetContext) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                    ),
                    child: const SizedBox(
                      key: Key('sheet-content'),
                      height: 300,
                      width: 300,
                    ),
                  ),
                ),
                child: const Text('打开弹层'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开弹层'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byKey(const Key('sheet-content'))).height, 300);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('sheet-content'))).height, 300);
    expect(
      tester.getRect(find.byKey(const Key('sheet-content'))).bottom,
      lessThanOrEqualTo(500),
    );
  });

  testWidgets('glass sheet keeps ListTile working without Material ancestor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showAppModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheetContext) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.event_available_rounded),
                          title: const Text('新增固定日程'),
                          onTap: () => Navigator.pop(sheetContext, 'fixed'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.view_week_outlined),
                          title: const Text('打开规划界面'),
                          onTap: () => Navigator.pop(sheetContext, 'plan'),
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('打开弹层'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开弹层'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('新增固定日程'), findsOneWidget);
    expect(find.text('打开规划界面'), findsOneWidget);

    await tester.tap(find.text('新增固定日程'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
