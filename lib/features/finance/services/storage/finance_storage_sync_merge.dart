part of '../finance_storage.dart';

/// Filters category writes that would leave the local catalog with a broken
/// or deeper-than-two-level hierarchy. Validate the projected batch instead
/// of its input order so a valid root/child pair still imports when the
/// child appears first in a backup or sync response.
Future<Set<String>> _invalidCategoryHierarchyUuids(
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

String? _normalizeCategoryParentUuid(String? value) =>
    AppTextUtils.trimToNull(value);

Future<int> _mergeCategories(
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

Future<int> _mergePaymentMethods(
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

Future<int> _mergeTransactions(
  DatabaseExecutor db,
  List<FinanceTransaction> items, {
  Set<String> forceRemoteKeys = const {},
  Set<String>? deferredTransactionUuids,
  Set<String>? repairedRefundUuids,
}) async {
  var changed = 0;
  final changedOriginalUuids = <String>{};
  final duplicateInstallmentKeys = _duplicateInstallmentIndexKeys(items);
  final orderedItems =
      items.where((item) {
        final key = _installmentIndexKey(item);
        return item.isDeleted ||
            key == null ||
            !duplicateInstallmentKeys.contains(key);
      }).toList()..sort((left, right) {
        // Create/restore originals before active refunds, but remove refunds
        // before deleting or changing the type of their originals.
        return _transactionMergePriority(left)
            .compareTo(_transactionMergePriority(right));
      });
  // Batch the initial reads, then update these caches after each accepted
  // write so later dependency rounds see the transaction's current state.
  const batchSize = 400;
  const scheduleBatchSize = 300;
  final transactionUuids = <String>{
    for (final item in orderedItems) item.uuid,
    for (final item in orderedItems)
      if (item.type == FinanceTransactionType.refund &&
          !item.isDeleted &&
          item.relatedTransactionUuid?.trim().isNotEmpty == true)
        item.relatedTransactionUuid!.trim(),
  }.toList();
  final targetInstallmentKeys = orderedItems
      .where(
        (item) =>
            !item.isDeleted &&
            item.isInstallment &&
            item.installmentGroupUuid != null &&
            item.installmentIndex != null,
      )
      .map(
        (item) => (
          groupUuid: item.installmentGroupUuid!,
          installmentIndex: item.installmentIndex!,
        ),
      )
      .toSet()
      .toList(growable: false);
  final existingTransactionsByUuid = <String, FinanceTransaction>{};
  final activeInstallmentUuidsByGroupAndIndex =
      <String, Map<num, Set<Object?>>>{};
  final activeRefundsByOriginalUuid =
      <String, Map<String, FinanceTransaction>>{};

  for (var offset = 0; offset < transactionUuids.length; offset += batchSize) {
    final nextOffset = offset + batchSize;
    final end = nextOffset < transactionUuids.length
        ? nextOffset
        : transactionUuids.length;
    final batch = transactionUuids.sublist(offset, end);
    final placeholders = List.filled(batch.length, '?').join(',');
    final rows = await db.query(
      'finance_transactions',
      where:
          'uuid IN ($placeholders) OR '
          "(type = 'refund' AND is_deleted = 0 AND "
          'related_transaction_uuid IN ($placeholders))',
      whereArgs: [...batch, ...batch],
    );
    for (final row in rows) {
      final transaction = FinanceTransaction.fromMap(row);
      existingTransactionsByUuid[transaction.uuid] = transaction;
      final rawRelatedUuid = row['related_transaction_uuid'];
      if (row['type'] == FinanceTransactionType.refund.name &&
          row['is_deleted'] == 0 &&
          rawRelatedUuid is String) {
        (activeRefundsByOriginalUuid[rawRelatedUuid] ??=
                <String, FinanceTransaction>{})[transaction.uuid] =
            transaction;
      }
    }
  }

  for (
    var offset = 0;
    offset < targetInstallmentKeys.length;
    offset += scheduleBatchSize
  ) {
    final nextOffset = offset + scheduleBatchSize;
    final end = nextOffset < targetInstallmentKeys.length
        ? nextOffset
        : targetInstallmentKeys.length;
    final batch = targetInstallmentKeys.sublist(offset, end);
    final schedulePredicates = List.filled(
      batch.length,
      '(installment_group_uuid = ? AND installment_index = ?)',
    ).join(' OR ');
    final scheduleArgs = <Object?>[];
    for (final key in batch) {
      scheduleArgs
        ..add(key.groupUuid)
        ..add(key.installmentIndex);
    }
    final rows = await db.query(
      'finance_transactions',
      columns: ['uuid', 'installment_group_uuid', 'installment_index'],
      where: 'is_deleted = 0 AND ($schedulePredicates)',
      whereArgs: scheduleArgs,
    );
    for (final row in rows) {
      final groupUuid = row['installment_group_uuid'];
      final installmentIndex = row['installment_index'];
      if (groupUuid is! String || installmentIndex is! num) continue;
      final byIndex = activeInstallmentUuidsByGroupAndIndex.putIfAbsent(
        groupUuid,
        () => <num, Set<Object?>>{},
      );
      (byIndex[installmentIndex] ??= <Object?>{}).add(row['uuid']);
    }
  }

  void removeCachedActiveInstallment(FinanceTransaction transaction) {
    if (transaction.isDeleted) return;
    final groupUuid = transaction.installmentGroupUuid;
    final installmentIndex = transaction.installmentIndex;
    if (groupUuid == null || installmentIndex == null) return;
    final byIndex = activeInstallmentUuidsByGroupAndIndex[groupUuid];
    final uuids = byIndex?[installmentIndex];
    uuids?.remove(transaction.uuid);
    if (uuids?.isEmpty == true) byIndex?.remove(installmentIndex);
  }

  bool hasInstallmentIndexConflict(FinanceTransaction item) {
    final groupUuid = item.installmentGroupUuid;
    final installmentIndex = item.installmentIndex;
    if (item.isDeleted ||
        !item.isInstallment ||
        groupUuid == null ||
        installmentIndex == null) {
      return false;
    }
    final uuids =
        activeInstallmentUuidsByGroupAndIndex[groupUuid]?[installmentIndex];
    return uuids?.any((uuid) => uuid != item.uuid) ?? false;
  }

  int activeRefundedMinor(String originalUuid, {String? excludingRefundUuid}) {
    final refunds = activeRefundsByOriginalUuid[originalUuid]?.values;
    if (refunds == null) return 0;
    var total = 0;
    for (final refund in refunds) {
      if (refund.uuid != excludingRefundUuid) {
        total += refund.amountMinor;
      }
    }
    return total;
  }

  void validateTransactionRefundState(FinanceTransaction transaction) {
    final originalUuid = transaction.relatedTransactionUuid?.trim();
    if (transaction.type == FinanceTransactionType.refund &&
        !transaction.isDeleted &&
        originalUuid?.isNotEmpty == true) {
      if (originalUuid == transaction.uuid) {
        throw StateError('退款账单不能绑定自己');
      }
      final original = existingTransactionsByUuid[originalUuid!];
      if (original == null) throw StateError('原账单不存在');
      if (original.isDeleted ||
          original.type != FinanceTransactionType.expense) {
        throw StateError('只能对未删除的支出账单发起退款');
      }
      if (_refundPrecedesOriginal(transaction, original)) {
        throw StateError('退款时间不能早于原支出时间');
      }
      final refunded = activeRefundedMinor(
        original.uuid,
        excludingRefundUuid: transaction.uuid,
      );
      final remaining = original.amountMinor - refunded;
      if (transaction.amountMinor > remaining) {
        final remainingMinor = remaining.clamp(0, original.amountMinor).toInt();
        throw StateError('退款金额超过剩余可退金额 $remainingMinor 分');
      }
    }

    final activeRefunded = activeRefundedMinor(transaction.uuid);
    if (activeRefunded > 0 &&
        (transaction.isDeleted ||
            transaction.type != FinanceTransactionType.expense ||
            transaction.amountMinor < activeRefunded)) {
      throw StateError('该账单已关联退款，请先处理退款记录');
    }
    if (activeRefunded > 0 &&
        transaction.type == FinanceTransactionType.expense) {
      final refunds = activeRefundsByOriginalUuid[transaction.uuid]?.values;
      if (refunds?.any(
            (refund) => _refundPrecedesOriginal(refund, transaction),
          ) ??
          false) {
        throw StateError('原支出时间不能晚于关联退款时间');
      }
    }
  }

  void updateCachedTransaction(
    FinanceTransaction item, {
    FinanceTransaction? previous,
  }) {
    if (previous != null) removeCachedActiveInstallment(previous);
    if (previous != null &&
        !previous.isDeleted &&
        previous.type == FinanceTransactionType.refund &&
        previous.relatedTransactionUuid != null) {
      final refunds =
          activeRefundsByOriginalUuid[previous.relatedTransactionUuid!];
      refunds?.remove(previous.uuid);
      if (refunds?.isEmpty == true) {
        activeRefundsByOriginalUuid.remove(previous.relatedTransactionUuid);
      }
    }
    existingTransactionsByUuid[item.uuid] = item;
    if (!item.isDeleted &&
        item.type == FinanceTransactionType.refund &&
        item.relatedTransactionUuid != null) {
      (activeRefundsByOriginalUuid[item.relatedTransactionUuid!] ??=
              <String, FinanceTransaction>{})[item.uuid] =
          item;
    }
    if (item.isDeleted) return;
    final groupUuid = item.installmentGroupUuid;
    final installmentIndex = item.installmentIndex;
    if (groupUuid == null || installmentIndex == null) return;
    final byIndex = activeInstallmentUuidsByGroupAndIndex.putIfAbsent(
      groupUuid,
      () => <num, Set<Object?>>{},
    );
    (byIndex[installmentIndex] ??= <Object?>{}).add(item.uuid);
  }

  var pending = orderedItems;
  while (pending.isNotEmpty) {
    final deferred = <FinanceTransaction>[];
    final changedBeforeRound = changed;
    for (final item in pending) {
      if (hasInstallmentIndexConflict(item)) continue;
      final existing = existingTransactionsByUuid[item.uuid];
      if (existing != null) {
        final isRestoringLegacyTransferProjection =
            !existing.pendingSync &&
            existing.isDeleted &&
            !item.isDeleted &&
            item.type == FinanceTransactionType.transfer &&
            item.updatedAt == existing.updatedAt &&
            item.version == existing.version;
        if (!forceRemoteKeys.contains('transactions:${item.uuid}') &&
            !isRestoringLegacyTransferProjection &&
            !_isIncomingWinner(
              item.updatedAt,
              item.version,
              existing.updatedAt,
              existing.version,
            )) {
          continue;
        }
      }
      try {
        validateTransactionRefundState(item);
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
      updateCachedTransaction(item, previous: existing);
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

int _transactionMergePriority(FinanceTransaction item) {
  if (item.type == FinanceTransactionType.expense && !item.isDeleted) {
    return 0;
  }
  if (item.type == FinanceTransactionType.refund) {
    return item.isDeleted ? 1 : 2;
  }
  return 3;
}

Future<int> _mergeLoans(
  DatabaseExecutor db,
  List<FinanceLoan> items, {
  Set<String> forceRemoteKeys = const {},
}) async {
  var changed = 0;
  const batchSize = 400;
  final loanUuids = items.map((item) => item.uuid).toSet().toList();
  final loansByUuid = <String, FinanceLoan>{};
  for (var offset = 0; offset < loanUuids.length; offset += batchSize) {
    final nextOffset = offset + batchSize;
    final end = nextOffset < loanUuids.length ? nextOffset : loanUuids.length;
    final batch = loanUuids.sublist(offset, end);
    final placeholders = List.filled(batch.length, '?').join(',');
    final rows = await db.query(
      'finance_loans',
      where: 'uuid IN ($placeholders)',
      whereArgs: batch,
    );
    for (final row in rows) {
      final loan = FinanceLoan.fromMap(row);
      loansByUuid[loan.uuid] = loan;
    }
  }

  final loansWithChangedTerms = <String>{};
  final potentialCurrentByUuid = Map<String, FinanceLoan>.of(loansByUuid);
  for (final item in items) {
    final current = potentialCurrentByUuid[item.uuid];
    if (current != null && _loanTermsDiffer(current, item)) {
      loansWithChangedTerms.add(item.uuid);
    }
    potentialCurrentByUuid[item.uuid] = item;
  }
  final paidLoanUuids = <String>{};
  final paidCheckUuids = loansWithChangedTerms.toList(growable: false);
  for (var offset = 0; offset < paidCheckUuids.length; offset += batchSize) {
    final nextOffset = offset + batchSize;
    final end = nextOffset < paidCheckUuids.length
        ? nextOffset
        : paidCheckUuids.length;
    final batch = paidCheckUuids.sublist(offset, end);
    final placeholders = List.filled(batch.length, '?').join(',');
    final rows = await db.query(
      'finance_loan_installments',
      columns: ['loan_uuid'],
      distinct: true,
      where: 'is_paid = 1 AND loan_uuid IN ($placeholders)',
      whereArgs: batch,
    );
    paidLoanUuids.addAll(rows.map((row) => row['loan_uuid'] as String));
  }

  for (final item in items) {
    final current = loansByUuid[item.uuid];
    if (current == null) {
      await db.insert('finance_loans', _remoteValues(item.toMap()));
      loansByUuid[item.uuid] = item;
      changed++;
      continue;
    }
    if (!forceRemoteKeys.contains('loans:${item.uuid}') &&
        !_isIncomingWinner(
          item.updatedAt,
          item.version,
          current.updatedAt,
          current.version,
        )) {
      continue;
    }
    if (_loanTermsDiffer(current, item) && paidLoanUuids.contains(item.uuid)) {
      continue;
    }
    await db.update(
      'finance_loans',
      _remoteValues(item.toMap()),
      where: 'uuid = ?',
      whereArgs: [item.uuid],
    );
    loansByUuid[item.uuid] = item;
    changed++;
  }
  return changed;
}

Future<int> _mergeLoanInstallments(
  DatabaseExecutor db,
  List<FinanceLoanInstallment> items, {
  Set<String> forceRemoteKeys = const {},
}) async {
  var changed = 0;
  final loanScheduleCache = <String, List<FinanceLoanScheduleAllocation>>{};
  const batchSize = 400;
  const scheduleBatchSize = 300;
  final loanUuids = items.map((item) => item.loanUuid).toSet().toList();
  final installmentUuids = items.map((item) => item.uuid).toSet().toList();
  final targetScheduleKeys = items
      .where((item) => !item.isDeleted)
      .map(
        (item) =>
            (loanUuid: item.loanUuid, installmentIndex: item.installmentIndex),
      )
      .toSet()
      .toList(growable: false);
  final loansByUuid = <String, FinanceLoan>{};
  final installmentsByUuid = <String, FinanceLoanInstallment>{};
  final activeInstallmentUuidsByLoanAndIndex =
      <String, Map<num, Set<Object?>>>{};

  for (var offset = 0; offset < loanUuids.length; offset += batchSize) {
    final nextOffset = offset + batchSize;
    final end = nextOffset < loanUuids.length ? nextOffset : loanUuids.length;
    final batch = loanUuids.sublist(offset, end);
    final placeholders = List.filled(batch.length, '?').join(',');
    final loanRows = await db.query(
      'finance_loans',
      where: 'uuid IN ($placeholders)',
      whereArgs: batch,
    );
    for (final row in loanRows) {
      final loan = FinanceLoan.fromMap(row);
      loansByUuid[loan.uuid] = loan;
    }
  }

  for (
    var offset = 0;
    offset < targetScheduleKeys.length;
    offset += scheduleBatchSize
  ) {
    final nextOffset = offset + scheduleBatchSize;
    final end = nextOffset < targetScheduleKeys.length
        ? nextOffset
        : targetScheduleKeys.length;
    final batch = targetScheduleKeys.sublist(offset, end);
    final schedulePredicates = List.filled(
      batch.length,
      '(loan_uuid = ? AND installment_index = ?)',
    ).join(' OR ');
    final scheduleArgs = <Object?>[];
    for (final key in batch) {
      scheduleArgs
        ..add(key.loanUuid)
        ..add(key.installmentIndex);
    }
    final scheduleRows = await db.query(
      'finance_loan_installments',
      columns: ['uuid', 'loan_uuid', 'installment_index'],
      where: 'is_deleted = 0 AND ($schedulePredicates)',
      whereArgs: scheduleArgs,
    );
    for (final row in scheduleRows) {
      final loanUuid = row['loan_uuid'];
      final index = row['installment_index'];
      if (loanUuid is! String || index is! num) continue;
      final byIndex = activeInstallmentUuidsByLoanAndIndex.putIfAbsent(
        loanUuid,
        () => <num, Set<Object?>>{},
      );
      (byIndex[index] ??= <Object?>{}).add(row['uuid']);
    }
  }

  for (var offset = 0; offset < installmentUuids.length; offset += batchSize) {
    final nextOffset = offset + batchSize;
    final end = nextOffset < installmentUuids.length
        ? nextOffset
        : installmentUuids.length;
    final batch = installmentUuids.sublist(offset, end);
    final placeholders = List.filled(batch.length, '?').join(',');
    final existingRows = await db.query(
      'finance_loan_installments',
      where: 'uuid IN ($placeholders)',
      whereArgs: batch,
    );
    for (final row in existingRows) {
      final installment = FinanceLoanInstallment.fromMap(row);
      installmentsByUuid[installment.uuid] = installment;
    }
  }

  void removeCachedActiveInstallment(FinanceLoanInstallment installment) {
    final byIndex = activeInstallmentUuidsByLoanAndIndex[installment.loanUuid];
    final uuids = byIndex?[installment.installmentIndex];
    uuids?.remove(installment.uuid);
    if (uuids?.isEmpty == true) {
      byIndex?.remove(installment.installmentIndex);
    }
  }

  void updateCachedInstallment(
    FinanceLoanInstallment item, {
    FinanceLoanInstallment? previous,
  }) {
    if (previous != null && !previous.isDeleted) {
      removeCachedActiveInstallment(previous);
    }
    installmentsByUuid[item.uuid] = item;
    if (!item.isDeleted) {
      final byIndex = activeInstallmentUuidsByLoanAndIndex.putIfAbsent(
        item.loanUuid,
        () => <num, Set<Object?>>{},
      );
      (byIndex[item.installmentIndex] ??= <Object?>{}).add(item.uuid);
    }
  }

  for (final item in items) {
    final loan = loansByUuid[item.loanUuid];
    if (loan == null ||
        (loan.isDeleted && !item.isDeleted) ||
        (!item.isDeleted &&
            !_matchesLoanInstallmentSchedule(loan, item, loanScheduleCache))) {
      continue;
    }
    if (!item.isDeleted) {
      final duplicateUuids =
          activeInstallmentUuidsByLoanAndIndex[item.loanUuid]?[item
              .installmentIndex];
      if (duplicateUuids?.any((uuid) => uuid != item.uuid) ?? false) {
        continue;
      }
    }
    final existing = installmentsByUuid[item.uuid];
    if (existing == null) {
      await db.insert('finance_loan_installments', _remoteValues(item.toMap()));
      updateCachedInstallment(item);
      changed++;
      continue;
    }
    final current = existing;
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
    updateCachedInstallment(item, previous: current);
    changed++;
  }
  return changed;
}

Future<int> _mergeBudgets(
  DatabaseExecutor db,
  List<FinanceBudget> items, {
  Set<String> forceRemoteKeys = const {},
}) async {
  var changed = 0;
  const uuidBatchSize = 400;
  const scopeBatchSize = 300;

  Future<List<Map<String, dynamic>>> queryRowsByUuid(
    String table,
    List<String> uuids, {
    List<String>? columns,
  }) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; offset < uuids.length; offset += uuidBatchSize) {
      final nextOffset = offset + uuidBatchSize;
      final end = nextOffset < uuids.length ? nextOffset : uuids.length;
      final batch = uuids.sublist(offset, end);
      final placeholders = List.filled(batch.length, '?').join(',');
      result.addAll(
        await db.query(
          table,
          columns: columns,
          where: 'uuid IN ($placeholders)',
          whereArgs: batch,
        ),
      );
    }
    return result;
  }

  final categoryUuids = items
      .map((item) => item.categoryUuid)
      .whereType<String>()
      .toSet()
      .toList(growable: false);
  final paymentMethodUuids = items
      .where((item) => item.categoryUuid == null)
      .map((item) => item.paymentMethodUuid)
      .whereType<String>()
      .toSet()
      .toList(growable: false);
  final expenseCategoryUuids = <String>{};
  for (final row in await queryRowsByUuid(
    'finance_categories',
    categoryUuids,
    columns: const ['uuid', 'type'],
  )) {
    final category = FinanceCategory.fromMap(row);
    if (category.type == FinanceCategoryType.expense) {
      expenseCategoryUuids.add(category.uuid);
    }
  }
  final existingPaymentMethodUuids = (await queryRowsByUuid(
    'finance_payment_methods',
    paymentMethodUuids,
    columns: const ['uuid'],
  )).map((row) => row['uuid'] as String).toSet();

  bool hasValidScope(FinanceBudget budget) {
    final categoryUuid = budget.categoryUuid;
    if (categoryUuid != null) {
      return expenseCategoryUuids.contains(categoryUuid);
    }
    final paymentMethodUuid = budget.paymentMethodUuid;
    return paymentMethodUuid == null ||
        existingPaymentMethodUuids.contains(paymentMethodUuid);
  }

  final uniqueScopes = <String, FinanceBudget>{};
  for (final item in items) {
    if (hasValidScope(item)) {
      uniqueScopes.putIfAbsent(_budgetScopeKey(item), () => item);
    }
  }
  final scopeBudgetsByKey = <String, List<FinanceBudget>>{};
  final scopes = uniqueScopes.values.toList(growable: false);
  for (var offset = 0; offset < scopes.length; offset += scopeBatchSize) {
    final nextOffset = offset + scopeBatchSize;
    final end = nextOffset < scopes.length ? nextOffset : scopes.length;
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    for (final budget in scopes.sublist(offset, end)) {
      if (budget.paymentMethodUuid != null) {
        whereParts.add(
          'month_key = ? AND category_uuid IS NULL AND payment_method_uuid = ?',
        );
        whereArgs
          ..add(budget.monthKey)
          ..add(budget.paymentMethodUuid);
      } else if (budget.categoryUuid == null) {
        whereParts.add(
          'month_key = ? AND category_uuid IS NULL AND payment_method_uuid IS NULL',
        );
        whereArgs.add(budget.monthKey);
      } else {
        whereParts.add(
          'month_key = ? AND category_uuid = ? AND payment_method_uuid IS NULL',
        );
        whereArgs
          ..add(budget.monthKey)
          ..add(budget.categoryUuid);
      }
    }
    if (whereParts.isEmpty) continue;
    final rows = await db.query(
      'finance_budgets',
      where: whereParts.map((part) => '($part)').join(' OR '),
      whereArgs: whereArgs,
    );
    for (final row in rows) {
      final budget = FinanceBudget.fromMap(row);
      scopeBudgetsByKey
          .putIfAbsent(_budgetScopeKey(budget), () => <FinanceBudget>[])
          .add(budget);
    }
  }

  for (final item in items) {
    if (!hasValidScope(item)) continue;
    final scopeKey = _budgetScopeKey(item);
    final scopeRows = scopeBudgetsByKey[scopeKey] ?? const <FinanceBudget>[];
    if (scopeRows.isEmpty) {
      await db.insert('finance_budgets', _remoteValues(item.toMap()));
      scopeBudgetsByKey[scopeKey] = [item];
      changed++;
      continue;
    }

    var current = scopeRows.first;
    for (final candidate in scopeRows.skip(1)) {
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
        forceIncoming || sameWinner || _isIncomingBudgetWinner(item, current);
    if (!incomingWins) {
      if (scopeRows.length > 1) {
        await _deleteOtherBudgetsInScope(db, current);
        scopeBudgetsByKey[scopeKey] = [current];
        changed++;
      }
      continue;
    }
    _preserveBalanceSnapshotForUnchangedAmount(item, current);
    await _deleteBudgetsInScope(db, item);
    await db.insert('finance_budgets', _remoteValues(item.toMap()));
    scopeBudgetsByKey[scopeKey] = [item];
    changed++;
  }
  return changed;
}

List<FinanceBudget> _latestBudgetsByScope(List<FinanceBudget> items) {
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

bool _isIncomingBudgetWinner(FinanceBudget incoming, FinanceBudget current) {
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

void _preserveBalanceSnapshotForUnchangedAmount(
  FinanceBudget incoming,
  FinanceBudget current,
) {
  if (incoming.isPaymentMethod &&
      current.isPaymentMethod &&
      incoming.balanceSnapshotAt == null &&
      incoming.monthKey == current.monthKey &&
      incoming.paymentMethodUuid == current.paymentMethodUuid &&
      incoming.amountMinor == current.amountMinor) {
    // Older clients and backups omit the snapshot time. A note or deletion
    // update must not turn their update time into a new balance baseline.
    incoming.balanceSnapshotAt = current.effectiveBalanceSnapshotAt;
  }
}

Future<int> _mergeRecurringRules(
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

Future<int> _mergeTemplates(
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

bool _isIncomingWinner(
  int incomingUpdatedAt,
  int incomingVersion,
  int currentUpdatedAt,
  int currentVersion,
) {
  return incomingUpdatedAt > currentUpdatedAt ||
      (incomingUpdatedAt == currentUpdatedAt &&
          incomingVersion > currentVersion);
}
