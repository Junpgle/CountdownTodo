part of '../finance_storage.dart';

Future<List<FinanceTransaction>> _getTransactions({
  bool includeDeleted = false,
  DateTime? from,
  DateTime? to,
  String? keyword,
  String? categoryUuid,
  FinanceTransactionType? type,
  int? limit,
}) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final where = <String>[];
  final args = <Object?>[];

  if (!includeDeleted) {
    where.add('is_deleted = 0');
  }
  if (from != null) {
    where.add('transaction_date >= ?');
    args.add(dateKey(from));
  }
  if (to != null) {
    where.add('transaction_date < ?');
    args.add(dateKey(to));
  }
  if (keyword != null && keyword.trim().isNotEmpty) {
    where.add('''(
      merchant LIKE ? OR note LIKE ? OR transaction_date LIKE ?
    )''');
    final query = '%${keyword.trim()}%';
    args.add(query);
    args.add(query);
    args.add(query);
  }
  if (categoryUuid != null && categoryUuid.isNotEmpty) {
    where.add('category_uuid = ?');
    args.add(categoryUuid);
  }
  if (type != null) {
    where.add('type = ?');
    args.add(type.name);
  }

  final rows = await db.query(
    'finance_transactions',
    where: where.isEmpty ? null : where.join(' AND '),
    whereArgs: args,
    orderBy: 'transaction_date DESC, occurred_at DESC, updated_at DESC',
    limit: limit,
  );
  return rows.map(FinanceTransaction.fromMap).toList();
}

Future<List<FinanceTransaction>> _getBalanceTransactions({
  required int snapshotAt,
  required DateTime before,
  required Iterable<String> paymentMethodUuids,
}) async {
  final methodUuids = paymentMethodUuids
      .map((uuid) => uuid.trim())
      .where((uuid) => uuid.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (methodUuids.isEmpty) return const [];

  await FinanceStorage.ensureReady();
  final db = await _database;
  // Stay below SQLite's bind-variable limit even if a user has created an
  // unusually large number of payment methods. Balance aggregation does not
  // depend on row order, so avoid sorting the historical result set.
  const batchSize = 400;
  final rows = <Map<String, Object?>>[];
  for (var offset = 0; offset < methodUuids.length; offset += batchSize) {
    final nextOffset = offset + batchSize;
    final end = nextOffset < methodUuids.length
        ? nextOffset
        : methodUuids.length;
    final batch = methodUuids.sublist(offset, end);
    final placeholders = List.filled(batch.length, '?').join(',');
    rows.addAll(
      await db.query(
        'finance_transactions',
        where:
            'is_deleted = 0 AND '
            '(payment_method_uuid IN ($placeholders) OR '
            'target_payment_method_uuid IN ($placeholders)) AND '
            'transaction_date < ? AND '
            '(transaction_date >= ? OR created_at > ?)',
        // Stored ledger dates belong to their recorded timezone. The largest
        // difference between two supported offsets is 28 hours; widen the
        // date bounds and let balanceEventAt apply the exact instant cutoff.
        whereArgs: [
          ...batch,
          ...batch,
          dateKey(before.add(const Duration(days: 2))),
          dateKey(
            DateTime.fromMillisecondsSinceEpoch(snapshotAt)
                .subtract(const Duration(days: 2)),
          ),
          snapshotAt,
        ],
      ),
    );
  }
  return rows.map(FinanceTransaction.fromMap).toList();
}

Future<FinanceTransaction?> _getTransaction(String uuid) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final rows = await db.query(
    'finance_transactions',
    where: 'uuid = ?',
    whereArgs: [uuid],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return FinanceTransaction.fromMap(rows.first);
}

/// Reads only the requested transaction identities, including trash rows, so
/// generated recurring bills are not shown twice in future commitments.
Future<Set<String>> _getExistingTransactionUuids(Iterable<String> uuids) async {
  final values = uuids
      .map((uuid) => uuid.trim())
      .where((uuid) => uuid.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (values.isEmpty) return const <String>{};

  await FinanceStorage.ensureReady();
  final db = await _database;
  const batchSize = 400;
  final existing = <String>{};
  for (var offset = 0; offset < values.length; offset += batchSize) {
    final nextOffset = offset + batchSize;
    final end = nextOffset < values.length ? nextOffset : values.length;
    final batch = values.sublist(offset, end);
    final rows = await db.query(
      'finance_transactions',
      columns: ['uuid'],
      where: 'uuid IN (${List.filled(batch.length, '?').join(',')})',
      whereArgs: batch,
    );
    existing.addAll(rows.map((row) => row['uuid'] as String));
  }
  return existing;
}

Future<List<FinanceTransaction>> _getRefundsForTransaction(
  String transactionUuid, {
  bool includeDeleted = false,
}) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final rows = await db.query(
    'finance_transactions',
    where: includeDeleted
        ? "type = 'refund' AND related_transaction_uuid = ?"
        : "type = 'refund' AND related_transaction_uuid = ? AND is_deleted = 0",
    whereArgs: [transactionUuid],
    orderBy: 'transaction_date ASC, occurred_at ASC, updated_at ASC',
  );
  return rows.map(FinanceTransaction.fromMap).toList();
}

Future<int> _getRemainingRefundableMinor(
  String transactionUuid, {
  String? excludingRefundUuid,
}) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final original = await _findByUuid(
    db,
    'finance_transactions',
    transactionUuid,
  );
  if (original == null) return 0;
  final transaction = FinanceTransaction.fromMap(original);
  if (transaction.isDeleted ||
      transaction.type != FinanceTransactionType.expense) {
    return 0;
  }
  final refunded = await _activeRefundedMinor(
    db,
    transactionUuid,
    excludingRefundUuid: excludingRefundUuid,
  );
  return (transaction.amountMinor - refunded)
      .clamp(0, transaction.amountMinor)
      .toInt();
}

