part of '../finance_models.dart';

class FinanceTransaction {
  String uuid;
  FinanceTransactionType type;
  int amountMinor;
  String currencyCode;
  String? categoryUuid;
  String? paymentMethodUuid;
  String? targetPaymentMethodUuid;
  String transactionDate;
  int? occurredAt;
  int timezoneOffsetMinutes;
  String? merchant;
  String? note;
  FinanceEntrySource source;
  String? relatedTodoUuid;
  String? relatedPlanBlockUuid;
  String? relatedTransactionUuid;
  String? installmentGroupUuid;
  int? installmentIndex;
  int? installmentCount;
  int? installmentTotalMinor;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;
  String? deviceId;
  bool pendingSync;

  FinanceTransaction({
    String? uuid,
    this.type = FinanceTransactionType.expense,
    required this.amountMinor,
    this.currencyCode = FinanceDefaults.defaultCurrencyCode,
    this.categoryUuid,
    this.paymentMethodUuid,
    this.targetPaymentMethodUuid,
    required this.transactionDate,
    int? occurredAt,
    int? timezoneOffsetMinutes,
    this.merchant,
    this.note,
    this.source = FinanceEntrySource.manual,
    this.relatedTodoUuid,
    this.relatedPlanBlockUuid,
    this.relatedTransactionUuid,
    this.installmentGroupUuid,
    this.installmentIndex,
    this.installmentCount,
    this.installmentTotalMinor,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  }) : timezoneOffsetMinutes =
           timezoneOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes,
       uuid = uuid ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
       occurredAt = occurredAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isExpenseLike =>
      type == FinanceTransactionType.expense ||
      type == FinanceTransactionType.refund;

  bool get isInstallment =>
      installmentGroupUuid?.trim().isNotEmpty == true &&
      (installmentCount ?? 0) > 1 &&
      (installmentIndex ?? 0) > 0;

  String? get installmentLabel =>
      isInstallment ? '${installmentIndex!}/${installmentCount!} 期' : null;

  /// Wall-clock time in the timezone saved with the transaction. Using the
  /// viewing device's timezone would make a valid occurrence look unrelated
  /// to its ledger date after travel or a sync to another timezone.
  DateTime? get occurrenceLocalTime {
    final timestamp = occurredAt;
    if (timestamp == null || timestamp <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      timestamp,
      isUtc: true,
    ).add(Duration(minutes: timezoneOffsetMinutes));
  }

