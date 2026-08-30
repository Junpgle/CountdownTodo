import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../../utils/json_value_parser.dart';

/// 账单的现金流类型。
///
/// 金额在模型中始终保存为正整数（人民币分），方向由该枚举决定。
enum FinanceTransactionType { expense, income, refund }

enum FinanceCategoryType { expense, income }

enum FinanceEntrySource { manual, import, ai, automation }

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
    if (totalMinor <= 0) {
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
      throw ArgumentError.value(
        count,
        'count',
        '分期月数不能超过金额的分（人民币分）',
      );
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
enum FinanceLoanRepaymentMethod {
  equalPrincipalInterest,
  equalPrincipal,
}

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
    if (principalMinor <= 0) {
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
      throw ArgumentError.value(
        termMonths,
        'termMonths',
        '贷款期限不能超过本金的分数金额',
      );
    }
    if (repaymentDay < 1 || repaymentDay > 31) {
      throw ArgumentError.value(
          repaymentDay, 'repaymentDay', '还款日必须在 1-31 日之间');
    }

    final monthlyRate = annualInterestRateBps / 120000.0;
    final fixedPayment =
        repaymentMethod == FinanceLoanRepaymentMethod.equalPrincipalInterest &&
                monthlyRate > 0
            ? _annuityPayment(
                principalMinor: principalMinor,
                monthlyRate: monthlyRate,
                termMonths: termMonths,
              )
            : 0;
    final equalPrincipal = principalMinor ~/ termMonths;
    final principalRemainder = principalMinor % termMonths;
    var remaining = principalMinor;

    return List<FinanceLoanScheduleAllocation>.generate(termMonths, (index) {
      final interest = (remaining * monthlyRate).round();
      int principalPayment;
      if (repaymentMethod ==
              FinanceLoanRepaymentMethod.equalPrincipalInterest &&
          monthlyRate > 0) {
        principalPayment =
            index == termMonths - 1 ? remaining : fixedPayment - interest;
        if (principalPayment <= 0 && remaining > 0) principalPayment = 1;
      } else {
        principalPayment =
            equalPrincipal + (index < principalRemainder ? 1 : 0);
      }
      if (principalPayment > remaining) principalPayment = remaining;
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
    required double monthlyRate,
    required int termMonths,
  }) {
    final factor = math.pow(1 + monthlyRate, termMonths).toDouble();
    final payment = principalMinor * monthlyRate * factor / (factor - 1);
    return payment.round().clamp(1, 9007199254740991).toInt();
  }

  static DateTime _dueDate(
      DateTime startDate, int repaymentDay, int monthIndex) {
    final target = DateTime(startDate.year, startDate.month + monthIndex, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
      target.year,
      target.month,
      math.min(repaymentDay, lastDay),
    );
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
  })  : uuid = uuid ?? const Uuid().v4(),
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
      principalMinor:
          _int(map['principal_minor'] ?? map['principalMinor']).abs(),
      currencyCode: _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      annualInterestRateBps: _int(
        map['annual_interest_rate_bps'] ?? map['annualInterestRateBps'],
      ).clamp(0, FinanceLoanCalculator.maxAnnualInterestRateBps),
      termMonths: _int(
        map['term_months'] ?? map['termMonths'],
        fallback: FinanceLoanCalculator.minTermMonths,
      ),
      startDate: _string(map['start_date'] ?? map['startDate']) ??
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
    this.interestTransactionUuid,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  })  : uuid = uuid ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isOverdue {
    if (isPaid) return false;
    final today = DateTime.now();
    return dateFromKey(dueDate).isBefore(
      DateTime(today.year, today.month, today.day),
    );
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
      principalMinor:
          _int(map['principal_minor'] ?? map['principalMinor']).abs(),
      interestMinor: _int(map['interest_minor'] ?? map['interestMinor']).abs(),
      remainingPrincipalMinor: _int(
        map['remaining_principal_minor'] ?? map['remainingPrincipalMinor'],
      ).abs(),
      isPaid: _bool(map['is_paid'] ?? map['isPaid']),
      paidAt: _nullableInt(map['paid_at'] ?? map['paidAt']),
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

  const FinanceLoanOverview({
    required this.loan,
    required this.installments,
  });

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
  return '${value.replaceFirst(RegExp(r'\.?0+$'), '')}%';
}

