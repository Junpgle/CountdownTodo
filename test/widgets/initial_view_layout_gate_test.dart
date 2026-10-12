import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:countdown_todo/widgets/initial_view_layout_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('waits one laid-out frame before mounting focusable app UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      InitialViewLayoutGate(
        child: MaterialApp(
          home: Scaffold(
            body: TextButton(onPressed: () {}, child: const Text('首页')),
          ),
        ),
      ),
    );

    expect(find.text('首页'), findsNothing);
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.forward,
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pump();
    expect(find.text('首页'), findsOneWidget);
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.forward,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
