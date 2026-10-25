/// A setting which must be replaced before a new plan can use current choices.
class PlanSettingCorrection {
  const PlanSettingCorrection({
    required this.label,
    required this.originalValue,
    required this.replacementValue,
  });

  final String label;
  final String originalValue;
  final String replacementValue;

  String get summary => '$label：$originalValue → $replacementValue';
}

/// Supported values and safe defaults shared by plan reuse and recovery.
class PlanSettingsCompatibility {
  const PlanSettingsCompatibility({
    required this.reminderMinutes,
    required this.pomodoroMinutes,
    required this.pomodoroRounds,
    this.corrections = const [],
  });

  static const int defaultReminderMinutes = 5;
  static const int defaultPomodoroMinutes = 25;
  static const int defaultPomodoroRounds = 0;

  static const List<int> reminderOptions = [0, 5, 10, 15, 30];
  static const List<int> pomodoroOptions = [15, 20, 25, 30, 45, 60];
  static const List<int> roundOptions = [0, 1, 2, 3, 4, 5, 6];

  final int reminderMinutes;
  final int pomodoroMinutes;
  final int pomodoroRounds;
  final List<PlanSettingCorrection> corrections;

  static PlanSettingsCompatibility normalize({
    required Object? reminderMinutes,
    required Object? pomodoroMinutes,
    required Object? pomodoroRounds,
  }) {
    final corrections = <PlanSettingCorrection>[];

    int normalizedValue({
      required Object? value,
      required List<int> options,
      required int fallback,
      required String label,
      required String Function(int value) format,
    }) {
      if (value is int && options.contains(value)) return value;

      final originalValue = value is int ? format(value) : '无法识别';
      corrections.add(
        PlanSettingCorrection(
          label: label,
          originalValue: originalValue,
          replacementValue: format(fallback),
        ),
      );
      return fallback;
    }

    return PlanSettingsCompatibility(
      reminderMinutes: normalizedValue(
        value: reminderMinutes,
        options: reminderOptions,
        fallback: defaultReminderMinutes,
        label: '提前提醒',
        format: (value) => value == 0 ? '不提醒' : '$value 分钟前',
      ),
      pomodoroMinutes: normalizedValue(
        value: pomodoroMinutes,
        options: pomodoroOptions,
        fallback: defaultPomodoroMinutes,
        label: '单轮番茄',
        format: (value) => '$value 分钟',
      ),
      pomodoroRounds: normalizedValue(
        value: pomodoroRounds,
        options: roundOptions,
        fallback: defaultPomodoroRounds,
        label: '番茄轮数',
        format: (value) => value == 0 ? '按规划时长' : '$value 轮',
      ),
      corrections: corrections,
    );
  }
}
