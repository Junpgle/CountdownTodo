import 'package:countdown_todo/services/animation_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to the elegant speed preset', () async {
    expect(
      await AnimationConfigService.getPreset(),
      AnimationPreset.balanced,
    );
    expect(
      await AnimationConfigService.getAnimationSpeedPreset(),
      AnimationSpeedPreset.elegant,
    );
    expect(
      await AnimationConfigService.getAnimationDuration(),
      AnimationSpeedPreset.elegant.duration,
    );
  });

  test('saving a speed preset updates duration and clears performance preset',
      () async {
    await AnimationConfigService.setPreset(AnimationPreset.performance);
    await AnimationConfigService.setAnimationSpeedPreset(
      AnimationSpeedPreset.balanced,
    );

    expect(await AnimationConfigService.getPreset(), isNull);
    expect(
      await AnimationConfigService.getAnimationSpeedPreset(),
      AnimationSpeedPreset.balanced,
    );
    expect(
      await AnimationConfigService.getAnimationDuration(),
      AnimationSpeedPreset.balanced.duration,
    );
  });

  test('manual duration changes are treated as a custom speed', () async {
    await AnimationConfigService.setAnimationSpeedPreset(
      AnimationSpeedPreset.fast,
    );
    await AnimationConfigService.setAnimationDuration(450);

    expect(await AnimationConfigService.getAnimationSpeedPreset(), isNull);
    expect(await AnimationConfigService.getAnimationDuration(), 450);
  });
}
