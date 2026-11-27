import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/optional_liquid_glass_backdrop.dart';
import 'package:countdown_todo/widgets/sticky_announcement_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setPowerSaveMode(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
  });

  testWidgets('shows the announcement creation time', (tester) async {
    final announcement = TeamAnnouncement(
      uuid: 'announcement-1',
      teamUuid: 'team-1',
      title: '考试安排',
      content: '请查看最新安排。',
      creatorName: '管理员',
      createdAt: DateTime(2026, 12, 4, 9, 15).millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OptionalLiquidGlassBackdropScope(
            isSolidBackground: true,
            child: StickyAnnouncementBanner(
              announcement: announcement,
              onAcknowledge: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('12-04 09:15'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
