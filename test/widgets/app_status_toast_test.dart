import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/app_status_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LiquidGlassEffectService.setEnabled(false);
  });

  tearDown(AppStatusToast.dismissCurrent);

  testWidgets('status toast appears below its anchor without shifting content',
      (tester) async {
    final anchorKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(
                  key: ValueKey<String>('unchanged-content'),
                  color: Colors.white,
                ),
              ),
              Positioned(
                top: 24,
                right: 20,
                child: Builder(
                  builder: (context) => SizedBox(
                    key: anchorKey,
                    width: 40,
                    height: 40,
                    child: IconButton(
                      onPressed: () {
                        AppStatusToast.show(
                          context: context,
                          anchorKey: anchorKey,
                          message: '数据同步完成',
                          duration: const Duration(milliseconds: 500),
                        );
                      },
                      icon: const Icon(Icons.sync),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final contentRectBefore =
        tester.getRect(find.byKey(const ValueKey<String>('unchanged-content')));
    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump();

    final toastFinder = find.byKey(const ValueKey<String>('app-status-toast'));
    expect(find.text('数据同步完成'), findsOneWidget);
    final messageText = tester.widget<Text>(find.text('数据同步完成'));
    expect(messageText.style?.decoration, TextDecoration.none);
    expect(tester.getTopLeft(toastFinder).dy,
        greaterThan(tester.getBottomLeft(find.byKey(anchorKey)).dy));
    expect(
      tester.getRect(find.byKey(const ValueKey<String>('unchanged-content'))),
      contentRectBefore,
    );

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(toastFinder, findsNothing);
  });
}