/// 解析百分比形式的年利率，例如 12、12.5、12.50%。
int? parseFinanceInterestRate(String raw) {
  final input = raw.trim().replaceAll('%', '').replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(input)) return null;
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

/// 周期账单的重复频率。
enum FinanceRecurringFrequency { monthly, yearly }

extension FinanceTransactionTypeLabel on FinanceTransactionType {
  String get label {
    switch (this) {
      case FinanceTransactionType.expense:
        return '支出';
      case FinanceTransactionType.income:
        return '收入';
      case FinanceTransactionType.refund:
        return '退款';
    }
  }

  String get signedPrefix => this == FinanceTransactionType.expense ? '-' : '+';
}

extension FinanceCategoryTypeLabel on FinanceCategoryType {
  String get label => this == FinanceCategoryType.expense ? '支出' : '收入';
}

extension FinanceEntrySourceLabel on FinanceEntrySource {
  String get label {
    switch (this) {
      case FinanceEntrySource.manual:
        return '手动';
      case FinanceEntrySource.import:
        return '导入';
      case FinanceEntrySource.ai:
        return 'AI';
      case FinanceEntrySource.automation:
        return '自动';
    }
  }
}

extension FinanceRecurringFrequencyLabel on FinanceRecurringFrequency {
  String get label {
    switch (this) {
      case FinanceRecurringFrequency.monthly:
        return '每月';
      case FinanceRecurringFrequency.yearly:
        return '每年';
    }
  }
}

/// 记账默认数据使用稳定 ID，保证同一账号的多设备不会重复生成系统分类。
abstract final class FinanceDefaults {
  static const String defaultCurrencyCode = 'CNY';

  static const List<Map<String, dynamic>> categories = [
    {
      'uuid': 'finance-system-category-food',
      'name': '餐饮',
      'icon': '🍜',
      'type': 'expense',
      'sort_order': 10,
    },
    {
      'uuid': 'finance-system-category-transport',
      'name': '交通',
      'icon': '🚇',
      'type': 'expense',
      'sort_order': 20,
    },
    {
      'uuid': 'finance-system-category-shopping',
      'name': '购物',
      'icon': '🛍️',
      'type': 'expense',
      'sort_order': 30,
    },
    {
      'uuid': 'finance-system-category-housing',
      'name': '居住',
      'icon': '🏠',
      'type': 'expense',
      'sort_order': 40,
    },
    {
      'uuid': 'finance-system-category-learning',
      'name': '学习',
      'icon': '📚',
      'type': 'expense',
      'sort_order': 50,
    },
    {
      'uuid': 'finance-system-category-entertainment',
      'name': '娱乐',
      'icon': '🎮',
      'type': 'expense',
      'sort_order': 60,
    },
    {
      'uuid': 'finance-system-category-health',
      'name': '健康',
      'icon': '💊',
      'type': 'expense',
      'sort_order': 70,
    },
    {
      'uuid': 'finance-system-category-social',
      'name': '社交',
      'icon': '🎁',
      'type': 'expense',
      'sort_order': 80,
    },
    {
      'uuid': 'finance-system-category-subscription',
      'name': '订阅',
      'icon': '🔔',
      'type': 'expense',
      'sort_order': 90,
    },
    {
      'uuid': 'finance-system-category-ai-service',
      'name': 'AI 服务',
      'icon': '✨',
      'type': 'expense',
      'sort_order': 95,
    },
    {
      'uuid': 'finance-system-category-loan-interest',
      'name': '贷款利息',
      'icon': '🏦',
      'type': 'expense',
      'sort_order': 97,
    },
    {
      'uuid': 'finance-system-category-other-expense',
      'name': '其他',
      'icon': '📦',
      'type': 'expense',
      'sort_order': 100,
    },
    {
      'uuid': 'finance-system-category-salary',
      'name': '工资',
      'icon': '💼',
      'type': 'income',
      'sort_order': 10,
    },
    {
      'uuid': 'finance-system-category-pocket-money',
      'name': '零花钱',
      'icon': '💰',
      'type': 'income',
      'sort_order': 20,
    },
    {
      'uuid': 'finance-system-category-bonus',
      'name': '奖金',
      'icon': '🏆',
      'type': 'income',
      'sort_order': 30,
    },
    {
      'uuid': 'finance-system-category-refund',
      'name': '退款',
      'icon': '↩️',
      'type': 'income',
      'sort_order': 40,
    },
    {
      'uuid': 'finance-system-category-other-income',
      'name': '其他',
      'icon': '➕',
      'type': 'income',
      'sort_order': 100,
    },
  ];

