import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../services/database_helper.dart';
import '../../../services/storage/app_settings_storage.dart';
import '../../../storage_service.dart';
import '../models/finance_models.dart';

/// 记账领域的本地 SQLite 存储。
///
/// 该类不依赖用户名参数：DatabaseHelper 会根据当前登录用户打开隔离的
/// `uni_sync_<username>.db`，因此记账数据天然按账号隔离。
abstract final class FinanceStorage {
  static const int _maxDateTimeMillis = 8640000000000000;
  static const int _maxFinanceTimezoneOffsetMinutes = 14 * 60;
  static const int _maxTemplateUseCount = 0x7fffffff;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  @visibleForTesting
  static Database? databaseOverride;
  static Database? _readyDatabase;
  static Future<void>? _readyFuture;

  static Future<Database> get _database async =>
      databaseOverride ?? await DatabaseHelper.instance.database;

  /// All writes originating from this device stay pending until the server
  /// acknowledges the exact request snapshot. Remote merges use
  /// [_remoteValues] so a downloaded row can never become a new local upload.
  static Map<String, dynamic> _localValues(Map<String, dynamic> values) => {
    ...values,
    'pending_sync': 1,
  };

  static Map<String, dynamic> _remoteValues(Map<String, dynamic> values) => {
    ...values,
    'pending_sync': 0,
  };

  static Future<void> ensureReady() async {
    final db = await _database;
    if (identical(_readyDatabase, db)) {
      await _readyFuture;
      await _repairLegacyRefundCategories(db);
      return;
    }

    final ready = _ensureReadyFor(db);
    _readyDatabase = db;
    _readyFuture = ready;
    try {
      await ready;
      await _repairLegacyRefundCategories(db);
    } catch (_) {
      if (identical(_readyDatabase, db) && identical(_readyFuture, ready)) {
        _readyDatabase = null;
        _readyFuture = null;
      }
      rethrow;
    }
  }

