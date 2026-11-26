part of '../finance_models.dart';

/// 一笔账单的分期金额和发生日期。
class FinanceInstallmentAllocation {
  final int index;
  final int count;
  final int amountMinor;
  final DateTime date;

  const FinanceInstallmentAllocation({
    required this.index,
    required this.count,
    required this.amountMinor,
    required this.date,
  });
}

/// 负责将一笔账单按月拆分成金额精确相等的多笔交易。
abstract final class FinanceInstallmentCalculator {
  static const int minCount = 2;
  static const int maxCount = 60;

  /// 分摊到的每笔金额都必须大于 0，因此期数不能超过总金额（分）。
  static List<FinanceInstallmentAllocation> split({
    required int totalMinor,
    required int count,
    required DateTime startDate,
  }) {
    if (!isSafeFinanceAmountMinor(totalMinor) || totalMinor == 0) {
      throw ArgumentError.value(totalMinor, 'totalMinor', '金额必须大于 0');
    }
    if (count < minCount || count > maxCount) {
      throw ArgumentError.value(
        count,
        'count',
        '分期月数必须在 $minCount-$maxCount 之间',
      );
    }
    if (count > totalMinor) {
      throw ArgumentError.value(count, 'count', '分期月数不能超过金额的分（人民币分）');
    }

    final baseAmount = totalMinor ~/ count;
    final remainder = totalMinor % count;
    return List<FinanceInstallmentAllocation>.generate(count, (index) {
      // 无法整除的余数放在前几期，确保所有账单金额仍然是整数分，
      // 且各期相差最多 1 分。
      final amount = baseAmount + (index < remainder ? 1 : 0);
      return FinanceInstallmentAllocation(
        index: index + 1,
        count: count,
        amountMinor: amount,
        date: addMonthsPreservingDay(startDate, index),
      );
    });
  }

