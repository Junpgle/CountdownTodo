import 'package:flutter/material.dart';

class ExportTypeOption {
  final String key;
  final String label;
  final IconData icon;
  final int count;
  final String description;

  const ExportTypeOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.count,
    required this.description,
  });
}

class ExportOptions {
  final bool removeTeamBinding;
  final bool removeImagePath;
  final bool removeConflictData;
  final bool removeDeviceId;

  const ExportOptions({
    this.removeTeamBinding = false,
    this.removeImagePath = true,
    this.removeConflictData = true,
    this.removeDeviceId = true,
  });
}

class ExportResult {
  final bool success;
  final String? filePath;
  final String? errorMessage;
  final int totalItems;

  const ExportResult({
    required this.success,
    this.filePath,
    this.errorMessage,
    required this.totalItems,
  });
}

enum TeamDataStrategy { skip, convertToPersonal }

enum UuidStrategy { keepOriginal, regenerate }

enum ImportDataScope {
  productivity,
  courses,
  habits,
  finance,
  challenge,
  settings,
}

const Set<String> teamScopedImportDataKeys = {
  'todo_groups',
  'todos',
  'countdowns',
  'time_logs',
  'fixed_schedules',
  'courses',
};

extension ImportDataScopeDetails on ImportDataScope {
  String get label => switch (this) {
    ImportDataScope.productivity => '待办、规划与专注',
    ImportDataScope.courses => '课表',
    ImportDataScope.habits => '习惯与睡眠训练',
    ImportDataScope.finance => '记账',
    ImportDataScope.challenge => '30天挑战',
    ImportDataScope.settings => '偏好设置',
  };

  IconData get icon => switch (this) {
    ImportDataScope.productivity => Icons.checklist_rounded,
    ImportDataScope.courses => Icons.school_outlined,
    ImportDataScope.habits => Icons.track_changes_outlined,
    ImportDataScope.finance => Icons.account_balance_wallet_outlined,
    ImportDataScope.challenge => Icons.emoji_events_outlined,
    ImportDataScope.settings => Icons.settings_outlined,
  };

  List<String> get dataKeys => switch (this) {
    ImportDataScope.productivity => const [
      'todo_groups',
      'todos',
      'countdowns',
      'todo_plan_blocks',
      'fixed_schedules',
      'time_logs',
      'pomodoro_tags',
      'pomodoro_records',
    ],
    ImportDataScope.courses => const ['courses'],
    ImportDataScope.habits => const ['habits'],
    ImportDataScope.finance => const ['finance'],
    ImportDataScope.challenge => const ['thirty_day_challenge'],
    ImportDataScope.settings => const ['settings'],
  };
}

ImportDataScope? importDataScopeForKey(String key) {
  for (final scope in ImportDataScope.values) {
    if (scope.dataKeys.contains(key)) return scope;
  }
  return null;
}

class ImportOptions {
  final TeamDataStrategy teamStrategy;
  final UuidStrategy uuidStrategy;
  final Set<ImportDataScope>? selectedScopes;

  const ImportOptions({
    this.teamStrategy = TeamDataStrategy.skip,
    this.uuidStrategy = UuidStrategy.keepOriginal,
    this.selectedScopes,
  });
}

class ImportPreview {
  final int fileVersion;
  final String? appVersion;
  final DateTime exportedAt;
  final List<ImportTypePreview> types;
  final List<ImportScopePreview> scopes;
  final List<String> unsupportedKeys;

  const ImportPreview({
    required this.fileVersion,
    this.appVersion,
    required this.exportedAt,
    required this.types,
    required this.scopes,
    required this.unsupportedKeys,
  });
}

int teamScopedImportCount(
  ImportPreview preview,
  Set<ImportDataScope> selectedScopes,
) {
  final selectedKeys = selectedScopes.expand((scope) => scope.dataKeys).toSet();
  return preview.types
      .where(
        (type) =>
            teamScopedImportDataKeys.contains(type.key) &&
            selectedKeys.contains(type.key),
      )
      .fold(0, (total, type) => total + type.teamCount);
}

class ImportScopePreview {
  final ImportDataScope scope;
  final List<ImportTypePreview> types;

  const ImportScopePreview({required this.scope, required this.types});

  String get label => scope.label;
  IconData get icon => scope.icon;
  int get count => types.fold(0, (total, type) => total + type.count);
  int get deletedCount =>
      types.fold(0, (total, type) => total + type.deletedCount);
  int get teamCount => types
      .where((type) => teamScopedImportDataKeys.contains(type.key))
      .fold(0, (total, type) => total + type.teamCount);
}

class ImportTypePreview {
  final String key;
  final String label;
  final int count;
  final int deletedCount;
  int teamCount;
  int conflictCount;

  ImportTypePreview({
    required this.key,
    required this.label,
    required this.count,
    this.deletedCount = 0,
    this.teamCount = 0,
    this.conflictCount = 0,
  });
}

class ImportResult {
  final bool success;
  final String? errorMessage;
  final int importedCount;
  final int skippedCount;
  final int updatedCount;
  final List<ImportScopeRestoreSummary> scopeSummaries;

  const ImportResult({
    required this.success,
    this.errorMessage,
    required this.importedCount,
    required this.skippedCount,
    required this.updatedCount,
    this.scopeSummaries = const [],
  });
}

enum ImportScopeRestoreKind {
  recordChanges,
  settingsApplied,
  challengeRestored,
}

class ImportScopeRestoreSummary {
  final ImportDataScope scope;
  final ImportScopeRestoreKind kind;
  final int importedCount;
  final int updatedCount;
  final int skippedCount;
  final int detailCount;

  const ImportScopeRestoreSummary({
    required this.scope,
    required this.kind,
    this.importedCount = 0,
    this.updatedCount = 0,
    this.skippedCount = 0,
    this.detailCount = 0,
  });
}
