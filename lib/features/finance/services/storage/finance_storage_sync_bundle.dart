part of '../finance_storage.dart';

Future<Map<String, dynamic>> _getExportBundle() async {
  await FinanceStorage.ensureReady();
  final transactions = await FinanceStorage.getTransactions(
    includeDeleted: true,
  );
  final categories = await FinanceStorage.getCategories(
    includeArchived: true,
    includeDeleted: true,
  );
  final paymentMethods = await FinanceStorage.getPaymentMethods(
    includeArchived: true,
    includeDeleted: true,
  );
  final budgets = await FinanceStorage.getBudgets(includeDeleted: true);
  final recurringRules = await FinanceStorage.getRecurringRules(
    includeDeleted: true,
  );
  final templates = await FinanceStorage.getTemplates(includeDeleted: true);
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

void _removeDeviceIdsFromExportBundle(Map<String, dynamic> bundle) {
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
Future<Map<String, int>> _importBundle(
  Map<String, dynamic> bundle, {
  String Function(String value)? remapUuid,
}) async {
  await FinanceStorage.ensureReady();
  final database = await _database;
  final result = await database.transaction(
    (txn) => _importBundleInTransaction(txn, bundle, remapUuid: remapUuid),
  );
  final incomingTransactions = bundle['transactions'];
  final repairedLegacyRefunds = _hasIncomingRefund(incomingTransactions)
      ? await _repairLegacyRefundCategories(database)
      : 0;
  if ((result['imported'] ?? 0) > 0 ||
      (result['updated'] ?? 0) > 0 ||
      repairedLegacyRefunds > 0) {
    _notifyChanged();
  }
  return result;
}

Future<Map<String, int>> _importBundleInTransaction(
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
      if (existing == null || (!item.iconCustomized && !item.nameCustomized)) {
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
      return _transactionMergePriority(
        FinanceTransaction.fromMap(left),
      ).compareTo(_transactionMergePriority(FinanceTransaction.fromMap(right)));
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
        : _latestBudgetsByScope(scopeRows.map(FinanceBudget.fromMap).toList())
              .single;
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
    if (current != null) {
      _preserveBalanceSnapshotForUnchangedAmount(item, current);
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
        !_hasSafeRawFinanceAmount(map, 'principal_minor', 'principalMinor') ||
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

  final loanInstallmentInput = _importListOfMaps(bundle, 'loan_installments');
  skipped += loanInstallmentInput.invalidCount;
  final loanInstallmentMaps = loanInstallmentInput.maps
    ..sort(_compareRawLoanInstallmentMaps);
  final seenActiveLoanInstallments = <String>{};
  final loanScheduleCache = <String, List<FinanceLoanScheduleAllocation>>{};
  final loadedLoanInstallmentSchedules = <String>{};
  final activeInstallmentUuidsByLoanAndIndex =
      <String, Map<num, Set<Object?>>>{};
  void removeCachedActiveInstallment(FinanceLoanInstallment installment) {
    final byIndex = activeInstallmentUuidsByLoanAndIndex[installment.loanUuid];
    final uuids = byIndex?[installment.installmentIndex];
    uuids?.remove(installment.uuid);
    if (uuids?.isEmpty == true) {
      byIndex?.remove(installment.installmentIndex);
    }
  }

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
    item.paymentMethodUuid = _remapNullable(item.paymentMethodUuid, remap);
    if (!_isValidLoanInstallment(item)) {
      skipped++;
      continue;
    }
    final parentLoan = await _findByUuid(db, 'finance_loans', item.loanUuid);
    final loan = parentLoan == null ? null : FinanceLoan.fromMap(parentLoan);
    if (loan == null ||
        (loan.isDeleted && !item.isDeleted) ||
        (!item.isDeleted &&
            !_matchesLoanInstallmentSchedule(loan, item, loanScheduleCache))) {
      skipped++;
      continue;
    }
    final scheduleKey = '${item.loanUuid}\u0000${item.installmentIndex}';
    if (!item.isDeleted && !seenActiveLoanInstallments.add(scheduleKey)) {
      skipped++;
      continue;
    }
    if (!item.isDeleted) {
      if (loadedLoanInstallmentSchedules.add(item.loanUuid)) {
        final existingSchedules = await db.query(
          'finance_loan_installments',
          columns: ['uuid', 'installment_index'],
          where: 'loan_uuid = ? AND is_deleted = 0',
          whereArgs: [item.loanUuid],
        );
        final byIndex = activeInstallmentUuidsByLoanAndIndex.putIfAbsent(
          item.loanUuid,
          () => <num, Set<Object?>>{},
        );
        for (final row in existingSchedules) {
          final index = row['installment_index'];
          if (index is! num) continue;
          (byIndex[index] ??= <Object?>{}).add(row['uuid']);
        }
      }
      final duplicateUuids =
          activeInstallmentUuidsByLoanAndIndex[item.loanUuid]?[item
              .installmentIndex];
      if (duplicateUuids?.any((uuid) => uuid != item.uuid) ?? false) {
        skipped++;
        continue;
      }
    }
    final existing = await _findByUuid(
      db,
      'finance_loan_installments',
      item.uuid,
    );
    FinanceLoanInstallment? currentForSchedule;
    if (existing == null) {
      await db.insert('finance_loan_installments', _localValues(item.toMap()));
      imported++;
    } else {
      final current = FinanceLoanInstallment.fromMap(existing);
      currentForSchedule = current;
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
    if (currentForSchedule != null &&
        !currentForSchedule.isDeleted &&
        loadedLoanInstallmentSchedules.contains(currentForSchedule.loanUuid)) {
      removeCachedActiveInstallment(currentForSchedule);
    }
    if (!item.isDeleted &&
        loadedLoanInstallmentSchedules.contains(item.loanUuid)) {
      final byIndex = activeInstallmentUuidsByLoanAndIndex.putIfAbsent(
        item.loanUuid,
        () => <num, Set<Object?>>{},
      );
      (byIndex[item.installmentIndex] ??= <Object?>{}).add(item.uuid);
    }
  }

  return {'imported': imported, 'skipped': skipped, 'updated': updated};
}

/// 将服务端返回的个人记账快照按 updated_at/version 合并到本地。
///
/// 记账没有通用 op_logs，因此同步源必须使用一笔 SQLite 事务完成整批
/// upsert。系统分类的类型/层级仍由客户端内置定义，用户自定义名称和
/// 图标则作为个人覆盖项接受云端合并；系统付款方式仍保持本地默认。
Future<int> _mergeRemoteBundle(
  Map<String, dynamic> bundle, {
  Set<String> forceRemoteKeys = const {},
  Set<String>? deferredTransactionUuids,
  Set<String>? changedSections,
}) async {
  await FinanceStorage.ensureReady();
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
          return item.isSystem && (item.iconCustomized || item.nameCustomized);
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
            _isSafeRawFinanceAmount(map['amount_minor'] ?? map['amountMinor']),
      )
      .map(_normalizeRemoteFinanceEntrySource)
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
        (map) =>
            _hasRawFinanceUuid(map) &&
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
        (map) =>
            _hasRawFinanceUuid(map) &&
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
            _hasSafeRawIntegerRange(
              map,
              'repayment_day',
              'repaymentDay',
              1,
              31,
            ),
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
    changed += await _mergeLoans(txn, loans, forceRemoteKeys: forceRemoteKeys);
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
  final repairedLegacyRefunds =
      !transactions.any((item) => item.type == FinanceTransactionType.refund)
      ? 0
      : await _repairLegacyRefundCategories(db);
  changed += repairedLegacyRefunds;
  if (changed > 0) {
    _notifyChanged(
      requestSync: repairedRefundUuids.isNotEmpty || repairedLegacyRefunds > 0,
    );
  }
  return changed;
}

/// Clears pending markers only for rows that were part of the request and
/// are still at the same local version. A later local edit therefore keeps
/// its marker even when the earlier request finishes afterwards.
Future<int> _acknowledgePendingChanges(
  Map<String, dynamic> requestPayload,
  List<dynamic> acknowledgements,
) async {
  if (acknowledgements.isEmpty) return 0;
  await FinanceStorage.ensureReady();
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
    'budgets': ['finance_budgets_changes', 'finance_balance_snapshots_changes'],
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
        where:
            'uuid = ? AND pending_sync = 1 AND updated_at = ? AND version = ?',
        whereArgs: [uuid, requestedUpdatedAt, requestedVersion],
      );
      acknowledged += count;
    }
  });
  return acknowledged;
}

List<Map<String, dynamic>> _listOfMaps(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
}

({List<Map<String, dynamic>> maps, int invalidCount}) _importListOfMaps(
  Map<String, dynamic> bundle,
  String key,
) {
  final raw = bundle[key];
  if (raw is! List) {
    return (maps: <Map<String, dynamic>>[], invalidCount: raw == null ? 0 : 1);
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
