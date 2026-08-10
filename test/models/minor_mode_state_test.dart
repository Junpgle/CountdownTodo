import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/models/minor_mode_state.dart';
import 'package:countdown_todo/services/minor_mode_policy.dart';

void main() {
  MinorModeState state({
    bool systemSupported = true,
    bool systemEnabled = false,
    bool manualEnabled = false,
    MinorAgeBand ageBand = MinorAgeBand.unknown,
  }) {
    return MinorModeState(
      systemSupported: systemSupported,
      systemEnabled: systemEnabled,
      manualEnabled: manualEnabled,
      source: systemEnabled
          ? MinorModeSource.chinaSystem
          : manualEnabled
              ? MinorModeSource.manual
              : MinorModeSource.unsupported,
      ageBand: ageBand,
      parentAuthenticationSupported: true,
    );
  }

  test('effective minor mode combines system and manual state', () {
    expect(state().effectiveMinorMode, isFalse);
    expect(state(manualEnabled: true).effectiveMinorMode, isTrue);
    expect(state(systemEnabled: true).effectiveMinorMode, isTrue);
    expect(
      state(systemEnabled: true, manualEnabled: true).effectiveMinorMode,
      isTrue,
    );
  });

  test('system mode remains effective when app manual mode is off', () {
    final systemState = state(systemEnabled: true, manualEnabled: false);

    expect(systemState.effectiveMinorMode, isTrue);
    expect(
        systemState.copyWith(manualEnabled: false).effectiveMinorMode, isTrue);
  });

  test('maps Android age ranges and unknown values safely', () {
    expect(
      MinorAgeBandSystemMapping.fromSystemAgeRange(0),
      MinorAgeBand.unknown,
    );
    expect(
      MinorAgeBandSystemMapping.fromSystemAgeRange(1),
      MinorAgeBand.under3,
    );
    expect(
      MinorAgeBandSystemMapping.fromSystemAgeRange(2),
      MinorAgeBand.age3to7,
    );
    expect(
      MinorAgeBandSystemMapping.fromSystemAgeRange(3),
      MinorAgeBand.age8to11,
    );
    expect(
      MinorAgeBandSystemMapping.fromSystemAgeRange(4),
      MinorAgeBand.age12to15,
    );
    expect(
      MinorAgeBandSystemMapping.fromSystemAgeRange(5),
      MinorAgeBand.age16to17,
    );
    expect(
      MinorAgeBandSystemMapping.fromSystemAgeRange('invalid'),
      MinorAgeBand.unknown,
    );
  });

  test('maps a local birth date to the policy age band', () {
    final today = DateTime(2026, 8, 10);
    expect(
      MinorAgeBandSystemMapping.fromBirthDate(
        DateTime(2014, 8, 10),
        today: today,
      ),
      MinorAgeBand.age12to15,
    );
    expect(
      MinorAgeBandSystemMapping.fromBirthDate(
        DateTime(2009, 8, 11),
        today: today,
      ),
      MinorAgeBand.age16to17,
    );
    expect(
      MinorAgeBandSystemMapping.fromBirthDate(
        DateTime(2000, 1, 1),
        today: today,
      ),
      MinorAgeBand.adult,
    );
    expect(
      MinorAgeBandSystemMapping.fromBirthDate(
        DateTime(2027, 1, 1),
        today: today,
      ),
      MinorAgeBand.unknown,
    );
  });

  test('unknown minor age does not silently allow advanced AI', () {
    expect(
      MinorModePolicy.allowsAdvancedAiInteraction(state(systemEnabled: true)),
      isFalse,
    );
    expect(
      MinorModePolicy.allowsAdvancedAiInteraction(
        state(systemEnabled: true, ageBand: MinorAgeBand.age16to17),
      ),
      isTrue,
    );
    expect(
      MinorModePolicy.isAllowedByAge(
        state(systemEnabled: true),
        MinorModeAction.llmConfiguration,
      ),
      isTrue,
    );
  });

  test('unsupported platform state is safe and keeps manual fallback', () {
    final unsupported = MinorModeState.fromPlatformMap(
      const <Object?, Object?>{},
      manualEnabled: true,
    );

    expect(unsupported.systemSupported, isFalse);
    expect(unsupported.systemEnabled, isFalse);
    expect(unsupported.effectiveMinorMode, isTrue);
    expect(unsupported.source, MinorModeSource.manual);
  });
}
