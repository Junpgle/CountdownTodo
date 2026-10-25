import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../models/journal_entry.dart';
import 'journal_media_service.dart';

class JournalStorage {
  JournalStorage._({
    required this.databaseLoader,
    required this.reconcileMedia,
  });

  @visibleForTesting
  factory JournalStorage.forTesting({
    required Future<Database> Function(String accountId) databaseLoader,
  }) => JournalStorage._(databaseLoader: databaseLoader, reconcileMedia: false);

  static final instance = JournalStorage._(
    databaseLoader: DatabaseHelper.instance.databaseForUser,
    reconcileMedia: true,
  );
  final Future<Database> Function(String accountId) databaseLoader;
  final bool reconcileMedia;
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

  static bool _isSqlLikeCaseInvariant(String term) {
    for (final rune in term.runes) {
      final character = String.fromCharCode(rune);
      if (character.toLowerCase() != character.toUpperCase()) return false;
    }
    return true;
  }

  /// Loads a compact page for the timeline/photo wall. Image bytes are loaded
  /// only for an entry opened by the user or for a visible web preview.
  Future<List<JournalEntry>> loadEntries({
    required String accountId,
    int limit = 40,
    int offset = 0,
    String? searchQuery,
    List<String> searchTerms = const [],
    DateTime? occurredOn,
  }) => _loadEntryPage(
    accountId: accountId,
    isDeleted: false,
    limit: limit,
    offset: offset,
    searchQuery: searchQuery,
    searchTerms: searchTerms,
    occurredOn: occurredOn,
  );

  Future<List<JournalEntry>> loadTrashEntries({
    required String accountId,
    int limit = 40,
    int offset = 0,
  }) => _loadEntryPage(
    accountId: accountId,
    isDeleted: true,
    limit: limit,
    offset: offset,
  );

  Future<int> countTrashEntries({required String accountId}) async {
    final db = await databaseLoader(accountId);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM journal_entries WHERE is_deleted = 1',
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<JournalEntry>> _loadEntryPage({
    required String accountId,
    required bool isDeleted,
    int limit = 40,
    int offset = 0,
    String? searchQuery,
    List<String> searchTerms = const [],
    DateTime? occurredOn,
  }) async {
    final db = await databaseLoader(accountId);
    if (reconcileMedia) await _reconcileMediaIfNeeded(db, accountId);
    final query = searchQuery?.trim() ?? '';
    final hasQuery = query.isNotEmpty;
    final where = <String>['is_deleted = ${isDeleted ? 1 : 0}'];
    final whereArgs = <Object?>[];
    if (hasQuery) {
      where.add('(title LIKE ? OR content LIKE ?)');
      whereArgs.addAll(['%$query%', '%$query%']);
    }
    for (final rawTerm in searchTerms) {
      final term = rawTerm.trim();
      // Keep the first keyword's legacy LIKE filter. Push only case-invariant
      // additional terms down; Dart handles the rest without Unicode misses.
      if (term.isEmpty || !_isSqlLikeCaseInvariant(term)) continue;
      where.add('(title LIKE ? OR content LIKE ?)');
      whereArgs.addAll(['%$term%', '%$term%']);
    }
    if (occurredOn != null) {
      final start = DateTime(occurredOn.year, occurredOn.month, occurredOn.day);
      final end = DateTime(
        occurredOn.year,
        occurredOn.month,
        occurredOn.day + 1,
      );
      where.add('occurred_at >= ? AND occurred_at < ?');
      whereArgs
        ..add(start.millisecondsSinceEpoch)
        ..add(end.millisecondsSinceEpoch);
    }
    final entryRows = await db.query(
      'journal_entries',
      where: where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: isDeleted
          ? 'updated_at DESC, occurred_at DESC'
          : 'occurred_at DESC, created_at DESC',
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
        .map(
          (row) => JournalEntry.fromMap(
            row,
            attachments: grouped[row['uuid']?.toString()] ?? const [],
          ),
        )
        .toList();
  }

  Future<JournalEntry?> loadEntry(String id, {String? accountId}) async {
    final db = await _databaseFor(accountId);
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
  Future<JournalAttachment?> loadAttachment(
    String id, {
    String? accountId,
  }) async {
    final db = await _databaseFor(accountId);
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
    List<JournalAttachment> attachments, {
    String? accountId,
    bool requireExisting = false,
  }) async {
    final db = await _databaseFor(accountId);
    await db.transaction((txn) async {
      final existing = await txn.query(
        'journal_entries',
        columns: const ['is_deleted'],
        where: 'uuid = ?',
        whereArgs: [entry.id],
        limit: 1,
      );
      if (requireExisting && existing.isEmpty) {
        throw const JournalEntryUnavailableException('这篇日记已不存在，当前编辑内容仍保留。');
      }
      if (existing.isNotEmpty && existing.first['is_deleted'] == 1) {
        throw const JournalEntryUnavailableException(
          '这篇日记已移入回收站，请先恢复后再保存；当前编辑内容仍保留。',
        );
      }
      if (!requireExisting && existing.isNotEmpty) {
        throw const JournalEntryUnavailableException('日记标识已被使用，请返回后重新创建。');
      }
      await txn.insert(
        'journal_entries',
        entry.copyWith(isDeleted: false).toMap(),
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

  Future<bool> moveEntryToTrash(String id, {String? accountId}) async {
    final db = await _databaseFor(accountId);
    return db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final changed = await txn.update(
        'journal_entries',
        {'is_deleted': 1, 'updated_at': now},
        where: 'uuid = ? AND is_deleted = 0',
        whereArgs: [id],
      );
      return changed == 1;
    });
  }

  Future<bool> restoreEntryFromTrash(String id, {String? accountId}) async {
    final db = await _databaseFor(accountId);
    return db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final changed = await txn.update(
        'journal_entries',
        {'is_deleted': 0, 'updated_at': now},
        where: 'uuid = ? AND is_deleted = 1',
        whereArgs: [id],
      );
      return changed == 1;
    });
  }

  Future<List<JournalAttachment>?> permanentlyDeleteEntryFromTrash(
    String id, {
    String? accountId,
  }) async {
    final db = await _databaseFor(accountId);
    return db.transaction((txn) async {
      final entries = await txn.query(
        'journal_entries',
        columns: const ['uuid'],
        where: 'uuid = ? AND is_deleted = 1',
        whereArgs: [id],
        limit: 1,
      );
      if (entries.isEmpty) return null;
      final rows = await txn.query(
        'journal_attachments',
        where: 'entry_uuid = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'journal_attachments',
        where: 'entry_uuid = ?',
        whereArgs: [id],
      );
      final deleted = await txn.delete(
        'journal_entries',
        where: 'uuid = ? AND is_deleted = 1',
        whereArgs: [id],
      );
      if (deleted != 1) {
        throw const JournalEntryUnavailableException('这篇日记已变化，请刷新回收站后重试。');
      }
      _reconciledMediaAccountId = null;
      return rows.map(JournalAttachment.fromMap).toList(growable: false);
    });
  }

  void invalidateMediaReconciliation() {
    _reconciledMediaAccountId = null;
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

  Future<Database> _databaseFor(String? accountId) => accountId == null
      ? DatabaseHelper.instance.database
      : databaseLoader(accountId);
}

final class JournalEntryUnavailableException implements Exception {
  final String message;

  const JournalEntryUnavailableException(this.message);

  @override
  String toString() => message;
}
