import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../models/journal_entry.dart';
import 'journal_media_service.dart';

class JournalStorage {
  JournalStorage._();

  static final instance = JournalStorage._();
  static const _attachmentMetadataColumns = [
    'uuid',
    'entry_uuid',
    'local_path',
    'mime_type',
    'width',
    'height',
    'sort_order',
    'file_size',
    'created_at',
  ];
  String? _reconciledMediaAccountId;

  /// Loads a compact page for the timeline/photo wall. Image bytes are loaded
  /// only for an entry opened by the user or for a visible web preview.
  Future<List<JournalEntry>> loadEntries({
    required String accountId,
    int limit = 40,
    int offset = 0,
    String? searchQuery,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await _reconcileMediaIfNeeded(db, accountId);
    final query = searchQuery?.trim() ?? '';
    final hasQuery = query.isNotEmpty;
    final entryRows = await db.query(
      'journal_entries',
      where: hasQuery
          ? 'is_deleted = 0 AND (title LIKE ? OR content LIKE ?)'
          : 'is_deleted = 0',
      whereArgs: hasQuery ? ['%$query%', '%$query%'] : null,
      orderBy: 'occurred_at DESC, created_at DESC',
      limit: limit,
      offset: offset,
    );
    if (entryRows.isEmpty) return [];

    final entryIds = entryRows
        .map((row) => row['uuid']?.toString())
        .whereType<String>()
        .toList();
    final placeholders = List.filled(entryIds.length, '?').join(', ');
    final attachmentRows = await db.query(
      'journal_attachments',
      columns: _attachmentMetadataColumns,
      where: 'entry_uuid IN ($placeholders)',
      whereArgs: entryIds,
      orderBy: 'entry_uuid, sort_order ASC, created_at ASC',
    );
    final grouped = <String, List<JournalAttachment>>{};
    for (final row in attachmentRows) {
      final attachment = JournalAttachment.fromMap(row);
      grouped.putIfAbsent(attachment.entryId, () => []).add(attachment);
    }
    return entryRows
        .map((row) => JournalEntry.fromMap(
              row,
              attachments: grouped[row['uuid']?.toString()] ?? const [],
            ))
        .toList();
  }

  Future<JournalEntry?> loadEntry(String id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'journal_entries',
      where: 'uuid = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final attachments = await db.query(
      'journal_attachments',
      where: 'entry_uuid = ?',
      whereArgs: [id],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return JournalEntry.fromMap(
      rows.first,
      attachments: attachments.map(JournalAttachment.fromMap).toList(),
    );
  }

  /// Retrieves one attachment's bytes when a web preview becomes visible.
  /// Native previews use the local path and do not need this query.
  Future<JournalAttachment?> loadAttachment(String id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'journal_attachments',
      where: 'uuid = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : JournalAttachment.fromMap(rows.first);
  }

  Future<void> saveEntry(
    JournalEntry entry,
    List<JournalAttachment> attachments,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.insert(
        'journal_entries',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'journal_attachments',
        where: 'entry_uuid = ?',
        whereArgs: [entry.id],
      );
      for (var index = 0; index < attachments.length; index++) {
        final attachment = attachments[index].copyWith(
          entryId: entry.id,
          sortOrder: index,
        );
        await txn.insert(
          'journal_attachments',
          attachment.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<JournalAttachment>> deleteEntry(String id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'journal_attachments',
      where: 'entry_uuid = ?',
      whereArgs: [id],
    );
    await db.transaction((txn) async {
      await txn.delete('journal_attachments',
          where: 'entry_uuid = ?', whereArgs: [id]);
      await txn.delete('journal_entries', where: 'uuid = ?', whereArgs: [id]);
    });
    return rows.map(JournalAttachment.fromMap).toList();
  }

  Future<void> _reconcileMediaIfNeeded(Database db, String accountId) async {
    if (_reconciledMediaAccountId == accountId) return;
    final rows = await db.query(
      'journal_attachments',
      columns: const ['local_path'],
      where: 'local_path IS NOT NULL AND local_path != ?',
      whereArgs: [''],
    );
    final paths = rows
        .map((row) => row['local_path']?.toString())
        .whereType<String>()
        .toSet();
    await JournalMediaService.instance.cleanupOrphanedMedia(
      accountId: accountId,
      referencedPaths: paths,
    );
    _reconciledMediaAccountId = accountId;
  }
}
