import 'dart:async';

import 'package:countdown_todo/widgets/settings_focus_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> reveal(WidgetTester tester) async {
  for (var i = 0; i < 85; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    if (find
        .byKey(const ValueKey('settings-focus-highlight'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
  }
}

void main() {
  testWidgets('locates a lazy off-screen control without changing its value', (
    tester,
  ) async {
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsFocusPage(
          labels: const ['目标开关'],
          child: Scaffold(
            body: ListView.builder(
              itemCount: 80,
              itemBuilder: (context, index) => index == 64
                  ? SwitchListTile(
                      title: const Text('目标开关'),
                      value: false,
                      onChanged: (_) => changed = true,
                    )
                  : SizedBox(height: 100, child: Text('选项 $index')),
            ),
          ),
        ),
      ),
    );
    await reveal(tester);
    expect(find.text('目标开关').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-focus-highlight')),
      findsOneWidget,
    );
    expect(changed, false);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('waits for async loading, then matches a dynamic date label', (
    tester,
  ) async {
    final load = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsFocusPage(
          labels: const ['开学日期:'],
          child: Scaffold(
            body: FutureBuilder<void>(
              future: load.future,
              builder: (_, snapshot) =>
                  snapshot.connectionState == ConnectionState.done
                  ? ListView(
                      children: const [
                        SizedBox(height: 1000),
                        Text('开学日期: 2026/09/01'),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    load.complete();
    await reveal(tester);
    expect(find.text('开学日期: 2026/09/01').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'conditional setting locates its prerequisite and explains availability',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsFocusPage(
            labels: const ['必应分辨率'],
            fallbackLabels: const ['壁纸来源'],
            child: Scaffold(
              body: ListView.builder(
                itemCount: 30,
                itemBuilder: (_, index) => SizedBox(
                  height: 70,
                  child: Text(index == 0 ? '壁纸来源' : '内容 $index'),
                ),
              ),
            ),
          ),
        ),
      );
      await reveal(tester);
      expect(find.text('壁纸来源').hitTestable(), findsOneWidget);
      expect(find.textContaining('满足设备、登录条件'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposed/loading pages cancel pending locator timers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsFocusPage(
          labels: ['尚未加载的选项'],
          child: Scaffold(body: CircularProgressIndicator()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });
}
