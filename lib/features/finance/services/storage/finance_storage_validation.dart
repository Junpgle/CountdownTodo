part of '../finance_storage.dart';

bool _isValidTransaction(FinanceTransaction item) {
  return item.uuid.trim().isNotEmpty &&
      isSafeFinanceAmountMinor(item.amountMinor) &&
      item.amountMinor > 0 &&
      (item.isDeleted || _hasValidInstallmentFields(item)) &&
      (item.installmentTotalMinor == null ||
          (isSafeFinanceAmountMinor(item.installmentTotalMinor!) &&
              item.installmentTotalMinor! > 0)) &&
      _isDateKey(item.transactionDate);
}

bool _hasValidInstallmentFields(FinanceTransaction item) {
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
          (isSafeFinanceAmountMinor(total) && total >= item.amountMinor));
}

bool _hasValidRawInstallmentFields(Map<String, dynamic> raw) {
  final isDeleted = raw['is_deleted'] ?? raw['isDeleted'];
  if (isDeleted == true || isDeleted == 1 || isDeleted == '1') return true;
  final groupValue =
      raw['installment_group_uuid'] ?? raw['installmentGroupUuid'];
  final indexValue = raw['installment_index'] ?? raw['installmentIndex'];
  final countValue = raw['installment_count'] ?? raw['installmentCount'];
  final totalValue =
      raw['installment_total_minor'] ?? raw['installmentTotalMinor'];
  final hasGroupValue =
      groupValue != null &&
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

String? _installmentIndexKey(FinanceTransaction item) {
  if (!item.isInstallment) return null;
  return '${item.installmentGroupUuid}\u0000${item.installmentIndex}';
}

Set<String> _duplicateInstallmentIndexKeys(Iterable<FinanceTransaction> items) {
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

Future<bool> _hasInstallmentIndexConflict(
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
    where:
        'installment_group_uuid = ? AND installment_index = ? '
        'AND uuid != ? AND is_deleted = 0',
    whereArgs: [groupUuid, installmentIndex, item.uuid],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Linked refunds inherit classification from their original. Repair after
/// the whole batch so this derived edit cannot block a newer refund amount.
Future<int> _alignLinkedRefunds(
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
    final chunk = uuids.sublist(
      offset,
      end > uuids.length ? uuids.length : end,
    );
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

Future<int> _activeRefundedMinor(
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

Future<List<FinanceTransaction>> _getActiveRefundsForTransaction(
  DatabaseExecutor db,
  String originalUuid,
) async {
  final rows = await db.query(
    'finance_transactions',
    where:
        "type = 'refund' AND related_transaction_uuid = ? "
        'AND is_deleted = 0',
    whereArgs: [originalUuid],
  );
  return rows.map(FinanceTransaction.fromMap).toList(growable: false);
}

bool _refundPrecedesOriginal(
  FinanceTransaction refund,
  FinanceTransaction original,
) {
  final dateOrder = refund.transactionDate.compareTo(original.transactionDate);
  if (dateOrder != 0) return dateOrder < 0;

  final refundOccurrence = refund.occurrenceLocalTime;
  final originalOccurrence = original.occurrenceLocalTime;
  if (refund.occurredAt == null ||
      original.occurredAt == null ||
      refundOccurrence == null ||
      originalOccurrence == null ||
      dateKey(refundOccurrence) != refund.transactionDate ||
      dateKey(originalOccurrence) != original.transactionDate) {
    return false;
  }
  // The entry editor displays and preserves occurrence times to the minute.
  return (refund.occurredAt! ~/ 60000) < (original.occurredAt! ~/ 60000);
}

Future<void> _validateTransactionRefundState(
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
    if (original.isDeleted || original.type != FinanceTransactionType.expense) {
      throw StateError('只能对未删除的支出账单发起退款');
    }
    if (_refundPrecedesOriginal(transaction, original)) {
      throw StateError('退款时间不能早于原支出时间');
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
  if (activeRefunded > 0 &&
      transaction.type == FinanceTransactionType.expense) {
    final refunds = await _getActiveRefundsForTransaction(db, transaction.uuid);
    if (refunds.any((refund) => _refundPrecedesOriginal(refund, transaction))) {
      throw StateError('原支出时间不能晚于关联退款时间');
    }
  }
}

bool _isValidImportedTransaction(
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

bool _isValidRawTransactionType(Map<String, dynamic> raw) {
  final value = raw['type'];
  return const {'expense', 'income', 'refund', 'transfer'}.contains(value) ||
      const {0, 1, 2, 3, '0', '1', '2', '3'}.contains(value);
}

Map<String, dynamic> _normalizeRemoteFinanceEntrySource(
  Map<String, dynamic> raw,
) {
  final value = raw['source'];
  if (value == null ||
      const {'manual', 'import', 'ai', 'automation'}.contains(value)) {
    return raw;
  }
  // Keep the transaction itself when an older server has malformed source
  // metadata; losing the ledger row would also lose its amount and date.
  return {...raw, 'source': 'manual'};
}

bool _hasIncomingRefund(Object? rawTransactions) {
  if (rawTransactions is! List) return false;
  return rawTransactions.any((raw) {
    if (raw is! Map) return false;
    final type = raw['type'];
    return type == 'refund' || type == 2 || type == '2';
  });
}

bool _hasValidRawOptionalTransactionType(Map<String, dynamic> raw) {
  final value = raw['type'];
  return value == null || _isValidRawTransactionType(raw);
}

bool _hasValidRawRecurringFrequency(Map<String, dynamic> raw) {
  final value = raw['frequency'];
  return value == null ||
      _isValidRawEnumValue(
        value,
        FinanceRecurringFrequency.values.map((item) => item.name),
        FinanceRecurringFrequency.values.length,
      );
}

bool _hasValidRawLoanRepaymentMethod(Map<String, dynamic> raw) {
  final value = raw['repayment_method'] ?? raw['repaymentMethod'];
  return value == null ||
      _isValidRawEnumValue(
        value,
        FinanceLoanRepaymentMethod.values.map((item) => item.name),
        FinanceLoanRepaymentMethod.values.length,
      );
}

bool _isValidRawEnumValue(
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

bool _hasSafeRawFinanceTimestamps(Map<String, dynamic> raw) {
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
      DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      ).add(Duration(minutes: timezoneOffset));
    }
  } catch (_) {
    return false;
  }
  return true;
}

int? _rawFinanceTimestampMillis(dynamic value, {bool allowDateString = false}) {
  final timestamp = _rawFinanceInteger(value);
  if (timestamp != null) {
    return timestamp >= -_maxDateTimeMillis && timestamp <= _maxDateTimeMillis
        ? timestamp
        : null;
  }
  if (allowDateString && value is String) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed != null) {
      final millis = AppTimeFormats.toServerTimestamp(parsed);
      if (millis >= -_maxDateTimeMillis && millis <= _maxDateTimeMillis) {
        return millis;
      }
    }
  }
  return null;
}

int? _rawFinanceInteger(dynamic value) {
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

bool _isSafeRawFinanceAmount(dynamic value) {
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

bool _isSafeRawFinanceCount(dynamic value, int maximum) {
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

bool _hasValidRawFinanceDateKey(
  Map<String, dynamic> map,
  String snakeCaseKey,
  String camelCaseKey,
) {
  final value = map[snakeCaseKey] ?? map[camelCaseKey];
  return value is String && _isDateKey(value);
}

bool _hasValidRawFinanceMonthKey(Map<String, dynamic> map) {
  final value = map['month_key'] ?? map['monthKey'];
  return value is String && _monthKeyPattern.hasMatch(value);
}

bool _hasSafeRawIntegerRange(
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

bool _hasValidRawRecurringScheduleFields(Map<String, dynamic> map) {
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

bool _hasSafeOptionalRawIntegerRange(
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

bool _hasValidRawLoanInstallmentScheduleFields(Map<String, dynamic> map) =>
    _hasValidRawFinanceDateKey(map, 'due_date', 'dueDate') &&
    _hasSafeRawIntegerRange(
      map,
      'installment_index',
      'installmentIndex',
      1,
      FinanceLoanCalculator.maxTermMonths,
    );

int _compareRawLoanInstallmentMaps(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  final leftLoan = (left['loan_uuid'] ?? left['loanUuid'])?.toString() ?? '';
  final rightLoan = (right['loan_uuid'] ?? right['loanUuid'])?.toString() ?? '';
  final byLoan = leftLoan.compareTo(rightLoan);
  if (byLoan != 0) return byLoan;

  final leftIndex =
      _rawFinanceInteger(
        left['installment_index'] ?? left['installmentIndex'],
      ) ??
      0;
  final rightIndex =
      _rawFinanceInteger(
        right['installment_index'] ?? right['installmentIndex'],
      ) ??
      0;
  final byIndex = leftIndex.compareTo(rightIndex);
  if (byIndex != 0) return byIndex;

  final leftUpdatedAt =
      _rawFinanceTimestampMillis(
        left['updated_at'] ?? left['updatedAt'],
        allowDateString: true,
      ) ??
      0;
  final rightUpdatedAt =
      _rawFinanceTimestampMillis(
        right['updated_at'] ?? right['updatedAt'],
        allowDateString: true,
      ) ??
      0;
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

List<FinanceLoanInstallment> _deduplicateActiveLoanInstallments(
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

bool _hasSafeRawTemplateUseCount(Map<String, dynamic> map) =>
    _isSafeRawFinanceCount(
      map['use_count'] ?? map['useCount'],
      _maxTemplateUseCount,
    );

bool _hasValidRawCategoryType(Map<String, dynamic> map) {
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

bool _hasRawFinanceUuid(Map<String, dynamic> map) {
  final raw = map['uuid'] ?? map['id'];
  final value = raw?.toString().trim();
  return value != null && value.isNotEmpty && value != 'null';
}

bool _hasSafeRawFinanceAmount(
  Map<String, dynamic> map,
  String snakeCaseKey,
  String camelCaseKey,
) => _isSafeRawFinanceAmount(map[snakeCaseKey] ?? map[camelCaseKey]);

bool _hasSafeRawLoanInterestRate(Map<String, dynamic> map) {
  final value = map['annual_interest_rate_bps'] ?? map['annualInterestRateBps'];
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

bool _hasSafeRawLoanInstallmentAmounts(Map<String, dynamic> map) =>
    _hasSafeRawFinanceAmount(map, 'payment_minor', 'paymentMinor') &&
    _hasSafeRawFinanceAmount(map, 'principal_minor', 'principalMinor') &&
    _hasSafeRawFinanceAmount(map, 'interest_minor', 'interestMinor') &&
    _hasSafeRawFinanceAmount(
      map,
      'remaining_principal_minor',
      'remainingPrincipalMinor',
    );

bool _isValidLoan(FinanceLoan item) {
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

void _validateLoan(FinanceLoan loan) {
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

bool _isValidLoanInstallment(FinanceLoanInstallment item) {
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
      (item.paymentMethodUuid == null || (item.isPaid && (paidAt ?? 0) > 0));
}

Future<bool> _hasPaidLoanInstallments(
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

bool _sameLoanInstallmentSchedule(
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

bool _matchesLoanInstallmentSchedule(
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
      installment.remainingPrincipalMinor == expected.remainingPrincipalMinor;
}

bool _loanTermsDiffer(FinanceLoan left, FinanceLoan right) {
  return left.principalMinor != right.principalMinor ||
      left.currencyCode != right.currencyCode ||
      left.annualInterestRateBps != right.annualInterestRateBps ||
      left.termMonths != right.termMonths ||
      left.startDate != right.startDate ||
      left.repaymentDay != right.repaymentDay ||
      left.repaymentMethod != right.repaymentMethod;
}

void _mergeLoanEdits(
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

bool _isValidBudget(FinanceBudget item) {
  final balanceSnapshotAt = item.balanceSnapshotAt;
  final now = DateTime.now().millisecondsSinceEpoch;
  final hasValidBalanceSnapshot = item.isPaymentMethod
      ? balanceSnapshotAt == null ||
            (balanceSnapshotAt > 0 &&
                balanceSnapshotAt <= _maxDateTimeMillis &&
                balanceSnapshotAt <= now &&
                _isBalanceSnapshotForMonth(item.monthKey, balanceSnapshotAt))
      : balanceSnapshotAt == null;
  return item.uuid.trim().isNotEmpty &&
      !(item.categoryUuid != null && item.paymentMethodUuid != null) &&
      isSafeFinanceAmountMinor(item.amountMinor) &&
      (item.isPaymentMethod ? item.amountMinor >= 0 : item.amountMinor > 0) &&
      hasValidBalanceSnapshot &&
      _monthKeyPattern.hasMatch(item.monthKey);
}

bool _isBalanceSnapshotForMonth(String monthKey, int snapshotAt) {
  if (!_monthKeyPattern.hasMatch(monthKey)) return false;
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

bool _isValidBalanceSnapshotAt(String monthKey, int snapshotAt) {
  return snapshotAt > 0 &&
      snapshotAt <= DateTime.now().millisecondsSinceEpoch &&
      _isBalanceSnapshotForMonth(monthKey, snapshotAt);
}

bool _hasValidRawBalanceSnapshot(Map<String, dynamic> map) {
  final raw = map['balance_snapshot_at'] ?? map['balanceSnapshotAt'];
  if (raw == null) return true;
  final timestamp = _rawFinanceTimestampMillis(raw);
  return timestamp != null && timestamp > 0;
}

Future<bool> _hasValidBudgetScope(
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

bool _isValidRecurringRule(FinanceRecurringRule item) {
  if (item.uuid.trim().isEmpty) return false;
  try {
    _validateRecurringRule(item);
    return true;
  } catch (_) {
    return false;
  }
}

bool _isValidTemplate(FinanceEntryTemplate item) {
  if (item.uuid.trim().isEmpty) return false;
  try {
    _validateTemplate(item);
    return true;
  } catch (_) {
    return false;
  }
}

bool _isValidName(String value) => value.trim().isNotEmpty;

bool _hasValidRawFinanceName(Map<String, dynamic> map) {
  final value = map['name'];
  return value is String && value.trim().isNotEmpty;
}
