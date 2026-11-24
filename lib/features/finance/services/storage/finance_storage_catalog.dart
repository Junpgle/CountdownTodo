part of '../finance_storage.dart';

Future<List<FinanceCategory>> _getCategories({
  FinanceCategoryType? type,
  bool includeArchived = false,
  bool includeDeleted = false,
}) async {
  await FinanceStorage.ensureReady();
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

Future<void> _saveCategory(
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
  await FinanceStorage.ensureReady();
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

void _mergeCategoryEdits(
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

Future<void> _archiveCategory(String uuid) async {
  await FinanceStorage.ensureReady();
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
    final children = await txn.query(
      'finance_categories',
      where: 'parent_uuid = ? AND is_deleted = 0',
      whereArgs: [uuid],
    );
    category
      ..isArchived = true
      ..markAsChanged();
    var cascadeUpdatedAt = category.updatedAt;
    for (final raw in children) {
      final child = FinanceCategory.fromMap(raw);
      if (child.updatedAt >= cascadeUpdatedAt) {
        cascadeUpdatedAt = child.updatedAt + 1;
      }
    }
    // The shared timestamp identifies children archived as part of this
    // parent operation, so a later restore can preserve older child archives.
    category.updatedAt = cascadeUpdatedAt;
    await txn.update(
      'finance_categories',
      _localValues(category.toMap()),
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    for (final raw in children) {
      final child = FinanceCategory.fromMap(raw);
      if (child.isSystem || child.isArchived) continue;
      child
        ..isArchived = true
        ..markAsChanged();
      child.updatedAt = cascadeUpdatedAt;
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

Future<bool> _unarchiveCategory(String uuid) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final restored = await db.transaction<bool>((txn) async {
    final existing = await txn.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (existing.isEmpty) return false;
    final category = FinanceCategory.fromMap(existing.first);
    if (category.isSystem || category.isDeleted) return false;

    FinanceCategory? archivedParent;
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
        archivedParent = parent;
      } else if (!category.isArchived) {
        return false;
      }
    } else if (!category.isArchived) {
      return false;
    }

    final categoryToRestore = archivedParent ?? category;
    if (categoryToRestore.isSystem || !categoryToRestore.isArchived) {
      return false;
    }
    final cascadeUpdatedAt = categoryToRestore.updatedAt;
    categoryToRestore
      ..isArchived = false
      ..markAsChanged();
    await txn.update(
      'finance_categories',
      _localValues(categoryToRestore.toMap()),
      where: 'uuid = ?',
      whereArgs: [categoryToRestore.uuid],
    );
    final children = await txn.query(
      'finance_categories',
      where: 'parent_uuid = ? AND is_deleted = 0 AND is_archived = 1',
      whereArgs: [categoryToRestore.uuid],
    );
    for (final raw in children) {
      final child = FinanceCategory.fromMap(raw);
      final isRequestedChild =
          archivedParent != null && child.uuid == category.uuid;
      if (child.isSystem ||
          (child.updatedAt != cascadeUpdatedAt && !isRequestedChild)) {
        continue;
      }
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

Future<bool> _hasTransactionsForCategory(String uuid) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final result = await db.rawQuery(
    'SELECT COUNT(*) AS count FROM finance_transactions '
    'WHERE category_uuid = ?',
    [uuid],
  );
  return (result.first['count'] as num?)?.toInt() != 0;
}

Future<List<FinancePaymentMethod>> _getPaymentMethods({
  bool includeArchived = false,
  bool includeDeleted = false,
}) async {
  await FinanceStorage.ensureReady();
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

Future<void> _savePaymentMethod(
  FinancePaymentMethod method, {
  FinancePaymentMethod? original,
}) async {
  if (method.name.trim().isEmpty) {
    throw ArgumentError.value(method.name, 'name', '付款方式名称不能为空');
  }
  if (original != null && original.uuid != method.uuid) {
    throw ArgumentError.value(original.uuid, 'original', '付款方式标识不匹配');
  }
  await FinanceStorage.ensureReady();
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
      final baselineChanged =
          original != null &&
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

void _mergePaymentMethodEdits(
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

Future<void> _archivePaymentMethod(String uuid) async {
  await FinanceStorage.ensureReady();
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

Future<void> _unarchivePaymentMethod(String uuid) async {
  await FinanceStorage.ensureReady();
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

Future<List<FinanceBudget>> _getBudgets({
  String? monthKey,
  bool includeDeleted = false,
}) async {
  await FinanceStorage.ensureReady();
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

Future<FinanceBudget?> _getBudget(String uuid) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final rows = await db.query(
    'finance_budgets',
    where: 'uuid = ?',
    whereArgs: [uuid],
    limit: 1,
  );
  return rows.isEmpty ? null : FinanceBudget.fromMap(rows.first);
}

Future<void> _saveBudget(
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
  if (!_monthKeyPattern.hasMatch(budget.monthKey)) {
    throw ArgumentError.value(budget.monthKey, 'monthKey', '月份格式无效');
  }
  if (budget.categoryUuid != null && budget.paymentMethodUuid != null) {
    throw ArgumentError('预算只能对应一个分类或付款方式');
  }
  if (original != null && original.uuid != budget.uuid) {
    throw ArgumentError.value(original.uuid, 'original', '预算标识不匹配');
  }
  if (balanceSnapshotAt != null) {
    if (!budget.isPaymentMethod ||
        !_isValidBalanceSnapshotAt(budget.monthKey, balanceSnapshotAt)) {
      throw ArgumentError.value(
        balanceSnapshotAt,
        'balanceSnapshotAt',
        '余额对应时间必须在所选月份内且不晚于现在',
      );
    }
  }
  await FinanceStorage.ensureReady();
  final db = await _database;
  await db.transaction((txn) async {
    if (!await _hasValidBudgetScope(txn, budget)) {
      throw ArgumentError.value(budget, 'budget', '预算必须关联有效的支出分类或付款方式');
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
      final baselineChanged =
          original != null &&
          (current.version != original.version ||
              current.updatedAt != original.updatedAt);
      if (baselineChanged) {
        _mergeBudgetEdits(current, original, budget);
        final snapshotTimeUnchanged =
            balanceSnapshotAt == original.effectiveBalanceSnapshotAt;
        final currentSnapshotStillMatchesScope =
            current.isPaymentMethod &&
            budget.isPaymentMethod &&
            current.monthKey == original.monthKey &&
            current.paymentMethodUuid == original.paymentMethodUuid &&
            budget.monthKey == current.monthKey &&
            budget.paymentMethodUuid == current.paymentMethodUuid;
        if (snapshotTimeUnchanged &&
            currentSnapshotStillMatchesScope &&
            current.effectiveBalanceSnapshotAt !=
                original.effectiveBalanceSnapshotAt) {
          // A stale amount edit must not restore the old snapshot instant
          // when another device has updated that instant in the meantime.
          balanceSnapshotAt = current.effectiveBalanceSnapshotAt;
        }
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
      final keepsExistingSnapshot =
          sameBalance && !resetBalanceSnapshot && balanceSnapshotAt == null;
      final nextSnapshotAt =
          balanceSnapshotAt ??
          (keepsExistingSnapshot
              ? current.effectiveBalanceSnapshotAt
              : DateTime.now().millisecondsSinceEpoch);
      if (!keepsExistingSnapshot &&
          !_isValidBalanceSnapshotAt(budget.monthKey, nextSnapshotAt)) {
        throw ArgumentError.value(
          nextSnapshotAt,
          'balanceSnapshotAt',
          '余额对应时间必须在所选月份内且不晚于现在',
        );
      }
      budget.balanceSnapshotAt = nextSnapshotAt;
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

void _mergeBudgetEdits(
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

Future<void> _deleteBudget(String uuid) async {
  final budget = await FinanceStorage.getBudget(uuid);
  if (budget == null || budget.isDeleted) return;
  final original = FinanceBudget.fromMap(budget.toMap());
  budget.isDeleted = true;
  budget.markAsChanged();
  await FinanceStorage.saveBudget(budget, original: original);
}

Future<void> _restoreBudget(String uuid) async {
  final budget = await FinanceStorage.getBudget(uuid);
  if (budget == null || !budget.isDeleted) return;
  final original = FinanceBudget.fromMap(budget.toMap());
  budget.isDeleted = false;
  budget.markAsChanged();
  await FinanceStorage.saveBudget(budget, original: original);
}

String _budgetScopeKey(FinanceBudget budget) {
  final scope = budget.paymentMethodUuid == null
      ? 'category:${budget.categoryUuid ?? ''}'
      : 'payment:${budget.paymentMethodUuid}';
  return '${budget.monthKey}\u0000$scope';
}

Future<List<Map<String, dynamic>>> _findAllBudgetsByScope(
  DatabaseExecutor db,
  FinanceBudget budget,
) {
  if (budget.paymentMethodUuid != null) {
    return db.query(
      'finance_budgets',
      where:
          'month_key = ? AND category_uuid IS NULL AND payment_method_uuid = ?',
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

Future<void> _deleteBudgetsInScope(
  DatabaseExecutor db,
  FinanceBudget budget,
) async {
  if (budget.paymentMethodUuid != null) {
    await db.delete(
      'finance_budgets',
      where:
          'month_key = ? AND category_uuid IS NULL AND payment_method_uuid = ?',
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

Future<void> _deleteOtherBudgetsInScope(
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
