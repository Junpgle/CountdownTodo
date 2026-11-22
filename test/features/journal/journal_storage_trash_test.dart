import 'dart:io';
import 'dart:typed_data';

import 'package:countdown_todo/features/journal/models/journal_entry.dart';
import 'package:countdown_todo/features/journal/services/journal_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database database;
  late JournalStorage storage;
  const accountId = 'journal-trash-storage-test';

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.ensureJournalSchema(database);
    storage = JournalStorage.forTesting(databaseLoader: (_) async => database);
  });

  tearDown(() => database.close());

  test('移入回收站保留原日记与照片，恢复后回到活动时间线', () async {
    final entry = JournalEntry(
      id: 'trash-entry-1',
      title: '留住这一天',
      content: '山路上的晚霞。',
      occurredAt: DateTime(2026, 10, 21, 18),
    );
    final imageBytes = Uint8List.fromList([5, 8, 13, 21]);
    final attachment = JournalAttachment(
      id: 'trash-image-1',
      entryId: entry.id,
      imageData: imageBytes,
      mimeType: 'image/png',
      sortOrder: 0,
    );
    await storage.saveEntry(entry, [attachment], accountId: accountId);

    expect(
      await storage.moveEntryToTrash(entry.id, accountId: accountId),
      isTrue,
    );
    expect(
      await storage.moveEntryToTrash(entry.id, accountId: accountId),
      isFalse,
    );
    expect(await storage.loadEntries(accountId: accountId), isEmpty);

    final trashed = await storage.loadTrashEntries(accountId: accountId);
    expect(trashed, hasLength(1));
    expect(trashed.single.id, entry.id);
    expect(trashed.single.content, entry.content);
    expect(trashed.single.attachments.single.id, attachment.id);
    expect(
      (await storage.loadAttachment(
        attachment.id,
        accountId: accountId,
      ))!.imageData,
      imageBytes,
    );

    expect(
      await storage.restoreEntryFromTrash(entry.id, accountId: accountId),
      isTrue,
    );
    expect(
      await storage.restoreEntryFromTrash(entry.id, accountId: accountId),
      isFalse,
    );
    final restored = await storage.loadEntry(entry.id, accountId: accountId);
    expect(restored?.id, entry.id);
    expect(restored?.occurredAt, entry.occurredAt);
    expect(restored?.content, entry.content);
    expect(restored?.attachments.single.id, attachment.id);
    expect(await storage.countTrashEntries(accountId: accountId), 0);
  });

  test('旧编辑器不能通过保存把回收站日记重新写回', () async {
    final entry = JournalEntry(
      id: 'trash-stale-editor',
      title: '保存前打开的日记',
      content: '原文',
    );
    await storage.saveEntry(entry, const [], accountId: accountId);
    await storage.moveEntryToTrash(entry.id, accountId: accountId);

    await expectLater(
      storage.saveEntry(
        entry.copyWith(content: '旧页面中的修改'),
        const [],
        accountId: accountId,
        requireExisting: true,
      ),
      throwsA(isA<JournalEntryUnavailableException>()),
    );
    expect(await storage.loadEntries(accountId: accountId), isEmpty);
    expect(
      (await storage.loadTrashEntries(accountId: accountId)).single.content,
      '原文',
    );
  });

  test('永久删除只清理指定的回收站日记及其附件', () async {
    final first = JournalEntry(id: 'trash-purge-first', content: '第一篇');
    final second = JournalEntry(id: 'trash-purge-second', content: '第二篇');
    final firstPhoto = JournalAttachment(
      id: 'trash-purge-photo-first',
      entryId: first.id,
      imageData: Uint8List.fromList([1, 2]),
    );
    final secondPhoto = JournalAttachment(
      id: 'trash-purge-photo-second',
      entryId: second.id,
      imageData: Uint8List.fromList([3, 4]),
    );
    await storage.saveEntry(first, [firstPhoto], accountId: accountId);
    await storage.saveEntry(second, [secondPhoto], accountId: accountId);
    await storage.moveEntryToTrash(first.id, accountId: accountId);
    await storage.moveEntryToTrash(second.id, accountId: accountId);

    final removed = await storage.permanentlyDeleteEntryFromTrash(
      first.id,
      accountId: accountId,
    );
    expect(removed?.map((item) => item.id), [firstPhoto.id]);
    expect(
      await storage.permanentlyDeleteEntryFromTrash(
        first.id,
        accountId: accountId,
      ),
      isNull,
    );
    expect(
      (await storage.loadTrashEntries(accountId: accountId)).map((e) => e.id),
      [second.id],
    );
    expect(
      await storage.loadAttachment(firstPhoto.id, accountId: accountId),
      isNull,
    );
    expect(
      (await storage.loadAttachment(secondPhoto.id, accountId: accountId))?.id,
      secondPhoto.id,
    );
    expect(await storage.loadEntry(first.id, accountId: accountId), isNull);
  });

  test('回收站查询、恢复和计数只作用于当前账号数据库', () async {
    final secondAccountDirectory = await Directory.systemTemp.createTemp(
      'journal-trash-account-',
    );
    final secondAccountDatabase = await databaseFactoryFfi.openDatabase(
      '${secondAccountDirectory.path}/account-b.sqlite',
    );
    addTearDown(() async {
      await secondAccountDatabase.close();
      await secondAccountDirectory.delete(recursive: true);
    });
    await DatabaseHelper.ensureJournalSchema(secondAccountDatabase);
    final accountStorage = JournalStorage.forTesting(
      databaseLoader: (id) async =>
          id == 'journal-trash-account-a' ? database : secondAccountDatabase,
    );
    final sameIdInFirstAccount = JournalEntry(
      id: 'same-local-uuid',
      title: '账号 A',
    );
    final sameIdInSecondAccount = JournalEntry(
      id: 'same-local-uuid',
      title: '账号 B',
    );
    await accountStorage.saveEntry(
      sameIdInFirstAccount,
      const [],
      accountId: 'journal-trash-account-a',
    );
    await accountStorage.saveEntry(
      sameIdInSecondAccount,
      const [],
      accountId: 'journal-trash-account-b',
    );

    expect(
      await accountStorage.moveEntryToTrash(
        sameIdInFirstAccount.id,
        accountId: 'journal-trash-account-a',
      ),
      isTrue,
    );
    expect(
      await accountStorage.countTrashEntries(
        accountId: 'journal-trash-account-a',
      ),
      1,
    );
    expect(
      await accountStorage.countTrashEntries(
        accountId: 'journal-trash-account-b',
      ),
      0,
    );
    expect(
      (await accountStorage.loadEntry(
        sameIdInSecondAccount.id,
        accountId: 'journal-trash-account-b',
      ))?.title,
      '账号 B',
    );
  });
}