  static Future<void> _ensureReadyFor(Database db) async {
    await db.transaction((txn) async {
      for (final raw in FinanceDefaults.categories) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await txn.insert('finance_categories', {
          'uuid': raw['uuid'],
          'name': raw['name'],
          'type': raw['type'],
          'icon': raw['icon'],
          'icon_customized': 0,
          'name_customized': 0,
          'parent_uuid': raw['parent_uuid'],
          'is_system': 1,
          'is_archived': 0,
          'is_deleted': 0,
          'sort_order': raw['sort_order'],
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'pending_sync': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.rawUpdate(
          '''
          UPDATE finance_categories
          SET name = CASE WHEN name_customized = 1 THEN name ELSE ? END,
              type = ?,
              parent_uuid = ?,
              is_archived = 0,
              is_deleted = 0,
              sort_order = ?
          WHERE uuid = ? AND is_system = 1
          ''',
          [
            raw['name'],
            raw['type'],
            raw['parent_uuid'],
            raw['sort_order'],
            raw['uuid'],
          ],
        );
      }
      for (final raw in FinanceDefaults.paymentMethods) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await txn.insert('finance_payment_methods', {
          'uuid': raw['uuid'],
          'name': raw['name'],
          'icon': raw['icon'],
          'is_system': 1,
          'is_archived': 0,
          'is_deleted': 0,
          'sort_order': raw['sort_order'],
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'pending_sync': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  static Future<void> _repairLegacyRefundCategories(Database db) async {
    final migrationNow = DateTime.now().millisecondsSinceEpoch;
    final repairedCount = await db.rawUpdate(
      '''
      UPDATE finance_transactions
      SET category_uuid = ?,
          version = version + 1,
          updated_at = CASE
            WHEN updated_at >= ? THEN updated_at + 1
            ELSE ?
          END,
          pending_sync = 1
      WHERE type = 'refund'
        AND category_uuid IN (
          SELECT uuid FROM finance_categories WHERE type = 'income'
        )
      ''',
      ['finance-system-category-refund', migrationNow, migrationNow],
    );
    if (repairedCount > 0) _notifyChanged();
  }

  static Future<List<FinanceTransaction>> getTransactions({
    bool includeDeleted = false,
    DateTime? from,
    DateTime? to,
    String? keyword,
    String? categoryUuid,
    FinanceTransactionType? type,
    int? limit,
  }) async {
    await ensureReady();
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

  static Future<List<FinanceTransaction>> getBalanceTransactions({
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

    await ensureReady();
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
      rows.addAll(
        await db.query(
          'finance_transactions',
          where: 'is_deleted = 0 AND payment_method_uuid IN '
              '(${List.filled(batch.length, '?').join(',')}) AND '
              'transaction_date < ? AND '
              '(transaction_date >= ? OR created_at > ?)',
          // Stored ledger dates belong to their recorded timezone. The largest
          // difference between two supported offsets is 28 hours; widen the
          // date bounds and let balanceEventAt apply the exact instant cutoff.
          whereArgs: [
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

  static Future<FinanceTransaction?> getTransaction(String uuid) async {
    await ensureReady();
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

  static Future<List<FinanceTransaction>> getRefundsForTransaction(
    String transactionUuid, {
    bool includeDeleted = false,
  }) async {
    await ensureReady();
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

  static Future<int> getRemainingRefundableMinor(
    String transactionUuid, {
    String? excludingRefundUuid,
  }) async {
    await ensureReady();
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

  static Future<List<FinanceTransaction>> getDeletedTransactions() async {
    await ensureReady();
    final db = await _database;
    final rows = await db.query(
      'finance_transactions',
      where: 'is_deleted = 1',
      orderBy: 'updated_at DESC',
    );
    return rows.map(FinanceTransaction.fromMap).toList();
  }

  static Future<void> saveTransaction(
    FinanceTransaction transaction, {
    FinanceTransaction? original,
  }) async {
    if (!transaction.isDeleted && !_hasValidInstallmentFields(transaction)) {
      throw ArgumentError.value(
        transaction,
        'transaction',
        '分期期数或总金额无效',
      );
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
    await ensureReady();
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
        if (existing.isDeleted &&
            changesDeletedState &&
            !transaction.isDeleted) {
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

  /// 原子保存一组分期账单。
  ///
  /// 每一期都是正常的 transaction，因此月度统计、搜索、导出和同步都能
  /// 沿用现有路径；分期字段只负责把这些交易重新识别为同一组。
  static Future<List<FinanceTransaction>> saveInstallmentPlan({
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
    await ensureReady();

    var existing = existingInstallments;
    if (existing.isEmpty && transaction.installmentGroupUuid != null) {
      existing = await getInstallmentGroup(
        transaction.installmentGroupUuid!,
        includeDeleted: true,
      );
    }
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
      final staleGroup = existing.length != currentByUuid.length ||
          existing.any((baseline) {
            final current = currentByUuid[baseline.uuid];
            return current == null ||
                current.version != baseline.version ||
                current.updatedAt != baseline.updatedAt;
          });
      final staleEditedItem = original != null &&
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
        final previousOccurrence =
            old?.occurrenceLocalTime ?? transaction.occurrenceLocalTime;
        final occurrenceAt = previousOccurrence == null
            ? null
            : DateTime.utc(
                allocation.date.year,
                allocation.date.month,
                allocation.date.day,
                previousOccurrence.hour,
                previousOccurrence.minute,
              ).millisecondsSinceEpoch -
                transaction.timezoneOffsetMinutes * 60000;
        final item = FinanceTransaction(
          uuid: old?.uuid ?? (allocation.index == 1 ? transaction.uuid : null),
          type: transaction.type,
          amountMinor: allocation.amountMinor,
          currencyCode: transaction.currencyCode,
          categoryUuid: transaction.categoryUuid,
          paymentMethodUuid: transaction.paymentMethodUuid,
          transactionDate: dateKey(allocation.date),
          occurredAt: occurrenceAt,
          timezoneOffsetMinutes: transaction.timezoneOffsetMinutes,
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
          isDeleted: old?.isDeleted == true &&
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

  static Future<List<FinanceTransaction>> getInstallmentGroup(
    String groupUuid, {
    bool includeDeleted = false,
  }) async {
    await ensureReady();
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

  static Future<void> deleteInstallmentGroup(String groupUuid) async {
    await ensureReady();
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

  static Future<void> restoreInstallmentGroup(String groupUuid) async {
    await ensureReady();
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

  static Future<List<FinanceLoan>> getLoans({
    bool includeDeleted = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final rows = await db.query(
      'finance_loans',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'start_date DESC, updated_at DESC',
    );
    return rows.map(FinanceLoan.fromMap).toList();
  }

  static Future<FinanceLoan?> getLoan(
    String uuid, {
    bool includeDeleted = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final where = <String>['uuid = ?'];
    if (!includeDeleted) where.add('is_deleted = 0');
    final rows = await db.query(
      'finance_loans',
      where: where.join(' AND '),
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : FinanceLoan.fromMap(rows.first);
  }

  static Future<List<FinanceLoanInstallment>> getLoanInstallments(
    String loanUuid, {
    bool includeDeleted = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final loanRow = await _findByUuid(db, 'finance_loans', loanUuid);
    if (loanRow == null) return const [];
    final loan = FinanceLoan.fromMap(loanRow);
    final where = <String>['loan_uuid = ?'];
    final args = <Object?>[loanUuid];
    if (!includeDeleted) {
      where
        ..add('is_deleted = 0')
        ..add('installment_index <= ?');
      args.add(loan.termMonths);
    }
    final rows = await db.query(
      'finance_loan_installments',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'installment_index ASC, due_date ASC',
    );
    return rows.map(FinanceLoanInstallment.fromMap).toList();
  }

  static Future<FinanceLoanInstallment?> getLoanInstallment(
    String uuid, {
    bool includeDeleted = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final where = <String>['uuid = ?'];
    if (!includeDeleted) where.add('is_deleted = 0');
    final rows = await db.query(
      'finance_loan_installments',
      where: where.join(' AND '),
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : FinanceLoanInstallment.fromMap(rows.first);
  }

  /// 保存贷款并在同一事务中生成或重算整套还款计划。
  static Future<void> saveLoan(
    FinanceLoan loan, {
    FinanceLoan? original,
  }) async {
    _validateLoan(loan);
    if (original != null && original.uuid != loan.uuid) {
      throw ArgumentError.value(original.uuid, 'original', '贷款标识不匹配');
    }
    await ensureReady();
    final db = await _database;
    await db.transaction((txn) async {
      final existingRow = await _findByUuid(txn, 'finance_loans', loan.uuid);
      final existing = existingRow == null
          ? null
          : FinanceLoan.fromMap(existingRow);
      if (existing != null) {
        if (original != null &&
            (existing.version != original.version ||
                existing.updatedAt != original.updatedAt)) {
          _mergeLoanEdits(existing, original, loan);
          _validateLoan(loan);
        } else if (original == null &&
            (existing.version > loan.version ||
                existing.updatedAt > loan.updatedAt)) {
          throw StateError('贷款已更新，请重新加载后再保存');
        }
        if (existing.isDeleted) {
          throw StateError('贷款已删除，请先恢复后再编辑');
        }
      } else if (original != null) {
        throw StateError('贷款已不存在，请重新加载后再保存');
      }
      final existingInstallments = existing == null
          ? <FinanceLoanInstallment>[]
          : await _loanInstallmentsInTransaction(txn, loan.uuid);
      final hasPaidInstallment = existingInstallments.any((item) => item.isPaid);
      if (existing != null &&
          hasPaidInstallment &&
          _loanTermsDiffer(existing, loan)) {
        throw StateError('已有还款记录后不能修改本金、币种、利率、期限、借款日期、还款日或还款方式');
      }
      final allocations = FinanceLoanCalculator.generate(
        principalMinor: loan.principalMinor,
        annualInterestRateBps: loan.annualInterestRateBps,
        termMonths: loan.termMonths,
        startDate: dateFromKey(loan.startDate),
        repaymentDay: loan.repaymentDay,
        repaymentMethod: loan.repaymentMethod,
      );
      final existingByIndex = <int, FinanceLoanInstallment>{};
      for (final item in existingInstallments) {
        if (item.installmentIndex > 0) {
          existingByIndex[item.installmentIndex] = item;
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (existing != null) {
        loan.version = existing.version;
        loan.createdAt = existing.createdAt;
        loan.updatedAt = existing.updatedAt;
        loan.deviceId = existing.deviceId;
        loan.markAsChanged();
      } else {
        loan.pendingSync = true;
      }
      await txn.insert(
        'finance_loans',
        _localValues(loan.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final allocation in allocations) {
        final old = existingByIndex[allocation.index];
        final installment = FinanceLoanInstallment(
          uuid: old?.uuid,
          loanUuid: loan.uuid,
          installmentIndex: allocation.index,
          dueDate: allocation.dueDate,
          paymentMinor: allocation.paymentMinor,
          principalMinor: allocation.principalMinor,
          interestMinor: allocation.interestMinor,
          remainingPrincipalMinor: allocation.remainingPrincipalMinor,
          isPaid: old?.isPaid ?? false,
          paidAt: old?.paidAt,
          paymentMethodUuid: old?.paymentMethodUuid,
          interestTransactionUuid: old?.interestTransactionUuid,
          isDeleted: false,
          version: old?.version ?? 1,
          createdAt: old?.createdAt ?? now,
          updatedAt: old?.updatedAt ?? now,
          deviceId: loan.deviceId,
        );
        if (old != null) installment.markAsChanged();
        installment.pendingSync = true;
        await txn.insert(
          'finance_loan_installments',
          _localValues(installment.toMap()),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final old in existingInstallments) {
        if (old.installmentIndex <= loan.termMonths || old.isDeleted) {
          continue;
        }
        old.isDeleted = true;
        old.markAsChanged();
        await txn.update(
          'finance_loan_installments',
          _localValues(old.toMap()),
          where: 'uuid = ?',
          whereArgs: [old.uuid],
        );
      }
    });
    _notifyChanged();
  }

  /// Cash movements are stored on repayment records, separately from interest
  /// expenses, so even a zero-interest repayment changes the account balance.
  /// Recycling a loan or its plan does not undo an actual payment.
  static Future<List<FinanceLoanInstallment>> getPaidLoanInstallments() async {
    await ensureReady();
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT installment.* FROM finance_loan_installments AS installment
      JOIN finance_loans AS loan ON loan.uuid = installment.loan_uuid
      WHERE installment.is_paid = 1 AND installment.paid_at > 0
        AND installment.payment_method_uuid IS NOT NULL
        AND (
          installment.is_deleted = 1
          OR installment.installment_index <= loan.term_months
        )
    ''');
    return rows.map(FinanceLoanInstallment.fromMap).toList();
  }

  /// Includes recycled and canceled repayments so their interest bills remain
  /// managed through the repayment even after its current bill pointer clears.
  static Future<FinanceLoanInstallment?> getRepaymentForInterestTransaction(
    String transactionUuid,
  ) async {
    await ensureReady();
    return _findRepaymentForInterestTransaction(
      await _database,
      transactionUuid,
    );
  }

  static Future<FinanceLoanInstallment?> _findRepaymentForInterestTransaction(
    DatabaseExecutor db,
    String transactionUuid,
  ) async {
    final rows = await db.rawQuery('''
      SELECT installment.* FROM finance_loan_installments AS installment
      WHERE installment.interest_transaction_uuid = ?
        OR installment.uuid = (
          SELECT related_transaction_uuid FROM finance_transactions WHERE uuid = ?
        )
      ORDER BY CASE WHEN installment.interest_transaction_uuid = ? THEN 0 ELSE 1 END
      LIMIT 1
    ''', [transactionUuid, transactionUuid, transactionUuid]);
    return rows.isEmpty ? null : FinanceLoanInstallment.fromMap(rows.single);
  }

  static Future<void> _validateLoanInterestEdit(
    DatabaseExecutor db,
    FinanceTransaction transaction,
  ) async {
    final repayment = await _findRepaymentForInterestTransaction(
      db,
      transaction.uuid,
    );
    if (repayment == null) return;
    if (!repayment.isPaid ||
        repayment.interestTransactionUuid != transaction.uuid) {
      // Canceled or replaced bills may be deleted to clean up legacy data,
      // but only the repayment operation can activate its current interest.
      if (!transaction.isDeleted) {
        throw StateError(
          repayment.isPaid
              ? '这笔利息已由新的还款账单替代，请在贷款还款中查看当前账单'
              : '关联还款已撤销，不能单独恢复利息账单；请在贷款还款中重新标记已还款',
        );
      }
      return;
    }
    if (transaction.isDeleted) {
      throw StateError('贷款利息账单由还款记录管理，请在贷款还款中修改或撤销还款');
    }
    final existing = await _findByUuid(
      db,
      'finance_transactions',
      transaction.uuid,
    );
    final values = transaction.toMap();
    const repaymentFields = [
      'type',
      'amount_minor',
      'currency_code',
      'category_uuid',
      'payment_method_uuid',
      'transaction_date',
      'occurred_at',
      'timezone_offset_minutes',
      'related_transaction_uuid',
      'installment_group_uuid',
      'installment_index',
      'installment_count',
      'installment_total_minor',
    ];
    if (existing == null ||
        repaymentFields.any((key) => existing[key] != values[key])) {
      throw StateError('贷款利息账单由还款记录管理，请在贷款还款中修改或撤销还款');
    }
  }

  static Future<void> _validateInstallmentRestore(
    DatabaseExecutor db,
    FinanceTransaction transaction,
  ) async {
    final groupUuid = transaction.installmentGroupUuid;
    final installmentIndex = transaction.installmentIndex;
    if (!transaction.isInstallment ||
        groupUuid == null ||
        installmentIndex == null) {
      return;
    }

    final rows = await db.query(
      'finance_transactions',
      where: 'installment_group_uuid = ?',
      whereArgs: [groupUuid],
    );
    int? currentCount;
    for (final row in rows) {
      final count = FinanceTransaction.fromMap(row).installmentCount;
      if (count != null &&
          count > 1 &&
          (currentCount == null || count < currentCount)) {
        currentCount = count;
      }
    }
    if (currentCount != null && installmentIndex > currentCount) {
      throw StateError('此期已超出当前分期计划，请先调整分期期数后再恢复');
    }
  }

  /// Only interest enters consumption statistics. The full repayment amount
  /// reduces the selected account at paidAt through getPaidLoanInstallments.
  static Future<void> setLoanInstallmentPaid(
    String installmentUuid,
    bool paid, {
    String? paymentMethodUuid,
    DateTime? paidAt,
  }) async {
    await ensureReady();
    final db = await _database;
    final changed = await db.transaction<bool>((txn) async {
      final row = await _findByUuid(
        txn,
        'finance_loan_installments',
        installmentUuid,
      );
      if (row == null) return false;
      final installment = FinanceLoanInstallment.fromMap(row);
      if (installment.isDeleted) return false;
      final loanRow = await _findByUuid(
        txn,
        'finance_loans',
        installment.loanUuid,
      );
      if (loanRow == null || FinanceLoan.fromMap(loanRow).isDeleted) {
        throw StateError('关联的贷款不存在或已删除');
      }
      final loan = FinanceLoan.fromMap(loanRow);
      if (installment.installmentIndex > loan.termMonths) {
        throw StateError('还款期次超出贷款期限');
      }
      if (installment.isPaid == paid &&
          paymentMethodUuid == null &&
          paidAt == null) {
        return false;
      }
      if (paid) {
        final paymentDate = paidAt ?? DateTime.now();
        if (paymentDate.isAfter(DateTime.now()) || paymentDate.year < 2000) {
          throw ArgumentError('还款时间必须在 2000 年之后且不晚于现在');
        }
        final methodUuid = paymentMethodUuid?.trim();
        if (methodUuid != null && methodUuid.isNotEmpty) {
          final method = await _findByUuid(
            txn,
            'finance_payment_methods',
            methodUuid,
          );
          if (method == null ||
              FinancePaymentMethod.fromMap(method).isDeleted) {
            throw StateError('还款账户不存在或已删除');
          }
          if (FinancePaymentMethod.fromMap(method).isArchived &&
              methodUuid != installment.paymentMethodUuid) {
            throw StateError('请选择未归档的还款账户');
          }
        }
        installment.isPaid = true;
        installment.paidAt = paymentDate.millisecondsSinceEpoch;
        installment.paymentMethodUuid = methodUuid?.isNotEmpty == true
            ? methodUuid
            : null;
        if (installment.interestMinor > 0) {
          final stableUuid =
              installment.interestTransactionUuid ??
              _loanInterestTransactionUuid(installment.uuid);
          final existingRow = await _findByUuid(
            txn,
            'finance_transactions',
            stableUuid,
          );
          final interestTransaction = existingRow == null
              ? FinanceTransaction(
                  uuid: stableUuid,
                  type: FinanceTransactionType.expense,
                  amountMinor: installment.interestMinor,
                  currencyCode: loan.currencyCode,
                  categoryUuid: 'finance-system-category-loan-interest',
                  paymentMethodUuid: installment.paymentMethodUuid,
                  transactionDate: dateKey(paymentDate),
                  occurredAt: installment.paidAt,
                  timezoneOffsetMinutes: paymentDate.timeZoneOffset.inMinutes,
                  merchant: '贷款利息 · ${loan.name}',
                  note:
                      '第 ${installment.installmentIndex}/${loan.termMonths} 期利息；同步归还本金',
                  source: FinanceEntrySource.automation,
                  relatedTransactionUuid: installment.uuid,
                  deviceId: loan.deviceId,
                  pendingSync: true,
                )
              : FinanceTransaction.fromMap(existingRow);
          if (existingRow != null) {
            interestTransaction
              ..type = FinanceTransactionType.expense
              ..amountMinor = installment.interestMinor
              ..currencyCode = loan.currencyCode
              ..categoryUuid = 'finance-system-category-loan-interest'
              ..paymentMethodUuid = installment.paymentMethodUuid
              ..transactionDate = dateKey(paymentDate)
              ..occurredAt = installment.paidAt
              ..timezoneOffsetMinutes = paymentDate.timeZoneOffset.inMinutes
              ..merchant = '贷款利息 · ${loan.name}'
              ..note =
                  '第 ${installment.installmentIndex}/${loan.termMonths} 期利息；同步归还本金'
              ..source = FinanceEntrySource.automation
              ..relatedTransactionUuid = installment.uuid
              ..isDeleted = false
              ..markAsChanged();
          }
          installment.interestTransactionUuid = interestTransaction.uuid;
          await _validateTransactionRefundState(txn, interestTransaction);
          await txn.insert(
            'finance_transactions',
            _localValues(interestTransaction.toMap()),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } else {
        final interestTransactionUuid = installment.interestTransactionUuid;
        if (interestTransactionUuid != null) {
          final row = await _findByUuid(
            txn,
            'finance_transactions',
            interestTransactionUuid,
          );
          if (row != null) {
            final interestTransaction = FinanceTransaction.fromMap(row);
            final wasDeleted = interestTransaction.isDeleted;
            interestTransaction.isDeleted = true;
            await _validateTransactionRefundState(txn, interestTransaction);
            if (!wasDeleted) {
              interestTransaction.markAsChanged();
              await txn.update(
                'finance_transactions',
                _localValues(interestTransaction.toMap()),
                where: 'uuid = ?',
                whereArgs: [interestTransaction.uuid],
              );
            }
          }
        }
        installment.isPaid = false;
        installment.paidAt = null;
        installment.paymentMethodUuid = null;
        installment.interestTransactionUuid = null;
      }
      installment.markAsChanged();
      await txn.update(
        'finance_loan_installments',
        _localValues(installment.toMap()),
        where: 'uuid = ?',
        whereArgs: [installment.uuid],
      );
      return true;
    });
    if (changed) _notifyChanged();
  }

  static String _loanInterestTransactionUuid(String installmentUuid) {
    return const Uuid().v5(
      '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
      'countdown-todo/finance-loan-interest/v1/$installmentUuid',
    );
  }

  static Future<void> deleteLoan(String uuid) async {
    await _setLoanDeleted(uuid, true);
  }

  static Future<void> restoreLoan(String uuid) async {
    await _setLoanDeleted(uuid, false);
  }

  static Future<List<FinanceLoanInstallment>> _loanInstallmentsInTransaction(
    DatabaseExecutor db,
    String loanUuid,
  ) async {
    final rows = await db.query(
      'finance_loan_installments',
      where: 'loan_uuid = ?',
      whereArgs: [loanUuid],
      orderBy: 'installment_index ASC, due_date ASC',
    );
    return rows.map(FinanceLoanInstallment.fromMap).toList();
  }

  static Future<void> _setLoanDeleted(String uuid, bool deleted) async {
    await ensureReady();
    final db = await _database;
    final changed = await db.transaction<bool>((txn) async {
      final row = await _findByUuid(txn, 'finance_loans', uuid);
      if (row == null) return false;
      final loan = FinanceLoan.fromMap(row);
      if (loan.isDeleted == deleted) return false;
      final installments = await _loanInstallmentsInTransaction(txn, uuid);
      loan.isDeleted = deleted;
      loan.markAsChanged();
      await txn.update(
        'finance_loans',
        _localValues(loan.toMap()),
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      for (final installment in installments) {
        if (installment.isDeleted == deleted ||
            (!deleted && installment.installmentIndex > loan.termMonths)) {
          continue;
        }
        installment.isDeleted = deleted;
        installment.markAsChanged();
        await txn.update(
          'finance_loan_installments',
          _localValues(installment.toMap()),
          where: 'uuid = ?',
          whereArgs: [installment.uuid],
        );
      }
      return true;
    });
    if (changed) _notifyChanged();
  }

  static Future<void> deleteTransaction(String uuid) async {
    final transaction = await getTransaction(uuid);
    if (transaction == null || transaction.isDeleted) return;
    final original = FinanceTransaction.fromMap(transaction.toMap());
    transaction.isDeleted = true;
    transaction.markAsChanged();
    await saveTransaction(transaction, original: original);
  }

  static Future<void> restoreTransaction(String uuid) async {
    final transaction = await getTransaction(uuid);
    if (transaction == null || !transaction.isDeleted) return;
    final original = FinanceTransaction.fromMap(transaction.toMap());
    transaction.isDeleted = false;
    transaction.markAsChanged();
    await saveTransaction(transaction, original: original);
  }

  static Future<List<FinanceCategory>> getCategories({
    FinanceCategoryType? type,
    bool includeArchived = false,
    bool includeDeleted = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) {
      where.add('is_deleted = 0');
    }
    if (!includeArchived) {
      where.add(
        'is_archived = 0 AND NOT EXISTS ('
        'SELECT 1 FROM finance_categories AS parent '
        'WHERE parent.uuid = finance_categories.parent_uuid '
        'AND parent.is_archived = 1 AND parent.is_deleted = 0)',
      );
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
    }
    final rows = await db.query(
      'finance_categories',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'type ASC, sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(FinanceCategory.fromMap).toList();
  }

  static Future<void> saveCategory(
    FinanceCategory category, {
    FinanceCategory? original,
  }) async {
    if (category.name.trim().isEmpty) {
      throw ArgumentError.value(category.name, 'name', '分类名称不能为空');
    }
    if (original != null && original.uuid != category.uuid) {
      throw ArgumentError.value(original.uuid, 'original', '分类标识不匹配');
    }
    final parentUuid = category.parentUuid?.trim();
    category.parentUuid = parentUuid == null || parentUuid.isEmpty
        ? null
        : parentUuid;
    await ensureReady();
    final db = await _database;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: [category.uuid],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final existing = FinanceCategory.fromMap(existingRows.first);
        if (existing.isDeleted) {
          throw StateError('分类已删除，请重新加载后再编辑');
        }
        final baselineChanged =
            original != null &&
            (existing.version != original.version ||
                existing.updatedAt != original.updatedAt);
        if (baselineChanged) {
          _mergeCategoryEdits(existing, original, category);
          category
            ..version = existing.version
            ..updatedAt = existing.updatedAt
            ..createdAt = existing.createdAt
            ..markAsChanged();
        } else if (original == null &&
            (category.version < existing.version ||
                category.updatedAt < existing.updatedAt)) {
          throw StateError('分类已更新，请重新加载后再保存');
        }
        if (existing.isSystem) {
          // System categories keep their built-in identity and hierarchy while
          // name and icon overrides remain user-owned fields.
          final defaults = FinanceDefaults.categories.firstWhere(
            (item) => item['uuid'] == existing.uuid,
            orElse: () => const <String, dynamic>{},
          );
          category
            ..isSystem = true
            ..type = existing.type
            ..colorValue = existing.colorValue
            ..parentUuid = existing.parentUuid
            ..sortOrder = existing.sortOrder
            ..isArchived = false
            ..isDeleted = false
            ..nameCustomized = defaults.isEmpty
                ? category.name != existing.name || existing.nameCustomized
                : category.name != defaults['name'] || existing.nameCustomized
            ..iconCustomized = defaults.isEmpty
                ? category.icon != existing.icon || existing.iconCustomized
                : category.icon != defaults['icon'] || existing.iconCustomized;
          if (category.version <= existing.version ||
              category.updatedAt <= existing.updatedAt) {
            category
              ..uuid = existing.uuid
              ..createdAt = existing.createdAt
              ..version = existing.version
              ..updatedAt = existing.updatedAt
              ..markAsChanged();
          }
        } else {
          category
            ..isSystem = false
            ..createdAt = existing.createdAt;
        }
      } else if (category.isSystem || _isSystemUuid(category.uuid)) {
        throw ArgumentError.value(category.uuid, 'uuid', '系统分类只能使用内置分类标识');
      }
      if (category.parentUuid != null) {
        if (category.parentUuid == category.uuid) {
          throw ArgumentError.value(
            category.parentUuid,
            'parentUuid',
            '分类不能将自己设置为上级大类',
          );
        }
        final parentRows = await txn.query(
          'finance_categories',
          where: 'uuid = ? AND is_deleted = 0',
          whereArgs: [category.parentUuid],
          limit: 1,
        );
        if (parentRows.isEmpty) {
          throw ArgumentError.value(category.parentUuid, 'parentUuid', '上级大类不存在');
        }
        final parent = FinanceCategory.fromMap(parentRows.first);
        if (parent.type != category.type ||
            parent.parentUuid?.trim().isNotEmpty == true) {
          throw ArgumentError.value(
            category.parentUuid,
            'parentUuid',
            '上级分类必须是同一收支类型的一级分类',
          );
        }
        if (parent.isArchived && !category.isArchived) {
          throw ArgumentError.value(
            category.parentUuid,
            'parentUuid',
            '上级分类已归档，请先恢复后再添加二级分类',
          );
        }
      }
      if (category.parentUuid != null) {
        final children = await txn.query(
          'finance_categories',
          columns: ['uuid'],
          where: 'parent_uuid = ? AND is_deleted = 0',
          whereArgs: [category.uuid],
          limit: 1,
        );
        if (children.isNotEmpty) {
          throw ArgumentError.value(
            category.parentUuid,
            'parentUuid',
            '已有二级分类，请先移动二级分类后再调整上级',
          );
        }
      }
      category.pendingSync = true;
      await txn.insert(
        'finance_categories',
        _localValues(category.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

    });
    _notifyChanged();
  }

  static void _mergeCategoryEdits(
    FinanceCategory current,
    FinanceCategory original,
    FinanceCategory incoming,
  ) {
    if (incoming.name == original.name) incoming.name = current.name;
    if (incoming.type == original.type) incoming.type = current.type;
    if (incoming.icon == original.icon) incoming.icon = current.icon;
    if (incoming.iconCustomized == original.iconCustomized) {
      incoming.iconCustomized = current.iconCustomized;
    }
    if (incoming.nameCustomized == original.nameCustomized) {
      incoming.nameCustomized = current.nameCustomized;
    }
    if (incoming.colorValue == original.colorValue) {
      incoming.colorValue = current.colorValue;
    }
    if (incoming.parentUuid == original.parentUuid) {
      incoming.parentUuid = current.parentUuid;
    }
    if (incoming.isSystem == original.isSystem) {
      incoming.isSystem = current.isSystem;
    }
    if (incoming.isArchived == original.isArchived) {
      incoming.isArchived = current.isArchived;
    }
    if (incoming.isDeleted == original.isDeleted) {
      incoming.isDeleted = current.isDeleted;
    }
    if (incoming.sortOrder == original.sortOrder) {
      incoming.sortOrder = current.sortOrder;
    }
  }

  static Future<void> archiveCategory(String uuid) async {
    await ensureReady();
    final db = await _database;
    final changed = await db.transaction<bool>((txn) async {
      final existing = await txn.query(
        'finance_categories',
        where: 'uuid = ? AND is_deleted = 0',
        whereArgs: [uuid],
        limit: 1,
      );
      if (existing.isEmpty) return false;
      final category = FinanceCategory.fromMap(existing.first);
      if (category.isSystem || category.isArchived) return false;
      category
        ..isArchived = true
        ..markAsChanged();
      await txn.update(
        'finance_categories',
        _localValues(category.toMap()),
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      final children = await txn.query(
        'finance_categories',
        where: 'parent_uuid = ? AND is_deleted = 0 AND is_archived = 0',
        whereArgs: [uuid],
      );
      for (final raw in children) {
        final child = FinanceCategory.fromMap(raw);
        if (child.isSystem) continue;
        child
          ..isArchived = true
          ..markAsChanged();
        await txn.update(
          'finance_categories',
          _localValues(child.toMap()),
          where: 'uuid = ?',
          whereArgs: [child.uuid],
        );
      }
      return true;
    });
    if (changed) _notifyChanged();
  }

  static Future<bool> unarchiveCategory(String uuid) async {
    await ensureReady();
    final db = await _database;
    final restored = await db.transaction<bool>((txn) async {
      final existing = await txn.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      if (existing.isEmpty) return false;
      var category = FinanceCategory.fromMap(existing.first);
      if (category.isSystem || category.isDeleted) return false;
      final categoryWasArchived = category.isArchived;

      final parentUuid = _normalizeCategoryParentUuid(category.parentUuid);
      if (parentUuid != null) {
        final parentRows = await txn.query(
          'finance_categories',
          where: 'uuid = ? AND is_deleted = 0',
          whereArgs: [parentUuid],
          limit: 1,
        );
        if (parentRows.isEmpty) return false;
        final parent = FinanceCategory.fromMap(parentRows.first);
        if (parent.type != category.type ||
            _normalizeCategoryParentUuid(parent.parentUuid) != null) {
          return false;
        }
        if (parent.isArchived) {
          category = parent;
        } else if (!categoryWasArchived) {
          return false;
        }
      } else if (!categoryWasArchived) {
        return false;
      }

      if (category.isSystem || !category.isArchived) return false;
      category
        ..isArchived = false
        ..markAsChanged();
      await txn.update(
        'finance_categories',
        _localValues(category.toMap()),
        where: 'uuid = ?',
        whereArgs: [category.uuid],
      );
      final children = await txn.query(
        'finance_categories',
        where: 'parent_uuid = ? AND is_deleted = 0 AND is_archived = 1',
        whereArgs: [category.uuid],
      );
      for (final raw in children) {
        final child = FinanceCategory.fromMap(raw);
        if (child.isSystem) continue;
        child
          ..isArchived = false
          ..markAsChanged();
        await txn.update(
          'finance_categories',
          _localValues(child.toMap()),
          where: 'uuid = ?',
          whereArgs: [child.uuid],
        );
      }
      return true;
    });
    if (restored) _notifyChanged();
    return restored;
  }

  static Future<bool> hasTransactionsForCategory(String uuid) async {
    await ensureReady();
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM finance_transactions '
      'WHERE category_uuid = ?',
      [uuid],
    );
    return (result.first['count'] as num?)?.toInt() != 0;
  }

  static Future<List<FinancePaymentMethod>> getPaymentMethods({
    bool includeArchived = false,
    bool includeDeleted = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final where = <String>[];
    if (!includeDeleted) where.add('is_deleted = 0');
    if (!includeArchived) where.add('is_archived = 0');
    final rows = await db.query(
      'finance_payment_methods',
      where: where.isEmpty ? null : where.join(' AND '),
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(FinancePaymentMethod.fromMap).toList();
  }

  static Future<void> savePaymentMethod(
    FinancePaymentMethod method, {
    FinancePaymentMethod? original,
  }) async {
    if (method.name.trim().isEmpty) {
      throw ArgumentError.value(method.name, 'name', '付款方式名称不能为空');
    }
    if (original != null && original.uuid != method.uuid) {
      throw ArgumentError.value(original.uuid, 'original', '付款方式标识不匹配');
    }
    await ensureReady();
    final db = await _database;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'finance_payment_methods',
        where: 'uuid = ?',
        whereArgs: [method.uuid],
        limit: 1,
      );
      var itemToSave = FinancePaymentMethod.fromMap(method.toMap());
      if (existingRows.isNotEmpty) {
        final existing = FinancePaymentMethod.fromMap(existingRows.first);
        final baselineChanged = original != null &&
            (existing.version != original.version ||
                existing.updatedAt != original.updatedAt);
        if (baselineChanged) {
          _mergePaymentMethodEdits(existing, original, itemToSave);
          itemToSave
            ..version = existing.version
            ..updatedAt = existing.updatedAt
            ..createdAt = existing.createdAt;
          itemToSave.markAsChanged();
        } else if (original == null &&
            (existing.version > itemToSave.version ||
                existing.updatedAt > itemToSave.updatedAt)) {
          throw StateError('付款方式已更新，请重新加载后再保存');
        }
        if (existing.isDeleted) {
          throw StateError('付款方式已删除，请重新加载后再编辑');
        }
        if (existing.isSystem) {
          throw StateError('系统付款方式不能编辑');
        }
        itemToSave.createdAt = existing.createdAt;
      }
      if (itemToSave.name.trim().isEmpty) {
        throw ArgumentError.value(itemToSave.name, 'name', '付款方式名称不能为空');
      }
      itemToSave.pendingSync = true;
      await txn.insert(
        'finance_payment_methods',
        _localValues(itemToSave.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _notifyChanged();
  }

  static void _mergePaymentMethodEdits(
    FinancePaymentMethod current,
    FinancePaymentMethod original,
    FinancePaymentMethod incoming,
  ) {
    if (incoming.name == original.name) incoming.name = current.name;
    if (incoming.icon == original.icon) incoming.icon = current.icon;
    if (incoming.colorValue == original.colorValue) {
      incoming.colorValue = current.colorValue;
    }
    if (incoming.isSystem == original.isSystem) {
      incoming.isSystem = current.isSystem;
    }
    if (incoming.isArchived == original.isArchived) {
      incoming.isArchived = current.isArchived;
    }
    if (incoming.isDeleted == original.isDeleted) {
      incoming.isDeleted = current.isDeleted;
    }
    if (incoming.sortOrder == original.sortOrder) {
      incoming.sortOrder = current.sortOrder;
    }
  }

  static Future<void> archivePaymentMethod(String uuid) async {
    await ensureReady();
    final db = await _database;
    final changed = await db.transaction<bool>((txn) async {
      final existing = await txn.query(
        'finance_payment_methods',
        where: 'uuid = ? AND is_deleted = 0',
        whereArgs: [uuid],
        limit: 1,
      );
      if (existing.isEmpty) return false;
      final method = FinancePaymentMethod.fromMap(existing.first);
      if (method.isSystem || method.isArchived) return false;
      method
        ..isArchived = true
        ..markAsChanged();
      await txn.update(
        'finance_payment_methods',
        _localValues(method.toMap()),
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      return true;
    });
    if (changed) _notifyChanged();
  }

  static Future<void> unarchivePaymentMethod(String uuid) async {
    await ensureReady();
    final db = await _database;
    final changed = await db.transaction<bool>((txn) async {
      final existing = await txn.query(
        'finance_payment_methods',
        where: 'uuid = ? AND is_deleted = 0',
        whereArgs: [uuid],
        limit: 1,
      );
      if (existing.isEmpty) return false;
      final method = FinancePaymentMethod.fromMap(existing.first);
      if (method.isSystem || !method.isArchived) return false;
      method
        ..isArchived = false
        ..markAsChanged();
      await txn.update(
        'finance_payment_methods',
        _localValues(method.toMap()),
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      return true;
    });
    if (changed) _notifyChanged();
  }

  static Future<List<FinanceBudget>> getBudgets({
    String? monthKey,
    bool includeDeleted = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) where.add('is_deleted = 0');
    if (monthKey != null && monthKey.isNotEmpty) {
      where.add('month_key = ?');
      args.add(monthKey);
    }
    final rows = await db.query(
      'finance_budgets',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy:
          'CASE WHEN category_uuid IS NULL AND payment_method_uuid IS NULL '
          'THEN 0 WHEN payment_method_uuid IS NULL THEN 1 ELSE 2 END, '
          'updated_at DESC',
    );
    return rows.map(FinanceBudget.fromMap).toList();
  }

  static Future<FinanceBudget?> getBudget(String uuid) async {
    await ensureReady();
    final db = await _database;
    final rows = await db.query(
      'finance_budgets',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : FinanceBudget.fromMap(rows.first);
  }

  static Future<void> saveBudget(
    FinanceBudget budget, {
    FinanceBudget? original,
    bool resetBalanceSnapshot = false,
    int? balanceSnapshotAt,
  }) async {
    if (!isSafeFinanceAmountMinor(budget.amountMinor) ||
        (!budget.isPaymentMethod && budget.amountMinor == 0)) {
      throw ArgumentError.value(
        budget.amountMinor,
        'amountMinor',
        budget.isPaymentMethod ? '余额不能为负数' : '预算金额必须大于 0',
      );
    }
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(budget.monthKey)) {
      throw ArgumentError.value(budget.monthKey, 'monthKey', '月份格式无效');
    }
    if (budget.categoryUuid != null && budget.paymentMethodUuid != null) {
      throw ArgumentError('预算只能对应一个分类或付款方式');
    }
    if (original != null && original.uuid != budget.uuid) {
      throw ArgumentError.value(original.uuid, 'original', '预算标识不匹配');
    }
    if (balanceSnapshotAt != null) {
      final snapshotTime = DateTime.fromMillisecondsSinceEpoch(
        balanceSnapshotAt,
      );
      if (!budget.isPaymentMethod ||
          balanceSnapshotAt <= 0 ||
          balanceSnapshotAt > DateTime.now().millisecondsSinceEpoch ||
          financeMonthKey(snapshotTime) != budget.monthKey) {
        throw ArgumentError.value(
          balanceSnapshotAt,
          'balanceSnapshotAt',
          '余额对应时间必须在所选月份内且不晚于现在',
        );
      }
    }
    await ensureReady();
    final db = await _database;
    await db.transaction((txn) async {
      if (!await _hasValidBudgetScope(txn, budget)) {
        throw ArgumentError.value(
          budget,
          'budget',
          '预算必须关联有效的支出分类或付款方式',
        );
      }
      final existingByUuid = await _findByUuid(
        txn,
        'finance_budgets',
        budget.uuid,
      );
      var current = existingByUuid == null
          ? null
          : FinanceBudget.fromMap(existingByUuid);
      if (current != null) {
        final changesDeletedState =
            original != null && budget.isDeleted != original.isDeleted;
        final baselineChanged = original != null &&
            (current.version != original.version ||
                current.updatedAt != original.updatedAt);
        if (baselineChanged) {
          _mergeBudgetEdits(current, original, budget);
          budget
            ..version = current.version
            ..updatedAt = current.updatedAt
            ..createdAt = current.createdAt
            ..deviceId = current.deviceId
            ..markAsChanged();
        } else if (original == null &&
            (current.version > budget.version ||
                current.updatedAt > budget.updatedAt)) {
          throw StateError('预算已更新，请重新加载后再保存');
        }
        if (current.isDeleted && !changesDeletedState) {
          throw StateError('预算已删除，请重新加载后再编辑');
        }
        budget
          ..createdAt = current.createdAt
          ..deviceId = current.deviceId;
      } else if (original != null) {
        throw StateError('预算已不存在，请重新加载后再保存');
      }
      if (budget.isPaymentMethod) {
        final sameBalance =
            current != null &&
            current.monthKey == budget.monthKey &&
            current.paymentMethodUuid == budget.paymentMethodUuid &&
            current.amountMinor == budget.amountMinor;
        budget.balanceSnapshotAt =
            balanceSnapshotAt ??
            (sameBalance && !resetBalanceSnapshot
                ? current.effectiveBalanceSnapshotAt
                : DateTime.now().millisecondsSinceEpoch);
      } else {
        budget.balanceSnapshotAt = null;
      }
      if (current != null &&
          (current.monthKey != budget.monthKey ||
              current.categoryUuid != budget.categoryUuid ||
              current.paymentMethodUuid != budget.paymentMethodUuid)) {
        current
          ..isDeleted = true
          ..markAsChanged();
        await txn.update(
          'finance_budgets',
          _localValues(current.toMap()),
          where: 'uuid = ?',
          whereArgs: [current.uuid],
        );

        final now = DateTime.now().millisecondsSinceEpoch;
        budget
          ..uuid = FinanceBudget.stableUuid(
            budget.monthKey,
            budget.categoryUuid,
            paymentMethodUuid: budget.paymentMethodUuid,
          )
          ..version = 1
          ..createdAt = now
          ..updatedAt = now > current.updatedAt ? now : current.updatedAt + 1;
        current = null;
      }
      if (current == null) {
        final stableUuid = FinanceBudget.stableUuid(
          budget.monthKey,
          budget.categoryUuid,
          paymentMethodUuid: budget.paymentMethodUuid,
        );
        budget.uuid = stableUuid;
        final stableExisting = await _findByUuid(
          txn,
          'finance_budgets',
          stableUuid,
        );
        if (stableExisting != null) {
          final previous = FinanceBudget.fromMap(stableExisting);
          if (!previous.isDeleted) {
            throw StateError('该月份的预算范围已经存在');
          }
          budget
            ..version = previous.version + 1
            ..createdAt = previous.createdAt
            ..updatedAt = previous.updatedAt >= budget.updatedAt
                ? previous.updatedAt + 1
                : budget.updatedAt;
        }
      }
      final where = <String>['month_key = ?', 'is_deleted = 0', 'uuid != ?'];
      final args = <Object?>[budget.monthKey, budget.uuid];
      if (budget.paymentMethodUuid != null) {
        where
          ..add('category_uuid IS NULL')
          ..add('payment_method_uuid = ?');
        args.add(budget.paymentMethodUuid);
      } else {
        where.add('payment_method_uuid IS NULL');
        if (budget.categoryUuid == null) {
          where.add('category_uuid IS NULL');
        } else {
          where.add('category_uuid = ?');
          args.add(budget.categoryUuid);
        }
      }
      final duplicates = await txn.query(
        'finance_budgets',
        columns: ['uuid'],
        where: where.join(' AND '),
        whereArgs: args,
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        throw StateError('该月份的预算范围已经存在');
      }
      budget.pendingSync = true;
      await txn.insert(
        'finance_budgets',
        _localValues(budget.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _notifyChanged();
  }

  static void _mergeBudgetEdits(
    FinanceBudget current,
    FinanceBudget original,
    FinanceBudget incoming,
  ) {
    if (incoming.monthKey == original.monthKey) {
      incoming.monthKey = current.monthKey;
    }
    if (incoming.categoryUuid == original.categoryUuid) {
      incoming.categoryUuid = current.categoryUuid;
    }
    if (incoming.paymentMethodUuid == original.paymentMethodUuid) {
      incoming.paymentMethodUuid = current.paymentMethodUuid;
    }
    if (incoming.amountMinor == original.amountMinor) {
      incoming.amountMinor = current.amountMinor;
    }
    if (incoming.currencyCode == original.currencyCode) {
      incoming.currencyCode = current.currencyCode;
    }
    if (incoming.note == original.note) incoming.note = current.note;
    if (incoming.isDeleted == original.isDeleted) {
      incoming.isDeleted = current.isDeleted;
    }
  }

  static Future<void> deleteBudget(String uuid) async {
    final budget = await getBudget(uuid);
    if (budget == null || budget.isDeleted) return;
    final original = FinanceBudget.fromMap(budget.toMap());
    budget.isDeleted = true;
    budget.markAsChanged();
    await saveBudget(budget, original: original);
  }

  static Future<void> restoreBudget(String uuid) async {
    final budget = await getBudget(uuid);
    if (budget == null || !budget.isDeleted) return;
    final original = FinanceBudget.fromMap(budget.toMap());
    budget.isDeleted = false;
    budget.markAsChanged();
    await saveBudget(budget, original: original);
  }

  static Future<List<FinanceRecurringRule>> getRecurringRules({
    bool includeDeleted = false,
    bool enabledOnly = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) where.add('is_deleted = 0');
    if (enabledOnly) where.add('is_enabled = 1');
    final rows = await db.query(
      'finance_recurring_rules',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'is_enabled DESC, updated_at DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(FinanceRecurringRule.fromMap).toList();
  }

  static Future<FinanceRecurringRule?> getRecurringRule(String uuid) async {
    await ensureReady();
    final db = await _database;
    final rows = await db.query(
      'finance_recurring_rules',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : FinanceRecurringRule.fromMap(rows.first);
  }

  static Future<void> saveRecurringRule(
    FinanceRecurringRule rule, {
    FinanceRecurringRule? original,
  }) async {
    _validateRecurringRule(rule);
    if (original != null && original.uuid != rule.uuid) {
      throw ArgumentError.value(original.uuid, 'original', '周期账单标识不匹配');
    }
    rule.pendingSync = true;
    await ensureReady();
    final db = await _database;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'finance_recurring_rules',
        where: 'uuid = ?',
        whereArgs: [rule.uuid],
        limit: 1,
      );
      var itemToSave = rule;
      if (existingRows.isNotEmpty) {
        final existing = FinanceRecurringRule.fromMap(existingRows.first);
        if (existing.isDeleted &&
            (original == null || rule.isDeleted == original.isDeleted)) {
          throw StateError('周期账单已删除，请重新加载后再编辑');
        }
        final baselineChanged = original != null &&
            (existing.version != original.version ||
                existing.updatedAt != original.updatedAt);
        if (baselineChanged) {
          itemToSave = _mergeRecurringRuleEdits(existing, original, rule);
          itemToSave.lastGeneratedPeriod = _editedRecurringGenerationPeriod(
            existing,
            itemToSave,
          );
          itemToSave.markAsChanged();
          _validateRecurringRule(itemToSave);
        } else {
          if (rule.version <= existing.version ||
              rule.updatedAt <= existing.updatedAt) {
            throw StateError('周期账单已更新，请重新加载后再保存');
          }
          itemToSave.lastGeneratedPeriod = _editedRecurringGenerationPeriod(
            existing,
            rule,
          );
        }
      } else {
        if (original != null) {
          throw StateError('周期账单已不存在，请重新加载后再保存');
        }
        itemToSave.lastGeneratedPeriod = rule.effectiveLastGeneratedPeriod;
      }
      await txn.insert(
        'finance_recurring_rules',
        _localValues(itemToSave.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _notifyChanged();
  }

  static Future<void> deleteRecurringRule(String uuid) async {
    final rule = await getRecurringRule(uuid);
    if (rule == null || rule.isDeleted) return;
    final original = FinanceRecurringRule.fromMap(rule.toMap());
    rule.isDeleted = true;
    rule.markAsChanged();
    await saveRecurringRule(rule, original: original);
  }

  static Future<void> restoreRecurringRule(String uuid) async {
    final rule = await getRecurringRule(uuid);
    if (rule == null || !rule.isDeleted) return;
    final original = FinanceRecurringRule.fromMap(rule.toMap());
    rule.isDeleted = false;
    rule.markAsChanged();
    await saveRecurringRule(rule, original: original);
  }

  static Future<void> setRecurringRuleEnabled(String uuid, bool enabled) async {
    final rule = await getRecurringRule(uuid);
    if (rule == null || rule.isDeleted || rule.isEnabled == enabled) return;
    final original = FinanceRecurringRule.fromMap(rule.toMap());
    rule.isEnabled = enabled;
    rule.markAsChanged();
    await saveRecurringRule(rule, original: original);
  }

  static Future<bool> materializeRecurringRule(
    FinanceRecurringRule rule, {
    required DateTime dueAt,
    required String periodKey,
  }) async {
    if (periodKey.trim().isEmpty) return false;
    await ensureReady();
    final db = await _database;
    var repairedGenerationMarker = false;
    final generated = await db.transaction<bool>((txn) async {
      final rows = await txn.query(
        'finance_recurring_rules',
        where: 'uuid = ?',
        whereArgs: [rule.uuid],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final current = FinanceRecurringRule.fromMap(rows.first);
      current.lastGeneratedPeriod = current.effectiveLastGeneratedPeriod;
      final expectedDueAt = current.dueDateFor(dueAt.year, dueAt.month);
      final expectedPeriod = current.frequency == FinanceRecurringFrequency.yearly
          ? '${dueAt.year}'
          : financeMonthKey(dueAt);
      if (current.isDeleted ||
          !current.isEnabled ||
          !current.autoGenerate ||
          current.frequency != rule.frequency ||
          expectedDueAt == null ||
          !expectedDueAt.isAtSameMomentAs(dueAt) ||
          periodKey != expectedPeriod ||
          (current.lastGeneratedPeriod != null &&
              _generatedPeriodOrder(current.lastGeneratedPeriod!) >=
                  _generatedPeriodOrder(periodKey))) {
        return false;
      }

      final stableTransactionUuid = _recurringTransactionUuid(
        current.uuid,
        periodKey,
      );
      final existingStableTransaction = await txn.query(
        'finance_transactions',
        columns: ['uuid'],
        where: 'uuid = ?',
        whereArgs: [stableTransactionUuid],
        limit: 1,
      );
      if (existingStableTransaction.isNotEmpty) {
        // 新版本使用确定性交易 UUID。即使规则标记曾被旧快照清空，
        // 同一规则和周期也只会命中这一笔账单。
        current.lastGeneratedPeriod = _latestGeneratedPeriod(
          current.lastGeneratedPeriod,
          periodKey,
        );
        current.markAsChanged();
        repairedGenerationMarker = true;
        await txn.update(
          'finance_recurring_rules',
          _localValues(current.toMap()),
          where: 'uuid = ?',
          whereArgs: [current.uuid],
        );
        return false;
      }

      final detail = <String>[
        if (current.note?.trim().isNotEmpty == true) current.note!.trim(),
        '自动生成 · ${current.name}',
      ].join(' · ');
      final transaction = FinanceTransaction(
        uuid: stableTransactionUuid,
        type: current.type,
        amountMinor: current.amountMinor,
        currencyCode: current.currencyCode,
        categoryUuid: current.categoryUuid,
        paymentMethodUuid: current.paymentMethodUuid,
        transactionDate: dateKey(dueAt),
        occurredAt: dueAt.millisecondsSinceEpoch,
        timezoneOffsetMinutes: dueAt.timeZoneOffset.inMinutes,
        merchant: current.merchant?.trim().isNotEmpty == true
            ? current.merchant!.trim()
            : current.name,
        note: detail,
        source: FinanceEntrySource.automation,
        deviceId: current.deviceId,
      );
      await txn.insert(
        'finance_transactions',
        _localValues(transaction.toMap()),
      );

      current.lastGeneratedPeriod = _latestGeneratedPeriod(
        current.lastGeneratedPeriod,
        periodKey,
      );
      current.markAsChanged();
      await txn.update(
        'finance_recurring_rules',
        _localValues(current.toMap()),
        where: 'uuid = ?',
        whereArgs: [current.uuid],
      );
      return true;
    });
    if (generated || repairedGenerationMarker) _notifyChanged();
    return generated;
  }

  static String _recurringTransactionUuid(String ruleUuid, String periodKey) {
    return const Uuid().v5(
      '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
      'countdown-todo/finance-recurring/v1/$ruleUuid/$periodKey',
    );
  }

  static String? _latestGeneratedPeriod(String? current, String? incoming) {
    if (current == null || incoming == null) return current ?? incoming;
    return _generatedPeriodOrder(incoming) >= _generatedPeriodOrder(current)
        ? incoming
        : current;
  }

  static String? _mergeRecurringGenerationPeriod(
    FinanceRecurringRule current,
    FinanceRecurringRule incoming,
  ) {
    if (current.frequency != incoming.frequency) {
      return incoming.effectiveLastGeneratedPeriod ??
          incoming.generationPeriodBefore(
            DateTime.fromMillisecondsSinceEpoch(incoming.updatedAt),
          );
    }
    // Generation progress cannot be rolled back by a stale edit or backup.
    return _latestGeneratedPeriod(
      current.effectiveLastGeneratedPeriod,
      incoming.effectiveLastGeneratedPeriod,
    );
  }

  static String? _editedRecurringGenerationPeriod(
    FinanceRecurringRule current,
    FinanceRecurringRule incoming,
  ) {
    if (current.frequency != incoming.frequency ||
        current.isEnabled != incoming.isEnabled ||
        current.autoGenerate != incoming.autoGenerate ||
        current.isDeleted != incoming.isDeleted) {
      return incoming.generationPeriodBefore(DateTime.now());
    }
    return _mergeRecurringGenerationPeriod(current, incoming);
  }

  static FinanceRecurringRule _mergeRecurringRuleEdits(
    FinanceRecurringRule current,
    FinanceRecurringRule original,
    FinanceRecurringRule incoming,
  ) {
    final merged = FinanceRecurringRule.fromMap(current.toMap());
    if (incoming.name != original.name) merged.name = incoming.name;
    if (incoming.type != original.type) merged.type = incoming.type;
    if (incoming.amountMinor != original.amountMinor) {
      merged.amountMinor = incoming.amountMinor;
    }
    if (incoming.currencyCode != original.currencyCode) {
      merged.currencyCode = incoming.currencyCode;
    }
    if (incoming.categoryUuid != original.categoryUuid) {
      merged.categoryUuid = incoming.categoryUuid;
    }
    if (incoming.paymentMethodUuid != original.paymentMethodUuid) {
      merged.paymentMethodUuid = incoming.paymentMethodUuid;
    }
    if (incoming.merchant != original.merchant) {
      merged.merchant = incoming.merchant;
    }
    if (incoming.note != original.note) merged.note = incoming.note;
    if (incoming.frequency != original.frequency) {
      merged.frequency = incoming.frequency;
    }
    if (incoming.dayOfMonth != original.dayOfMonth) {
      merged.dayOfMonth = incoming.dayOfMonth;
    }
    if (incoming.monthOfYear != original.monthOfYear) {
      merged.monthOfYear = incoming.monthOfYear;
    }
    if (incoming.startDate != original.startDate) {
      merged.startDate = incoming.startDate;
    }
    if (incoming.endDate != original.endDate) {
      merged.endDate = incoming.endDate;
    }
    if (incoming.reminderMinutes != original.reminderMinutes) {
      merged.reminderMinutes = incoming.reminderMinutes;
    }
    if (incoming.autoGenerate != original.autoGenerate) {
      merged.autoGenerate = incoming.autoGenerate;
    }
    if (incoming.isEnabled != original.isEnabled) {
      merged.isEnabled = incoming.isEnabled;
    }
    if (incoming.isDeleted != original.isDeleted) {
      merged.isDeleted = incoming.isDeleted;
    }
    return merged;
  }

  static FinanceEntryTemplate _mergeTemplateEdits(
    FinanceEntryTemplate current,
    FinanceEntryTemplate original,
    FinanceEntryTemplate incoming,
  ) {
    final merged = FinanceEntryTemplate.fromMap(current.toMap());
    if (incoming.name != original.name) merged.name = incoming.name;
    if (incoming.type != original.type) merged.type = incoming.type;
    if (incoming.amountMinor != original.amountMinor) {
      merged.amountMinor = incoming.amountMinor;
    }
    if (incoming.currencyCode != original.currencyCode) {
      merged.currencyCode = incoming.currencyCode;
    }
    if (incoming.categoryUuid != original.categoryUuid) {
      merged.categoryUuid = incoming.categoryUuid;
    }
    if (incoming.paymentMethodUuid != original.paymentMethodUuid) {
      merged.paymentMethodUuid = incoming.paymentMethodUuid;
    }
    if (incoming.merchant != original.merchant) {
      merged.merchant = incoming.merchant;
    }
    if (incoming.note != original.note) merged.note = incoming.note;
    if (incoming.isDeleted != original.isDeleted) {
      merged.isDeleted = incoming.isDeleted;
    }
    if (incoming.useCount != original.useCount) {
      merged.useCount =
          (current.useCount + incoming.useCount - original.useCount)
              .clamp(0, 0x7fffffff)
              .toInt();
    }
    if (incoming.lastUsedAt != null &&
        (current.lastUsedAt == null ||
            incoming.lastUsedAt! > current.lastUsedAt!)) {
      merged.lastUsedAt = incoming.lastUsedAt;
    }
    return merged;
  }

  static int _generatedPeriodOrder(String value) {
    final parts = value.split('-');
    final year = int.tryParse(parts.first) ?? -1;
    final month = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return year * 100 + month;
  }

  static Future<List<FinanceEntryTemplate>> getTemplates({
    bool includeDeleted = false,
  }) async {
    await ensureReady();
    final db = await _database;
    final rows = await db.query(
      'finance_entry_templates',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy:
          'use_count DESC, last_used_at DESC, updated_at DESC, '
          'name COLLATE NOCASE ASC',
    );
    return rows.map(FinanceEntryTemplate.fromMap).toList();
  }

  static Future<FinanceEntryTemplate?> getTemplate(String uuid) async {
    await ensureReady();
    final db = await _database;
    final rows = await db.query(
      'finance_entry_templates',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : FinanceEntryTemplate.fromMap(rows.first);
  }

  static Future<void> saveTemplate(
    FinanceEntryTemplate template, {
    FinanceEntryTemplate? original,
  }) async {
    _validateTemplate(template);
    if (original != null && original.uuid != template.uuid) {
      throw ArgumentError.value(original.uuid, 'original', '模板标识不匹配');
    }
    await ensureReady();
    final db = await _database;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'finance_entry_templates',
        where: 'uuid = ?',
        whereArgs: [template.uuid],
        limit: 1,
      );
      var itemToSave = FinanceEntryTemplate.fromMap(template.toMap());
      if (existingRows.isNotEmpty) {
        final existing = FinanceEntryTemplate.fromMap(existingRows.first);
        if (existing.isDeleted &&
            (original == null || itemToSave.isDeleted == original.isDeleted)) {
          throw StateError('快捷模板已删除，请重新加载后再编辑');
        }
        final baselineChanged =
            original != null &&
            (existing.version != original.version ||
                existing.updatedAt != original.updatedAt);
        if (baselineChanged) {
          itemToSave = _mergeTemplateEdits(existing, original, itemToSave);
          itemToSave.markAsChanged();
          _validateTemplate(itemToSave);
        } else if (itemToSave.version <= existing.version ||
            itemToSave.updatedAt <= existing.updatedAt) {
          throw StateError('快捷模板已更新，请重新加载后再保存');
        }
      } else if (original != null) {
        throw StateError('快捷模板已不存在，请重新加载后再保存');
      }
      itemToSave.pendingSync = true;
      await txn.insert(
        'finance_entry_templates',
        _localValues(itemToSave.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _notifyChanged();
  }

  static Future<void> deleteTemplate(String uuid) async {
    final template = await getTemplate(uuid);
    if (template == null || template.isDeleted) return;
    final original = FinanceEntryTemplate.fromMap(template.toMap());
    template.isDeleted = true;
    template.markAsChanged();
    await saveTemplate(template, original: original);
  }

  static Future<void> restoreTemplate(String uuid) async {
    final template = await getTemplate(uuid);
    if (template == null || !template.isDeleted) return;
    final original = FinanceEntryTemplate.fromMap(template.toMap());
    template.isDeleted = false;
    template.markAsChanged();
    await saveTemplate(template, original: original);
  }

  static Future<void> markTemplateUsed(String uuid) async {
    final template = await getTemplate(uuid);
    if (template == null || template.isDeleted) return;
    final original = FinanceEntryTemplate.fromMap(template.toMap());
    template.useCount++;
    template.lastUsedAt = DateTime.now().millisecondsSinceEpoch;
    template.markAsChanged();
    await saveTemplate(template, original: original);
  }

  static void _validateRecurringRule(FinanceRecurringRule rule) {
    if (rule.name.trim().isEmpty) {
      throw ArgumentError.value(rule.name, 'name', '周期账单名称不能为空');
    }
    if (rule.type == FinanceTransactionType.refund) {
      throw ArgumentError.value(rule.type, 'type', '周期规则不支持退款类型');
    }
    if (!isSafeFinanceAmountMinor(rule.amountMinor) || rule.amountMinor == 0) {
      throw ArgumentError.value(rule.amountMinor, 'amountMinor', '金额必须大于 0');
    }
    if (!_isDateKey(rule.startDate)) {
      throw ArgumentError.value(rule.startDate, 'startDate', '开始日期格式无效');
    }
    if (rule.endDate != null && !_isDateKey(rule.endDate!)) {
      throw ArgumentError.value(rule.endDate, 'endDate', '结束日期格式无效');
    }
    if (rule.endDate != null &&
        dateFromKey(rule.endDate!).isBefore(dateFromKey(rule.startDate))) {
      throw ArgumentError.value(rule.endDate, 'endDate', '结束日期不能早于开始日期');
    }
    if (rule.dayOfMonth < 1 || rule.dayOfMonth > 31) {
      throw ArgumentError.value(
        rule.dayOfMonth,
        'dayOfMonth',
        '日期必须在 1 到 31 之间',
      );
    }
    if (rule.frequency == FinanceRecurringFrequency.yearly &&
        (rule.monthOfYear < 1 || rule.monthOfYear > 12)) {
      throw ArgumentError.value(
        rule.monthOfYear,
        'monthOfYear',
        '月份必须在 1 到 12 之间',
      );
    }
    if (rule.reminderMinutes < 0 || rule.reminderMinutes > 10080) {
      throw ArgumentError.value(
        rule.reminderMinutes,
        'reminderMinutes',
        '提醒提前时间必须在 0 到 7 天之间',
      );
    }
  }

  static void _validateTemplate(FinanceEntryTemplate template) {
    if (template.name.trim().isEmpty) {
      throw ArgumentError.value(template.name, 'name', '模板名称不能为空');
    }
    if (template.type == FinanceTransactionType.refund) {
      throw ArgumentError.value(template.type, 'type', '模板不支持退款类型');
    }
    if (!isSafeFinanceAmountMinor(template.amountMinor) ||
        template.amountMinor == 0) {
      throw ArgumentError.value(
        template.amountMinor,
        'amountMinor',
        '金额必须大于 0',
      );
    }
    if (template.useCount < 0 || template.useCount > _maxTemplateUseCount) {
      throw ArgumentError.value(
        template.useCount,
        'useCount',
        '使用次数必须在 0 到 $_maxTemplateUseCount 之间',
      );
    }
  }

  static bool _isDateKey(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed != null && dateKey(parsed) == value;
  }

  static Future<FinanceSummary> getSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    final transactions = await getTransactions(from: from, to: to);
    return FinanceSummary.fromTransactions(transactions);
  }

  static Future<Map<String, dynamic>> getExportBundle() async {
    await ensureReady();
    final transactions = await getTransactions(includeDeleted: true);
    final categories = await getCategories(
      includeArchived: true,
      includeDeleted: true,
    );
    final paymentMethods = await getPaymentMethods(
      includeArchived: true,
      includeDeleted: true,
    );
    final budgets = await getBudgets(includeDeleted: true);
    final recurringRules = await getRecurringRules(includeDeleted: true);
    final templates = await getTemplates(includeDeleted: true);
    final db = await _database;
    final loanRows = await db.query('finance_loans');
    final loanInstallmentRows = await db.query('finance_loan_installments');
    return {
      'transactions': transactions.map((item) => item.toJson()).toList(),
      'categories': categories.map((item) => item.toJson()).toList(),
      'payment_methods': paymentMethods.map((item) => item.toJson()).toList(),
      'budgets': budgets.map((item) => item.toJson()).toList(),
      'recurring_rules': recurringRules.map((item) => item.toJson()).toList(),
      'templates': templates.map((item) => item.toJson()).toList(),
      'loans': loanRows
          .map(FinanceLoan.fromMap)
          .map((item) => item.toJson())
          .toList(),
      'loan_installments': loanInstallmentRows
          .map(FinanceLoanInstallment.fromMap)
          .map((item) => item.toJson())
          .toList(),
    };
  }

  static void removeDeviceIdsFromExportBundle(Map<String, dynamic> bundle) {
    for (final key in [
      'transactions',
      'categories',
      'payment_methods',
      'budgets',
      'recurring_rules',
      'templates',
      'loans',
      'loan_installments',
    ]) {
      final items = bundle[key];
      if (items is! List) continue;
      for (final item in items) {
        if (item is Map<String, dynamic>) item['device_id'] = null;
      }
    }
  }

  /// 导入 JSON 备份中的记账数据。所有记录仍然写入当前用户的本地库，
  /// 不携带团队归属，也不会写入同步操作日志。
  static Future<Map<String, int>> importBundle(
    Map<String, dynamic> bundle, {
    String Function(String value)? remapUuid,
  }) async {
    await ensureReady();
    final database = await _database;
    final result = await database.transaction(
      (txn) => _importBundleInTransaction(txn, bundle, remapUuid: remapUuid),
    );
    if ((result['imported'] ?? 0) > 0 || (result['updated'] ?? 0) > 0) {
      _notifyChanged();
    }
    return result;
  }

  static Future<Map<String, int>> _importBundleInTransaction(
    DatabaseExecutor db,
    Map<String, dynamic> bundle, {
    String Function(String value)? remapUuid,
  }) async {
    final remap = remapUuid ?? (value) => value;
    var imported = 0;
    var skipped = 0;
    var updated = 0;

    final categoryCandidates = <String, FinanceCategory>{};
    final categoryInput = _importListOfMaps(bundle, 'categories');
    skipped += categoryInput.invalidCount;
    final categoryMaps = categoryInput.maps;
    for (final map in categoryMaps) {
      if (!_hasRawFinanceUuid(map) ||
          !_hasValidRawCategoryType(map) ||
          !_hasValidRawFinanceName(map)) {
        skipped++;
        continue;
      }
      final item = FinanceCategory.fromMap(map);
      final oldUuid = item.uuid;
      if (_isSystemUuid(oldUuid)) {
        // Built-in category identity remains local and trusted. A backup can
        // restore explicit name and icon overrides, but cannot change its
        // type or hierarchy (or create a new system category).
        if (!_isSystemCategoryUuid(oldUuid)) {
          skipped++;
          continue;
        }
        final existing = await _findByUuid(db, 'finance_categories', oldUuid);
        if (existing == null ||
            (!item.iconCustomized && !item.nameCustomized)) {
          skipped++;
          continue;
        }
        final current = FinanceCategory.fromMap(existing);
        final hasIconChange = item.iconCustomized && current.icon != item.icon;
        final hasNameChange = item.nameCustomized && current.name != item.name;
        if (!hasIconChange && !hasNameChange) {
          skipped++;
          continue;
        }
        if (hasIconChange) {
          current
            ..icon = item.icon
            ..iconCustomized = true;
        }
        if (hasNameChange) {
          current
            ..name = item.name
            ..nameCustomized = true;
        }
        current.markAsChanged();
        await db.update(
          'finance_categories',
          _localValues(current.toMap()),
          where: 'uuid = ?',
          whereArgs: [oldUuid],
        );
        updated++;
        continue;
      }
      if (item.isSystem) {
        skipped++;
        continue;
      }
      item.uuid = remap(oldUuid);
      item.parentUuid = _normalizeCategoryParentUuid(
        _remapNullable(item.parentUuid, remap),
      );
      if (_isSystemUuid(item.uuid)) {
        skipped++;
        continue;
      }
      final existing = await _findByUuid(db, 'finance_categories', item.uuid);
      if (existing != null &&
          item.updatedAt <= FinanceCategory.fromMap(existing).updatedAt) {
        skipped++;
        continue;
      }
      final previous = categoryCandidates[item.uuid];
      if (previous != null && item.updatedAt <= previous.updatedAt) {
        skipped++;
        continue;
      }
      if (previous != null) skipped++;
      categoryCandidates[item.uuid] = item;
    }

    final invalidCategoryUuids = await _invalidCategoryHierarchyUuids(
      db,
      categoryCandidates.values,
    );
    for (final item in categoryCandidates.values) {
      if (invalidCategoryUuids.contains(item.uuid)) {
        skipped++;
        continue;
      }
      final existing = await _findByUuid(db, 'finance_categories', item.uuid);
      if (existing == null) {
        await db.insert('finance_categories', _localValues(item.toMap()));
        imported++;
      } else {
        await db.update(
          'finance_categories',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      }
    }

    final paymentInput = _importListOfMaps(bundle, 'payment_methods');
    skipped += paymentInput.invalidCount;
    final paymentMaps = paymentInput.maps;
    for (final map in paymentMaps) {
      if (!_hasRawFinanceUuid(map) || !_hasValidRawFinanceName(map)) {
        skipped++;
        continue;
      }
      final item = FinancePaymentMethod.fromMap(map);
      if (item.isSystem || _isSystemUuid(item.uuid)) {
        skipped++;
        continue;
      }
      if (!item.isSystem) item.uuid = remap(item.uuid);
      if (item.isSystem) {
        item.isArchived = false;
        item.isDeleted = false;
      }
      final existing = await _findByUuid(
        db,
        'finance_payment_methods',
        item.uuid,
      );
      if (existing == null) {
        await db.insert(
          'finance_payment_methods',
          item.isSystem
              ? _remoteValues(item.toMap())
              : _localValues(item.toMap()),
        );
        imported++;
      } else if (item.updatedAt >
          FinancePaymentMethod.fromMap(existing).updatedAt) {
        await db.update(
          'finance_payment_methods',
          item.isSystem
              ? _remoteValues(item.toMap())
              : _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      } else {
        skipped++;
      }
    }

    final recurringRuleInput = _importListOfMaps(bundle, 'recurring_rules');
    skipped += recurringRuleInput.invalidCount;
    final recurringRuleMaps = recurringRuleInput.maps;
    for (final map in recurringRuleMaps) {
      if (!_hasRawFinanceUuid(map) ||
          !_hasSafeRawFinanceAmount(map, 'amount_minor', 'amountMinor') ||
          !_hasValidRawFinanceName(map) ||
          !_hasValidRawOptionalTransactionType(map) ||
          !_hasValidRawRecurringFrequency(map) ||
          !_hasValidRawRecurringScheduleFields(map) ||
          !_hasValidRawFinanceDateKey(map, 'start_date', 'startDate') ||
          !_hasSafeRawFinanceTimestamps(map)) {
        skipped++;
        continue;
      }
      final item = FinanceRecurringRule.fromMap(map);
      item.uuid = remap(item.uuid);
      item.categoryUuid = _remapNullable(item.categoryUuid, remap);
      item.paymentMethodUuid = _remapNullable(item.paymentMethodUuid, remap);
      if (item.type == FinanceTransactionType.refund || item.amountMinor <= 0) {
        skipped++;
        continue;
      }
      try {
        _validateRecurringRule(item);
      } catch (_) {
        skipped++;
        continue;
      }
      final existing = await _findByUuid(
        db,
        'finance_recurring_rules',
        item.uuid,
      );
      if (existing == null) {
        item.lastGeneratedPeriod = item.effectiveLastGeneratedPeriod;
        await db.insert('finance_recurring_rules', _localValues(item.toMap()));
        imported++;
      } else if (item.updatedAt >
          FinanceRecurringRule.fromMap(existing).updatedAt) {
        item.lastGeneratedPeriod = _mergeRecurringGenerationPeriod(
          FinanceRecurringRule.fromMap(existing),
          item,
        );
        await db.update(
          'finance_recurring_rules',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      } else {
        skipped++;
      }
    }

    final templateInput = _importListOfMaps(bundle, 'templates');
    skipped += templateInput.invalidCount;
    final templateMaps = templateInput.maps;
    for (final map in templateMaps) {
      if (!_hasRawFinanceUuid(map) ||
          !_hasSafeRawFinanceAmount(map, 'amount_minor', 'amountMinor') ||
          !_hasValidRawFinanceName(map) ||
          !_hasSafeRawTemplateUseCount(map) ||
          !_hasValidRawOptionalTransactionType(map)) {
        skipped++;
        continue;
      }
      final item = FinanceEntryTemplate.fromMap(map);
      item.uuid = remap(item.uuid);
      item.categoryUuid = _remapNullable(item.categoryUuid, remap);
      item.paymentMethodUuid = _remapNullable(item.paymentMethodUuid, remap);
      if (item.type == FinanceTransactionType.refund || item.amountMinor <= 0) {
        skipped++;
        continue;
      }
      try {
        _validateTemplate(item);
      } catch (_) {
        skipped++;
        continue;
      }
      final existing = await _findByUuid(
        db,
        'finance_entry_templates',
        item.uuid,
      );
      if (existing == null) {
        await db.insert('finance_entry_templates', _localValues(item.toMap()));
        imported++;
      } else if (item.updatedAt >
          FinanceEntryTemplate.fromMap(existing).updatedAt) {
        await db.update(
          'finance_entry_templates',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      } else {
        skipped++;
      }
    }

    final transactionInput = _importListOfMaps(bundle, 'transactions');
    skipped += transactionInput.invalidCount;
    final transactionMaps = transactionInput.maps
      ..sort((left, right) {
        return _transactionMergePriority(FinanceTransaction.fromMap(left))
            .compareTo(
              _transactionMergePriority(FinanceTransaction.fromMap(right)),
            );
      });
    final changedOriginalUuids = <String>{};
    var pendingTransactions = <FinanceTransaction>[];
    for (final map in transactionMaps) {
      final item = FinanceTransaction.fromMap(map);
      item.uuid = remap(item.uuid);
      item.categoryUuid = _remapNullable(item.categoryUuid, remap);
      item.paymentMethodUuid = _remapNullable(item.paymentMethodUuid, remap);
      item.relatedTransactionUuid = _remapNullable(
        item.relatedTransactionUuid,
        remap,
      );
      item.relatedTodoUuid = _remapNullable(item.relatedTodoUuid, remap);
      item.relatedPlanBlockUuid = _remapNullable(
        item.relatedPlanBlockUuid,
        remap,
      );
      item.installmentGroupUuid = _remapNullable(
        item.installmentGroupUuid,
        remap,
      );
      item.source = FinanceEntrySource.import;
      if (!_isValidImportedTransaction(map, item)) {
        skipped++;
        continue;
      }
      pendingTransactions.add(item);
    }
    final duplicateInstallmentKeys = _duplicateInstallmentIndexKeys(
      pendingTransactions,
    );
    final skippedDuplicateInstallments = pendingTransactions.where((item) {
      final key = _installmentIndexKey(item);
      return !item.isDeleted &&
          key != null &&
          duplicateInstallmentKeys.contains(key);
    }).length;
    skipped += skippedDuplicateInstallments;
    pendingTransactions.removeWhere((item) {
      final key = _installmentIndexKey(item);
      return !item.isDeleted &&
          key != null &&
          duplicateInstallmentKeys.contains(key);
    });
    while (pendingTransactions.isNotEmpty) {
      final deferred = <FinanceTransaction>[];
      var applied = 0;
      for (final item in pendingTransactions) {
        if (await _hasInstallmentIndexConflict(db, item)) {
          skipped++;
          continue;
        }
        final existing = await _findByUuid(db, 'finance_transactions', item.uuid);
        if (existing != null &&
            item.updatedAt <= FinanceTransaction.fromMap(existing).updatedAt) {
          skipped++;
          continue;
        }
        try {
          await _validateTransactionRefundState(db, item, alignCategory: false);
        } on StateError {
          deferred.add(item);
          continue;
        }
        if (existing == null) {
          await db.insert('finance_transactions', _localValues(item.toMap()));
          imported++;
        } else {
          await db.update(
            'finance_transactions',
            _localValues(item.toMap()),
            where: 'uuid = ?',
            whereArgs: [item.uuid],
          );
          updated++;
        }
        applied++;
        changedOriginalUuids.add(item.uuid);
        if (item.type == FinanceTransactionType.refund &&
            item.relatedTransactionUuid != null) {
          changedOriginalUuids.add(item.relatedTransactionUuid!);
        }
      }
      // A refund decrease/deletion can unblock an earlier expense decrease or
      // another refund increase. Retry only while this batch makes progress.
      if (applied == 0) {
        skipped += deferred.length;
        break;
      }
      pendingTransactions = deferred;
    }
    final repairedRefunds = <String>{};
    await _alignLinkedRefunds(
      db,
      originalUuids: changedOriginalUuids,
      repairedUuids: repairedRefunds,
    );
    updated += repairedRefunds
        .where((uuid) => !changedOriginalUuids.contains(uuid))
        .length;

    final importedBudgets = <FinanceBudget>[];
    final budgetInput = _importListOfMaps(bundle, 'budgets');
    skipped += budgetInput.invalidCount;
    for (final map in budgetInput.maps) {
      if (!_hasRawFinanceUuid(map) ||
          !_isSafeRawFinanceAmount(map['amount_minor'] ?? map['amountMinor']) ||
          !_hasValidRawFinanceMonthKey(map) ||
          !_hasValidRawBalanceSnapshot(map)) {
        skipped++;
        continue;
      }
      final item = FinanceBudget.fromMap(map);
      item.uuid = remap(item.uuid);
      item.categoryUuid = _remapNullable(item.categoryUuid, remap);
      item.paymentMethodUuid = _remapNullable(item.paymentMethodUuid, remap);
      if (!_isValidBudget(item) || !await _hasValidBudgetScope(db, item)) {
        skipped++;
        continue;
      }
      importedBudgets.add(item);
    }
    final budgets = _latestBudgetsByScope(importedBudgets);
    skipped += importedBudgets.length - budgets.length;
    for (final item in budgets) {
      final existing = await _findByUuid(db, 'finance_budgets', item.uuid);
      if (existing != null) {
        final current = FinanceBudget.fromMap(existing);
        if (_budgetScopeKey(current) != _budgetScopeKey(item) &&
            !_isIncomingBudgetWinner(item, current)) {
          skipped++;
          continue;
        }
      }
      final scopeRows = await _findAllBudgetsByScope(db, item);
      final current = scopeRows.isEmpty
          ? null
          : _latestBudgetsByScope(
              scopeRows.map(FinanceBudget.fromMap).toList(),
            ).single;
      if (current != null && !_isIncomingBudgetWinner(item, current)) {
        // Repair duplicates left by older importers without overwriting the
        // newest local value with a stale backup.
        if (scopeRows.length > 1) {
          await _deleteOtherBudgetsInScope(db, current);
          updated++;
        }
        skipped++;
        continue;
      }
      await _deleteOtherBudgetsInScope(db, item);
      await db.insert(
        'finance_budgets',
        _localValues(item.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (existing == null && scopeRows.isEmpty) {
        imported++;
      } else {
        updated++;
      }
    }

    final loanInput = _importListOfMaps(bundle, 'loans');
    skipped += loanInput.invalidCount;
    final loanMaps = loanInput.maps;
    for (final map in loanMaps) {
      if (!_hasRawFinanceUuid(map) ||
          !_hasSafeRawFinanceAmount(
            map,
            'principal_minor',
            'principalMinor',
          ) ||
          !_hasSafeRawLoanInterestRate(map) ||
          !_hasValidRawLoanRepaymentMethod(map) ||
          !_hasValidRawFinanceName(map) ||
          !_hasValidRawFinanceDateKey(map, 'start_date', 'startDate') ||
          !_hasSafeRawIntegerRange(
            map,
            'term_months',
            'termMonths',
            FinanceLoanCalculator.minTermMonths,
            FinanceLoanCalculator.maxTermMonths,
          ) ||
          !_hasSafeRawIntegerRange(map, 'repayment_day', 'repaymentDay', 1, 31)) {
        skipped++;
        continue;
      }
      final item = FinanceLoan.fromMap(map);
      item.uuid = remap(item.uuid);
      if (!_isValidLoan(item)) {
        skipped++;
        continue;
      }
      final existing = await _findByUuid(db, 'finance_loans', item.uuid);
      if (existing == null) {
        await db.insert('finance_loans', _localValues(item.toMap()));
        imported++;
      } else {
        final current = FinanceLoan.fromMap(existing);
        if (item.updatedAt <= current.updatedAt) {
          skipped++;
          continue;
        }
        if (_loanTermsDiffer(current, item) &&
            await _hasPaidLoanInstallments(db, item.uuid)) {
          skipped++;
          continue;
        }
        await db.update(
          'finance_loans',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      }
    }

    final loanInstallmentInput = _importListOfMaps(
      bundle,
      'loan_installments',
    );
    skipped += loanInstallmentInput.invalidCount;
    final loanInstallmentMaps = loanInstallmentInput.maps
      ..sort(_compareRawLoanInstallmentMaps);
    final seenActiveLoanInstallments = <String>{};
    final loanScheduleCache =
        <String, List<FinanceLoanScheduleAllocation>>{};
    for (final map in loanInstallmentMaps) {
      if (!_hasRawFinanceUuid(map) ||
          !_hasSafeRawLoanInstallmentAmounts(map) ||
          !_hasValidRawLoanInstallmentScheduleFields(map) ||
          !_hasSafeRawFinanceTimestamps(map)) {
        skipped++;
        continue;
      }
      final item = FinanceLoanInstallment.fromMap(map);
      item.uuid = remap(item.uuid);
      item.loanUuid = remap(item.loanUuid);
      item.interestTransactionUuid = _remapNullable(
        item.interestTransactionUuid,
        remap,
      );
      item.paymentMethodUuid = _remapNullable(
        item.paymentMethodUuid,
        remap,
      );
      if (!_isValidLoanInstallment(item)) {
        skipped++;
        continue;
      }
      final parentLoan = await _findByUuid(db, 'finance_loans', item.loanUuid);
      final loan = parentLoan == null
          ? null
          : FinanceLoan.fromMap(parentLoan);
      if (loan == null ||
          (loan.isDeleted && !item.isDeleted) ||
          (!item.isDeleted &&
              !_matchesLoanInstallmentSchedule(
                loan,
                item,
                loanScheduleCache,
              ))) {
        skipped++;
        continue;
      }
      final scheduleKey = '${item.loanUuid}\u0000${item.installmentIndex}';
      if (!item.isDeleted && !seenActiveLoanInstallments.add(scheduleKey)) {
        skipped++;
        continue;
      }
      if (!item.isDeleted) {
        final duplicateSchedules = await db.query(
          'finance_loan_installments',
          columns: ['uuid'],
          where:
              'loan_uuid = ? AND installment_index = ? AND is_deleted = 0',
          whereArgs: [item.loanUuid, item.installmentIndex],
        );
        if (duplicateSchedules.any((row) => row['uuid'] != item.uuid)) {
          skipped++;
          continue;
        }
      }
      final existing = await _findByUuid(
        db,
        'finance_loan_installments',
        item.uuid,
      );
      if (existing == null) {
        await db.insert(
          'finance_loan_installments',
          _localValues(item.toMap()),
        );
        imported++;
      } else {
        final current = FinanceLoanInstallment.fromMap(existing);
        if (item.updatedAt <= current.updatedAt ||
            (current.isPaid && !_sameLoanInstallmentSchedule(current, item))) {
          skipped++;
          continue;
        }
        await db.update(
          'finance_loan_installments',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      }
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  /// 将服务端返回的个人记账快照按 updated_at/version 合并到本地。
  ///
  /// 记账没有通用 op_logs，因此同步源必须使用一笔 SQLite 事务完成整批
  /// upsert。系统分类的类型/层级仍由客户端内置定义，用户自定义名称和
  /// 图标则作为个人覆盖项接受云端合并；系统付款方式仍保持本地默认。
  static Future<int> mergeRemoteBundle(
    Map<String, dynamic> bundle, {
    Set<String> forceRemoteKeys = const {},
    Set<String>? deferredTransactionUuids,
    Set<String>? changedSections,
  }) async {
    await ensureReady();
    final categories = _listOfMaps(bundle['categories'])
        .where(_hasRawFinanceUuid)
        .where(_hasValidRawFinanceName)
        .where(_hasValidRawCategoryType)
        .map((map) {
          final item = FinanceCategory.fromMap(map);
          item.parentUuid = _normalizeCategoryParentUuid(item.parentUuid);
          return item;
        })
        .where((item) {
          if (!_isValidName(item.name)) return false;
          if (_isSystemUuid(item.uuid)) {
            if (!_isSystemCategoryUuid(item.uuid)) return false;
            return item.isSystem &&
                (item.iconCustomized || item.nameCustomized);
          }
          return !item.isSystem;
        })
        .toList(growable: false);
    final paymentMethods = _listOfMaps(bundle['payment_methods'])
        .where(_hasRawFinanceUuid)
        .where(_hasValidRawFinanceName)
        .map(FinancePaymentMethod.fromMap)
        .where(
          (item) =>
              !item.isSystem &&
              !_isSystemUuid(item.uuid) &&
              _isValidName(item.name),
        )
        .toList(growable: false);
    final transactions = _listOfMaps(bundle['transactions'])
        .where(
          (map) =>
              _hasRawFinanceUuid(map) &&
              _isValidRawTransactionType(map) &&
              _hasValidRawFinanceDateKey(
                map,
                'transaction_date',
                'transactionDate',
              ) &&
              _hasSafeRawFinanceTimestamps(map) &&
              _hasValidRawInstallmentFields(map) &&
              _isSafeRawFinanceAmount(
                map['amount_minor'] ?? map['amountMinor'],
              ),
        )
        .map(FinanceTransaction.fromMap)
        .where(_isValidTransaction)
        .toList(growable: false);
    final budgets = _latestBudgetsByScope(
      _listOfMaps(bundle['budgets'])
          .where(
            (map) =>
                _hasRawFinanceUuid(map) &&
                _isSafeRawFinanceAmount(
                  map['amount_minor'] ?? map['amountMinor'],
                ) &&
                _hasValidRawFinanceMonthKey(map) &&
                _hasValidRawBalanceSnapshot(map),
          )
          .map(FinanceBudget.fromMap)
          .where(_isValidBudget)
          .toList(growable: false),
    );
    final recurringRules = _listOfMaps(bundle['recurring_rules'])
        .where(
          (map) => _hasRawFinanceUuid(map) &&
              _hasValidRawFinanceName(map) &&
              _hasSafeRawFinanceAmount(map, 'amount_minor', 'amountMinor') &&
              _hasValidRawOptionalTransactionType(map) &&
              _hasValidRawRecurringFrequency(map) &&
              _hasValidRawRecurringScheduleFields(map) &&
              _hasValidRawFinanceDateKey(map, 'start_date', 'startDate') &&
              _hasSafeRawFinanceTimestamps(map),
        )
        .map(FinanceRecurringRule.fromMap)
        .where(_isValidRecurringRule)
        .toList(growable: false);
    final templates = _listOfMaps(bundle['templates'])
        .where(
          (map) => _hasRawFinanceUuid(map) &&
              _hasValidRawFinanceName(map) &&
              _hasSafeRawFinanceAmount(map, 'amount_minor', 'amountMinor') &&
              _hasSafeRawTemplateUseCount(map) &&
              _hasValidRawOptionalTransactionType(map),
        )
        .map(FinanceEntryTemplate.fromMap)
        .where(_isValidTemplate)
        .toList(growable: false);
    final loans = _listOfMaps(bundle['loans'])
        .where(
          (map) =>
              _hasRawFinanceUuid(map) &&
              _hasValidRawFinanceName(map) &&
              _hasSafeRawFinanceAmount(
                map,
                'principal_minor',
                'principalMinor',
              ) &&
              _hasSafeRawLoanInterestRate(map) &&
              _hasValidRawLoanRepaymentMethod(map) &&
              _hasValidRawFinanceDateKey(map, 'start_date', 'startDate') &&
              _hasSafeRawIntegerRange(
                map,
                'term_months',
                'termMonths',
                FinanceLoanCalculator.minTermMonths,
                FinanceLoanCalculator.maxTermMonths,
              ) &&
              _hasSafeRawIntegerRange(map, 'repayment_day', 'repaymentDay', 1, 31),
        )
        .map(FinanceLoan.fromMap)
        .where(_isValidLoan)
        .toList(growable: false);
    final loanInstallments = _deduplicateActiveLoanInstallments(
      _listOfMaps(bundle['loan_installments'])
          .where(_hasRawFinanceUuid)
          .where(_hasSafeRawLoanInstallmentAmounts)
          .where(_hasValidRawLoanInstallmentScheduleFields)
          .where(_hasSafeRawFinanceTimestamps)
          .map(FinanceLoanInstallment.fromMap)
          .where(_isValidLoanInstallment)
          .toList(growable: false),
    );

    final db = await _database;
    var changed = 0;
    final repairedRefundUuids = <String>{};
    await db.transaction((txn) async {
      changed += await _mergeCategories(
        txn,
        categories,
        forceRemoteKeys: forceRemoteKeys,
      );
      changed += await _mergePaymentMethods(
        txn,
        paymentMethods,
        forceRemoteKeys: forceRemoteKeys,
      );
      changed += await _mergeTransactions(
        txn,
        transactions,
        forceRemoteKeys: forceRemoteKeys,
        deferredTransactionUuids: deferredTransactionUuids,
        repairedRefundUuids: repairedRefundUuids,
      );
      changed += await _mergeLoans(
        txn,
        loans,
        forceRemoteKeys: forceRemoteKeys,
      );
      changed += await _mergeLoanInstallments(
        txn,
        loanInstallments,
        forceRemoteKeys: forceRemoteKeys,
      );
      changed += await _mergeBudgets(
        txn,
        budgets,
        forceRemoteKeys: forceRemoteKeys,
      );
      final recurringRuleChanges = await _mergeRecurringRules(
        txn,
        recurringRules,
        forceRemoteKeys: forceRemoteKeys,
      );
      changed += recurringRuleChanges;
      if (recurringRuleChanges > 0) {
        changedSections?.add('recurring_rules');
      }
      changed += await _mergeTemplates(
        txn,
        templates,
        forceRemoteKeys: forceRemoteKeys,
      );
    });
    if (changed > 0) {
      _notifyChanged(requestSync: repairedRefundUuids.isNotEmpty);
    }
    return changed;
  }

  /// Clears pending markers only for rows that were part of the request and
  /// are still at the same local version. A later local edit therefore keeps
  /// its marker even when the earlier request finishes afterwards.
  static Future<int> acknowledgePendingChanges(
    Map<String, dynamic> requestPayload,
    List<dynamic> acknowledgements,
  ) async {
    if (acknowledgements.isEmpty) return 0;
    await ensureReady();
    const tableByKey = <String, String>{
      'categories': 'finance_categories',
      'payment_methods': 'finance_payment_methods',
      'transactions': 'finance_transactions',
      'loans': 'finance_loans',
      'loan_installments': 'finance_loan_installments',
      'budgets': 'finance_budgets',
      'recurring_rules': 'finance_recurring_rules',
      'templates': 'finance_entry_templates',
    };
    const sectionsByTableKey = <String, List<String>>{
      'categories': ['finance_categories_changes'],
      'payment_methods': ['finance_payment_methods_changes'],
      'transactions': ['finance_transactions_changes'],
      'loans': ['finance_loans_changes'],
      'loan_installments': [
        'finance_loan_installments_changes',
        'finance_loan_account_changes',
      ],
      'budgets': [
        'finance_budgets_changes',
        'finance_balance_snapshots_changes',
      ],
      'recurring_rules': ['finance_recurring_rules_changes'],
      'templates': ['finance_entry_templates_changes'],
    };
    final requestedByKey = <String, Map<String, dynamic>>{};
    for (final entry in sectionsByTableKey.entries) {
      for (final section in entry.value) {
        final raw = requestPayload[section];
        if (raw is! List) continue;
        for (final value in raw.whereType<Map>()) {
          final item = Map<String, dynamic>.from(value);
          final uuid = item['uuid']?.toString() ?? item['id']?.toString() ?? '';
          if (uuid.isNotEmpty) {
            requestedByKey['${entry.key}:$uuid'] = item;
          }
        }
      }
    }

    final db = await _database;
    var acknowledged = 0;
    await db.transaction((txn) async {
      for (final value in acknowledgements.whereType<Map>()) {
        final tableKey = value['table']?.toString() ?? '';
        final table = tableByKey[tableKey];
        if (table == null) continue;
        final uuid = value['uuid']?.toString() ?? value['id']?.toString() ?? '';
        if (uuid.isEmpty) continue;
        final requested = requestedByKey['$tableKey:$uuid'];
        if (requested == null) continue;
        final requestedUpdatedAt = _asInt(
          requested['updated_at'] ?? requested['updatedAt'],
        );
        final requestedVersion = _asInt(requested['version']);
        final rows = await txn.query(
          table,
          columns: ['updated_at', 'version'],
          where: 'uuid = ? AND pending_sync = 1',
          whereArgs: [uuid],
          limit: 1,
        );
        if (rows.isEmpty ||
            _asInt(rows.first['updated_at']) != requestedUpdatedAt ||
            _asInt(rows.first['version']) != requestedVersion) {
          continue;
        }
        final appliedUpdatedAt = _asInt(value['updated_at']);
        final appliedVersion = _asInt(value['version']);
        // Acknowledgements are the only path that clears a pending marker.
        // Require the server's final ordering metadata as well as the UUID;
        // an incomplete response must be retried instead of being treated as
        // a successful upload.
        if (appliedUpdatedAt <= 0 || appliedVersion <= 0) continue;
        final update = <String, dynamic>{'pending_sync': 0};
        update['updated_at'] = appliedUpdatedAt;
        update['version'] = appliedVersion;
        final count = await txn.update(
          table,
          update,
          where: 'uuid = ? AND pending_sync = 1 AND updated_at = ? AND version = ?',
          whereArgs: [uuid, requestedUpdatedAt, requestedVersion],
        );
        acknowledged += count;
      }
    });
    return acknowledged;
  }

  /// Filters category writes that would leave the local catalog with a broken
  /// or deeper-than-two-level hierarchy. Validate the projected batch instead
  /// of its input order so a valid root/child pair still imports when the
  /// child appears first in a backup or sync response.
  static Future<Set<String>> _invalidCategoryHierarchyUuids(
    DatabaseExecutor db,
    Iterable<FinanceCategory> candidates,
  ) async {
    final candidateByUuid = <String, FinanceCategory>{
      for (final item in candidates)
        if (!item.isSystem && !_isSystemUuid(item.uuid)) item.uuid: item,
    };
    if (candidateByUuid.isEmpty) return <String>{};

    final rows = await db.query('finance_categories');
    final currentByUuid = <String, FinanceCategory>{
      for (final row in rows)
        FinanceCategory.fromMap(row).uuid: FinanceCategory.fromMap(row),
    };
    final structuralCandidates = <String>{};
    for (final entry in candidateByUuid.entries) {
      final current = currentByUuid[entry.key];
      final incoming = entry.value;
      if (current == null ||
          _normalizeCategoryParentUuid(current.parentUuid) !=
              _normalizeCategoryParentUuid(incoming.parentUuid) ||
          current.type != incoming.type ||
          current.isDeleted != incoming.isDeleted ||
          current.isArchived != incoming.isArchived) {
        structuralCandidates.add(entry.key);
      }
    }
    if (structuralCandidates.isEmpty) return <String>{};

    final rejected = <String>{};
    while (true) {
      final projected = Map<String, FinanceCategory>.from(currentByUuid);
      for (final entry in candidateByUuid.entries) {
        if (!rejected.contains(entry.key)) projected[entry.key] = entry.value;
      }

      final newlyRejected = <String>{};
      for (final start in projected.values.where((item) => !item.isDeleted)) {
        final path = <FinanceCategory>[];
        final pathIndex = <String, int>{};
        var cursor = start;
        var reachedRoot = false;
        var foundBrokenEdge = false;

        while (true) {
          final cycleStart = pathIndex[cursor.uuid];
          if (cycleStart != null) {
            final cycleUuids = path
                .skip(cycleStart)
                .map((item) => item.uuid)
                .where(structuralCandidates.contains)
                .where((uuid) => !rejected.contains(uuid))
                .toList();
            if (cycleUuids.isNotEmpty) {
              cycleUuids.sort((left, right) {
                final byTimestamp = candidateByUuid[left]!.updatedAt.compareTo(
                  candidateByUuid[right]!.updatedAt,
                );
                return byTimestamp != 0 ? byTimestamp : left.compareTo(right);
              });
              newlyRejected.add(cycleUuids.first);
            }
            foundBrokenEdge = true;
            break;
          }

          pathIndex[cursor.uuid] = path.length;
          path.add(cursor);
          final parentUuid = _normalizeCategoryParentUuid(cursor.parentUuid);
          if (parentUuid == null) {
            reachedRoot = true;
            break;
          }

          final parent = projected[parentUuid];
          if (parent == null ||
              parent.isDeleted ||
              (parent.isArchived && !cursor.isArchived) ||
              parent.type != cursor.type) {
            if (structuralCandidates.contains(cursor.uuid) &&
                !rejected.contains(cursor.uuid)) {
              newlyRejected.add(cursor.uuid);
            } else if (structuralCandidates.contains(parentUuid) &&
                !rejected.contains(parentUuid)) {
              newlyRejected.add(parentUuid);
            }
            foundBrokenEdge = true;
            break;
          }
          cursor = parent;
        }

        if (reachedRoot && !foundBrokenEdge && path.length > 2) {
          // `path` runs from the current category toward its root. The node
          // and its parent at each level are the two incoming edges that can
          // have introduced a third level. Prefer rejecting the deepest
          // incoming category so the valid parent hierarchy can be retained.
          for (var index = 0; index + 2 < path.length; index++) {
            final child = path[index];
            final parent = path[index + 1];
            if (structuralCandidates.contains(child.uuid) &&
                !rejected.contains(child.uuid)) {
              newlyRejected.add(child.uuid);
              break;
            }
            if (structuralCandidates.contains(parent.uuid) &&
                !rejected.contains(parent.uuid)) {
              newlyRejected.add(parent.uuid);
              break;
            }
          }
        }
      }

      if (newlyRejected.isEmpty) break;
      rejected.addAll(newlyRejected);
    }
    return rejected;
  }

  static String? _normalizeCategoryParentUuid(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static Future<int> _mergeCategories(
    DatabaseExecutor db,
    List<FinanceCategory> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    final hierarchyCandidates = <FinanceCategory>[];
    for (final item in items.where((item) => !item.isSystem)) {
      final existing = await _findByUuid(db, 'finance_categories', item.uuid);
      if (existing == null) {
        hierarchyCandidates.add(item);
        continue;
      }
      final current = FinanceCategory.fromMap(existing);
      if (forceRemoteKeys.contains('categories:${item.uuid}') ||
          _isIncomingWinner(
            item.updatedAt,
            item.version,
            current.updatedAt,
            current.version,
          )) {
        hierarchyCandidates.add(item);
      }
    }
    final invalidCategoryUuids = await _invalidCategoryHierarchyUuids(
      db,
      hierarchyCandidates,
    );

    var changed = 0;
    for (final item in items) {
      if (!item.isSystem && invalidCategoryUuids.contains(item.uuid)) {
        continue;
      }
      final existing = await _findByUuid(db, 'finance_categories', item.uuid);
      if (existing == null) {
        await db.insert('finance_categories', _remoteValues(item.toMap()));
        changed++;
        continue;
      }
      final current = FinanceCategory.fromMap(existing);
      final isSystemOverride =
          item.isSystem &&
          _isSystemCategoryUuid(item.uuid) &&
          (item.iconCustomized || item.nameCustomized);
      if (isSystemOverride && current.isSystem) {
        // A freshly initialized device has a new local timestamp for its
        // default row. It must not beat cloud overrides solely because that
        // timestamp is newer. A pending local override still follows normal
        // LWW/conflict handling below.
        item
          ..name = item.nameCustomized ? item.name : current.name
          ..nameCustomized = item.nameCustomized || current.nameCustomized
          ..icon = item.iconCustomized ? item.icon : current.icon
          ..iconCustomized = item.iconCustomized || current.iconCustomized
          ..type = current.type
          ..colorValue = current.colorValue
          ..parentUuid = current.parentUuid
          ..sortOrder = current.sortOrder
          ..isSystem = true
          ..isArchived = false
          ..isDeleted = false;
      }
      if (!forceRemoteKeys.contains('categories:${item.uuid}') &&
          !(isSystemOverride &&
              !current.iconCustomized &&
              !current.nameCustomized &&
              !current.pendingSync) &&
          !_isIncomingWinner(
            item.updatedAt,
            item.version,
            current.updatedAt,
            current.version,
          )) {
        continue;
      }
      await db.update(
        'finance_categories',
        _remoteValues(item.toMap()),
        where: 'uuid = ?',
        whereArgs: [item.uuid],
      );
      changed++;
    }
    return changed;
  }

  static Future<int> _mergePaymentMethods(
    DatabaseExecutor db,
    List<FinancePaymentMethod> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    var changed = 0;
    for (final item in items) {
      final existing = await _findByUuid(
        db,
        'finance_payment_methods',
        item.uuid,
      );
      if (existing == null) {
        await db.insert('finance_payment_methods', _remoteValues(item.toMap()));
        changed++;
        continue;
      }
      final current = FinancePaymentMethod.fromMap(existing);
      if (!forceRemoteKeys.contains('payment_methods:${item.uuid}') &&
          !_isIncomingWinner(
            item.updatedAt,
            item.version,
            current.updatedAt,
            current.version,
          )) {
        continue;
      }
      await db.update(
        'finance_payment_methods',
        _remoteValues(item.toMap()),
        where: 'uuid = ?',
        whereArgs: [item.uuid],
      );
      changed++;
    }
    return changed;
  }

  static Future<int> _mergeTransactions(
    DatabaseExecutor db,
    List<FinanceTransaction> items, {
    Set<String> forceRemoteKeys = const {},
    Set<String>? deferredTransactionUuids,
    Set<String>? repairedRefundUuids,
  }) async {
    var changed = 0;
    final changedOriginalUuids = <String>{};
    final duplicateInstallmentKeys = _duplicateInstallmentIndexKeys(items);
    final orderedItems = items
      .where((item) {
        final key = _installmentIndexKey(item);
        return item.isDeleted ||
            key == null ||
            !duplicateInstallmentKeys.contains(key);
      })
      .toList()
      ..sort((left, right) {
        // Create/restore originals before active refunds, but remove refunds
        // before deleting or changing the type of their originals.
        return _transactionMergePriority(left)
            .compareTo(_transactionMergePriority(right));
      });
    var pending = orderedItems;
    while (pending.isNotEmpty) {
      final deferred = <FinanceTransaction>[];
      final changedBeforeRound = changed;
      for (final item in pending) {
        if (await _hasInstallmentIndexConflict(db, item)) continue;
        final existing = await _findByUuid(db, 'finance_transactions', item.uuid);
        if (existing != null) {
          final current = FinanceTransaction.fromMap(existing);
          if (!forceRemoteKeys.contains('transactions:${item.uuid}') &&
              !_isIncomingWinner(
                item.updatedAt,
                item.version,
                current.updatedAt,
                current.version,
              )) {
            continue;
          }
        }
        try {
          await _validateTransactionRefundState(db, item, alignCategory: false);
        } on StateError {
          deferred.add(item);
          continue;
        }
        if (existing == null) {
          await db.insert('finance_transactions', _remoteValues(item.toMap()));
        } else {
          await db.update(
            'finance_transactions',
            _remoteValues(item.toMap()),
            where: 'uuid = ?',
            whereArgs: [item.uuid],
          );
        }
        changedOriginalUuids.add(item.uuid);
        if (item.type == FinanceTransactionType.refund &&
            item.relatedTransactionUuid != null) {
          changedOriginalUuids.add(item.relatedTransactionUuid!);
        }
        changed++;
      }
      if (changed == changedBeforeRound) {
        deferredTransactionUuids?.addAll(deferred.map((item) => item.uuid));
        break;
      }
      pending = deferred;
    }
    final repairedRefunds = <String>{};
    await _alignLinkedRefunds(
      db,
      originalUuids: changedOriginalUuids,
      repairedUuids: repairedRefunds,
    );
    changed += repairedRefunds
        .where((uuid) => !changedOriginalUuids.contains(uuid))
        .length;
    repairedRefundUuids?.addAll(repairedRefunds);
    return changed;
  }

  static int _transactionMergePriority(FinanceTransaction item) {
    if (item.type == FinanceTransactionType.expense && !item.isDeleted) {
      return 0;
    }
    if (item.type == FinanceTransactionType.refund) {
      return item.isDeleted ? 1 : 2;
    }
    return 3;
  }

  static Future<int> _mergeLoans(
    DatabaseExecutor db,
    List<FinanceLoan> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    var changed = 0;
    for (final item in items) {
      final existing = await _findByUuid(db, 'finance_loans', item.uuid);
      if (existing == null) {
        await db.insert('finance_loans', _remoteValues(item.toMap()));
        changed++;
        continue;
      }
      final current = FinanceLoan.fromMap(existing);
      if (!forceRemoteKeys.contains('loans:${item.uuid}') &&
          !_isIncomingWinner(
            item.updatedAt,
            item.version,
            current.updatedAt,
            current.version,
          )) {
        continue;
      }
      if (_loanTermsDiffer(current, item) &&
          await _hasPaidLoanInstallments(db, item.uuid)) {
        continue;
      }
      await db.update(
        'finance_loans',
        _remoteValues(item.toMap()),
        where: 'uuid = ?',
        whereArgs: [item.uuid],
      );
      changed++;
    }
    return changed;
  }

  static Future<int> _mergeLoanInstallments(
    DatabaseExecutor db,
    List<FinanceLoanInstallment> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    var changed = 0;
    final loanScheduleCache =
        <String, List<FinanceLoanScheduleAllocation>>{};
    for (final item in items) {
      final parentLoan = await _findByUuid(db, 'finance_loans', item.loanUuid);
      final loan = parentLoan == null
          ? null
          : FinanceLoan.fromMap(parentLoan);
      if (loan == null ||
          (loan.isDeleted && !item.isDeleted) ||
          (!item.isDeleted &&
              !_matchesLoanInstallmentSchedule(
                loan,
                item,
                loanScheduleCache,
              ))) {
        continue;
      }
      if (!item.isDeleted) {
        final duplicateSchedules = await db.query(
          'finance_loan_installments',
          columns: ['uuid'],
          where:
              'loan_uuid = ? AND installment_index = ? AND is_deleted = 0',
          whereArgs: [item.loanUuid, item.installmentIndex],
        );
        if (duplicateSchedules.any((row) => row['uuid'] != item.uuid)) {
          continue;
        }
      }
      final existing = await _findByUuid(
        db,
        'finance_loan_installments',
        item.uuid,
      );
      if (existing == null) {
        await db.insert(
          'finance_loan_installments',
          _remoteValues(item.toMap()),
        );
        changed++;
        continue;
      }
      final current = FinanceLoanInstallment.fromMap(existing);
      if (!forceRemoteKeys.contains('loan_installments:${item.uuid}') &&
          !_isIncomingWinner(
            item.updatedAt,
            item.version,
            current.updatedAt,
            current.version,
      )) {
        continue;
      }
      if (current.isPaid && !_sameLoanInstallmentSchedule(current, item)) {
        continue;
      }
      await db.update(
        'finance_loan_installments',
        _remoteValues(item.toMap()),
        where: 'uuid = ?',
        whereArgs: [item.uuid],
      );
      changed++;
    }
    return changed;
  }

  static Future<int> _mergeBudgets(
    DatabaseExecutor db,
    List<FinanceBudget> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    var changed = 0;
    for (final item in items) {
      if (!await _hasValidBudgetScope(db, item)) continue;
      final scopeRows = await _findAllBudgetsByScope(db, item);
      if (scopeRows.isEmpty) {
        await db.insert('finance_budgets', _remoteValues(item.toMap()));
        changed++;
        continue;
      }

      var current = FinanceBudget.fromMap(scopeRows.first);
      for (final row in scopeRows.skip(1)) {
        final candidate = FinanceBudget.fromMap(row);
        if (_isIncomingBudgetWinner(candidate, current)) {
          current = candidate;
        }
      }
      final forceIncoming = forceRemoteKeys.contains('budgets:${item.uuid}');
      final sameWinner =
          current.uuid == item.uuid &&
          current.updatedAt == item.updatedAt &&
          current.version == item.version;
      final incomingWins =
          forceIncoming ||
          sameWinner ||
          _isIncomingBudgetWinner(item, current);
      if (!incomingWins) {
        if (scopeRows.length > 1) {
          await _deleteOtherBudgetsInScope(db, current);
          changed++;
        }
        continue;
      }
      await _deleteBudgetsInScope(db, item);
      await db.insert('finance_budgets', _remoteValues(item.toMap()));
      changed++;
    }
    return changed;
  }

  static List<FinanceBudget> _latestBudgetsByScope(List<FinanceBudget> items) {
    final latest = <String, FinanceBudget>{};
    for (final item in items) {
      final key = _budgetScopeKey(item);
      final current = latest[key];
      if (current == null || _isIncomingBudgetWinner(item, current)) {
        latest[key] = item;
      }
    }
    return latest.values.toList(growable: false);
  }

  static bool _isIncomingBudgetWinner(
    FinanceBudget incoming,
    FinanceBudget current,
  ) {
    if (incoming.updatedAt != current.updatedAt) {
      return incoming.updatedAt > current.updatedAt;
    }
    if (incoming.uuid != current.uuid &&
        incoming.isDeleted != current.isDeleted) {
      // Replacing a scope retires its old UUID at the replacement timestamp.
      // The old row's bumped version must not beat the active replacement.
      return !incoming.isDeleted;
    }
    return incoming.version > current.version;
  }

  static Future<int> _mergeRecurringRules(
    DatabaseExecutor db,
    List<FinanceRecurringRule> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    var changed = 0;
    for (final item in items) {
      final existing = await _findByUuid(
        db,
        'finance_recurring_rules',
        item.uuid,
      );
      if (existing == null) {
        item.lastGeneratedPeriod = item.effectiveLastGeneratedPeriod;
        await db.insert('finance_recurring_rules', _remoteValues(item.toMap()));
        changed++;
        continue;
      }
      final current = FinanceRecurringRule.fromMap(existing);
      if (!forceRemoteKeys.contains('recurring_rules:${item.uuid}') &&
          !_isIncomingWinner(
            item.updatedAt,
            item.version,
            current.updatedAt,
            current.version,
          )) {
        continue;
      }
      item.lastGeneratedPeriod = _mergeRecurringGenerationPeriod(current, item);
      await db.update(
        'finance_recurring_rules',
        _remoteValues(item.toMap()),
        where: 'uuid = ?',
        whereArgs: [item.uuid],
      );
      changed++;
    }
    return changed;
  }

  static Future<int> _mergeTemplates(
    DatabaseExecutor db,
    List<FinanceEntryTemplate> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    var changed = 0;
    for (final item in items) {
      final existing = await _findByUuid(
        db,
        'finance_entry_templates',
        item.uuid,
      );
      if (existing == null) {
        await db.insert('finance_entry_templates', _remoteValues(item.toMap()));
        changed++;
        continue;
      }
      final current = FinanceEntryTemplate.fromMap(existing);
      if (!forceRemoteKeys.contains('templates:${item.uuid}') &&
          !_isIncomingWinner(
            item.updatedAt,
            item.version,
            current.updatedAt,
            current.version,
          )) {
        continue;
      }
      await db.update(
        'finance_entry_templates',
        _remoteValues(item.toMap()),
        where: 'uuid = ?',
        whereArgs: [item.uuid],
      );
      changed++;
    }
    return changed;
  }

  static bool _isIncomingWinner(
    int incomingUpdatedAt,
    int incomingVersion,
    int currentUpdatedAt,
    int currentVersion,
  ) {
    return incomingUpdatedAt > currentUpdatedAt ||
        (incomingUpdatedAt == currentUpdatedAt &&
            incomingVersion > currentVersion);
  }

  static bool _isValidTransaction(FinanceTransaction item) {
    return item.uuid.trim().isNotEmpty &&
        isSafeFinanceAmountMinor(item.amountMinor) &&
        item.amountMinor > 0 &&
        (item.isDeleted || _hasValidInstallmentFields(item)) &&
        (item.installmentTotalMinor == null ||
            (isSafeFinanceAmountMinor(item.installmentTotalMinor!) &&
                item.installmentTotalMinor! > 0)) &&
        _isDateKey(item.transactionDate);
  }

  static bool _hasValidInstallmentFields(FinanceTransaction item) {
    final groupUuid = item.installmentGroupUuid?.trim();
    final hasInstallmentFields =
        (groupUuid?.isNotEmpty ?? false) ||
        item.installmentIndex != null ||
        item.installmentCount != null ||
        item.installmentTotalMinor != null;
    if (!hasInstallmentFields) return true;
    final index = item.installmentIndex;
    final count = item.installmentCount;
    final total = item.installmentTotalMinor;
    return item.type == FinanceTransactionType.expense &&
        groupUuid?.isNotEmpty == true &&
        index != null &&
        index >= 1 &&
        count != null &&
        count >= FinanceInstallmentCalculator.minCount &&
        count <= FinanceLoanCalculator.maxTermMonths &&
        index <= count &&
        (total == null ||
            (isSafeFinanceAmountMinor(total) &&
                total >= item.amountMinor));
  }

  static bool _hasValidRawInstallmentFields(Map<String, dynamic> raw) {
    final isDeleted = raw['is_deleted'] ?? raw['isDeleted'];
    if (isDeleted == true || isDeleted == 1 || isDeleted == '1') return true;
    final groupValue =
        raw['installment_group_uuid'] ?? raw['installmentGroupUuid'];
    final indexValue = raw['installment_index'] ?? raw['installmentIndex'];
    final countValue = raw['installment_count'] ?? raw['installmentCount'];
    final totalValue =
        raw['installment_total_minor'] ?? raw['installmentTotalMinor'];
    final hasGroupValue = groupValue != null &&
        (groupValue is! String || groupValue.trim().isNotEmpty);
    if (!hasGroupValue &&
        indexValue == null &&
        countValue == null &&
        totalValue == null) {
      return true;
    }
    if (groupValue is! String || groupValue.trim().isEmpty) return false;
    final index = _rawFinanceInteger(indexValue);
    final count = _rawFinanceInteger(countValue);
    if (index == null ||
        index < 1 ||
        count == null ||
        count < FinanceInstallmentCalculator.minCount ||
        count > FinanceLoanCalculator.maxTermMonths ||
        index > count) {
      return false;
    }
    if (totalValue == null) return true;
    final amountValue = raw['amount_minor'] ?? raw['amountMinor'];
    if (!_isSafeRawFinanceAmount(totalValue) ||
        !_isSafeRawFinanceAmount(amountValue)) {
      return false;
    }
    final total = _asInt(totalValue);
    final amount = _asInt(amountValue);
    return total > 0 && amount > 0 && total >= amount;
  }

  static String? _installmentIndexKey(FinanceTransaction item) {
    if (!item.isInstallment) return null;
    return '${item.installmentGroupUuid}\u0000${item.installmentIndex}';
  }

  static Set<String> _duplicateInstallmentIndexKeys(
    Iterable<FinanceTransaction> items,
  ) {
    final uuidsByKey = <String, Set<String>>{};
    for (final item in items) {
      if (item.isDeleted) continue;
      final key = _installmentIndexKey(item);
      if (key == null) continue;
      uuidsByKey.putIfAbsent(key, () => <String>{}).add(item.uuid);
    }
    return uuidsByKey.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toSet();
  }

  static Future<bool> _hasInstallmentIndexConflict(
    DatabaseExecutor db,
    FinanceTransaction item,
  ) async {
    final groupUuid = item.installmentGroupUuid;
    final installmentIndex = item.installmentIndex;
    if (item.isDeleted ||
        !item.isInstallment ||
        groupUuid == null ||
        installmentIndex == null) {
      return false;
    }
    final rows = await db.query(
      'finance_transactions',
      columns: ['uuid'],
      where: 'installment_group_uuid = ? AND installment_index = ? '
          'AND uuid != ? AND is_deleted = 0',
      whereArgs: [groupUuid, installmentIndex, item.uuid],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Linked refunds inherit classification from their original. Repair after
  /// the whole batch so this derived edit cannot block a newer refund amount.
  static Future<int> _alignLinkedRefunds(
    DatabaseExecutor db, {
    required Iterable<String> originalUuids,
    Set<String>? repairedUuids,
  }) async {
    final uuids = originalUuids.toSet().toList();
    if (uuids.isEmpty) return 0;
    var repaired = 0;
    // Older Android SQLite builds allow only 999 bound variables per query.
    for (var offset = 0; offset < uuids.length; offset += 500) {
      final end = offset + 500;
      final chunk = uuids.sublist(offset, end > uuids.length ? uuids.length : end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery('''
      SELECT refund.*, original.category_uuid AS original_category_uuid,
        original.currency_code AS original_currency_code
      FROM finance_transactions AS refund
      JOIN finance_transactions AS original
        ON original.uuid = refund.related_transaction_uuid
      WHERE refund.type = 'refund' AND original.type = 'expense'
        AND original.is_deleted = 0 AND original.uuid IN ($placeholders)
        AND (refund.category_uuid IS NOT original.category_uuid
          OR refund.currency_code IS NOT original.currency_code)
    ''', chunk);
      for (final row in rows) {
        final refund = FinanceTransaction.fromMap(row)
          ..categoryUuid = row['original_category_uuid'] as String?
          ..currencyCode = row['original_currency_code'] as String;
        refund.markAsChanged();
        await db.update(
          'finance_transactions',
          _localValues(refund.toMap()),
          where: 'uuid = ?',
          whereArgs: [refund.uuid],
        );
        repairedUuids?.add(refund.uuid);
      }
      repaired += rows.length;
    }
    return repaired;
  }

  static Future<int> _activeRefundedMinor(
    DatabaseExecutor db,
    String originalUuid, {
    String? excludingRefundUuid,
  }) async {
    final where = <String>[
      "type = 'refund'",
      'related_transaction_uuid = ?',
      'is_deleted = 0',
    ];
    final args = <Object?>[originalUuid];
    if (excludingRefundUuid != null && excludingRefundUuid.isNotEmpty) {
      where.add('uuid != ?');
      args.add(excludingRefundUuid);
    }
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_minor), 0) AS total '
      'FROM finance_transactions WHERE ${where.join(' AND ')}',
      args,
    );
    return _asInt(rows.first['total']);
  }

  static Future<void> _validateTransactionRefundState(
    DatabaseExecutor db,
    FinanceTransaction transaction, {
    bool alignCategory = true,
  }) async {
    final originalUuid = transaction.relatedTransactionUuid?.trim();
    if (transaction.type == FinanceTransactionType.refund &&
        !transaction.isDeleted &&
        originalUuid?.isNotEmpty == true) {
      if (originalUuid == transaction.uuid) {
        throw StateError('退款账单不能绑定自己');
      }
      final originalRow = await _findByUuid(
        db,
        'finance_transactions',
        originalUuid!,
      );
      if (originalRow == null) throw StateError('原账单不存在');
      final original = FinanceTransaction.fromMap(originalRow);
      if (original.isDeleted ||
          original.type != FinanceTransactionType.expense) {
        throw StateError('只能对未删除的支出账单发起退款');
      }
      final refunded = await _activeRefundedMinor(
        db,
        original.uuid,
        excludingRefundUuid: transaction.uuid,
      );
      final remaining = original.amountMinor - refunded;
      if (transaction.amountMinor > remaining) {
        final remainingMinor = remaining.clamp(0, original.amountMinor).toInt();
        throw StateError('退款金额超过剩余可退金额 $remainingMinor 分');
      }
      if (alignCategory) {
        transaction
          ..currencyCode = original.currencyCode
          ..categoryUuid = original.categoryUuid;
      }
    }

    final activeRefunded = await _activeRefundedMinor(db, transaction.uuid);
    if (activeRefunded > 0 &&
        (transaction.isDeleted ||
            transaction.type != FinanceTransactionType.expense ||
            transaction.amountMinor < activeRefunded)) {
      throw StateError('该账单已关联退款，请先处理退款记录');
    }
  }

  static bool _isValidImportedTransaction(
    Map<String, dynamic> raw,
    FinanceTransaction item,
  ) {
    final rawUuid = raw['uuid'] ?? raw['id'];
    final rawDate = raw['transaction_date'] ?? raw['transactionDate'];
    final rawAmount = raw['amount_minor'] ?? raw['amountMinor'];
    return rawUuid?.toString().trim().isNotEmpty == true &&
        rawDate is String &&
        _isDateKey(rawDate) &&
        _isSafeRawFinanceAmount(rawAmount) &&
        _asInt(rawAmount) > 0 &&
        _isValidRawTransactionType(raw) &&
        _hasSafeRawFinanceTimestamps(raw) &&
        _hasValidRawInstallmentFields(raw) &&
        _isValidTransaction(item);
  }

  static bool _isValidRawTransactionType(Map<String, dynamic> raw) {
    final value = raw['type'];
    return const {'expense', 'income', 'refund'}.contains(value) ||
        const {0, 1, 2, '0', '1', '2'}.contains(value);
  }

  static bool _hasValidRawOptionalTransactionType(
    Map<String, dynamic> raw,
  ) {
    final value = raw['type'];
    return value == null || _isValidRawTransactionType(raw);
  }

  static bool _hasValidRawRecurringFrequency(Map<String, dynamic> raw) {
    final value = raw['frequency'];
    return value == null ||
        _isValidRawEnumValue(
          value,
          FinanceRecurringFrequency.values.map((item) => item.name),
          FinanceRecurringFrequency.values.length,
        );
  }

  static bool _hasValidRawLoanRepaymentMethod(Map<String, dynamic> raw) {
    final value = raw['repayment_method'] ?? raw['repaymentMethod'];
    return value == null ||
        _isValidRawEnumValue(
          value,
          FinanceLoanRepaymentMethod.values.map((item) => item.name),
          FinanceLoanRepaymentMethod.values.length,
        );
  }

  static bool _isValidRawEnumValue(
    dynamic value,
    Iterable<String> names,
    int valueCount,
  ) {
    if (value is num) {
      return value.isFinite &&
          value >= 0 &&
          value < valueCount &&
          value == value.roundToDouble();
    }
    return value is String && names.contains(value);
  }

  static bool _hasSafeRawFinanceTimestamps(Map<String, dynamic> raw) {
    final createdAtRaw = raw['created_at'] ?? raw['createdAt'];
    final updatedAtRaw = raw['updated_at'] ?? raw['updatedAt'];
    final occurredAtRaw = raw['occurred_at'] ?? raw['occurredAt'];
    final paidAtRaw = raw['paid_at'] ?? raw['paidAt'];
    final timezoneOffsetRaw =
        raw['timezone_offset_minutes'] ?? raw['timezoneOffsetMinutes'];

    final createdAt = _rawFinanceTimestampMillis(
      createdAtRaw,
      allowDateString: true,
    );
    final updatedAt = _rawFinanceTimestampMillis(
      updatedAtRaw,
      allowDateString: true,
    );
    final occurredAt = _rawFinanceTimestampMillis(occurredAtRaw);
    final paidAt = _rawFinanceTimestampMillis(paidAtRaw);
    if ((createdAtRaw != null && createdAt == null) ||
        (updatedAtRaw != null && updatedAt == null) ||
        (occurredAtRaw != null && occurredAt == null) ||
        (paidAtRaw != null && paidAt == null)) {
      return false;
    }

    final timezoneOffset = timezoneOffsetRaw == null
        ? 0
        : _rawFinanceInteger(timezoneOffsetRaw);
    if (timezoneOffset == null ||
        timezoneOffset < -_maxFinanceTimezoneOffsetMinutes ||
        timezoneOffset > _maxFinanceTimezoneOffsetMinutes) {
      return false;
    }

    try {
      for (final timestamp in [createdAt, occurredAt]) {
        if (timestamp == null || timestamp <= 0) continue;
        DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true).add(
          Duration(minutes: timezoneOffset),
        );
      }
    } catch (_) {
      return false;
    }
    return true;
  }

  static int? _rawFinanceTimestampMillis(
    dynamic value, {
    bool allowDateString = false,
  }) {
    final timestamp = _rawFinanceInteger(value);
    if (timestamp != null) {
      return timestamp >= -_maxDateTimeMillis &&
              timestamp <= _maxDateTimeMillis
          ? timestamp
          : null;
    }
    if (allowDateString && value is String) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        final millis = parsed.toUtc().millisecondsSinceEpoch;
        if (millis >= -_maxDateTimeMillis && millis <= _maxDateTimeMillis) {
          return millis;
        }
      }
    }
    return null;
  }

  static int? _rawFinanceInteger(dynamic value) {
    if (value is int) return value;
    if (value is num &&
        value.isFinite &&
        value >= -_maxDateTimeMillis &&
        value <= _maxDateTimeMillis &&
        value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = BigInt.tryParse(value.trim());
      if (parsed != null &&
          parsed >= BigInt.from(-_maxDateTimeMillis) &&
          parsed <= BigInt.from(_maxDateTimeMillis)) {
        return parsed.toInt();
      }
    }
    return null;
  }

  static bool _isSafeRawFinanceAmount(dynamic value) {
    if (value is int) return isSafeFinanceAmountMinor(value);
    if (value is num) {
      return value.isFinite &&
          value >= 0 &&
          value <= maxFinanceAmountMinor &&
          value == value.roundToDouble();
    }
    if (value is String) {
      final parsed = BigInt.tryParse(value.trim());
      return parsed != null &&
          parsed >= BigInt.zero &&
          parsed <= BigInt.from(maxFinanceAmountMinor);
    }
    return false;
  }

  static bool _isSafeRawFinanceCount(dynamic value, int maximum) {
    if (value == null) return true;
    if (value is int) return value >= 0 && value <= maximum;
    if (value is num) {
      return value.isFinite &&
          value >= 0 &&
          value <= maximum &&
          value == value.roundToDouble();
    }
    if (value is String) {
      final parsed = BigInt.tryParse(value.trim());
      return parsed != null &&
          parsed >= BigInt.zero &&
          parsed <= BigInt.from(maximum);
    }
    return false;
  }

  static bool _hasValidRawFinanceDateKey(
    Map<String, dynamic> map,
    String snakeCaseKey,
    String camelCaseKey,
  ) {
    final value = map[snakeCaseKey] ?? map[camelCaseKey];
    return value is String && _isDateKey(value);
  }

  static bool _hasValidRawFinanceMonthKey(Map<String, dynamic> map) {
    final value = map['month_key'] ?? map['monthKey'];
    return value is String &&
        RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value);
  }

  static bool _hasSafeRawIntegerRange(
    Map<String, dynamic> map,
    String snakeCaseKey,
    String camelCaseKey,
    int minimum,
    int maximum,
  ) {
    final value = map[snakeCaseKey] ?? map[camelCaseKey];
    final parsed = _rawFinanceInteger(value);
    return parsed != null && parsed >= minimum && parsed <= maximum;
  }

  static bool _hasValidRawRecurringScheduleFields(
    Map<String, dynamic> map,
  ) {
    return _hasSafeOptionalRawIntegerRange(
          map,
          'day_of_month',
          'dayOfMonth',
          1,
          31,
        ) &&
        _hasSafeOptionalRawIntegerRange(
          map,
          'month_of_year',
          'monthOfYear',
          1,
          12,
        ) &&
        _hasSafeOptionalRawIntegerRange(
          map,
          'reminder_minutes',
          'reminderMinutes',
          0,
          10080,
        );
  }

  static bool _hasSafeOptionalRawIntegerRange(
    Map<String, dynamic> map,
    String snakeCaseKey,
    String camelCaseKey,
    int minimum,
    int maximum,
  ) {
    final value = map[snakeCaseKey] ?? map[camelCaseKey];
    return value == null ||
        _hasSafeRawIntegerRange(
          map,
          snakeCaseKey,
          camelCaseKey,
          minimum,
          maximum,
        );
  }

  static bool _hasValidRawLoanInstallmentScheduleFields(
    Map<String, dynamic> map,
  ) =>
      _hasValidRawFinanceDateKey(map, 'due_date', 'dueDate') &&
      _hasSafeRawIntegerRange(
        map,
        'installment_index',
        'installmentIndex',
        1,
        FinanceLoanCalculator.maxTermMonths,
      );

  static int _compareRawLoanInstallmentMaps(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftLoan =
        (left['loan_uuid'] ?? left['loanUuid'])?.toString() ?? '';
    final rightLoan =
        (right['loan_uuid'] ?? right['loanUuid'])?.toString() ?? '';
    final byLoan = leftLoan.compareTo(rightLoan);
    if (byLoan != 0) return byLoan;

    final leftIndex = _rawFinanceInteger(
      left['installment_index'] ?? left['installmentIndex'],
    ) ?? 0;
    final rightIndex = _rawFinanceInteger(
      right['installment_index'] ?? right['installmentIndex'],
    ) ?? 0;
    final byIndex = leftIndex.compareTo(rightIndex);
    if (byIndex != 0) return byIndex;

    final leftUpdatedAt = _rawFinanceTimestampMillis(
      left['updated_at'] ?? left['updatedAt'],
      allowDateString: true,
    ) ?? 0;
    final rightUpdatedAt = _rawFinanceTimestampMillis(
      right['updated_at'] ?? right['updatedAt'],
      allowDateString: true,
    ) ?? 0;
    final byUpdatedAt = rightUpdatedAt.compareTo(leftUpdatedAt);
    if (byUpdatedAt != 0) return byUpdatedAt;

    final leftVersion = _rawFinanceInteger(left['version']) ?? 0;
    final rightVersion = _rawFinanceInteger(right['version']) ?? 0;
    final byVersion = rightVersion.compareTo(leftVersion);
    if (byVersion != 0) return byVersion;

    final leftUuid = (left['uuid'] ?? left['id'])?.toString() ?? '';
    final rightUuid = (right['uuid'] ?? right['id'])?.toString() ?? '';
    return leftUuid.compareTo(rightUuid);
  }

  static List<FinanceLoanInstallment> _deduplicateActiveLoanInstallments(
    List<FinanceLoanInstallment> items,
  ) {
    final deleted = <FinanceLoanInstallment>[];
    final activeBySchedule = <String, FinanceLoanInstallment>{};
    for (final item in items) {
      if (item.isDeleted) {
        deleted.add(item);
        continue;
      }
      final key = '${item.loanUuid}\u0000${item.installmentIndex}';
      final current = activeBySchedule[key];
      if (current == null ||
          item.updatedAt > current.updatedAt ||
          (item.updatedAt == current.updatedAt &&
              item.version > current.version) ||
          (item.updatedAt == current.updatedAt &&
              item.version == current.version &&
              item.uuid.compareTo(current.uuid) < 0)) {
        activeBySchedule[key] = item;
      }
    }
    return [...deleted, ...activeBySchedule.values];
  }

  static bool _hasSafeRawTemplateUseCount(Map<String, dynamic> map) =>
      _isSafeRawFinanceCount(
        map['use_count'] ?? map['useCount'],
        _maxTemplateUseCount,
      );

  static bool _hasValidRawCategoryType(Map<String, dynamic> map) {
    final value = map['type'] ?? map['category_type'];
    if (value == null) return true;
    if (value is num) {
      return value.isFinite &&
          value >= 0 &&
          value < FinanceCategoryType.values.length &&
          value == value.roundToDouble();
    }
    final type = value.toString().trim().toLowerCase();
    return type == FinanceCategoryType.expense.name ||
        type == FinanceCategoryType.income.name;
  }

  static bool _hasRawFinanceUuid(Map<String, dynamic> map) {
    final raw = map['uuid'] ?? map['id'];
    final value = raw?.toString().trim();
    return value != null && value.isNotEmpty && value != 'null';
  }

  static bool _hasSafeRawFinanceAmount(
    Map<String, dynamic> map,
    String snakeCaseKey,
    String camelCaseKey,
  ) =>
      _isSafeRawFinanceAmount(map[snakeCaseKey] ?? map[camelCaseKey]);

  static bool _hasSafeRawLoanInterestRate(Map<String, dynamic> map) {
    final value =
        map['annual_interest_rate_bps'] ?? map['annualInterestRateBps'];
    if (value == null) return true;
    if (value is int) {
      return value >= 0 &&
          value <= FinanceLoanCalculator.maxAnnualInterestRateBps;
    }
    if (value is num) {
      return value.isFinite &&
          value >= 0 &&
          value <= FinanceLoanCalculator.maxAnnualInterestRateBps &&
          value == value.roundToDouble();
    }
    if (value is String) {
      final parsed = BigInt.tryParse(value.trim());
      return parsed != null &&
          parsed >= BigInt.zero &&
          parsed <= BigInt.from(FinanceLoanCalculator.maxAnnualInterestRateBps);
    }
    return false;
  }

  static bool _hasSafeRawLoanInstallmentAmounts(Map<String, dynamic> map) =>
      _hasSafeRawFinanceAmount(map, 'payment_minor', 'paymentMinor') &&
      _hasSafeRawFinanceAmount(map, 'principal_minor', 'principalMinor') &&
      _hasSafeRawFinanceAmount(map, 'interest_minor', 'interestMinor') &&
      _hasSafeRawFinanceAmount(
        map,
        'remaining_principal_minor',
        'remainingPrincipalMinor',
      );

  static bool _isValidLoan(FinanceLoan item) {
    if (item.uuid.trim().isEmpty ||
        item.name.trim().isEmpty ||
        !_isDateKey(item.startDate)) {
      return false;
    }
    try {
      FinanceLoanCalculator.generate(
        principalMinor: item.principalMinor,
        annualInterestRateBps: item.annualInterestRateBps,
        termMonths: item.termMonths,
        startDate: dateFromKey(item.startDate),
        repaymentDay: item.repaymentDay,
        repaymentMethod: item.repaymentMethod,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _validateLoan(FinanceLoan loan) {
    if (loan.name.trim().isEmpty) {
      throw ArgumentError.value(loan.name, 'name', '贷款名称不能为空');
    }
    if (!_isDateKey(loan.startDate)) {
      throw ArgumentError.value(loan.startDate, 'startDate', '借款日期无效');
    }
    FinanceLoanCalculator.generate(
      principalMinor: loan.principalMinor,
      annualInterestRateBps: loan.annualInterestRateBps,
      termMonths: loan.termMonths,
      startDate: dateFromKey(loan.startDate),
      repaymentDay: loan.repaymentDay,
      repaymentMethod: loan.repaymentMethod,
    );
  }

  static bool _isValidLoanInstallment(FinanceLoanInstallment item) {
    final paidAt = item.paidAt;
    return item.uuid.trim().isNotEmpty &&
        item.loanUuid.trim().isNotEmpty &&
        item.installmentIndex > 0 &&
        _isDateKey(item.dueDate) &&
        isSafeFinanceAmountMinor(item.paymentMinor) &&
        item.paymentMinor > 0 &&
        isSafeFinanceAmountMinor(item.principalMinor) &&
        item.principalMinor > 0 &&
        isSafeFinanceAmountMinor(item.interestMinor) &&
        item.principalMinor <= maxFinanceAmountMinor - item.interestMinor &&
        item.paymentMinor == item.principalMinor + item.interestMinor &&
        isSafeFinanceAmountMinor(item.remainingPrincipalMinor) &&
        (paidAt == null || paidAt <= DateTime.now().millisecondsSinceEpoch) &&
        (item.paymentMethodUuid == null ||
            (item.isPaid && (paidAt ?? 0) > 0));
  }

  static Future<bool> _hasPaidLoanInstallments(
    DatabaseExecutor db,
    String loanUuid,
  ) async {
    final rows = await db.query(
      'finance_loan_installments',
      columns: ['uuid'],
      where: 'loan_uuid = ? AND is_paid = 1',
      whereArgs: [loanUuid],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static bool _sameLoanInstallmentSchedule(
    FinanceLoanInstallment left,
    FinanceLoanInstallment right,
  ) =>
      left.loanUuid == right.loanUuid &&
      left.installmentIndex == right.installmentIndex &&
      left.dueDate == right.dueDate &&
      left.paymentMinor == right.paymentMinor &&
      left.principalMinor == right.principalMinor &&
      left.interestMinor == right.interestMinor &&
      left.remainingPrincipalMinor == right.remainingPrincipalMinor;

  static bool _matchesLoanInstallmentSchedule(
    FinanceLoan loan,
    FinanceLoanInstallment installment,
    Map<String, List<FinanceLoanScheduleAllocation>> scheduleCache,
  ) {
    final index = installment.installmentIndex;
    if (index < 1 || index > loan.termMonths) return false;
    final schedule = scheduleCache.putIfAbsent(
      loan.uuid,
      () => FinanceLoanCalculator.generate(
        principalMinor: loan.principalMinor,
        annualInterestRateBps: loan.annualInterestRateBps,
        termMonths: loan.termMonths,
        startDate: dateFromKey(loan.startDate),
        repaymentDay: loan.repaymentDay,
        repaymentMethod: loan.repaymentMethod,
      ),
    );
    final expected = schedule[index - 1];
    return installment.dueDate == expected.dueDate &&
        installment.paymentMinor == expected.paymentMinor &&
        installment.principalMinor == expected.principalMinor &&
        installment.interestMinor == expected.interestMinor &&
        installment.remainingPrincipalMinor ==
            expected.remainingPrincipalMinor;
  }

  static bool _loanTermsDiffer(FinanceLoan left, FinanceLoan right) {
    return left.principalMinor != right.principalMinor ||
        left.currencyCode != right.currencyCode ||
        left.annualInterestRateBps != right.annualInterestRateBps ||
        left.termMonths != right.termMonths ||
        left.startDate != right.startDate ||
        left.repaymentDay != right.repaymentDay ||
        left.repaymentMethod != right.repaymentMethod;
  }

  static void _mergeLoanEdits(
    FinanceLoan current,
    FinanceLoan original,
    FinanceLoan incoming,
  ) {
    if (incoming.name == original.name) incoming.name = current.name;
    if (incoming.lender == original.lender) incoming.lender = current.lender;
    if (incoming.principalMinor == original.principalMinor) {
      incoming.principalMinor = current.principalMinor;
    }
    if (incoming.currencyCode == original.currencyCode) {
      incoming.currencyCode = current.currencyCode;
    }
    if (incoming.annualInterestRateBps == original.annualInterestRateBps) {
      incoming.annualInterestRateBps = current.annualInterestRateBps;
    }
    if (incoming.termMonths == original.termMonths) {
      incoming.termMonths = current.termMonths;
    }
    if (incoming.startDate == original.startDate) {
      incoming.startDate = current.startDate;
    }
    if (incoming.repaymentDay == original.repaymentDay) {
      incoming.repaymentDay = current.repaymentDay;
    }
    if (incoming.repaymentMethod == original.repaymentMethod) {
      incoming.repaymentMethod = current.repaymentMethod;
    }
    if (incoming.note == original.note) incoming.note = current.note;
    if (incoming.isDeleted == original.isDeleted) {
      incoming.isDeleted = current.isDeleted;
    }
  }

  static bool _isValidBudget(FinanceBudget item) {
    final balanceSnapshotAt = item.balanceSnapshotAt;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hasValidBalanceSnapshot = item.isPaymentMethod
        ? balanceSnapshotAt == null ||
              (balanceSnapshotAt > 0 &&
                  balanceSnapshotAt <= _maxDateTimeMillis &&
                  balanceSnapshotAt <= now &&
                  _isBalanceSnapshotForMonth(
                    item.monthKey,
                    balanceSnapshotAt,
                  ))
        : balanceSnapshotAt == null;
    return item.uuid.trim().isNotEmpty &&
        !(item.categoryUuid != null && item.paymentMethodUuid != null) &&
        isSafeFinanceAmountMinor(item.amountMinor) &&
        (item.isPaymentMethod ? item.amountMinor >= 0 : item.amountMinor > 0) &&
        hasValidBalanceSnapshot &&
        RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(item.monthKey);
  }

  static bool _isBalanceSnapshotForMonth(String monthKey, int snapshotAt) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(monthKey)) return false;
    final parts = monthKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final monthStart = DateTime(year, month);
    final nextMonth = DateTime(year, month + 1);
    final snapshot = DateTime.fromMillisecondsSinceEpoch(snapshotAt);
    // Snapshot timestamps do not store their source timezone. Allow the
    // maximum offset difference between devices around month boundaries.
    const timezoneDrift = Duration(hours: 28);
    return !snapshot.isBefore(monthStart.subtract(timezoneDrift)) &&
        snapshot.isBefore(nextMonth.add(timezoneDrift));
  }

  static bool _hasValidRawBalanceSnapshot(Map<String, dynamic> map) {
    final raw = map['balance_snapshot_at'] ?? map['balanceSnapshotAt'];
    if (raw == null) return true;
    final timestamp = _rawFinanceTimestampMillis(raw);
    return timestamp != null && timestamp > 0;
  }

  static Future<bool> _hasValidBudgetScope(
    DatabaseExecutor db,
    FinanceBudget budget,
  ) async {
    final categoryUuid = budget.categoryUuid;
    if (categoryUuid != null) {
      final row = await _findByUuid(db, 'finance_categories', categoryUuid);
      return row != null &&
          FinanceCategory.fromMap(row).type == FinanceCategoryType.expense;
    }
    final paymentMethodUuid = budget.paymentMethodUuid;
    if (paymentMethodUuid != null) {
      return await _findByUuid(
            db,
            'finance_payment_methods',
            paymentMethodUuid,
          ) !=
          null;
    }
    return true;
  }

  static bool _isValidRecurringRule(FinanceRecurringRule item) {
    if (item.uuid.trim().isEmpty) return false;
    try {
      _validateRecurringRule(item);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isValidTemplate(FinanceEntryTemplate item) {
    if (item.uuid.trim().isEmpty) return false;
    try {
      _validateTemplate(item);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isValidName(String value) => value.trim().isNotEmpty;

  static bool _hasValidRawFinanceName(Map<String, dynamic> map) {
    final value = map['name'];
    return value is String && value.trim().isNotEmpty;
  }

  static bool _isSystemUuid(String uuid) => uuid.startsWith('finance-system-');

  static bool _isSystemCategoryUuid(String uuid) =>
      uuid.startsWith('finance-system-category-');

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Future<Map<String, dynamic>?> _findByUuid(
    DatabaseExecutor db,
    String table,
    String uuid,
  ) async {
    final rows = await db.query(
      table,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static String _budgetScopeKey(FinanceBudget budget) {
    final scope = budget.paymentMethodUuid == null
        ? 'category:${budget.categoryUuid ?? ''}'
        : 'payment:${budget.paymentMethodUuid}';
    return '${budget.monthKey}\u0000$scope';
  }

  static Future<List<Map<String, dynamic>>> _findAllBudgetsByScope(
    DatabaseExecutor db,
    FinanceBudget budget,
  ) {
    if (budget.paymentMethodUuid != null) {
      return db.query(
        'finance_budgets',
        where: 'month_key = ? AND category_uuid IS NULL AND payment_method_uuid = ?',
        whereArgs: [budget.monthKey, budget.paymentMethodUuid],
      );
    }
    if (budget.categoryUuid == null) {
      return db.query(
        'finance_budgets',
        where: 'month_key = ? AND category_uuid IS NULL AND payment_method_uuid IS NULL',
        whereArgs: [budget.monthKey],
      );
    }
    return db.query(
      'finance_budgets',
      where:
          'month_key = ? AND category_uuid = ? AND payment_method_uuid IS NULL',
      whereArgs: [budget.monthKey, budget.categoryUuid],
    );
  }

  static Future<void> _deleteBudgetsInScope(
    DatabaseExecutor db,
    FinanceBudget budget,
  ) async {
    if (budget.paymentMethodUuid != null) {
      await db.delete(
        'finance_budgets',
        where: 'month_key = ? AND category_uuid IS NULL AND payment_method_uuid = ?',
        whereArgs: [budget.monthKey, budget.paymentMethodUuid],
      );
      return;
    }
    if (budget.categoryUuid == null) {
      await db.delete(
        'finance_budgets',
        where: 'month_key = ? AND category_uuid IS NULL AND payment_method_uuid IS NULL',
        whereArgs: [budget.monthKey],
      );
      return;
    }
    await db.delete(
      'finance_budgets',
      where:
          'month_key = ? AND category_uuid = ? AND payment_method_uuid IS NULL',
      whereArgs: [budget.monthKey, budget.categoryUuid],
    );
  }

  static Future<void> _deleteOtherBudgetsInScope(
    DatabaseExecutor db,
    FinanceBudget winner,
  ) async {
    if (winner.paymentMethodUuid != null) {
      await db.delete(
        'finance_budgets',
        where: 'month_key = ? AND category_uuid IS NULL AND payment_method_uuid = ? AND uuid != ?',
        whereArgs: [winner.monthKey, winner.paymentMethodUuid, winner.uuid],
      );
      return;
    }
    if (winner.categoryUuid == null) {
      await db.delete(
        'finance_budgets',
        where: 'month_key = ? AND category_uuid IS NULL AND payment_method_uuid IS NULL AND uuid != ?',
        whereArgs: [winner.monthKey, winner.uuid],
      );
      return;
    }
    await db.delete(
      'finance_budgets',
      where: 'month_key = ? AND category_uuid = ? AND payment_method_uuid IS NULL AND uuid != ?',
      whereArgs: [winner.monthKey, winner.categoryUuid, winner.uuid],
    );
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  static ({List<Map<String, dynamic>> maps, int invalidCount})
  _importListOfMaps(Map<String, dynamic> bundle, String key) {
    final raw = bundle[key];
    if (raw is! List) {
      return (
        maps: <Map<String, dynamic>>[],
        invalidCount: raw == null ? 0 : 1,
      );
    }

    final maps = <Map<String, dynamic>>[];
    var invalidCount = 0;
    for (final item in raw) {
      if (item is! Map) {
        invalidCount++;
        continue;
      }
      final map = <String, dynamic>{};
      var hasOnlyStringKeys = true;
      for (final entry in item.entries) {
        if (entry.key is! String) {
          hasOnlyStringKeys = false;
          break;
        }
        map[entry.key as String] = entry.value;
      }
      if (hasOnlyStringKeys) {
        maps.add(map);
      } else {
        invalidCount++;
      }
    }
    return (maps: maps, invalidCount: invalidCount);
  }

  static String? _remapNullable(
    String? value,
    String Function(String value) remap,
  ) {
    if (value == null || value.isEmpty) return value;
    if (value.startsWith('finance-system-')) return value;
    return remap(value);
  }

  static void _notifyChanged({bool requestSync = true}) {
    revision.value++;
    StorageService.triggerRefresh(const {DataRefreshDomain.finance});
    if (requestSync) unawaited(_requestSync());
  }

  static Future<void> _requestSync() async {
    final username = await StorageService.getCurrentUsername();
    if (username != null &&
        username.isNotEmpty &&
        await AppSettingsStorage.isFinanceCloudSyncEnabled(username)) {
      StorageService.requestSync(username);
    }
  }
}
