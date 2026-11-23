import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/widgets/manual_sync_dialog.dart';

void main() {
  Widget buildHost({
    required Size size,
    required bool initialSyncFinance,
    required ValueChanged<ManualSyncSelection?> onResult,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await showManualSyncOptionsDialog(
                    context,
                    initialSyncFinance: initialSyncFinance,
                  );
                  onResult(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('compact screen renders bottom sheet and toggles modules', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ManualSyncSelection? captured;
    await tester.pumpWidget(
      buildHost(
        size: const Size(390, 844),
        initialSyncFinance: false,
        onResult: (res) => captured = res,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('手动同步'), findsOneWidget);
    expect(find.text('当前通道：服务器同步 • 已选 8 / 9 项模块'), findsOneWidget);
    expect(find.text('服务器同步 (8)'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);

    // Toggle finance on -> 9/9 and button changes to 取消全选
    await tester.tap(find.text('记账'));
    await tester.pumpAndSettle();
    expect(find.text('当前通道：服务器同步 • 已选 9 / 9 项模块'), findsOneWidget);
    expect(find.text('服务器同步 (9)'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    // Tap 取消全选 -> 0/9 and submit button disabled
    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('当前通道：服务器同步 • 已选 0 / 9 项模块'), findsOneWidget);
    expect(find.text('请选择模块'), findsOneWidget);

    // Tap 待办事项 & 记账 -> 2/9 and submit
    await tester.tap(find.text('待办事项'));
    await tester.tap(find.text('记账'));
    await tester.pumpAndSettle();
    expect(find.text('服务器同步 (2)'), findsOneWidget);

    await tester.tap(find.text('服务器同步 (2)'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.syncTodos, isTrue);
    expect(captured!.syncFinance, isTrue);
    expect(captured!.syncCountdowns, isFalse);
    expect(captured!.selectedCount, 2);
  });

  testWidgets('wide screen renders centered dialog without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ManualSyncSelection? captured;
    await tester.pumpWidget(
      buildHost(
        size: const Size(1200, 800),
        initialSyncFinance: true,
        onResult: (res) => captured = res,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('当前通道：服务器同步 • 已选 9 / 9 项模块'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(captured, isNull);
  });

  testWidgets(
    'showManualSyncOptionsDialog with sourceKey opens floating dialog with container transform',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final buttonKey = GlobalKey();
      ManualSyncSelection? captured;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: IconButton(
                  key: buttonKey,
                  icon: const Icon(Icons.cloud_sync_rounded),
                  onPressed: () async {
                    captured = await showManualSyncOptionsDialog(
                      context,
                      initialSyncFinance: false,
                      sourceKey: buttonKey,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(buttonKey));
      await tester.pumpAndSettle();

      // Remains a floating dialog (host Scaffold is still the only Scaffold).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('手动同步'), findsOneWidget);
      expect(find.text('当前通道：服务器同步 • 已选 8 / 9 项模块'), findsOneWidget);
      expect(find.text('服务器同步 (8)'), findsOneWidget);

      await tester.tap(find.text('服务器同步 (8)'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.selectedCount, 8);
      expect(captured!.syncTodos, isTrue);
      expect(captured!.syncFinance, isFalse);
    },
  );
}
