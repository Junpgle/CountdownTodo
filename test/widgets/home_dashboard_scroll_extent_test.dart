import 'package:countdown_todo/screens/home_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone homepage tail reserves the pinned header and bottom inset', () {
    expect(
      homeDashboardPhoneScrollTailExtent(
        headerExtent: 112,
        bottomInset: 24,
      ),
      236,
    );
  });

  test('phone homepage tail remains usable without a pinned header', () {
    expect(
      homeDashboardPhoneScrollTailExtent(
        headerExtent: 0,
        bottomInset: 0,
      ),
      100,
    );
  });
}
