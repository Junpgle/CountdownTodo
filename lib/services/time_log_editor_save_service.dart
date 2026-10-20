import '../models.dart';

typedef TimeLogEditorWriter = Future<void> Function(
  String username,
  List<TimeLogItem> logs,
);

typedef TimeLogEditorReader = Future<List<TimeLogItem>> Function(
  String username,
);

enum TimeLogEditorSaveDisposition { saved, savedAfterReadBack, failed, unknown }

class TimeLogEditorSaveResult {
  const TimeLogEditorSaveResult._(this.disposition, {this.error});

  const TimeLogEditorSaveResult.saved()
    : this._(TimeLogEditorSaveDisposition.saved);

  const TimeLogEditorSaveResult.savedAfterReadBack(Object error)
    : this._(TimeLogEditorSaveDisposition.savedAfterReadBack, error: error);

  const TimeLogEditorSaveResult.failed(Object error)
    : this._(TimeLogEditorSaveDisposition.failed, error: error);

  const TimeLogEditorSaveResult.unknown(Object error)
    : this._(TimeLogEditorSaveDisposition.unknown, error: error);

  final TimeLogEditorSaveDisposition disposition;
  final Object? error;

  bool get isSaved =>
      disposition == TimeLogEditorSaveDisposition.saved ||
      disposition == TimeLogEditorSaveDisposition.savedAfterReadBack;
}

/// Writes a single stable UUID and resolves ambiguous post-commit failures by
/// reading that UUID back from local storage.
class TimeLogEditorSaveService {
  const TimeLogEditorSaveService(this._write, this._read);

  final TimeLogEditorWriter _write;
  final TimeLogEditorReader _read;

  Future<TimeLogEditorSaveResult> save(String username, TimeLogItem log) async {
    try {
      await _write(username, [log]);
      return const TimeLogEditorSaveResult.saved();
    } catch (error) {
      try {
        final savedLogs = await _read(username);
        for (final savedLog in savedLogs) {
          if (_samePersistedLog(savedLog, log)) {
            return TimeLogEditorSaveResult.savedAfterReadBack(error);
          }
        }
        return TimeLogEditorSaveResult.failed(error);
      } catch (readError) {
        return TimeLogEditorSaveResult.unknown(readError);
      }
    }
  }

  bool _samePersistedLog(TimeLogItem saved, TimeLogItem attempted) {
    if (saved.id != attempted.id ||
        saved.title != attempted.title ||
        saved.startTime != attempted.startTime ||
        saved.endTime != attempted.endTime ||
        saved.remark != attempted.remark ||
        saved.version != attempted.version ||
        saved.updatedAt != attempted.updatedAt ||
        saved.createdAt != attempted.createdAt ||
        saved.isDeleted != attempted.isDeleted ||
        _normalizeOptionalString(saved.deviceId) !=
            _normalizeOptionalString(attempted.deviceId) ||
        _normalizeOptionalString(saved.teamUuid) !=
            _normalizeOptionalString(attempted.teamUuid) ||
        saved.tagUuids.length != attempted.tagUuids.length) {
      return false;
    }

    for (var index = 0; index < saved.tagUuids.length; index++) {
      if (saved.tagUuids[index] != attempted.tagUuids[index]) return false;
    }
    return true;
  }

  String? _normalizeOptionalString(String? value) =>
      value == null || value.isEmpty ? null : value;
}
