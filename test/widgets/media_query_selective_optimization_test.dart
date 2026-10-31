import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SelectiveSizeConsumer extends StatelessWidget {
  final VoidCallback onBuild;
  const _SelectiveSizeConsumer({required this.onBuild});

  @override
  Widget build(BuildContext context) {
    onBuild();
    final size = MediaQuery.sizeOf(context);
    return SizedBox(
      width: size.width > 200 ? 50 : 20,
      height: 50,
      child: const Text('SizeConsumer'),
    );
  }
}

class _UnselectiveMediaQueryConsumer extends StatelessWidget {
  final VoidCallback onBuild;
  const _UnselectiveMediaQueryConsumer({required this.onBuild});

  @override
  Widget build(BuildContext context) {
    onBuild();
    final data = MediaQuery.of(context);
    return SizedBox(
      width: data.size.width > 200 ? 50 : 20,
      height: 50,
      child: const Text('UnselectiveConsumer'),
    );
  }
}

class _TestHarness extends StatefulWidget {
  final Widget child;

  const _TestHarness({required this.child});

  @override
  State<_TestHarness> createState() => _TestHarnessState();
}

class _TestHarnessState extends State<_TestHarness> {
  EdgeInsets insets = EdgeInsets.zero;

  void updateInsets(EdgeInsets newInsets) {
    setState(() {
      insets = newInsets;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: const Size(400, 800), viewInsets: insets),
          child: widget.child,
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MediaQuery.sizeOf isolates widget from keyboard viewInsets changes',
    (tester) async {
      var selectiveBuildCount = 0;
      var unselectiveBuildCount = 0;

      final childTree = Column(
        children: [
          _SelectiveSizeConsumer(onBuild: () => selectiveBuildCount++),
          _UnselectiveMediaQueryConsumer(
            onBuild: () => unselectiveBuildCount++,
          ),
        ],
      );

      await tester.pumpWidget(_TestHarness(child: childTree));
      expect(selectiveBuildCount, equals(1));
      expect(unselectiveBuildCount, equals(1));

      // Update insets on the parent MediaQuery
      final state = tester.state<_TestHarnessState>(find.byType(_TestHarness));
      state.updateInsets(const EdgeInsets.only(bottom: 300));
      await tester.pump();

      // The unselective consumer that accessed MediaQuery.of(context) MUST rebuild
      expect(unselectiveBuildCount, equals(2));

      // The optimized selective consumer that uses MediaQuery.sizeOf(context) MUST NOT rebuild!
      expect(
        selectiveBuildCount,
        equals(1),
        reason: 'MediaQuery.sizeOf(context) should not trigger rebuilds when viewInsets changes',
      );
    },
  );
}
