import 'package:countdown_todo/widgets/home_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pie chart painters stay mounted through animation frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenTimeCard(
            stats: [
              {
                'duration': 60,
                'device_name': 'Test Phone',
                'app_name': 'Editor',
              },
              {
                'duration': 30,
                'device_name': 'Windows PC',
                'app_name': 'Browser',
              },
            ],
            hasPermission: true,
            lastSyncTime: DateTime(2026, 10, 17, 12, 34),
            onOpenSettings: () {},
            onViewDetail: () {},
          ),
        ),
      ),
    );

    PieChartPainter painterFor(bool isAppChart) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<PieChartPainter>()
        .singleWhere((painter) => painter.isAppChart == isAppChart);

    final initialDevicePainter = painterFor(false);
    final initialAppPainter = painterFor(true);
    final initialProgress = initialDevicePainter.currentSweepProgress;
    expect(find.text('更新: 12:34'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));

    final updatedDevicePainter = painterFor(false);
    final updatedAppPainter = painterFor(true);

    expect(identical(updatedDevicePainter, initialDevicePainter), isTrue);
    expect(identical(updatedAppPainter, initialAppPainter), isTrue);
    expect(
      updatedDevicePainter.currentSweepProgress,
      greaterThan(initialProgress),
    );
    expect(updatedDevicePainter.currentSweepProgress, lessThan(1));
  });

  testWidgets('screen time charts cache by stats snapshot', (tester) async {
    var stats = <dynamic>[
      {'duration': 60, 'device_name': 'Test Phone', 'app_name': 'Editor'},
      {'duration': 30, 'device_name': 'Test Phone', 'app_name': 'Browser'},
      {'duration': 20, 'device_name': 'Windows PC', 'app_name': 'Writer'},
      {'duration': 10, 'device_name': 'Test Tablet', 'app_name': 'Chat'},
      {'duration': 5, 'device_name': 'Test Phone', 'app_name': 'Music'},
    ];
    var isLight = false;
    late StateSetter updateParent;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateParent = setState;
            return Scaffold(
              body: ScreenTimeCard(
                stats: stats,
                isLight: isLight,
                hasPermission: true,
                onOpenSettings: () {},
                onViewDetail: () {},
              ),
            );
          },
        ),
      ),
    );

    PieChartPainter painterFor(bool isAppChart) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<PieChartPainter>()
        .singleWhere((painter) => painter.isAppChart == isAppChart);

    final originalDevicePainter = painterFor(false);
    final originalAppPainter = painterFor(true);
    expect(originalDevicePainter.total, 125);
    expect(originalDevicePainter.data, {'手机': 95, '电脑': 20, '平板': 10});
    expect(originalAppPainter.data, {
      'Editor': 60,
      'Browser': 30,
      'Writer': 20,
      '其他': 15,
    });

    updateParent(() => isLight = true);
    await tester.pump();

    expect(identical(painterFor(false), originalDevicePainter), isTrue);
    expect(identical(painterFor(true), originalAppPainter), isTrue);

    updateParent(() {
      stats = [
        {'duration': 120, 'device_name': 'Test Phone', 'app_name': 'Notes'},
      ];
    });
    await tester.pump();

    final updatedDevicePainter = painterFor(false);
    final updatedAppPainter = painterFor(true);
    expect(identical(updatedDevicePainter, originalDevicePainter), isFalse);
    expect(identical(updatedAppPainter, originalAppPainter), isFalse);
    expect(updatedDevicePainter.total, 120);
    expect(updatedDevicePainter.data, {'手机': 120});
    expect(updatedAppPainter.data, {'Notes': 120});
  });
}
