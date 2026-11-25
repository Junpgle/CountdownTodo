import 'package:countdown_todo/screens/settings/widgets/data_transfer_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataTransferScaffold', () {
    testWidgets('renders single-column layout on narrow phone width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: DataTransferScaffold(
            title: '测试传输',
            isEmbedded: false,
            primaryChildren: [Text('PRIMARY')],
            secondaryChildren: [Text('SECONDARY')],
            narrowChildren: [Text('NARROW_ONLY')],
          ),
        ),
      );

      expect(find.text('测试传输'), findsOneWidget);
      expect(find.text('NARROW_ONLY'), findsOneWidget);
      expect(find.text('PRIMARY'), findsNothing);
    });

    testWidgets(
      'renders two-column layout on wide width and hides embedded AppBar',
      (tester) async {
        tester.view.physicalSize = const Size(900, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: DataTransferScaffold(
              title: '嵌入标题',
              isEmbedded: true,
              primaryChildren: [Text('PRIMARY')],
              secondaryChildren: [Text('SECONDARY')],
              narrowChildren: [Text('NARROW_ONLY')],
            ),
          ),
        );

        expect(find.text('嵌入标题'), findsNothing);
        expect(find.text('PRIMARY'), findsOneWidget);
        expect(find.text('SECONDARY'), findsOneWidget);
        expect(find.text('NARROW_ONLY'), findsNothing);
      },
    );

    testWidgets('shows loading indicator when isLoading is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DataTransferScaffold(
            title: '加载页',
            isEmbedded: false,
            isLoading: true,
            primaryChildren: [Text('PRIMARY')],
            secondaryChildren: [Text('SECONDARY')],
            narrowChildren: [Text('NARROW_ONLY')],
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('PRIMARY'), findsNothing);
      expect(find.text('NARROW_ONLY'), findsNothing);
    });
  });

  group('DataTransferSectionCard & DataTransferPrimaryActionButton', () {
    testWidgets('renders optional icon header and busy/idle button states', (
      tester,
    ) async {
      var pressed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const DataTransferSectionCard(
                  icon: Icons.tune,
                  title: '选项卡片',
                  children: [Text('卡片内容')],
                ),
                DataTransferPrimaryActionButton(
                  onPressed: () => pressed++,
                  isBusy: false,
                  icon: Icons.upload_file,
                  label: '开始导出',
                  busyLabel: '导出中...',
                ),
                const DataTransferPrimaryActionButton(
                  onPressed: null,
                  isBusy: true,
                  icon: Icons.upload_file,
                  label: '开始导出',
                  busyLabel: '导出中...',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.text('选项卡片'), findsOneWidget);
      expect(find.text('卡片内容'), findsOneWidget);
      expect(find.text('开始导出'), findsOneWidget);
      expect(find.text('导出中...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('开始导出'));
      await tester.pump();
      expect(pressed, 1);
    });
  });
}
