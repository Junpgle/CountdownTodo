import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../support/plan_availability_fixture.dart';

class _PomodoroUploadClient extends http.BaseClient {
  _PomodoroUploadClient(this.onUpload);

  final Future<void> Function(List<Map<String, dynamic>> records) onUpload;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body =
        jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    final records = (body['records'] as List)
        .whereType<Map>()
        .map((record) => Map<String, dynamic>.from(record))
        .toList();
    await onUpload(records);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"conflicts":[]}')),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanAvailabilityFixture fixture;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    ApiService.setBaseUrlOverride('http://pomodoro-sync.test');
  });

  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await fixture.dispose();
  });

  test(
    'upload acknowledges only operation logs captured before the request',
    () async {
      final firstUploadStarted = Completer<void>();
      final finishFirstUpload = Completer<void>();
      final uploads = <List<Map<String, dynamic>>>[];
      var uploadCount = 0;
      final client = _PomodoroUploadClient((records) async {
        uploads.add(records);
        if (uploadCount++ == 0) {
          firstUploadStarted.complete();
          await finishFirstUpload.future;
        }
      });

      Map<String, Object?> databaseRow(PomodoroRecord record) => {
        ...record.toJson(),
        'tag_uuids': jsonEncode(record.tagUuids),
      };

      Future<int> addPendingOperation(PomodoroRecord record) =>
          fixture.db.insert('op_logs', {
            'op_type': 'UPSERT',
            'target_table': 'pomodoro_records',
            'target_uuid': record.uuid,
            'data_json': jsonEncode(record.toJson()),
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'is_synced': 0,
            'sync_error': '',
          });

      final initial = PomodoroRecord(
        uuid: 'sync-race-record',
        startTime: 1000,
        endTime: 2000,
        plannedDuration: 60,
        actualDuration: 60,
        version: 1,
        createdAt: 500,
        updatedAt: 1000,
      );
      await fixture.db.insert('pomodoro_records', databaseRow(initial));
      final initialOperationId = await addPendingOperation(initial);

      final firstSync = PomodoroService.syncRecordsToCloud(client: client);
      await firstUploadStarted.future.timeout(const Duration(seconds: 5));
      final concurrentEdit = PomodoroRecord(
        uuid: initial.uuid,
        startTime: initial.startTime,
        endTime: initial.endTime,
        plannedDuration: initial.plannedDuration,
        actualDuration: initial.actualDuration,
        note: 'edited while upload was in flight',
        version: 2,
        createdAt: initial.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch + 1000,
      );
      await fixture.db.insert(
        'pomodoro_records',
        databaseRow(concurrentEdit),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final concurrentOperationId = await addPendingOperation(concurrentEdit);

      finishFirstUpload.complete();
      await firstSync;

      final afterFirstUpload = await fixture.db.query(
        'op_logs',
        where: 'id IN (?, ?)',
        whereArgs: [initialOperationId, concurrentOperationId],
        orderBy: 'id',
      );
      expect(afterFirstUpload, hasLength(2));
      expect(afterFirstUpload.first['is_synced'], 1);
      expect(afterFirstUpload.last['is_synced'], 0);
      expect(uploads.first.single['version'], 1);

      await PomodoroService.syncRecordsToCloud(client: client);

      expect(uploads, hasLength(2));
      expect(uploads.last.single['version'], 2);
      expect(uploads.last.single['note'], 'edited while upload was in flight');
      final afterSecondUpload = await fixture.db.query(
        'op_logs',
        where: 'target_table = ?',
        whereArgs: ['pomodoro_records'],
      );
      expect(
        afterSecondUpload.every((operation) => operation['is_synced'] == 1),
        isTrue,
      );
      client.close();
    },
  );
}
