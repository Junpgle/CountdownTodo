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

class ImportPreview {
  final int fileVersion;
  final String? appVersion;
  final DateTime exportedAt;
  final List<ImportTypePreview> types;

  const ImportPreview({
    required this.fileVersion,
    this.appVersion,
    required this.exportedAt,
    required this.types,
  });
}

class ImportTypePreview {
  final String key;
  final String label;
  final int count;
  int conflictCount;

  ImportTypePreview({
    required this.key,
    required this.label,
    required this.count,
    this.conflictCount = 0,
  });
}

class ImportResult {
  final bool success;
  final String? errorMessage;
  final int importedCount;
  final int skippedCount;
  final int updatedCount;

  const ImportResult({
    required this.success,
    this.errorMessage,
    required this.importedCount,
    required this.skippedCount,
    required this.updatedCount,
  });
}
