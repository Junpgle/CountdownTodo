part of '../finance_storage.dart';

Future<List<FinanceLoan>> _getLoans({bool includeDeleted = false}) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final rows = await db.query(
    'finance_loans',
    where: includeDeleted ? null : 'is_deleted = 0',
    orderBy: 'start_date DESC, updated_at DESC',
  );
  return rows.map(FinanceLoan.fromMap).toList();
}

Future<FinanceLoan?> _getLoan(
  String uuid, {
  bool includeDeleted = false,
}) async {
  await FinanceStorage.ensureReady();
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

Future<List<FinanceLoanInstallment>> _getLoanInstallments(
  String loanUuid, {
  bool includeDeleted = false,
  String? fromDueDate,
  String? toDueDate,
}) async {
  await FinanceStorage.ensureReady();
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
  if (fromDueDate != null) {
    where.add('due_date >= ?');
    args.add(fromDueDate);
  }
  if (toDueDate != null) {
    where.add('due_date < ?');
    args.add(toDueDate);
  }
  final rows = await db.query(
    'finance_loan_installments',
    where: where.join(' AND '),
    whereArgs: args,
    orderBy: 'installment_index ASC, due_date ASC',
  );
  return rows.map(FinanceLoanInstallment.fromMap).toList();
}

/// Loads scheduled installments for all active loans with one indexed join.
/// The term bound matches [getLoanInstallments]' default behavior.
Future<Map<String, List<FinanceLoanInstallment>>>
_getLoanInstallmentsForActiveLoans({
  String? fromDueDate,
  String? toDueDate,
}) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final where = <String>[
    'loan.is_deleted = 0',
    'installment.is_deleted = 0',
    'installment.installment_index <= loan.term_months',
  ];
  final args = <Object?>[];
  if (fromDueDate != null) {
    where.add('installment.due_date >= ?');
    args.add(fromDueDate);
  }
  if (toDueDate != null) {
    where.add('installment.due_date < ?');
    args.add(toDueDate);
  }
  final rows = await db.rawQuery('''
    SELECT installment.*
    FROM finance_loan_installments AS installment
    JOIN finance_loans AS loan ON loan.uuid = installment.loan_uuid
    WHERE ${where.join(' AND ')}
    ORDER BY installment.loan_uuid ASC,
      installment.installment_index ASC,
      installment.due_date ASC
  ''', args);
  final installmentsByLoan = <String, List<FinanceLoanInstallment>>{};
  for (final row in rows) {
    final installment = FinanceLoanInstallment.fromMap(row);
    installmentsByLoan
        .putIfAbsent(installment.loanUuid, () => <FinanceLoanInstallment>[])
        .add(installment);
  }
  return installmentsByLoan;
}

Future<FinanceLoanInstallment?> _getLoanInstallment(
  String uuid, {
  bool includeDeleted = false,
}) async {
  await FinanceStorage.ensureReady();
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
Future<void> _saveLoan(FinanceLoan loan, {FinanceLoan? original}) async {
  _validateLoan(loan);
  if (original != null && original.uuid != loan.uuid) {
    throw ArgumentError.value(original.uuid, 'original', '贷款标识不匹配');
  }
  await FinanceStorage.ensureReady();
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
Future<List<FinanceLoanInstallment>> _getPaidLoanInstallments() async {
  await FinanceStorage.ensureReady();
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
Future<FinanceLoanInstallment?> _getRepaymentForInterestTransaction(
  String transactionUuid,
) async {
  await FinanceStorage.ensureReady();
  return _findRepaymentForInterestTransaction(await _database, transactionUuid);
}

Future<FinanceLoanInstallment?> _findRepaymentForInterestTransaction(
  DatabaseExecutor db,
  String transactionUuid,
) async {
  final rows = await db.rawQuery(
    '''
    SELECT installment.* FROM finance_loan_installments AS installment
    WHERE installment.interest_transaction_uuid = ?
      OR installment.uuid = (
        SELECT related_transaction_uuid FROM finance_transactions WHERE uuid = ?
      )
    ORDER BY CASE WHEN installment.interest_transaction_uuid = ? THEN 0 ELSE 1 END
    LIMIT 1
  ''',
    [transactionUuid, transactionUuid, transactionUuid],
  );
  return rows.isEmpty ? null : FinanceLoanInstallment.fromMap(rows.single);
}

Future<void> _validateLoanInterestEdit(
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

Future<void> _validateInstallmentRestore(
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
Future<void> _setLoanInstallmentPaid(
  String installmentUuid,
  bool paid, {
  String? paymentMethodUuid,
  DateTime? paidAt,
}) async {
  await FinanceStorage.ensureReady();
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
      if (dateKey(paymentDate).compareTo(loan.startDate) < 0) {
        throw ArgumentError('还款时间不能早于贷款借款日期');
      }
      final methodUuid = paymentMethodUuid?.trim();
      if (methodUuid != null && methodUuid.isNotEmpty) {
        final method = await _findByUuid(
          txn,
          'finance_payment_methods',
          methodUuid,
        );
        if (method == null || FinancePaymentMethod.fromMap(method).isDeleted) {
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
        final loanRows = await txn.query(
          'finance_loans',
          where: 'is_deleted = 0',
        );
        final loanDisplayName = financeLoanDisplayName(
          loan,
          loanRows.map(FinanceLoan.fromMap),
        );
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
                merchant: '贷款利息 · $loanDisplayName',
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
            ..merchant = '贷款利息 · $loanDisplayName'
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

String _loanInterestTransactionUuid(String installmentUuid) {
  return const Uuid().v5(
    '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
    'countdown-todo/finance-loan-interest/v1/$installmentUuid',
  );
}

Future<void> _deleteLoan(String uuid) async {
  await _setLoanDeleted(uuid, true);
}

Future<void> _restoreLoan(String uuid) async {
  await _setLoanDeleted(uuid, false);
}

Future<List<FinanceLoanInstallment>> _loanInstallmentsInTransaction(
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

Future<void> _setLoanDeleted(String uuid, bool deleted) async {
  await FinanceStorage.ensureReady();
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
