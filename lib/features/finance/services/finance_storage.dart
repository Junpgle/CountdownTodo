import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../services/database_helper.dart';
import '../../../storage_service.dart';
import '../models/finance_models.dart';

/// 记账领域的本地 SQLite 存储。
///
/// 该类不依赖用户名参数：DatabaseHelper 会根据当前登录用户打开隔离的
/// `uni_sync_<username>.db`，因此记账数据天然按账号隔离。
abstract final class FinanceStorage {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  @visibleForTesting
  static Database? databaseOverride;

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
    for (final raw in FinanceDefaults.categories) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(
        'finance_categories',
        {
          'uuid': raw['uuid'],
          'name': raw['name'],
          'type': raw['type'],
          'icon': raw['icon'],
          'is_system': 1,
          'is_archived': 0,
          'is_deleted': 0,
          'sort_order': raw['sort_order'],
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'pending_sync': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    for (final raw in FinanceDefaults.paymentMethods) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(
        'finance_payment_methods',
        {
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
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
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

  static Future<void> saveTransaction(FinanceTransaction transaction) async {
    if (transaction.amountMinor <= 0) {
      throw ArgumentError.value(
        transaction.amountMinor,
        'amountMinor',
        '金额必须大于 0',
      );
    }
    transaction.pendingSync = true;
    await ensureReady();
    final db = await _database;
    await db.insert(
      'finance_transactions',
      _localValues(transaction.toMap()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
  }

  /// 原子保存一组分期账单。
  ///
  /// 每一期都是正常的 transaction，因此月度统计、搜索、导出和同步都能
  /// 沿用现有路径；分期字段只负责把这些交易重新识别为同一组。
  static Future<List<FinanceTransaction>> saveInstallmentPlan({
    required FinanceTransaction transaction,
    required int totalAmountMinor,
    required int installmentCount,
    required DateTime startDate,
    List<FinanceTransaction> existingInstallments = const [],
  }) async {
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

    final groupUuid = transaction.installmentGroupUuid ??
        existing
            .map((item) => item.installmentGroupUuid)
            .whereType<String>()
            .firstOrNull ??
        const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final saved = <FinanceTransaction>[];
    final db = await _database;

    await db.transaction((txn) async {
      for (final allocation in allocations) {
        final old = existingByIndex[allocation.index];
        final item = FinanceTransaction(
          uuid: old?.uuid ?? (allocation.index == 1 ? transaction.uuid : null),
          type: transaction.type,
          amountMinor: allocation.amountMinor,
          currencyCode: transaction.currencyCode,
          categoryUuid: transaction.categoryUuid,
          paymentMethodUuid: transaction.paymentMethodUuid,
          transactionDate: dateKey(allocation.date),
          occurredAt: old?.occurredAt ?? transaction.occurredAt,
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
          isDeleted: false,
          version: old?.version ?? 1,
          createdAt: old?.createdAt ??
              (allocation.index == 1 ? transaction.createdAt : now),
          updatedAt: old?.updatedAt ??
              (allocation.index == 1 ? transaction.updatedAt : now),
          deviceId: transaction.deviceId,
        );
        if (old != null) item.markAsChanged();
        item.pendingSync = true;
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
        await txn.update(
          'finance_transactions',
          _localValues(old.toMap()),
          where: 'uuid = ?',
          whereArgs: [old.uuid],
        );
      }
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
    final group = await getInstallmentGroup(groupUuid);
    if (group.isEmpty) return;
    final db = await _database;
    await db.transaction((txn) async {
      for (final transaction in group) {
        transaction.isDeleted = true;
        transaction.markAsChanged();
        await txn.update(
          'finance_transactions',
          _localValues(transaction.toMap()),
          where: 'uuid = ?',
          whereArgs: [transaction.uuid],
        );
      }
    });
    _notifyChanged();
  }

  static Future<void> restoreInstallmentGroup(String groupUuid) async {
    final group = await getInstallmentGroup(
      groupUuid,
      includeDeleted: true,
    );
    final deleted = group.where((item) => item.isDeleted).toList();
    if (deleted.isEmpty) return;
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
    if (restorable.isEmpty) return;
    final db = await _database;
    await db.transaction((txn) async {
      for (final transaction in restorable) {
        transaction.isDeleted = false;
        transaction.markAsChanged();
        await txn.update(
          'finance_transactions',
          _localValues(transaction.toMap()),
          where: 'uuid = ?',
          whereArgs: [transaction.uuid],
        );
      }
    });
    _notifyChanged();
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
    final where = <String>['loan_uuid = ?'];
    if (!includeDeleted) where.add('is_deleted = 0');
    final rows = await db.query(
      'finance_loan_installments',
      where: where.join(' AND '),
      whereArgs: [loanUuid],
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
  static Future<void> saveLoan(FinanceLoan loan) async {
    _validateLoan(loan);
    await ensureReady();
    final db = await _database;
    final existing = await getLoan(loan.uuid, includeDeleted: true);
    final existingInstallments = existing == null
        ? <FinanceLoanInstallment>[]
        : await getLoanInstallments(loan.uuid, includeDeleted: true);
    final hasPaidInstallment =
        existingInstallments.any((item) => item.isPaid && !item.isDeleted);
    if (existing != null &&
        hasPaidInstallment &&
        _loanTermsDiffer(existing, loan)) {
      throw StateError('已有还款记录后不能修改本金、利率、期限或还款方式');
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
      loan.markAsChanged();
    } else {
      loan.pendingSync = true;
    }

    await db.transaction((txn) async {
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

  /// 标记一期已还或撤销已还。标记已还时只把利息写入支出账单，
  /// 本金通过贷款剩余本金体现，不重复计入消费统计。
  static Future<void> setLoanInstallmentPaid(
    String installmentUuid,
    bool paid,
  ) async {
    final installment = await getLoanInstallment(installmentUuid);
    if (installment == null || installment.isDeleted) return;
    final loan = await getLoan(installment.loanUuid);
    if (loan == null) throw StateError('关联的贷款不存在或已删除');
    if (installment.isPaid == paid) return;

    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      if (paid) {
        installment.isPaid = true;
        installment.paidAt = now;
        if (installment.interestMinor > 0 &&
            installment.interestTransactionUuid == null) {
          final interestTransaction = FinanceTransaction(
            type: FinanceTransactionType.expense,
            amountMinor: installment.interestMinor,
            currencyCode: loan.currencyCode,
            categoryUuid: 'finance-system-category-loan-interest',
            transactionDate: installment.dueDate,
            occurredAt: now,
            timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
            merchant: '贷款利息 · ${loan.name}',
            note:
                '第 ${installment.installmentIndex}/${loan.termMonths} 期利息；同步归还本金',
            source: FinanceEntrySource.automation,
            relatedTransactionUuid: installment.uuid,
            deviceId: loan.deviceId,
            pendingSync: true,
          );
          installment.interestTransactionUuid = interestTransaction.uuid;
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
            if (!interestTransaction.isDeleted) {
              interestTransaction.isDeleted = true;
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
        installment.interestTransactionUuid = null;
      }
      installment.markAsChanged();
      await txn.update(
        'finance_loan_installments',
        _localValues(installment.toMap()),
        where: 'uuid = ?',
        whereArgs: [installment.uuid],
      );
    });
    _notifyChanged();
  }

  static Future<void> deleteLoan(String uuid) async {
    final loan = await getLoan(uuid);
    if (loan == null) return;
    final installments = await getLoanInstallments(uuid, includeDeleted: true);
    loan.isDeleted = true;
    loan.markAsChanged();
    final db = await _database;
    await db.transaction((txn) async {
      await txn.update(
        'finance_loans',
        _localValues(loan.toMap()),
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      for (final installment in installments) {
        if (installment.isDeleted) continue;
        installment.isDeleted = true;
        installment.markAsChanged();
        await txn.update(
          'finance_loan_installments',
          _localValues(installment.toMap()),
          where: 'uuid = ?',
          whereArgs: [installment.uuid],
        );
      }
    });
    _notifyChanged();
  }

  static Future<void> restoreLoan(String uuid) async {
    final loan = await getLoan(uuid, includeDeleted: true);
    if (loan == null || !loan.isDeleted) return;
    final installments = await getLoanInstallments(uuid, includeDeleted: true);
    loan.isDeleted = false;
    loan.markAsChanged();
    final db = await _database;
    await db.transaction((txn) async {
      await txn.update(
        'finance_loans',
        _localValues(loan.toMap()),
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
      for (final installment in installments) {
        if (!installment.isDeleted ||
            installment.installmentIndex > loan.termMonths) {
          continue;
        }
        installment.isDeleted = false;
        installment.markAsChanged();
        await txn.update(
          'finance_loan_installments',
          _localValues(installment.toMap()),
          where: 'uuid = ?',
          whereArgs: [installment.uuid],
        );
      }
    });
    _notifyChanged();
  }

  static Future<void> deleteTransaction(String uuid) async {
    final transaction = await getTransaction(uuid);
    if (transaction == null || transaction.isDeleted) return;
    transaction.isDeleted = true;
    transaction.markAsChanged();
    await saveTransaction(transaction);
  }

  static Future<void> restoreTransaction(String uuid) async {
    final transaction = await getTransaction(uuid);
    if (transaction == null || !transaction.isDeleted) return;
    transaction.isDeleted = false;
    transaction.markAsChanged();
    await saveTransaction(transaction);
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
      where.add('is_archived = 0');
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

  static Future<void> saveCategory(FinanceCategory category) async {
    if (category.name.trim().isEmpty) {
      throw ArgumentError.value(category.name, 'name', '分类名称不能为空');
    }
    category.pendingSync = true;
    await ensureReady();
    final db = await _database;
    await db.insert(
      'finance_categories',
      _localValues(category.toMap()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
  }

  static Future<void> archiveCategory(String uuid) async {
    await ensureReady();
    final db = await _database;
    final existing = await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (existing.isEmpty) return;
    final category = FinanceCategory.fromMap(existing.first);
    if (category.isSystem || category.isArchived) return;
    category.isArchived = true;
    category.markAsChanged();
    await db.update(
      'finance_categories',
      _localValues(category.toMap()),
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    _notifyChanged();
  }

  static Future<void> unarchiveCategory(String uuid) async {
    await ensureReady();
    final db = await _database;
    final existing = await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (existing.isEmpty) return;
    final category = FinanceCategory.fromMap(existing.first);
    if (!category.isArchived) return;
    category.isArchived = false;
    category.markAsChanged();
    await db.update(
      'finance_categories',
      _localValues(category.toMap()),
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    _notifyChanged();
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

  static Future<void> savePaymentMethod(FinancePaymentMethod method) async {
    if (method.name.trim().isEmpty) {
      throw ArgumentError.value(method.name, 'name', '付款方式名称不能为空');
    }
    method.pendingSync = true;
    await ensureReady();
    final db = await _database;
    await db.insert(
      'finance_payment_methods',
      _localValues(method.toMap()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
  }

  static Future<void> archivePaymentMethod(String uuid) async {
    await ensureReady();
    final db = await _database;
    final existing = await db.query(
      'finance_payment_methods',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (existing.isEmpty) return;
    final method = FinancePaymentMethod.fromMap(existing.first);
    if (method.isSystem || method.isArchived) return;
    method.isArchived = true;
    method.markAsChanged();
    await db.update(
      'finance_payment_methods',
      _localValues(method.toMap()),
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    _notifyChanged();
  }

  static Future<void> unarchivePaymentMethod(String uuid) async {
    await ensureReady();
    final db = await _database;
    final existing = await db.query(
      'finance_payment_methods',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (existing.isEmpty) return;
    final method = FinancePaymentMethod.fromMap(existing.first);
    if (!method.isArchived) return;
    method.isArchived = false;
    method.markAsChanged();
    await db.update(
      'finance_payment_methods',
      _localValues(method.toMap()),
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    _notifyChanged();
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
      orderBy: 'CASE WHEN category_uuid IS NULL THEN 0 ELSE 1 END, '
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

  static Future<void> saveBudget(FinanceBudget budget) async {
    if (budget.amountMinor <= 0) {
      throw ArgumentError.value(
        budget.amountMinor,
        'amountMinor',
        '预算金额必须大于 0',
      );
    }
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(budget.monthKey)) {
      throw ArgumentError.value(budget.monthKey, 'monthKey', '月份格式无效');
    }
    budget.pendingSync = true;
    await ensureReady();
    final db = await _database;
    final where = <String>[
      'month_key = ?',
      'is_deleted = 0',
      'uuid != ?',
    ];
    final args = <Object?>[budget.monthKey, budget.uuid];
    if (budget.categoryUuid == null) {
      where.add('category_uuid IS NULL');
    } else {
      where.add('category_uuid = ?');
      args.add(budget.categoryUuid);
    }
    final duplicates = await db.query(
      'finance_budgets',
      columns: ['uuid'],
      where: where.join(' AND '),
      whereArgs: args,
      limit: 1,
    );
    if (duplicates.isNotEmpty) {
      throw StateError('该月份的预算范围已经存在');
    }
    await db.insert(
      'finance_budgets',
      _localValues(budget.toMap()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
  }

  static Future<void> deleteBudget(String uuid) async {
    final budget = await getBudget(uuid);
    if (budget == null || budget.isDeleted) return;
    budget.isDeleted = true;
    budget.markAsChanged();
    await saveBudget(budget);
  }

  static Future<void> restoreBudget(String uuid) async {
    final budget = await getBudget(uuid);
    if (budget == null || !budget.isDeleted) return;
    budget.isDeleted = false;
    budget.markAsChanged();
    await saveBudget(budget);
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

  static Future<void> saveRecurringRule(FinanceRecurringRule rule) async {
    _validateRecurringRule(rule);
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
      if (existingRows.isNotEmpty) {
        final existing = FinanceRecurringRule.fromMap(existingRows.first);
        // 生成标记是幂等状态，不属于编辑表单的可回退字段。编辑页或
        // 并发请求拿到旧快照时，不能把已生成的较新周期覆盖掉。
        final latestPeriod = _latestGeneratedPeriod(
          existing.lastGeneratedPeriod,
          rule.lastGeneratedPeriod,
        );
        if (latestPeriod != rule.lastGeneratedPeriod) {
          rule.lastGeneratedPeriod = latestPeriod;
        }
      }
      await txn.insert(
        'finance_recurring_rules',
        _localValues(rule.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _notifyChanged();
  }

  static Future<void> deleteRecurringRule(String uuid) async {
    final rule = await getRecurringRule(uuid);
    if (rule == null || rule.isDeleted) return;
    rule.isDeleted = true;
    rule.isEnabled = false;
    rule.markAsChanged();
    await saveRecurringRule(rule);
  }

  static Future<void> restoreRecurringRule(String uuid) async {
    final rule = await getRecurringRule(uuid);
    if (rule == null || !rule.isDeleted) return;
    rule.isDeleted = false;
    rule.isEnabled = true;
    rule.markAsChanged();
    await saveRecurringRule(rule);
  }

  static Future<void> setRecurringRuleEnabled(
    String uuid,
    bool enabled,
  ) async {
    final rule = await getRecurringRule(uuid);
    if (rule == null || rule.isDeleted || rule.isEnabled == enabled) return;
    rule.isEnabled = enabled;
    rule.markAsChanged();
    await saveRecurringRule(rule);
  }

  static Future<bool> materializeRecurringRule(
    FinanceRecurringRule rule, {
    required DateTime dueAt,
    required String periodKey,
  }) async {
    if (periodKey.trim().isEmpty) return false;
    await ensureReady();
    final db = await _database;
    final generated = await db.transaction<bool>((txn) async {
      final rows = await txn.query(
        'finance_recurring_rules',
        where: 'uuid = ?',
        whereArgs: [rule.uuid],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final current = FinanceRecurringRule.fromMap(rows.first);
      if (current.isDeleted ||
          !current.isEnabled ||
          current.lastGeneratedPeriod == periodKey) {
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
        current.lastGeneratedPeriod = periodKey;
        current.markAsChanged();
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

      current.lastGeneratedPeriod = periodKey;
      current.markAsChanged();
      await txn.update(
        'finance_recurring_rules',
        _localValues(current.toMap()),
        where: 'uuid = ?',
        whereArgs: [current.uuid],
      );
      return true;
    });
    if (generated) _notifyChanged();
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
      orderBy: 'use_count DESC, last_used_at DESC, updated_at DESC, '
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

  static Future<void> saveTemplate(FinanceEntryTemplate template) async {
    _validateTemplate(template);
    template.pendingSync = true;
    await ensureReady();
    final db = await _database;
    await db.insert(
      'finance_entry_templates',
      _localValues(template.toMap()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
  }

  static Future<void> deleteTemplate(String uuid) async {
    final template = await getTemplate(uuid);
    if (template == null || template.isDeleted) return;
    template.isDeleted = true;
    template.markAsChanged();
    await saveTemplate(template);
  }

  static Future<void> restoreTemplate(String uuid) async {
    final template = await getTemplate(uuid);
    if (template == null || !template.isDeleted) return;
    template.isDeleted = false;
    template.markAsChanged();
    await saveTemplate(template);
  }

  static Future<void> markTemplateUsed(String uuid) async {
    final template = await getTemplate(uuid);
    if (template == null || template.isDeleted) return;
    template.useCount++;
    template.lastUsedAt = DateTime.now().millisecondsSinceEpoch;
    template.markAsChanged();
    await saveTemplate(template);
  }

  static void _validateRecurringRule(FinanceRecurringRule rule) {
    if (rule.name.trim().isEmpty) {
      throw ArgumentError.value(rule.name, 'name', '周期账单名称不能为空');
    }
    if (rule.type == FinanceTransactionType.refund) {
      throw ArgumentError.value(rule.type, 'type', '周期规则不支持退款类型');
    }
    if (rule.amountMinor <= 0) {
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
          rule.dayOfMonth, 'dayOfMonth', '日期必须在 1 到 31 之间');
    }
    if (rule.frequency == FinanceRecurringFrequency.yearly &&
        (rule.monthOfYear < 1 || rule.monthOfYear > 12)) {
      throw ArgumentError.value(
          rule.monthOfYear, 'monthOfYear', '月份必须在 1 到 12 之间');
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
    if (template.amountMinor <= 0) {
      throw ArgumentError.value(
          template.amountMinor, 'amountMinor', '金额必须大于 0');
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
    var income = 0;
    var expense = 0;
    var refund = 0;
    final expenseByCategory = <String, int>{};
    final incomeByCategory = <String, int>{};
    final expenseByDate = <String, int>{};

    for (final transaction in transactions) {
      final categoryUuid = transaction.categoryUuid ?? '';
      switch (transaction.type) {
        case FinanceTransactionType.income:
          income += transaction.amountMinor;
          incomeByCategory[categoryUuid] =
              (incomeByCategory[categoryUuid] ?? 0) + transaction.amountMinor;
        case FinanceTransactionType.expense:
          expense += transaction.amountMinor;
          expenseByCategory[categoryUuid] =
              (expenseByCategory[categoryUuid] ?? 0) + transaction.amountMinor;
          expenseByDate[transaction.transactionDate] =
              (expenseByDate[transaction.transactionDate] ?? 0) +
                  transaction.amountMinor;
        case FinanceTransactionType.refund:
          refund += transaction.amountMinor;
          expenseByCategory[categoryUuid] =
              (expenseByCategory[categoryUuid] ?? 0) - transaction.amountMinor;
          expenseByDate[transaction.transactionDate] =
              (expenseByDate[transaction.transactionDate] ?? 0) -
                  transaction.amountMinor;
      }
    }

    return FinanceSummary(
      incomeMinor: income,
      expenseMinor: expense,
      refundMinor: refund,
      transactionCount: transactions.length,
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
      expenseByDate: expenseByDate,
    );
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

  /// 导入 JSON 备份中的记账数据。所有记录仍然写入当前用户的本地库，
  /// 不携带团队归属，也不会写入同步操作日志。
  static Future<Map<String, int>> importBundle(
    Map<String, dynamic> bundle, {
    String Function(String value)? remapUuid,
  }) async {
    await ensureReady();
    final db = await _database;
    final remap = remapUuid ?? (value) => value;
    var imported = 0;
    var skipped = 0;
    var updated = 0;

    final categoryMaps = _listOfMaps(bundle['categories']);
    for (final map in categoryMaps) {
      final item = FinanceCategory.fromMap(map);
      final oldUuid = item.uuid;
      item.uuid = item.isSystem ? oldUuid : remap(oldUuid);
      item.parentUuid = _remapNullable(item.parentUuid, remap);
      if (item.isSystem) {
        item.isArchived = false;
        item.isDeleted = false;
      }
      final existing = await _findByUuid(
        db,
        'finance_categories',
        item.uuid,
      );
      if (existing == null) {
        await db.insert(
          'finance_categories',
          item.isSystem
              ? _remoteValues(item.toMap())
              : _localValues(item.toMap()),
        );
        imported++;
      } else if (item.updatedAt > FinanceCategory.fromMap(existing).updatedAt) {
        await db.update(
          'finance_categories',
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

    final paymentMaps = _listOfMaps(bundle['payment_methods']);
    for (final map in paymentMaps) {
      final item = FinancePaymentMethod.fromMap(map);
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

    final recurringRuleMaps = _listOfMaps(bundle['recurring_rules']);
    for (final map in recurringRuleMaps) {
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
        await db.insert(
          'finance_recurring_rules',
          _localValues(item.toMap()),
        );
        imported++;
      } else if (item.updatedAt >
          FinanceRecurringRule.fromMap(existing).updatedAt) {
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

    final templateMaps = _listOfMaps(bundle['templates']);
    for (final map in templateMaps) {
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
        await db.insert(
          'finance_entry_templates',
          _localValues(item.toMap()),
        );
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

    final transactionMaps = _listOfMaps(bundle['transactions']);
    for (final map in transactionMaps) {
      final item = FinanceTransaction.fromMap(map);
      item.uuid = remap(item.uuid);
      item.categoryUuid = _remapNullable(item.categoryUuid, remap);
      item.paymentMethodUuid = _remapNullable(item.paymentMethodUuid, remap);
      item.relatedTransactionUuid =
          _remapNullable(item.relatedTransactionUuid, remap);
      item.relatedTodoUuid = _remapNullable(item.relatedTodoUuid, remap);
      item.relatedPlanBlockUuid =
          _remapNullable(item.relatedPlanBlockUuid, remap);
      item.installmentGroupUuid =
          _remapNullable(item.installmentGroupUuid, remap);
      item.source = FinanceEntrySource.import;
      final existing = await _findByUuid(
        db,
        'finance_transactions',
        item.uuid,
      );
      if (existing == null) {
        await db.insert(
          'finance_transactions',
          _localValues(item.toMap()),
        );
        imported++;
      } else if (item.updatedAt >
          FinanceTransaction.fromMap(existing).updatedAt) {
        await db.update(
          'finance_transactions',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      } else {
        skipped++;
      }
    }

    final budgetMaps = _listOfMaps(bundle['budgets']);
    for (final map in budgetMaps) {
      final item = FinanceBudget.fromMap(map);
      item.uuid = remap(item.uuid);
      item.categoryUuid = _remapNullable(item.categoryUuid, remap);
      item.amountMinor = item.amountMinor.abs();
      if (item.amountMinor <= 0 ||
          !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(item.monthKey)) {
        skipped++;
        continue;
      }
      final existing = await _findByUuid(db, 'finance_budgets', item.uuid);
      final existingScope =
          existing == null ? await _findBudgetByScope(db, item) : null;
      if (existing == null && existingScope != null) {
        final current = FinanceBudget.fromMap(existingScope);
        if (item.updatedAt <= current.updatedAt) {
          skipped++;
          continue;
        }
        item.uuid = current.uuid;
        await db.update(
          'finance_budgets',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [current.uuid],
        );
        updated++;
      } else if (existing == null) {
        await db.insert(
          'finance_budgets',
          _localValues(item.toMap()),
        );
        imported++;
      } else if (item.updatedAt > FinanceBudget.fromMap(existing).updatedAt) {
        await db.update(
          'finance_budgets',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      } else {
        skipped++;
      }
    }

    final loanMaps = _listOfMaps(bundle['loans']);
    for (final map in loanMaps) {
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
      } else if (item.updatedAt > FinanceLoan.fromMap(existing).updatedAt) {
        await db.update(
          'finance_loans',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      } else {
        skipped++;
      }
    }

    final loanInstallmentMaps = _listOfMaps(bundle['loan_installments']);
    for (final map in loanInstallmentMaps) {
      final item = FinanceLoanInstallment.fromMap(map);
      item.uuid = remap(item.uuid);
      item.loanUuid = remap(item.loanUuid);
      item.interestTransactionUuid = _remapNullable(
        item.interestTransactionUuid,
        remap,
      );
      if (!_isValidLoanInstallment(item)) {
        skipped++;
        continue;
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
      } else if (item.updatedAt >
          FinanceLoanInstallment.fromMap(existing).updatedAt) {
        await db.update(
          'finance_loan_installments',
          _localValues(item.toMap()),
          where: 'uuid = ?',
          whereArgs: [item.uuid],
        );
        updated++;
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) _notifyChanged();
    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  /// 将服务端返回的个人记账快照按 updated_at/version 合并到本地。
  ///
  /// 记账没有通用 op_logs，因此同步源必须使用一笔 SQLite 事务完成整批
  /// upsert。系统分类和付款方式是客户端稳定默认数据，永远不接受云端覆盖。
  static Future<int> mergeRemoteBundle(
    Map<String, dynamic> bundle, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    await ensureReady();
    final categories = _listOfMaps(bundle['categories'])
        .map(FinanceCategory.fromMap)
        .where((item) =>
            !item.isSystem &&
            !_isSystemUuid(item.uuid) &&
            _isValidName(item.name))
        .toList(growable: false);
    final paymentMethods = _listOfMaps(bundle['payment_methods'])
        .map(FinancePaymentMethod.fromMap)
        .where((item) =>
            !item.isSystem &&
            !_isSystemUuid(item.uuid) &&
            _isValidName(item.name))
        .toList(growable: false);
    final transactions = _listOfMaps(bundle['transactions'])
        .map(FinanceTransaction.fromMap)
        .where(_isValidTransaction)
        .toList(growable: false);
    final budgets = _listOfMaps(bundle['budgets'])
        .map(FinanceBudget.fromMap)
        .where(_isValidBudget)
        .toList(growable: false);
    final recurringRules = _listOfMaps(bundle['recurring_rules'])
        .map(FinanceRecurringRule.fromMap)
        .where(_isValidRecurringRule)
        .toList(growable: false);
    final templates = _listOfMaps(bundle['templates'])
        .map(FinanceEntryTemplate.fromMap)
        .where(_isValidTemplate)
        .toList(growable: false);
    final loans = _listOfMaps(bundle['loans'])
        .map(FinanceLoan.fromMap)
        .where(_isValidLoan)
        .toList(growable: false);
    final loanInstallments = _listOfMaps(bundle['loan_installments'])
        .map(FinanceLoanInstallment.fromMap)
        .where(_isValidLoanInstallment)
        .toList(growable: false);

    final db = await _database;
    var changed = 0;
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
      changed += await _mergeRecurringRules(
        txn,
        recurringRules,
        forceRemoteKeys: forceRemoteKeys,
      );
      changed += await _mergeTemplates(
        txn,
        templates,
        forceRemoteKeys: forceRemoteKeys,
      );
    });
    if (changed > 0) _notifyChanged(requestSync: false);
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
    const sectionByTableKey = <String, String>{
      'categories': 'finance_categories_changes',
      'payment_methods': 'finance_payment_methods_changes',
      'transactions': 'finance_transactions_changes',
      'loans': 'finance_loans_changes',
      'loan_installments': 'finance_loan_installments_changes',
      'budgets': 'finance_budgets_changes',
      'recurring_rules': 'finance_recurring_rules_changes',
      'templates': 'finance_entry_templates_changes',
    };
    final requestedByKey = <String, Map<String, dynamic>>{};
    for (final entry in sectionByTableKey.entries) {
      final raw = requestPayload[entry.value];
      if (raw is! List) continue;
      for (final value in raw.whereType<Map>()) {
        final item = Map<String, dynamic>.from(value);
        final uuid = item['uuid']?.toString() ?? item['id']?.toString() ?? '';
        if (uuid.isNotEmpty) {
          requestedByKey['${entry.value}:$uuid'] = item;
        }
      }
    }

    final db = await _database;
    var acknowledged = 0;
    await db.transaction((txn) async {
      for (final value in acknowledgements.whereType<Map>()) {
        final tableKey = value['table']?.toString() ?? '';
        final table = tableByKey[tableKey];
        final section = sectionByTableKey[tableKey];
        if (table == null || section == null) continue;
        final uuid = value['uuid']?.toString() ?? value['id']?.toString() ?? '';
        if (uuid.isEmpty) continue;
        final requested = requestedByKey['$section:$uuid'];
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
          where:
              'uuid = ? AND pending_sync = 1 AND updated_at = ? AND version = ?',
          whereArgs: [uuid, requestedUpdatedAt, requestedVersion],
        );
        acknowledged += count;
      }
    });
    return acknowledged;
  }

  static Future<int> _mergeCategories(
    DatabaseExecutor db,
    List<FinanceCategory> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    var changed = 0;
    for (final item in items) {
      final existing = await _findByUuid(db, 'finance_categories', item.uuid);
      if (existing == null) {
        await db.insert('finance_categories', _remoteValues(item.toMap()));
        changed++;
        continue;
      }
      final current = FinanceCategory.fromMap(existing);
      if (!forceRemoteKeys.contains('categories:${item.uuid}') &&
          !_isIncomingWinner(item.updatedAt, item.version, current.updatedAt,
              current.version)) {
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
      final existing =
          await _findByUuid(db, 'finance_payment_methods', item.uuid);
      if (existing == null) {
        await db.insert(
          'finance_payment_methods',
          _remoteValues(item.toMap()),
        );
        changed++;
        continue;
      }
      final current = FinancePaymentMethod.fromMap(existing);
      if (!forceRemoteKeys.contains('payment_methods:${item.uuid}') &&
          !_isIncomingWinner(item.updatedAt, item.version, current.updatedAt,
              current.version)) {
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
  }) async {
    var changed = 0;
    for (final item in items) {
      final existing = await _findByUuid(db, 'finance_transactions', item.uuid);
      if (existing == null) {
        await db.insert(
          'finance_transactions',
          _remoteValues(item.toMap()),
        );
        changed++;
        continue;
      }
      final current = FinanceTransaction.fromMap(existing);
      if (!forceRemoteKeys.contains('transactions:${item.uuid}') &&
          !_isIncomingWinner(item.updatedAt, item.version, current.updatedAt,
              current.version)) {
        continue;
      }
      await db.update(
        'finance_transactions',
        _remoteValues(item.toMap()),
        where: 'uuid = ?',
        whereArgs: [item.uuid],
      );
      changed++;
    }
    return changed;
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
    for (final item in items) {
      final existing =
          await _findByUuid(db, 'finance_loan_installments', item.uuid);
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
      final existing = await _findByUuid(db, 'finance_budgets', item.uuid);
      if (existing == null) {
        await db.insert('finance_budgets', _remoteValues(item.toMap()));
        changed++;
        continue;
      }
      final current = FinanceBudget.fromMap(existing);
      if (!forceRemoteKeys.contains('budgets:${item.uuid}') &&
          !_isIncomingWinner(item.updatedAt, item.version, current.updatedAt,
              current.version)) {
        continue;
      }
      await db.update(
        'finance_budgets',
        _remoteValues(item.toMap()),
        where: 'uuid = ?',
        whereArgs: [item.uuid],
      );
      changed++;
    }
    return changed;
  }

  static Future<int> _mergeRecurringRules(
    DatabaseExecutor db,
    List<FinanceRecurringRule> items, {
    Set<String> forceRemoteKeys = const {},
  }) async {
    var changed = 0;
    for (final item in items) {
      final existing =
          await _findByUuid(db, 'finance_recurring_rules', item.uuid);
      if (existing == null) {
        await db.insert(
          'finance_recurring_rules',
          _remoteValues(item.toMap()),
        );
        changed++;
        continue;
      }
      final current = FinanceRecurringRule.fromMap(existing);
      if (!forceRemoteKeys.contains('recurring_rules:${item.uuid}') &&
          !_isIncomingWinner(item.updatedAt, item.version, current.updatedAt,
              current.version)) {
        continue;
      }
      final latestPeriod = _latestGeneratedPeriod(
        current.lastGeneratedPeriod,
        item.lastGeneratedPeriod,
      );
      if (latestPeriod != item.lastGeneratedPeriod) {
        // 服务端/旧设备返回的编辑快照可能带着较旧的运行时生成标记；
        // 该标记只能向前保留，否则下一次调度会把同一周期再次记账。
        item.lastGeneratedPeriod = latestPeriod;
      }
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
      final existing =
          await _findByUuid(db, 'finance_entry_templates', item.uuid);
      if (existing == null) {
        await db.insert(
          'finance_entry_templates',
          _remoteValues(item.toMap()),
        );
        changed++;
        continue;
      }
      final current = FinanceEntryTemplate.fromMap(existing);
      if (!forceRemoteKeys.contains('templates:${item.uuid}') &&
          !_isIncomingWinner(item.updatedAt, item.version, current.updatedAt,
              current.version)) {
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
        item.amountMinor > 0 &&
        _isDateKey(item.transactionDate);
  }

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
    return item.uuid.trim().isNotEmpty &&
        item.loanUuid.trim().isNotEmpty &&
        item.installmentIndex > 0 &&
        _isDateKey(item.dueDate) &&
        item.paymentMinor > 0 &&
        item.principalMinor > 0 &&
        item.interestMinor >= 0 &&
        item.paymentMinor == item.principalMinor + item.interestMinor &&
        item.remainingPrincipalMinor >= 0;
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

  static bool _isValidBudget(FinanceBudget item) {
    return item.uuid.trim().isNotEmpty &&
        item.amountMinor > 0 &&
        RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(item.monthKey);
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

  static bool _isSystemUuid(String uuid) => uuid.startsWith('finance-system-');

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

  static Future<Map<String, dynamic>?> _findBudgetByScope(
    DatabaseExecutor db,
    FinanceBudget budget,
  ) async {
    final where = <String>['month_key = ?', 'is_deleted = 0'];
    final args = <Object?>[budget.monthKey];
    if (budget.categoryUuid == null) {
      where.add('category_uuid IS NULL');
    } else {
      where.add('category_uuid = ?');
      args.add(budget.categoryUuid);
    }
    final rows = await db.query(
      'finance_budgets',
      where: where.join(' AND '),
      whereArgs: args,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
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
    if (username != null && username.isNotEmpty) {
      StorageService.requestSync(username);
    }
  }
}
