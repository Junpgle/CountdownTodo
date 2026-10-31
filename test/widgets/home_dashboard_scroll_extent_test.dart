import 'package:countdown_todo/screens/home_dashboard.dart';
import 'package:countdown_todo/widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone homepage tail reserves the pinned header and bottom inset', () {
    expect(
      homeDashboardPhoneScrollTailExtent(headerExtent: 112, bottomInset: 24),
      236,
    );
  });

  test('phone homepage tail remains usable without a pinned header', () {
    expect(
      homeDashboardPhoneScrollTailExtent(headerExtent: 0, bottomInset: 0),
      100,
    );
  });

  testWidgets(
    'pinned header layout updates headerExtent when an internal banner collapses',
    (tester) async {
      final showBanner = ValueNotifier<bool>(true);
      double? latestExtent;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingGlassPinnedHeaderLayout(
              initialHeaderExtent: 78,
              fadeContent: false,
              header: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 78, width: double.infinity),
                  ValueListenableBuilder<bool>(
                    valueListenable: showBanner,
                    builder: (context, visible, _) => visible
                        ? const SizedBox(height: 40, width: double.infinity)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              bodyBuilder: (context, headerExtent) {
                latestExtent = headerExtent;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(latestExtent, 118);

      showBanner.value = false;
      await tester.pump();
      await tester.pump();
      expect(latestExtent, 78);

      showBanner.dispose();
    },
  );
}