  static const List<Map<String, dynamic>> paymentMethods = [
    {
      'uuid': 'finance-system-payment-wechat',
      'name': '微信',
      'icon': '💬',
      'sort_order': 10,
    },
    {
      'uuid': 'finance-system-payment-alipay',
      'name': '支付宝',
      'icon': '🔵',
      'sort_order': 20,
    },
    {
      'uuid': 'finance-system-payment-bank',
      'name': '银行卡',
      'icon': '💳',
      'sort_order': 30,
    },
    {
      'uuid': 'finance-system-payment-cash',
      'name': '现金',
      'icon': '💵',
      'sort_order': 40,
    },
    {
      'uuid': 'finance-system-payment-credit',
      'name': '信用卡',
      'icon': '💳',
      'sort_order': 50,
    },
    {
      'uuid': 'finance-system-payment-other',
      'name': '其他',
      'icon': '💼',
      'sort_order': 100,
    },
  ];
}

class FinanceCategory {
  String uuid;
  String name;
  FinanceCategoryType type;
  String icon;
  int? colorValue;
  String? parentUuid;
  bool isSystem;
  bool isArchived;
  bool isDeleted;
  int sortOrder;
  int version;
  int createdAt;
  int updatedAt;
  bool pendingSync;

  FinanceCategory({
    String? uuid,
    required this.name,
    this.type = FinanceCategoryType.expense,
    this.icon = '📦',
    this.colorValue,
    this.parentUuid,
    this.isSystem = false,
    this.isArchived = false,
    this.isDeleted = false,
    this.sortOrder = 0,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.pendingSync = false,
  })  : uuid = uuid ?? const Uuid().v4(),
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
        'type': type.name,
        'icon': icon,
        'color_value': colorValue,
        'parent_uuid': parentUuid,
        'is_system': isSystem ? 1 : 0,
        'is_archived': isArchived ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'sort_order': sortOrder,
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'pending_sync': pendingSync ? 1 : 0,
      };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceCategory.fromMap(Map<String, dynamic> map) {
    return FinanceCategory(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      name: _string(map['name']) ?? '未命名分类',
      type: _categoryType(map['type'] ?? map['category_type']),
      icon: _string(map['icon']) ?? '📦',
      colorValue: _nullableInt(map['color_value'] ?? map['colorValue']),
      parentUuid: _nullableString(map['parent_uuid'] ?? map['parentUuid']),
      isSystem: _bool(map['is_system'] ?? map['isSystem']),
      isArchived: _bool(map['is_archived'] ?? map['isArchived']),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      sortOrder: _int(map['sort_order'] ?? map['sortOrder']),
      version: _int(map['version'], fallback: 1),
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
  }
}

class FinancePaymentMethod {
  String uuid;
  String name;
  String icon;
  int? colorValue;
  bool isSystem;
  bool isArchived;
  bool isDeleted;
  int sortOrder;
  int version;
  int createdAt;
  int updatedAt;
  bool pendingSync;

  FinancePaymentMethod({
    String? uuid,
    required this.name,
    this.icon = '💼',
    this.colorValue,
    this.isSystem = false,
    this.isArchived = false,
    this.isDeleted = false,
    this.sortOrder = 0,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.pendingSync = false,
  })  : uuid = uuid ?? const Uuid().v4(),
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
        'icon': icon,
        'color_value': colorValue,
        'is_system': isSystem ? 1 : 0,
        'is_archived': isArchived ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'sort_order': sortOrder,
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'pending_sync': pendingSync ? 1 : 0,
      };

  Map<String, dynamic> toJson() => toMap();

  factory FinancePaymentMethod.fromMap(Map<String, dynamic> map) {
    return FinancePaymentMethod(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      name: _string(map['name']) ?? '其他',
      icon: _string(map['icon']) ?? '💼',
      colorValue: _nullableInt(map['color_value'] ?? map['colorValue']),
      isSystem: _bool(map['is_system'] ?? map['isSystem']),
      isArchived: _bool(map['is_archived'] ?? map['isArchived']),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      sortOrder: _int(map['sort_order'] ?? map['sortOrder']),
      version: _int(map['version'], fallback: 1),
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
  }
}