Future<List<FinanceTransaction>> _getDeletedTransactions() async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final rows = await db.query(
    'finance_transactions',
    where: 'is_deleted = 1',
    orderBy: 'updated_at DESC',
  );
  return rows.map(FinanceTransaction.fromMap).toList();
}

Future<void> _saveTransaction(
  FinanceTransaction transaction, {
  FinanceTransaction? original,
}) async {
  if (!transaction.isDeleted &&
      !isFinanceDateKey(transaction.transactionDate)) {
    throw ArgumentError.value(
      transaction.transactionDate,
      'transactionDate',
      '账单日期无效',
    );
  }
  if (!transaction.isDeleted && !_hasValidInstallmentFields(transaction)) {
    throw ArgumentError.value(transaction, 'transaction', '分期期数或总金额无效');
  }
  if (!isSafeFinanceAmountMinor(transaction.amountMinor) ||
      transaction.amountMinor == 0) {
    throw ArgumentError.value(
      transaction.amountMinor,
      'amountMinor',
      '金额必须大于 0',
    );
  }
  final installmentTotalMinor = transaction.installmentTotalMinor;
  if (installmentTotalMinor != null &&
      (!isSafeFinanceAmountMinor(installmentTotalMinor) ||
          installmentTotalMinor == 0)) {
    throw ArgumentError.value(
      installmentTotalMinor,
      'installmentTotalMinor',
      '分期总额超出可保存范围',
    );
  }
  if (original != null && original.uuid != transaction.uuid) {
    throw ArgumentError.value(original.uuid, 'original', '账单标识不匹配');
  }
  transaction.pendingSync = true;
  await FinanceStorage.ensureReady();
  final db = await _database;
  await db.transaction((txn) async {
    final existingRow = await _findByUuid(
      txn,
      'finance_transactions',
      transaction.uuid,
    );
    if (existingRow != null) {
      final existing = FinanceTransaction.fromMap(existingRow);
      if (original != null &&
          (existing.version != original.version ||
              existing.updatedAt != original.updatedAt)) {
        throw StateError('账单已同步更新，请重新打开后再保存');
      }
      if (original == null &&
          (existing.version > transaction.version ||
              existing.updatedAt > transaction.updatedAt)) {
        throw StateError('账单已更新，请重新加载后再保存');
      }
      final changesDeletedState =
          original != null && transaction.isDeleted != original.isDeleted;
      if (existing.isDeleted && !changesDeletedState) {
        throw StateError('账单已删除，请重新加载后再编辑');
      }
      if (existing.isDeleted && changesDeletedState && !transaction.isDeleted) {
        await _validateInstallmentRestore(txn, existing);
      }
      transaction
        ..createdAt = existing.createdAt
        ..deviceId = existing.deviceId;
    } else if (original != null) {
      throw StateError('账单已不存在，请重新加载后再保存');
    }
    if (await _hasInstallmentIndexConflict(txn, transaction)) {
      throw StateError('该分期组已存在相同期号的账单');
    }
    await _validateLoanInterestEdit(txn, transaction);
    await _validateTransactionRefundState(txn, transaction);
    await txn.insert(
      'finance_transactions',
      _localValues(transaction.toMap()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _alignLinkedRefunds(txn, originalUuids: [transaction.uuid]);
  });
  _notifyChanged();
}

/// 批量保存多笔账单（例如账单导入），在单个数据库事务中完成写入并仅触发一次刷新。
Future<void> _saveTransactionsBatch(
  List<FinanceTransaction> transactions,
) async {
  if (transactions.isEmpty) return;
  for (final transaction in transactions) {
    if (!transaction.isDeleted &&
        !isFinanceDateKey(transaction.transactionDate)) {
      throw ArgumentError.value(
        transaction.transactionDate,
        'transactionDate',
        '账单日期无效',
      );
    }
    if (!transaction.isDeleted && !_hasValidInstallmentFields(transaction)) {
      throw ArgumentError.value(transaction, 'transaction', '分期期数或总金额无效');
    }
    if (!isSafeFinanceAmountMinor(transaction.amountMinor) ||
        transaction.amountMinor == 0) {
      throw ArgumentError.value(
        transaction.amountMinor,
        'amountMinor',
        '金额必须大于 0',
      );
    }
    final installmentTotalMinor = transaction.installmentTotalMinor;
    if (installmentTotalMinor != null &&
        (!isSafeFinanceAmountMinor(installmentTotalMinor) ||
            installmentTotalMinor == 0)) {
      throw ArgumentError.value(
        installmentTotalMinor,
        'installmentTotalMinor',
        '分期总额超出可保存范围',
      );
    }
    transaction.pendingSync = true;
  }

  await FinanceStorage.ensureReady();
  final db = await _database;
  await db.transaction((txn) async {
    final uuids = <String>[];
    for (final transaction in transactions) {
      if (await _hasInstallmentIndexConflict(txn, transaction)) {
        throw StateError('该分期组已存在相同期号的账单');
      }
      await _validateLoanInterestEdit(txn, transaction);
      await _validateTransactionRefundState(txn, transaction);
      await txn.insert(
        'finance_transactions',
        _localValues(transaction.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      uuids.add(transaction.uuid);
    }
    await _alignLinkedRefunds(txn, originalUuids: uuids);
  });
  _notifyChanged();
}

/// 原子保存一组分期账单。
///
/// 每一期都是正常的 transaction，因此月度统计、搜索、导出和同步都能
/// 沿用现有路径；分期字段只负责把这些交易重新识别为同一组。
Future<List<FinanceTransaction>> _saveInstallmentPlan({
  required FinanceTransaction transaction,
  FinanceTransaction? original,
  required int totalAmountMinor,
  required int installmentCount,
  required DateTime startDate,
  List<FinanceTransaction> existingInstallments = const [],
}) async {
  if (original != null && original.uuid != transaction.uuid) {
    throw ArgumentError.value(original.uuid, 'original', '分期账单标识不匹配');
  }
  final allocations = FinanceInstallmentCalculator.split(
    totalMinor: totalAmountMinor,
    count: installmentCount,
    startDate: startDate,
  );
  await FinanceStorage.ensureReady();

  var existing = existingInstallments;
  if (existing.isEmpty && transaction.installmentGroupUuid != null) {
    existing = await FinanceStorage.getInstallmentGroup(
      transaction.installmentGroupUuid!,
      includeDeleted: true,
    );
  }
  final isNewPlan = original == null && existing.isEmpty;
  final existingByIndex = <int, FinanceTransaction>{};
  for (final item in existing) {
    final index = item.installmentIndex;
    if (index != null && index > 0) existingByIndex[index] = item;
  }

  final groupUuid =
      transaction.installmentGroupUuid ??
      existing
          .map((item) => item.installmentGroupUuid)
          .whereType<String>()
          .firstOrNull ??
      const Uuid().v4();
  final now = DateTime.now().millisecondsSinceEpoch;
  final saved = <FinanceTransaction>[];
  final db = await _database;

  await db.transaction((txn) async {
    final currentRows = await txn.query(
      'finance_transactions',
      where: 'installment_group_uuid = ?',
      whereArgs: [groupUuid],
    );
    final currentByUuid = <String, FinanceTransaction>{};
    for (final row in currentRows) {
      final current = FinanceTransaction.fromMap(row);
      currentByUuid[current.uuid] = current;
    }
    final staleGroup =
        existing.length != currentByUuid.length ||
        existing.any((baseline) {
          final current = currentByUuid[baseline.uuid];
          return current == null ||
              current.version != baseline.version ||
              current.updatedAt != baseline.updatedAt;
        });
    final staleEditedItem =
        original != null &&
        (currentByUuid[original.uuid]?.version != original.version ||
            currentByUuid[original.uuid]?.updatedAt != original.updatedAt);
    if (staleGroup || staleEditedItem) {
      throw StateError('分期组已同步更新，请重新打开整组编辑后再保存');
    }
    final activeInstallmentIndexes = <int>{};
    for (final current in currentByUuid.values.where(
      (item) => !item.isDeleted,
    )) {
      if (!_hasValidInstallmentFields(current)) {
        throw StateError('分期组包含无效期次，请先删除无效记录后再编辑');
      }
      final index = current.installmentIndex;
      if (index != null && !activeInstallmentIndexes.add(index)) {
        throw StateError('分期组存在重复期号，请先删除重复账单后再编辑');
      }
    }
    final activeInstallmentCounts = currentByUuid.values
        .where((item) => !item.isDeleted)
        .map((item) => item.installmentCount)
        .whereType<int>()
        .where((count) => count > 1)
        .toList();
    final currentActiveInstallmentCount = activeInstallmentCounts.isEmpty
        ? null
        : activeInstallmentCounts.reduce(
            (left, right) => left < right ? left : right,
          );
    for (final allocation in allocations) {
      final old = existingByIndex[allocation.index];
      final oldOccurrence = old?.occurrenceLocalTime;
      DateTime? previousOccurrence;
      if (old != null &&
          oldOccurrence != null &&
          dateKey(oldOccurrence) == old.transactionDate) {
        previousOccurrence = oldOccurrence;
      } else {
        final transactionOccurrence = transaction.occurrenceLocalTime;
        previousOccurrence =
            transactionOccurrence != null &&
                dateKey(transactionOccurrence) == transaction.transactionDate
            ? transactionOccurrence
            : null;
      }
      final localOccurrence = previousOccurrence == null
          ? null
          : DateTime(
              allocation.date.year,
              allocation.date.month,
              allocation.date.day,
              previousOccurrence.hour,
              previousOccurrence.minute,
            );
      final timezoneOffsetMinutes = localOccurrence != null && isNewPlan
          ? localOccurrence.timeZoneOffset.inMinutes
          : old?.timezoneOffsetMinutes ?? transaction.timezoneOffsetMinutes;
      final occurrenceAt = localOccurrence == null
          ? null
          : DateTime.utc(
                  localOccurrence.year,
                  localOccurrence.month,
                  localOccurrence.day,
                  localOccurrence.hour,
                  localOccurrence.minute,
                  localOccurrence.second,
                  localOccurrence.millisecond,
                ).millisecondsSinceEpoch -
                timezoneOffsetMinutes * 60000;
      final item = FinanceTransaction(
        uuid: old?.uuid ?? (allocation.index == 1 ? transaction.uuid : null),
        type: transaction.type,
        amountMinor: allocation.amountMinor,
        currencyCode: transaction.currencyCode,
        categoryUuid: transaction.categoryUuid,
        paymentMethodUuid: transaction.paymentMethodUuid,
        transactionDate: dateKey(allocation.date),
        occurredAt: occurrenceAt,
        timezoneOffsetMinutes: timezoneOffsetMinutes,
        merchant: transaction.merchant,
        note: transaction.note,
        source: transaction.source,
        relatedTodoUuid: transaction.relatedTodoUuid,
        relatedPlanBlockUuid: transaction.relatedPlanBlockUuid,
        relatedTransactionUuid: transaction.relatedTransactionUuid,
        installmentGroupUuid: groupUuid,
        installmentIndex: allocation.index,
        installmentCount: allocation.count,
        installmentTotalMinor: totalAmountMinor,
        // 保留组内单独删除的期次。若该期次仅因旧计划缩短而删除，
        // 当前有效期数会小于它的序号；扩期时再将它恢复。
        isDeleted:
            old?.isDeleted == true &&
            (currentActiveInstallmentCount == null ||
                allocation.index <= currentActiveInstallmentCount),
        version: old?.version ?? 1,
        createdAt:
            old?.createdAt ??
            (allocation.index == 1 ? transaction.createdAt : now),
        updatedAt:
            old?.updatedAt ??
            (allocation.index == 1 ? transaction.updatedAt : now),
        deviceId: transaction.deviceId,
      );
      if (occurrenceAt == null) item.occurredAt = null;
      if (old != null) item.markAsChanged();
      item.pendingSync = true;
      await _validateLoanInterestEdit(txn, item);
      await _validateTransactionRefundState(txn, item);
      await txn.insert(
        'finance_transactions',
        _localValues(item.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      saved.add(item);
    }

    // 期数减少时，旧的多余期次进入回收站而不是物理删除，保证同步和
    // 数据恢复都能继续遵守现有的软删除规则。
    for (final old in existing) {
      final index = old.installmentIndex;
      if (index == null || index <= installmentCount || old.isDeleted) {
        continue;
      }
      old.isDeleted = true;
      old.markAsChanged();
      await _validateLoanInterestEdit(txn, old);
      await _validateTransactionRefundState(txn, old);
      await txn.update(
        'finance_transactions',
        _localValues(old.toMap()),
        where: 'uuid = ?',
        whereArgs: [old.uuid],
      );
    }
    await _alignLinkedRefunds(
      txn,
      originalUuids: saved.map((item) => item.uuid),
    );
  });
  _notifyChanged();
  return saved;
}

Future<List<FinanceTransaction>> _getInstallmentGroup(
  String groupUuid, {
  bool includeDeleted = false,
}) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final where = <String>['installment_group_uuid = ?'];
  final args = <Object?>[groupUuid];
  if (!includeDeleted) where.add('is_deleted = 0');
  final rows = await db.query(
    'finance_transactions',
    where: where.join(' AND '),
    whereArgs: args,
    orderBy: 'installment_index ASC, transaction_date ASC, occurred_at ASC',
  );
  return rows.map(FinanceTransaction.fromMap).toList();
}

Future<void> _deleteInstallmentGroup(String groupUuid) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final changed = await db.transaction<bool>((txn) async {
    final rows = await txn.query(
      'finance_transactions',
      where: 'installment_group_uuid = ? AND is_deleted = 0',
      whereArgs: [groupUuid],
      orderBy: 'installment_index ASC, transaction_date ASC, occurred_at ASC',
    );
    if (rows.isEmpty) return false;

    final group = rows.map(FinanceTransaction.fromMap);
    for (final transaction in group) {
      transaction.isDeleted = true;
      transaction.markAsChanged();
      await _validateLoanInterestEdit(txn, transaction);
      await _validateTransactionRefundState(txn, transaction);
      await txn.update(
        'finance_transactions',
        _localValues(transaction.toMap()),
        where: 'uuid = ?',
        whereArgs: [transaction.uuid],
      );
    }
    return true;
  });
  if (changed) _notifyChanged();
}

Future<void> _restoreInstallmentGroup(String groupUuid) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final changed = await db.transaction<bool>((txn) async {
    final rows = await txn.query(
      'finance_transactions',
      where: 'installment_group_uuid = ?',
      whereArgs: [groupUuid],
      orderBy: 'installment_index ASC, transaction_date ASC, occurred_at ASC',
    );
    final group = rows.map(FinanceTransaction.fromMap).toList();
    final deleted = group.where((item) => item.isDeleted).toList();
    if (deleted.isEmpty) return false;

    final counts = group
        .map((item) => item.installmentCount)
        .whereType<int>()
        .where((count) => count > 1)
        .toList();
    final currentCount = counts.isEmpty
        ? null
        : counts.reduce((left, right) => left < right ? left : right);
    final restorable = currentCount == null
        ? deleted
        : deleted.where((item) {
            final index = item.installmentIndex;
            return index == null || index <= currentCount;
          }).toList();
    if (restorable.isEmpty) return false;

    for (final transaction in restorable) {
      transaction.isDeleted = false;
      if (!_hasValidInstallmentFields(transaction)) {
        throw StateError('分期记录无效，无法恢复整组分期');
      }
      if (await _hasInstallmentIndexConflict(txn, transaction)) {
        throw StateError('同一期已存在账单，无法恢复整组分期');
      }
      transaction.markAsChanged();
      await _validateLoanInterestEdit(txn, transaction);
      await _validateTransactionRefundState(txn, transaction);
      await txn.update(
        'finance_transactions',
        _localValues(transaction.toMap()),
        where: 'uuid = ?',
        whereArgs: [transaction.uuid],
      );
    }
    return true;
  });
  if (changed) _notifyChanged();
}

Future<void> _deleteTransaction(String uuid) async {
  final transaction = await FinanceStorage.getTransaction(uuid);
  if (transaction == null || transaction.isDeleted) return;
  final original = FinanceTransaction.fromMap(transaction.toMap());
  transaction.isDeleted = true;
  transaction.markAsChanged();
  await FinanceStorage.saveTransaction(transaction, original: original);
}

Future<void> _restoreTransaction(String uuid) async {
  final transaction = await FinanceStorage.getTransaction(uuid);
  if (transaction == null || !transaction.isDeleted) return;
  final original = FinanceTransaction.fromMap(transaction.toMap());
  transaction.isDeleted = false;
  transaction.markAsChanged();
  await FinanceStorage.saveTransaction(transaction, original: original);
}

Future<FinanceSummary> _getSummary({
  required DateTime from,
  required DateTime to,
}) async {
  final transactions = await FinanceStorage.getTransactions(from: from, to: to);
  return FinanceSummary.fromTransactions(transactions);
}