  /// 按原始日期的“日”推进月份，短月自动落到当月最后一天。
  static DateTime addMonthsPreservingDay(DateTime date, int months) {
    final target = DateTime(
      date.year,
      date.month + months,
      1,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(
      target.year,
      target.month,
      day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }
}

/// 贷款的还款方式。
enum FinanceLoanRepaymentMethod { equalPrincipalInterest, equalPrincipal }

extension FinanceLoanRepaymentMethodLabel on FinanceLoanRepaymentMethod {
  String get label {
    switch (this) {
      case FinanceLoanRepaymentMethod.equalPrincipalInterest:
        return '等额本息';
      case FinanceLoanRepaymentMethod.equalPrincipal:
        return '等额本金';
    }
  }
}

/// 一笔贷款还款计划中的一行，尚未包含数据库 UUID 和支付状态。
class FinanceLoanScheduleAllocation {
  final int index;
  final String dueDate;
  final int paymentMinor;
  final int principalMinor;
  final int interestMinor;
  final int remainingPrincipalMinor;

  const FinanceLoanScheduleAllocation({
    required this.index,
    required this.dueDate,
    required this.paymentMinor,
    required this.principalMinor,
    required this.interestMinor,
    required this.remainingPrincipalMinor,
  });
}

/// 根据本金、年利率、期限和还款方式生成按月还款计划。
abstract final class FinanceLoanCalculator {
  static const int minTermMonths = 1;
  static const int maxTermMonths = 360;
  static const int maxAnnualInterestRateBps = 10000;

  /// 利率用基点保存：1200 表示年利率 12.00%。
  static List<FinanceLoanScheduleAllocation> generate({
    required int principalMinor,
    required int annualInterestRateBps,
    required int termMonths,
    required DateTime startDate,
    required int repaymentDay,
    FinanceLoanRepaymentMethod repaymentMethod =
        FinanceLoanRepaymentMethod.equalPrincipalInterest,
  }) {
    if (!isSafeFinanceAmountMinor(principalMinor) || principalMinor == 0) {
      throw ArgumentError.value(principalMinor, 'principalMinor', '本金必须大于 0');
    }
    if (annualInterestRateBps < 0 ||
        annualInterestRateBps > maxAnnualInterestRateBps) {
      throw ArgumentError.value(
        annualInterestRateBps,
        'annualInterestRateBps',
        '年利率必须在 0%-100% 之间',
      );
    }
    if (termMonths < minTermMonths || termMonths > maxTermMonths) {
      throw ArgumentError.value(
        termMonths,
        'termMonths',
        '贷款期限必须在 $minTermMonths-$maxTermMonths 个月之间',
      );
    }
    if (termMonths > principalMinor) {
      throw ArgumentError.value(termMonths, 'termMonths', '贷款期限不能超过本金的分数金额');
    }
    if (repaymentDay < 1 || repaymentDay > 31) {
      throw ArgumentError.value(
        repaymentDay,
        'repaymentDay',
        '还款日必须在 1-31 日之间',
      );
    }

    final monthlyRate = annualInterestRateBps / 120000.0;
    final fixedPayment =
        repaymentMethod == FinanceLoanRepaymentMethod.equalPrincipalInterest &&
            monthlyRate > 0
        ? _annuityPayment(
            principalMinor: principalMinor,
            annualInterestRateBps: annualInterestRateBps,
            termMonths: termMonths,
          )
        : 0;
    final equalPrincipal = principalMinor ~/ termMonths;
    final principalRemainder = principalMinor % termMonths;
    var remaining = principalMinor;

    return List<FinanceLoanScheduleAllocation>.generate(termMonths, (index) {
      final interest = _monthlyInterestMinor(remaining, annualInterestRateBps);
      int principalPayment;
      if (repaymentMethod ==
              FinanceLoanRepaymentMethod.equalPrincipalInterest &&
          monthlyRate > 0) {
        principalPayment = index == termMonths - 1
            ? remaining
            : fixedPayment - interest;
        if (principalPayment <= 0 && remaining > 0) principalPayment = 1;
      } else {
        principalPayment =
            equalPrincipal + (index < principalRemainder ? 1 : 0);
      }
      if (principalPayment > remaining) principalPayment = remaining;
      if (principalPayment > maxFinanceAmountMinor - interest) {
        throw ArgumentError.value(
          principalPayment,
          'paymentMinor',
          '每期还款金额超出可保存范围',
        );
      }
      final payment = principalPayment + interest;
      remaining -= principalPayment;
      return FinanceLoanScheduleAllocation(
        index: index + 1,
        dueDate: dateKey(_dueDate(startDate, repaymentDay, index + 1)),
        paymentMinor: payment,
        principalMinor: principalPayment,
        interestMinor: interest,
        remainingPrincipalMinor: remaining,
      );
    });
  }

  static int _annuityPayment({
    required int principalMinor,
    required int annualInterestRateBps,
    required int termMonths,
  }) {
    const monthlyRateDenominator = 120000;
    final denominatorBase = BigInt.from(monthlyRateDenominator);
    final rateNumerator = BigInt.from(annualInterestRateBps);
    final growth = (denominatorBase + rateNumerator).pow(termMonths);
    final baseGrowth = denominatorBase.pow(termMonths);
    final payment = _roundPositiveFractionHalfUp(
      BigInt.from(principalMinor) * rateNumerator * growth,
      denominatorBase * (growth - baseGrowth),
    );
    if (payment > BigInt.from(maxFinanceAmountMinor)) {
      throw ArgumentError.value(
        principalMinor,
        'principalMinor',
        '每期还款金额超出可保存范围',
      );
    }
    return payment.toInt();
  }

  /// Round monthly interest in integer minor units. Multiplying large balances
  /// by a double rate can move a value across a half-cent boundary.
  static int _monthlyInterestMinor(int principalMinor, int annualRateBps) {
    final numerator = BigInt.from(principalMinor) * BigInt.from(annualRateBps);
    final rounded = _roundPositiveFractionHalfUp(
      numerator,
      BigInt.from(120000),
    );
    return rounded.toInt();
  }

  static BigInt _roundPositiveFractionHalfUp(
    BigInt numerator,
    BigInt denominator,
  ) {
    final quotient = numerator ~/ denominator;
    final remainder = numerator % denominator;
    return quotient +
        (remainder * BigInt.from(2) >= denominator ? BigInt.one : BigInt.zero);
  }

  static DateTime _dueDate(
    DateTime startDate,
    int repaymentDay,
    int monthIndex,
  ) {
    final target = DateTime(startDate.year, startDate.month + monthIndex, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month, math.min(repaymentDay, lastDay));
  }
}

/// 贷款主记录。金额仍使用人民币分，利率用基点保存。
class FinanceLoan {
  String uuid;
  String name;
  String? lender;
  int principalMinor;
  String currencyCode;
  int annualInterestRateBps;
  int termMonths;
  String startDate;
  int repaymentDay;
  FinanceLoanRepaymentMethod repaymentMethod;
  String? note;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;
  String? deviceId;
  bool pendingSync;

  FinanceLoan({
    String? uuid,
    required this.name,
    this.lender,
    required this.principalMinor,
    this.currencyCode = FinanceDefaults.defaultCurrencyCode,
    this.annualInterestRateBps = 0,
    required this.termMonths,
    required this.startDate,
    required this.repaymentDay,
    this.repaymentMethod = FinanceLoanRepaymentMethod.equalPrincipalInterest,
    this.note,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  }) : uuid = uuid ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
    pendingSync = true;
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'name': name,
    'lender': lender,
    'principal_minor': principalMinor,
    'currency_code': currencyCode,
    'annual_interest_rate_bps': annualInterestRateBps,
    'term_months': termMonths,
    'start_date': startDate,
    'repayment_day': repaymentDay,
    'repayment_method': repaymentMethod.name,
    'note': note,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'device_id': deviceId,
    'pending_sync': pendingSync ? 1 : 0,
  };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceLoan.fromMap(Map<String, dynamic> map) {
    return FinanceLoan(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      name: _string(map['name']) ?? '未命名贷款',
      lender: _nullableString(map['lender']),
      principalMinor: _int(map['principal_minor'] ?? map['principalMinor'])
          .abs(),
      currencyCode:
          _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      annualInterestRateBps: _int(
        map['annual_interest_rate_bps'] ?? map['annualInterestRateBps'],
      ).clamp(0, FinanceLoanCalculator.maxAnnualInterestRateBps),
      termMonths: _int(
        map['term_months'] ?? map['termMonths'],
        fallback: FinanceLoanCalculator.minTermMonths,
      ),
      startDate:
          _string(map['start_date'] ?? map['startDate']) ??
          dateKey(DateTime.now()),
      repaymentDay: _int(
        map['repayment_day'] ?? map['repaymentDay'],
        fallback: 1,
      ),
      repaymentMethod: _loanRepaymentMethod(
        map['repayment_method'] ?? map['repaymentMethod'],
      ),
      note: _nullableString(map['note']),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      version: _int(map['version'], fallback: 1),
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      deviceId: _nullableString(map['device_id'] ?? map['deviceId']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
  }
}

String financeLoanDisplayName(
  FinanceLoan loan,
  Iterable<FinanceLoan> loans, {
  bool includeDeleted = false,
}) {
  final normalizedName = _normalizeFinanceDisplayName(loan.name);
  final sameNameLoans =
      loans
          .where(
            (item) =>
                (includeDeleted || !item.isDeleted) &&
                _normalizeFinanceDisplayName(item.name) == normalizedName,
          )
          .toList()
        ..sort((left, right) {
          final createdAt = left.createdAt.compareTo(right.createdAt);
          return createdAt != 0 ? createdAt : left.uuid.compareTo(right.uuid);
        });
  if (sameNameLoans.length < 2) return loan.name;
  final index = sameNameLoans.indexWhere((item) => item.uuid == loan.uuid);
  if (index < 0) return loan.name;
  return '${loan.name}（同名贷款 ${index + 1}/${sameNameLoans.length}）';
}

/// 贷款的一期还款记录，保存计划金额和是否已完成还款。
class FinanceLoanInstallment {
  String uuid;
  String loanUuid;
  int installmentIndex;
  String dueDate;
  int paymentMinor;
  int principalMinor;
  int interestMinor;
  int remainingPrincipalMinor;
  bool isPaid;
  int? paidAt;
  String? paymentMethodUuid;
  String? interestTransactionUuid;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;
  String? deviceId;
  bool pendingSync;

  FinanceLoanInstallment({
    String? uuid,
    required this.loanUuid,
    required this.installmentIndex,
    required this.dueDate,
    required this.paymentMinor,
    required this.principalMinor,
    required this.interestMinor,
    required this.remainingPrincipalMinor,
    this.isPaid = false,
    this.paidAt,
    this.paymentMethodUuid,
    this.interestTransactionUuid,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  }) : uuid = uuid ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isOverdue => isOverdueAt(DateTime.now());

  bool isOverdueAt(DateTime now) {
    if (isPaid) return false;
    return dateFromKey(dueDate).isBefore(CalendarDateMath.dateOnly(now));
  }

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
    pendingSync = true;
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'loan_uuid': loanUuid,
    'installment_index': installmentIndex,
    'due_date': dueDate,
    'payment_minor': paymentMinor,
    'principal_minor': principalMinor,
    'interest_minor': interestMinor,
    'remaining_principal_minor': remainingPrincipalMinor,
    'is_paid': isPaid ? 1 : 0,
    'paid_at': paidAt,
    'payment_method_uuid': paymentMethodUuid,
    'interest_transaction_uuid': interestTransactionUuid,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'device_id': deviceId,
    'pending_sync': pendingSync ? 1 : 0,
  };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceLoanInstallment.fromMap(Map<String, dynamic> map) {
    return FinanceLoanInstallment(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      loanUuid: _string(map['loan_uuid'] ?? map['loanUuid']) ?? '',
      installmentIndex: _int(
        map['installment_index'] ?? map['installmentIndex'],
        fallback: 1,
      ),
      dueDate:
          _string(map['due_date'] ?? map['dueDate']) ?? dateKey(DateTime.now()),
      paymentMinor: _int(map['payment_minor'] ?? map['paymentMinor']).abs(),
      principalMinor: _int(map['principal_minor'] ?? map['principalMinor'])
          .abs(),
      interestMinor: _int(map['interest_minor'] ?? map['interestMinor']).abs(),
      remainingPrincipalMinor: _int(
        map['remaining_principal_minor'] ?? map['remainingPrincipalMinor'],
      ).abs(),
      isPaid: _bool(map['is_paid'] ?? map['isPaid']),
      paidAt: _nullableInt(map['paid_at'] ?? map['paidAt']),
      paymentMethodUuid: _nullableString(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      interestTransactionUuid: _nullableString(
        map['interest_transaction_uuid'] ?? map['interestTransactionUuid'],
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

class FinanceLoanOverview {
  final FinanceLoan loan;
  final List<FinanceLoanInstallment> installments;

  const FinanceLoanOverview({required this.loan, required this.installments});

  int get paidPrincipalMinor => installments
      .where((item) => item.isPaid)
      .fold(0, (sum, item) => sum + item.principalMinor);

  int get outstandingPrincipalMinor {
    final value = loan.principalMinor - paidPrincipalMinor;
    return value < 0 ? 0 : value;
  }

  int get totalInterestMinor =>
      installments.fold(0, (sum, item) => sum + item.interestMinor);

  int get paidInterestMinor => installments
      .where((item) => item.isPaid)
      .fold(0, (sum, item) => sum + item.interestMinor);

  int get paidCount => installments.where((item) => item.isPaid).length;

  FinanceLoanInstallment? get nextInstallment {
    for (final installment in installments) {
      if (!installment.isPaid) return installment;
    }
    return null;
  }

  bool get isPaidOff =>
      installments.isNotEmpty && installments.every((item) => item.isPaid);
}

String formatFinanceInterestRate(int basisPoints) {
  final value = (basisPoints / 100).toStringAsFixed(2);
  return '${value.replaceFirst(_financeInterestRateDisplayPattern, '')}%';
}

/// 解析百分比形式的年利率，例如 12、12.5、12.50%。
int? parseFinanceInterestRate(String raw) {
  final input = raw.trim().replaceAll('%', '').replaceAll(',', '');
  if (!_financeInterestRateInputPattern.hasMatch(input)) return null;
  final parts = input.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  final basisPoints =
      whole * 100 + (int.tryParse(fraction.padRight(2, '0')) ?? 0);
  return basisPoints <= FinanceLoanCalculator.maxAnnualInterestRateBps
      ? basisPoints
      : null;
}
