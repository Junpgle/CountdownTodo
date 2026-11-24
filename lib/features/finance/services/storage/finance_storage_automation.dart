part of '../finance_storage.dart';

Future<List<FinanceRecurringRule>> _getRecurringRules({
  bool includeDeleted = false,
  bool enabledOnly = false,
}) async {
  await FinanceStorage.ensureReady();
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

Future<FinanceRecurringRule?> _getRecurringRule(String uuid) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final rows = await db.query(
    'finance_recurring_rules',
    where: 'uuid = ?',
    whereArgs: [uuid],
    limit: 1,
  );
  return rows.isEmpty ? null : FinanceRecurringRule.fromMap(rows.first);
}

Future<void> _saveRecurringRule(
  FinanceRecurringRule rule, {
  FinanceRecurringRule? original,
}) async {
  _validateRecurringRule(rule);
  if (original != null && original.uuid != rule.uuid) {
    throw ArgumentError.value(original.uuid, 'original', '周期账单标识不匹配');
  }
  rule.pendingSync = true;
  await FinanceStorage.ensureReady();
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
      final baselineChanged =
          original != null &&
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

Future<void> _deleteRecurringRule(String uuid) async {
  final rule = await FinanceStorage.getRecurringRule(uuid);
  if (rule == null || rule.isDeleted) return;
  final original = FinanceRecurringRule.fromMap(rule.toMap());
  rule.isDeleted = true;
  rule.markAsChanged();
  await FinanceStorage.saveRecurringRule(rule, original: original);
}

Future<void> _restoreRecurringRule(String uuid) async {
  final rule = await FinanceStorage.getRecurringRule(uuid);
  if (rule == null || !rule.isDeleted) return;
  final original = FinanceRecurringRule.fromMap(rule.toMap());
  rule.isDeleted = false;
  rule.markAsChanged();
  await FinanceStorage.saveRecurringRule(rule, original: original);
}

Future<void> _setRecurringRuleEnabled(String uuid, bool enabled) async {
  final rule = await FinanceStorage.getRecurringRule(uuid);
  if (rule == null || rule.isDeleted || rule.isEnabled == enabled) return;
  final original = FinanceRecurringRule.fromMap(rule.toMap());
  rule.isEnabled = enabled;
  rule.markAsChanged();
  await FinanceStorage.saveRecurringRule(rule, original: original);
}

Future<bool> _materializeRecurringRule(
  FinanceRecurringRule rule, {
  required DateTime dueAt,
  required String periodKey,
}) async {
  if (periodKey.trim().isEmpty) return false;
  await FinanceStorage.ensureReady();
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

    final siblingRuleRows = await txn.query(
      'finance_recurring_rules',
      where: 'is_deleted = 0',
    );
    final displayName = financeRecurringRuleDisplayName(
      current,
      siblingRuleRows.map(FinanceRecurringRule.fromMap),
    );
    final detail = <String>[
      if (current.note?.trim().isNotEmpty == true) current.note!.trim(),
      '自动生成 · $displayName',
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
          : displayName,
      note: detail,
      source: FinanceEntrySource.automation,
      deviceId: current.deviceId,
    );
    await txn.insert('finance_transactions', _localValues(transaction.toMap()));

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

String _recurringTransactionUuid(String ruleUuid, String periodKey) {
  return FinanceRecurringRule.transactionUuidForPeriod(ruleUuid, periodKey);
}

String? _latestGeneratedPeriod(String? current, String? incoming) {
  if (current == null || incoming == null) return current ?? incoming;
  return _generatedPeriodOrder(incoming) >= _generatedPeriodOrder(current)
      ? incoming
      : current;
}

String? _mergeRecurringGenerationPeriod(
  FinanceRecurringRule current,
  FinanceRecurringRule incoming,
) {
  if (current.frequency != incoming.frequency) {
    final marker = incoming.effectiveLastGeneratedPeriod;
    final barrier = _recurringProgressBeforeCurrentCycle(
      incoming,
      DateTime.now(),
    );
    if (marker == null) return barrier;
    return _latestGeneratedPeriod(marker, barrier);
  }
  // Generation progress cannot be rolled back by a stale edit or backup.
  final latest = _latestGeneratedPeriod(
    current.effectiveLastGeneratedPeriod,
    incoming.effectiveLastGeneratedPeriod,
  );
  if (!_hasRecurringScheduleChanged(current, incoming)) return latest;
  // A schedule change must not create a bill dated earlier this period just
  // because the previous rule had not yet been materialized.
  final passedPeriod = _recurringPastDueCurrentPeriod(incoming, DateTime.now());
  if (passedPeriod == null) return latest;
  return _latestGeneratedPeriod(latest, passedPeriod);
}

String? _editedRecurringGenerationPeriod(
  FinanceRecurringRule current,
  FinanceRecurringRule incoming,
) {
  if (current.frequency != incoming.frequency) {
    return _recurringProgressBeforeCurrentCycle(incoming, DateTime.now());
  }
  final latest = _mergeRecurringGenerationPeriod(current, incoming);
  if (current.isEnabled != incoming.isEnabled ||
      current.autoGenerate != incoming.autoGenerate ||
      current.isDeleted != incoming.isDeleted) {
    return _latestGeneratedPeriod(
      latest,
      incoming.generationPeriodBefore(DateTime.now()),
    );
  }
  return latest;
}

bool _hasRecurringScheduleChanged(
  FinanceRecurringRule current,
  FinanceRecurringRule incoming,
) =>
    current.frequency != incoming.frequency ||
    current.dayOfMonth != incoming.dayOfMonth ||
    current.monthOfYear != incoming.monthOfYear ||
    current.startDate != incoming.startDate ||
    current.endDate != incoming.endDate;

String _recurringProgressBeforeCurrentCycle(
  FinanceRecurringRule rule,
  DateTime now,
) {
  final due = rule.dueDateFor(
    now.year,
    rule.frequency == FinanceRecurringFrequency.yearly
        ? rule.monthOfYear
        : now.month,
  );
  if (due != null && !due.isAfter(now)) {
    return _recurringPeriodKeyFor(rule, due);
  }
  return rule.frequency == FinanceRecurringFrequency.yearly
      ? '${now.year - 1}'
      : financeMonthKey(DateTime(now.year, now.month - 1));
}

String? _recurringPastDueCurrentPeriod(
  FinanceRecurringRule rule,
  DateTime now,
) {
  final due = rule.dueDateFor(
    now.year,
    rule.frequency == FinanceRecurringFrequency.yearly
        ? rule.monthOfYear
        : now.month,
  );
  if (due == null || due.isAfter(now)) return null;
  return _recurringPeriodKeyFor(rule, due);
}

String _recurringPeriodKeyFor(FinanceRecurringRule rule, DateTime dueAt) =>
    rule.frequency == FinanceRecurringFrequency.yearly
    ? dueAt.year.toString()
    : financeMonthKey(dueAt);

FinanceRecurringRule _mergeRecurringRuleEdits(
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

FinanceEntryTemplate _mergeTemplateEdits(
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
    merged.useCount = (current.useCount + incoming.useCount - original.useCount)
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

int _generatedPeriodOrder(String value) {
  final parts = value.split('-');
  final year = int.tryParse(parts.first) ?? -1;
  final month = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return year * 100 + month;
}

Future<List<FinanceEntryTemplate>> _getTemplates({
  bool includeDeleted = false,
}) async {
  await FinanceStorage.ensureReady();
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

Future<FinanceEntryTemplate?> _getTemplate(String uuid) async {
  await FinanceStorage.ensureReady();
  final db = await _database;
  final rows = await db.query(
    'finance_entry_templates',
    where: 'uuid = ?',
    whereArgs: [uuid],
    limit: 1,
  );
  return rows.isEmpty ? null : FinanceEntryTemplate.fromMap(rows.first);
}

Future<void> _saveTemplate(
  FinanceEntryTemplate template, {
  FinanceEntryTemplate? original,
}) async {
  _validateTemplate(template);
  if (original != null && original.uuid != template.uuid) {
    throw ArgumentError.value(original.uuid, 'original', '模板标识不匹配');
  }
  await FinanceStorage.ensureReady();
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

Future<void> _deleteTemplate(String uuid) async {
  final template = await FinanceStorage.getTemplate(uuid);
  if (template == null || template.isDeleted) return;
  final original = FinanceEntryTemplate.fromMap(template.toMap());
  template.isDeleted = true;
  template.markAsChanged();
  await FinanceStorage.saveTemplate(template, original: original);
}

Future<void> _restoreTemplate(String uuid) async {
  final template = await FinanceStorage.getTemplate(uuid);
  if (template == null || !template.isDeleted) return;
  final original = FinanceEntryTemplate.fromMap(template.toMap());
  template.isDeleted = false;
  template.markAsChanged();
  await FinanceStorage.saveTemplate(template, original: original);
}

Future<void> _markTemplateUsed(String uuid) async {
  final template = await FinanceStorage.getTemplate(uuid);
  if (template == null || template.isDeleted) return;
  final original = FinanceEntryTemplate.fromMap(template.toMap());
  template.useCount++;
  template.lastUsedAt = DateTime.now().millisecondsSinceEpoch;
  template.markAsChanged();
  await FinanceStorage.saveTemplate(template, original: original);
}

void _validateRecurringRule(FinanceRecurringRule rule) {
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
    throw ArgumentError.value(rule.dayOfMonth, 'dayOfMonth', '日期必须在 1 到 31 之间');
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

void _validateTemplate(FinanceEntryTemplate template) {
  if (template.name.trim().isEmpty) {
    throw ArgumentError.value(template.name, 'name', '模板名称不能为空');
  }
  if (template.type == FinanceTransactionType.refund) {
    throw ArgumentError.value(template.type, 'type', '模板不支持退款类型');
  }
  if (!isSafeFinanceAmountMinor(template.amountMinor) ||
      template.amountMinor == 0) {
    throw ArgumentError.value(template.amountMinor, 'amountMinor', '金额必须大于 0');
  }
  if (template.useCount < 0 || template.useCount > _maxTemplateUseCount) {
    throw ArgumentError.value(
      template.useCount,
      'useCount',
      '使用次数必须在 0 到 $_maxTemplateUseCount 之间',
    );
  }
}

bool _isDateKey(String value) {
  return isFinanceDateKey(value);
}