class FinanceTransaction {
  String uuid;
  FinanceTransactionType type;
  int amountMinor;
  String currencyCode;
  String? categoryUuid;
  String? paymentMethodUuid;
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
    required this.transactionDate,
    int? occurredAt,
    this.timezoneOffsetMinutes = 0,
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
  })  : uuid = uuid ?? const Uuid().v4(),
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
    return FinanceTransaction(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      type: _transactionType(map['type']),
      amountMinor: amount < 0 ? -amount : amount,
      currencyCode: _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      categoryUuid:
          _nullableString(map['category_uuid'] ?? map['categoryUuid']),
      paymentMethodUuid: _nullableString(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      transactionDate: _string(
            map['transaction_date'] ?? map['transactionDate'],
          ) ??
          dateKey(DateTime.now()),
      occurredAt: _nullableInt(map['occurred_at'] ?? map['occurredAt']),
      timezoneOffsetMinutes: _int(
        map['timezone_offset_minutes'] ?? map['timezoneOffsetMinutes'],
      ),
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
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      deviceId: _nullableString(map['device_id'] ?? map['deviceId']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
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

  factory FinanceEntryDraft.fromJson(Map<String, dynamic> map) {
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
        : _int(minorValue).abs();
    return FinanceEntryDraft(
      type: _draftTransactionType(
        map['type'] ?? map['transaction_type'] ?? map['transactionType'],
      ),
      amountMinor: amountMinor,
      transactionDate: _string(
            map['transaction_date'] ??
                map['transactionDate'] ??
                map['date'] ??
                map['transaction_day'],
          ) ??
          dateKey(DateTime.now()),
      categoryUuid: _string(
        map['category_uuid'] ?? map['categoryUuid'],
      ),
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

  static int _draftAmountMinor(dynamic value) {
    if (value is num) return (value.toDouble() * 100).round().abs();
    final normalized = value
        ?.toString()
        .trim()
        .replaceAll(',', '')
        .replaceAll(RegExp(r'^[¥￥$€£]'), '')
        .replaceAll(
            RegExp(r'\s*(?:元|块|人民币|CNY)\s*$', caseSensitive: false), '');
    final parsed = double.tryParse(normalized ?? '');
    return parsed == null ? 0 : (parsed * 100).round().abs();
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
  String uuid;
  String monthKey;
  String? categoryUuid;
  int amountMinor;
  String currencyCode;
  String? note;
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
    required this.amountMinor,
    this.currencyCode = FinanceDefaults.defaultCurrencyCode,
    this.note,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  })  : uuid = uuid ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isOverall => categoryUuid == null;

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
        'amount_minor': amountMinor,
        'currency_code': currencyCode,
        'note': note,
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
      monthKey: _string(map['month_key'] ?? map['monthKey']) ??
          financeMonthKey(DateTime.now()),
      categoryUuid:
          _nullableString(map['category_uuid'] ?? map['categoryUuid']),
      amountMinor: _int(map['amount_minor'] ?? map['amountMinor']).abs(),
      currencyCode: _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
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

/// 周期账单规则。
///
/// `dayOfMonth` 在每月/每年的目标月份中使用，遇到短月时自动落在该月
/// 最后一天。`lastGeneratedPeriod` 是幂等标记：同一周期只允许生成一笔
/// 自动账单，避免应用重复启动造成重复记账。
class FinanceRecurringRule {
  String uuid;
  String name;
  FinanceTransactionType type;
  int amountMinor;
  String currencyCode;
  String? categoryUuid;
  String? paymentMethodUuid;
  String? merchant;
  String? note;
  FinanceRecurringFrequency frequency;
  int dayOfMonth;
  int monthOfYear;
  String startDate;
  String? endDate;
  int reminderMinutes;
  bool autoGenerate;
  bool isEnabled;
  bool isDeleted;
  String? lastGeneratedPeriod;
  int version;
  int createdAt;
  int updatedAt;
  String? deviceId;
  bool pendingSync;

  FinanceRecurringRule({
    String? uuid,
    required this.name,
    this.type = FinanceTransactionType.expense,
    required this.amountMinor,
    this.currencyCode = FinanceDefaults.defaultCurrencyCode,
    this.categoryUuid,
    this.paymentMethodUuid,
    this.merchant,
    this.note,
    this.frequency = FinanceRecurringFrequency.monthly,
    this.dayOfMonth = 1,
    this.monthOfYear = 1,
    required this.startDate,
    this.endDate,
    this.reminderMinutes = 1440,
    this.autoGenerate = true,
    this.isEnabled = true,
    this.isDeleted = false,
    this.lastGeneratedPeriod,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  })  : uuid = uuid ?? const Uuid().v4(),
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
        'type': type.name,
        'amount_minor': amountMinor,
        'currency_code': currencyCode,
        'category_uuid': categoryUuid,
        'payment_method_uuid': paymentMethodUuid,
        'merchant': merchant,
        'note': note,
        'frequency': frequency.name,
        'day_of_month': dayOfMonth,
        'month_of_year': monthOfYear,
        'start_date': startDate,
        'end_date': endDate,
        'reminder_minutes': reminderMinutes,
        'auto_generate': autoGenerate ? 1 : 0,
        'is_enabled': isEnabled ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
        'last_generated_period': lastGeneratedPeriod,
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'device_id': deviceId,
        'pending_sync': pendingSync ? 1 : 0,
      };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceRecurringRule.fromMap(Map<String, dynamic> map) {
    return FinanceRecurringRule(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      name: _string(map['name']) ?? '未命名周期账单',
      type: _transactionType(map['type']),
      amountMinor: _int(map['amount_minor'] ?? map['amountMinor']).abs(),
      currencyCode: _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      categoryUuid:
          _nullableString(map['category_uuid'] ?? map['categoryUuid']),
      paymentMethodUuid: _nullableString(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      merchant: _nullableString(map['merchant']),
      note: _nullableString(map['note']),
      frequency: _recurringFrequency(map['frequency']),
      dayOfMonth: _int(map['day_of_month'] ?? map['dayOfMonth'], fallback: 1),
      monthOfYear:
          _int(map['month_of_year'] ?? map['monthOfYear'], fallback: 1),
      startDate: _string(map['start_date'] ?? map['startDate']) ??
          dateKey(DateTime.now()),
      endDate: _nullableString(map['end_date'] ?? map['endDate']),
      reminderMinutes: _int(
        map['reminder_minutes'] ?? map['reminderMinutes'],
        fallback: 1440,
      ),
      autoGenerate: _boolOrDefault(
        map['auto_generate'] ?? map['autoGenerate'],
        true,
      ),
      isEnabled: _boolOrDefault(
        map['is_enabled'] ?? map['isEnabled'],
        true,
      ),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      lastGeneratedPeriod: _nullableString(
        map['last_generated_period'] ?? map['lastGeneratedPeriod'],
      ),
      version: _int(map['version'], fallback: 1),
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      deviceId: _nullableString(map['device_id'] ?? map['deviceId']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
  }
}

/// 快捷记账模板。模板只保存默认字段，不会直接产生账单。
class FinanceEntryTemplate {
  String uuid;
  String name;
  FinanceTransactionType type;
  int amountMinor;
  String currencyCode;
  String? categoryUuid;
  String? paymentMethodUuid;
  String? merchant;
  String? note;
  int useCount;
  int? lastUsedAt;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;
  String? deviceId;
  bool pendingSync;

  FinanceEntryTemplate({
    String? uuid,
    required this.name,
    this.type = FinanceTransactionType.expense,
    required this.amountMinor,
    this.currencyCode = FinanceDefaults.defaultCurrencyCode,
    this.categoryUuid,
    this.paymentMethodUuid,
    this.merchant,
    this.note,
    this.useCount = 0,
    this.lastUsedAt,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  })  : uuid = uuid ?? const Uuid().v4(),
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
        'type': type.name,
        'amount_minor': amountMinor,
        'currency_code': currencyCode,
        'category_uuid': categoryUuid,
        'payment_method_uuid': paymentMethodUuid,
        'merchant': merchant,
        'note': note,
        'use_count': useCount,
        'last_used_at': lastUsedAt,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'device_id': deviceId,
        'pending_sync': pendingSync ? 1 : 0,
      };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceEntryTemplate.fromMap(Map<String, dynamic> map) {
    return FinanceEntryTemplate(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      name: _string(map['name']) ?? '未命名模板',
      type: _transactionType(map['type']),
      amountMinor: _int(map['amount_minor'] ?? map['amountMinor']).abs(),
      currencyCode: _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      categoryUuid:
          _nullableString(map['category_uuid'] ?? map['categoryUuid']),
      paymentMethodUuid: _nullableString(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      merchant: _nullableString(map['merchant']),
      note: _nullableString(map['note']),
      useCount: _int(map['use_count'] ?? map['useCount']),
      lastUsedAt: _nullableInt(map['last_used_at'] ?? map['lastUsedAt']),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      version: _int(map['version'], fallback: 1),
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      deviceId: _nullableString(map['device_id'] ?? map['deviceId']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
  }
}

class FinanceSummary {
  final int incomeMinor;
  final int expenseMinor;
  final int refundMinor;
  final int transactionCount;
  final Map<String, int> expenseByCategory;
  final Map<String, int> incomeByCategory;
  final Map<String, int> expenseByDate;

  const FinanceSummary({
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.refundMinor = 0,
    this.transactionCount = 0,
    this.expenseByCategory = const {},
    this.incomeByCategory = const {},
    this.expenseByDate = const {},
  });

  int get netExpenseMinor => expenseMinor - refundMinor;

  int get balanceMinor => incomeMinor - netExpenseMinor;
}

String dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String financeMonthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

DateTime dateFromKey(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return DateTime.now();
  return DateTime(parsed.year, parsed.month, parsed.day);
}

FinanceTransactionType _transactionType(dynamic raw) {
  if (raw is num) {
    final index =
        raw.toInt().clamp(0, FinanceTransactionType.values.length - 1);
    return FinanceTransactionType.values[index];
  }
  final value = raw?.toString();
  return FinanceTransactionType.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceTransactionType.expense,
  );
}

FinanceRecurringFrequency _recurringFrequency(dynamic raw) {
  if (raw is num) {
    final index =
        raw.toInt().clamp(0, FinanceRecurringFrequency.values.length - 1);
    return FinanceRecurringFrequency.values[index];
  }
  final value = raw?.toString();
  return FinanceRecurringFrequency.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceRecurringFrequency.monthly,
  );
}

FinanceLoanRepaymentMethod _loanRepaymentMethod(dynamic raw) {
  if (raw is num) {
    final index =
        raw.toInt().clamp(0, FinanceLoanRepaymentMethod.values.length - 1);
    return FinanceLoanRepaymentMethod.values[index];
  }
  final value = raw?.toString();
  return FinanceLoanRepaymentMethod.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceLoanRepaymentMethod.equalPrincipalInterest,
  );
}

FinanceCategoryType _categoryType(dynamic raw) {
  if (raw is num) {
    final index = raw.toInt().clamp(0, FinanceCategoryType.values.length - 1);
    return FinanceCategoryType.values[index];
  }
  final value = raw?.toString();
  return FinanceCategoryType.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceCategoryType.expense,
  );
}

FinanceEntrySource _entrySource(dynamic raw) {
  final value = raw?.toString();
  return FinanceEntrySource.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceEntrySource.manual,
  );
}

String? _string(dynamic value) {
  if (value == null) return null;
  final result = value.toString().trim();
  return result.isEmpty || result == 'null' ? null : result;
}

String? _nullableString(dynamic value) => _string(value);

int _int(dynamic value, {int fallback = 0}) =>
    JsonValueParser.toInt(value, fallback: fallback);

int? _nullableInt(dynamic value) => JsonValueParser.toNullableInt(value);

int _timestamp(dynamic value) => JsonValueParser.epochMillisOrNow(value);

bool _bool(dynamic value) => value == true || value == 1 || value == '1';

bool _boolOrDefault(dynamic value, bool fallback) =>
    value == null ? fallback : _bool(value);
