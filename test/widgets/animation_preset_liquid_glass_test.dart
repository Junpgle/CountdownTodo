import 'package:countdown_todo/services/animation_config_service.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('performance preset disables the liquid glass effect', () async {
    await LiquidGlassEffectService.setEnabled(true);

    await AnimationConfigService.setPreset(AnimationPreset.performance);

    expect(LiquidGlassEffectService.isEnabled, isFalse);
    expect(
      await AnimationConfigService.getPreset(),
      AnimationPreset.performance,
    );
  });

  test('balanced preset enables liquid glass in standard mode', () async {
    await AnimationConfigService.setPreset(AnimationPreset.balanced);

    expect(LiquidGlassEffectService.isEnabled, isTrue);
    expect(LiquidGlassEffectService.mode, LiquidGlassEffectMode.standard);
  });

  test('expressive preset enables liquid glass in enhanced mode', () async {
    await AnimationConfigService.setPreset(AnimationPreset.expressive);

    expect(LiquidGlassEffectService.isEnabled, isTrue);
    expect(LiquidGlassEffectService.mode, LiquidGlassEffectMode.enhanced);
  });

  test('manual glass tweaks clear the active preset selection', () async {
    await AnimationConfigService.setPreset(AnimationPreset.balanced);
    expect(await AnimationConfigService.getPreset(), AnimationPreset.balanced);

    // 模拟用户在下方手动切换液态玻璃开关/模式后的行为。
    await LiquidGlassEffectService.setEnabled(false);
    await AnimationConfigService.clearActivePreset();

    expect(await AnimationConfigService.getPreset(), isNull);
    expect(LiquidGlassEffectService.isEnabled, isFalse);
  });
}
