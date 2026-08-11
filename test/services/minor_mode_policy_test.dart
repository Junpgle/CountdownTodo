import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/services/minor_mode_policy.dart';

void main() {
  test('capability matrix covers all official minor age bands', () {
    expect(MinorModePolicy.capabilityAgeBands, hasLength(5));
    expect(
      MinorModePolicy.capabilityRows.every(
        (row) =>
            row.availability.length ==
            MinorModePolicy.capabilityAgeBands.length,
      ),
      isTrue,
    );
  });

  test('advanced AI is unavailable below 16 and parent-gated at 16-17', () {
    final aiRow = MinorModePolicy.capabilityRows.firstWhere(
      (row) => row.label == 'AI 对话与高级 AI',
    );

    expect(
      aiRow.availability.sublist(0, 4),
      everyElement(MinorModeAvailability.unavailable),
    );
    expect(
      aiRow.availability.last,
      MinorModeAvailability.parentAuthentication,
    );
  });
}