  int balanceEventAt({int? snapshotAt}) {
    final timestamp = occurredAt;
    final occurred = occurrenceLocalTime;
    final ledgerDate = dateFromKey(transactionDate);
    final dateStartAt =
        DateTime.utc(
          ledgerDate.year,
          ledgerDate.month,
          ledgerDate.day,
        ).millisecondsSinceEpoch -
        timezoneOffsetMinutes * 60000;
    var eventAt = timestamp;
    if (eventAt == null || occurred == null) {
      // Legacy rows without a reliable time use their entry time, while a
      // future ledger date must still wait until that date begins.
      eventAt = createdAt > dateStartAt ? createdAt : dateStartAt;
    } else if (dateKey(occurred) != transactionDate) {
      final createdDate = dateKey(
        DateTime.fromMillisecondsSinceEpoch(
          createdAt,
          isUtc: true,
        ).add(Duration(minutes: timezoneOffsetMinutes)),
      );
      final occurrencePredatesEntry =
          timestamp != null && timestamp < createdAt;
      if (transactionDate.compareTo(createdDate) <= 0 ||
          occurrencePredatesEntry) {
        // A mismatched legacy occurrence timestamp should not rewrite an
        // account's balance before the row was entered. A future ledger day
        // may use its known occurrence time only if it is not older than the
        // row itself; stale timestamps must not make a planned bill apply now.
        eventAt = createdAt > dateStartAt ? createdAt : dateStartAt;
      }
    }
    if (snapshotAt != null &&
        eventAt <= snapshotAt &&
        eventAt ~/ 60000 == snapshotAt ~/ 60000 &&
        createdAt > snapshotAt) {
      return createdAt;
    }
    return eventAt;
  }

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
    pendingSync = true;
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'type': type.name,
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'category_uuid': categoryUuid,
    'payment_method_uuid': paymentMethodUuid,
    'target_payment_method_uuid': targetPaymentMethodUuid,
    'transaction_date': transactionDate,
    'occurred_at': occurredAt,
    'timezone_offset_minutes': timezoneOffsetMinutes,
    'merchant': merchant,
    'note': note,
    'source': source.name,
    'related_todo_uuid': relatedTodoUuid,
    'related_plan_block_uuid': relatedPlanBlockUuid,
    'related_transaction_uuid': relatedTransactionUuid,
    'installment_group_uuid': installmentGroupUuid,
    'installment_index': installmentIndex,
    'installment_count': installmentCount,
    'installment_total_minor': installmentTotalMinor,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'device_id': deviceId,
    'pending_sync': pendingSync ? 1 : 0,
  };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceTransaction.fromMap(Map<String, dynamic> map) {
    final amount = _int(map['amount_minor'] ?? map['amountMinor']);
    final createdAt = _timestamp(map['created_at'] ?? map['createdAt']);
    final occurredAt = _nullableInt(map['occurred_at'] ?? map['occurredAt']);
    final transactionDate =
        _string(map['transaction_date'] ?? map['transactionDate']) ??
        dateKey(DateTime.now());
    final timezoneOffsetMinutes = _nullableInt(
      map['timezone_offset_minutes'] ?? map['timezoneOffsetMinutes'],
    );
    final transaction = FinanceTransaction(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      type: _transactionType(map['type']),
      amountMinor: amount < 0 ? -amount : amount,
      currencyCode:
          _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      categoryUuid: _nullableString(
        map['category_uuid'] ?? map['categoryUuid'],
      ),
      paymentMethodUuid: _nullableString(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      targetPaymentMethodUuid: _nullableString(
        map['target_payment_method_uuid'] ?? map['targetPaymentMethodUuid'],
      ),
      transactionDate: transactionDate,
      occurredAt: occurredAt,
      timezoneOffsetMinutes:
          timezoneOffsetMinutes ??
          dateFromKey(transactionDate).timeZoneOffset.inMinutes,
      merchant: _nullableString(map['merchant']),
      note: _nullableString(map['note']),
      source: _entrySource(map['source']),
      relatedTodoUuid: _nullableString(
        map['related_todo_uuid'] ?? map['relatedTodoUuid'],
      ),
      relatedPlanBlockUuid: _nullableString(
        map['related_plan_block_uuid'] ?? map['relatedPlanBlockUuid'],
      ),
      relatedTransactionUuid: _nullableString(
        map['related_transaction_uuid'] ?? map['relatedTransactionUuid'],
      ),
      installmentGroupUuid: _nullableString(
        map['installment_group_uuid'] ?? map['installmentGroupUuid'],
      ),
      installmentIndex: _nullableInt(
        map['installment_index'] ?? map['installmentIndex'],
      ),
      installmentCount: _nullableInt(
        map['installment_count'] ?? map['installmentCount'],
      ),
      installmentTotalMinor: _nullableInt(
        map['installment_total_minor'] ?? map['installmentTotalMinor'],
      ),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      version: _int(map['version'], fallback: 1),
      createdAt: createdAt,
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      deviceId: _nullableString(map['device_id'] ?? map['deviceId']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
    if (occurredAt == null) transaction.occurredAt = null;
    return transaction;
  }
}

/// A bill recognized from text, an image, or the AI assistant.
///
/// A draft deliberately does not write to storage.  It is passed to the
/// normal entry editor so the user can review the amount, category, date and
/// note before saving it as a [FinanceTransaction].
class FinanceEntryDraft {
  FinanceTransactionType type;
  int amountMinor;
  String transactionDate;
  String? categoryUuid;
  String? categoryName;
  String? paymentMethodUuid;
  String? paymentMethodName;
  String? merchant;
  String? note;
  FinanceEntrySource source;
  String? originalText;
  bool isAdded;
  bool isIgnored;

  FinanceEntryDraft({
    required this.amountMinor,
    required this.transactionDate,
    this.type = FinanceTransactionType.expense,
    this.categoryUuid,
    this.categoryName,
    this.paymentMethodUuid,
    this.paymentMethodName,
    this.merchant,
    this.note,
    this.source = FinanceEntrySource.import,
    this.originalText,
    this.isAdded = false,
    this.isIgnored = false,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'amount_minor': amountMinor,
    'transaction_date': transactionDate,
    'category_uuid': categoryUuid,
    'category_name': categoryName,
    'payment_method_uuid': paymentMethodUuid,
    'payment_method_name': paymentMethodName,
    'merchant': merchant,
    'note': note,
    'source': source.name,
    'original_text': originalText,
    'is_added': isAdded,
    'is_ignored': isIgnored,
  };

  factory FinanceEntryDraft.fromJson(
    Map<String, dynamic> map, {
    DateTime? now,
    bool preserveRawDate = false,
  }) {
    final minorValue = map['amount_minor'] ?? map['amountMinor'];
    final amountMinor = minorValue == null
        ? _draftAmountMinor(
            map['amount'] ??
                map['amount_yuan'] ??
                map['amountYuan'] ??
                map['total'] ??
                map['total_amount'] ??
                map['totalAmount'] ??
                map['money'] ??
                map['price'],
          )
        : _safeDraftMinorValue(minorValue);
    return FinanceEntryDraft(
      type: _draftTransactionType(
        map['type'] ?? map['transaction_type'] ?? map['transactionType'],
      ),
      amountMinor: amountMinor,
      transactionDate: _draftTransactionDate(
        map['transaction_date'] ??
            map['transactionDate'] ??
            map['date'] ??
            map['transaction_day'],
        now: now,
        preserveRawDate: preserveRawDate,
      ),
      categoryUuid: _string(map['category_uuid'] ?? map['categoryUuid']),
      categoryName: _string(
        map['category_name'] ?? map['categoryName'] ?? map['category'],
      ),
      paymentMethodUuid: _string(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      paymentMethodName: _string(
        map['payment_method_name'] ??
            map['paymentMethodName'] ??
            map['payment_method'] ??
            map['paymentMethod'],
      ),
      merchant: _string(map['merchant'] ?? map['title'] ?? map['name']),
      note: _string(map['note'] ?? map['remark']),
      source: _entrySource(map['source']),
      originalText: _string(map['original_text'] ?? map['originalText']),
      isAdded: _bool(map['is_added'] ?? map['isAdded']),
      isIgnored: _bool(map['is_ignored'] ?? map['isIgnored']),
    );
  }

  static String _draftTransactionDate(
    dynamic value, {
    DateTime? now,
    required bool preserveRawDate,
  }) {
    final fallback = dateKey(now ?? DateTime.now());
    final raw = _string(value)?.trim();
    if (raw == null || raw.isEmpty) return fallback;
    if (preserveRawDate) return raw;

    final normalized = raw
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', '')
        .replaceAll('/', '-')
        .replaceAll('.', '-');
    final match = _financeDraftTransactionDatePattern.firstMatch(normalized);
    if (match == null) return fallback;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return fallback;
    }
    return dateKey(parsed);
  }

  static int _draftAmountMinor(dynamic value) {
    final normalized = (value is num ? value.toString() : value?.toString())
        ?.trim()
        .replaceAll(',', '')
        .replaceAll(_financeDraftAmountLeadingCurrencyPattern, '')
        .replaceAll(_financeDraftAmountTrailingUnitPattern, '');
    final match = _financeDraftAmountPattern.firstMatch(normalized ?? '');
    if (match == null) return 0;
    final wholeText = match.group(2) ?? '';
    final fraction = match.group(3) ?? '';
    if (wholeText.isEmpty && fraction.isEmpty) return 0;
    final whole = BigInt.tryParse(wholeText.isEmpty ? '0' : wholeText);
    if (whole == null) return 0;
    var amountMinor =
        whole * BigInt.from(100) +
        BigInt.tryParse(fraction.padRight(2, '0').substring(0, 2))!;
    if (fraction.length > 2 && fraction.codeUnitAt(2) >= 53) {
      amountMinor += BigInt.one;
    }
    if (amountMinor > BigInt.from(maxFinanceAmountMinor)) return 0;
    return amountMinor.toInt();
  }

  static int _safeDraftMinorValue(dynamic value) {
    BigInt? parsed;
    if (value is int) {
      parsed = BigInt.from(value);
    } else if (value is num &&
        value.isFinite &&
        value.abs() <= maxFinanceAmountMinor &&
        value == value.roundToDouble()) {
      parsed = BigInt.from(value.toInt());
    } else if (value is String) {
      parsed = BigInt.tryParse(value.trim());
    }
    if (parsed == null) return 0;
    final amountMinor = parsed.abs();
    if (amountMinor > BigInt.from(maxFinanceAmountMinor)) return 0;
    return amountMinor.toInt();
  }
}

FinanceTransactionType _draftTransactionType(dynamic raw) {
  final value = raw?.toString().trim().toLowerCase();
  if (value == 'income' ||
      value == '收入' ||
      value == '进账' ||
      value == '入账' ||
      value == '收款' ||
      value == '+') {
    return FinanceTransactionType.income;
  }
  if (value == 'refund' || value == '退款') {
    return FinanceTransactionType.refund;
  }
  return FinanceTransactionType.expense;
}

class FinanceBudget {
  static const String _uuidNamespace = '6ba7b812-9dad-11d1-80b4-00c04fd430c8';

  String uuid;
  String monthKey;
  String? categoryUuid;
  String? paymentMethodUuid;
  int amountMinor;
  String currencyCode;
  String? note;
  int? balanceSnapshotAt;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;
  String? deviceId;
  bool pendingSync;

  FinanceBudget({
    String? uuid,
    required this.monthKey,
    this.categoryUuid,
    this.paymentMethodUuid,
    required this.amountMinor,
    this.currencyCode = FinanceDefaults.defaultCurrencyCode,
    this.note,
    this.balanceSnapshotAt,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  }) : uuid = uuid ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  static String stableUuid(
    String monthKey,
    String? categoryUuid, {
    String? paymentMethodUuid,
  }) {
    final scope = paymentMethodUuid?.trim().isNotEmpty == true
        ? 'payment:${paymentMethodUuid!.trim()}'
        : categoryUuid?.trim().isNotEmpty == true
        ? categoryUuid!.trim()
        : 'overall';
    return const Uuid().v5(
      _uuidNamespace,
      'countdown-todo/finance-budget/v1/$monthKey/$scope',
    );
  }

  bool get isPaymentMethod => paymentMethodUuid != null;

  bool get isOverall => categoryUuid == null && paymentMethodUuid == null;

  /// Parent budgets already contain their child scopes in a combined total.
  static List<FinanceBudget> nonOverlappingCategories(
    Iterable<FinanceBudget> budgets,
    Iterable<FinanceCategory> categories,
  ) {
    final categoryMap = {
      for (final category in categories) category.uuid: category,
    };
    final scopes = <String, FinanceBudget>{};
    for (final budget in budgets) {
      final uuid = budget.categoryUuid;
      if (uuid == null || budget.isPaymentMethod || budget.isDeleted) continue;
      final current = scopes[uuid];
      if (current == null || budget.updatedAt > current.updatedAt) {
        scopes[uuid] = budget;
      }
    }
    final ancestors = <String, Set<String>>{};
    for (final uuid in scopes.keys) {
      final parents = <String>{};
      final visited = <String>{uuid};
      var category = categoryMap[uuid];
      while (category?.type == FinanceCategoryType.expense) {
        final parent = category!.parentUuid;
        if (parent == null || !visited.add(parent)) break;
        parents.add(parent);
        category = categoryMap[parent];
      }
      ancestors[uuid] = parents;
    }
    return [
      for (final entry in scopes.entries)
        if (!ancestors[entry.key]!.any(
          (parent) =>
              scopes.containsKey(parent) &&
              (!ancestors[parent]!.contains(entry.key) ||
                  parent.compareTo(entry.key) < 0),
        ))
          entry.value,
    ];
  }

  // Older rows used updated_at as the balance snapshot time. Keep that exact
  // instant even when a snapshot was edited from a different calendar month.
  int get effectiveBalanceSnapshotAt => balanceSnapshotAt ?? updatedAt;

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
    pendingSync = true;
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'month_key': monthKey,
    'category_uuid': categoryUuid,
    'payment_method_uuid': paymentMethodUuid,
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'note': note,
    'balance_snapshot_at': balanceSnapshotAt,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'device_id': deviceId,
    'pending_sync': pendingSync ? 1 : 0,
  };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceBudget.fromMap(Map<String, dynamic> map) {
    return FinanceBudget(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      monthKey:
          _string(map['month_key'] ?? map['monthKey']) ??
          financeMonthKey(DateTime.now()),
      categoryUuid: _nullableString(
        map['category_uuid'] ?? map['categoryUuid'],
      ),
      paymentMethodUuid: _nullableString(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      amountMinor: _int(map['amount_minor'] ?? map['amountMinor']).abs(),
      currencyCode:
          _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      note: _nullableString(map['note']),
      balanceSnapshotAt: _nullableInt(
        map['balance_snapshot_at'] ?? map['balanceSnapshotAt'],
      ),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      version: _int(map['version'], fallback: 1),
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      deviceId: _nullableString(map['device_id'] ?? map['deviceId']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
  }
}
