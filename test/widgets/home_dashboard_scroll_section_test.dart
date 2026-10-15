import 'dart:async';

import 'package:countdown_todo/widgets/home_dashboard_scroll_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoadingSection extends StatefulWidget {
  const _LoadingSection({required this.onLoad});

  final VoidCallback onLoad;

  @override
  State<_LoadingSection> createState() => _LoadingSectionState();
}

class _LoadingSectionState extends State<_LoadingSection> {
  bool loaded = false;
  late final Timer timer;

  @override
  void initState() {
    super.initState();
    widget.onLoad();
    timer = Timer(const Duration(milliseconds: 10), () {
      setState(() => loaded = true);
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(height: loaded ? 120 : 223);
}

void main() {
  testWidgets(
    'gentle drag across cache boundary retains loaded section height',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 384,
              height: 400,
              child: ListView.builder(
                controller: controller,
                itemCount: 3,
                itemBuilder: (context, index) => HomeDashboardScrollSection(
                  key: ValueKey(index),
                  child: index == 0
                      ? _LoadingSection(onLoad: () => loads++)
                      : const SizedBox(height: 2000),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      controller.jumpTo(500);
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(ListView)) + const Offset(180, 50),
      );
      var previous = controller.offset;
      for (var i = 0; i < 80; i++) {
        await gesture.moveBy(const Offset(0, 4));
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          controller.offset,
          lessThanOrEqualTo(previous + 0.01),
          reason: 'A steady drag must not jump back when a section reenters.',
        );
        previous = controller.offset;
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(250));

      // Cross the same boundary after release, while inertia is still active.
      controller.jumpTo(500);
      await tester.pump();
      await tester.fling(find.byType(ListView), const Offset(0, 60), 600);
      expect(controller.offset, greaterThan(370));
      previous = controller.offset;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          controller.offset,
          lessThanOrEqualTo(previous + 0.01),
          reason: 'Inertia must not jump back when a section reenters.',
        );
        previous = controller.offset;
      }
      expect(controller.offset, lessThan(370));
      expect(
        loads,
        1,
        reason: 'Leaving the cache must not restart async loading.',
      );
    },
  );
}
