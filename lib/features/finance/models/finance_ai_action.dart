import 'finance_models.dart';

/// A structured finance operation returned by the assistant.
///
/// Queries are informational and are resolved from the finance context that
/// is sent with the request.  Updates and deletes are deliberately kept as
/// pending actions so the chat UI can ask for confirmation before touching
/// the local ledger.
enum FinanceAiActionType { summary, list, update, delete, unknown }

class FinanceAiAction {
  FinanceAiAction({
    required this.type,
    this.transactionId,
    this.from,
    this.to,
    this.keyword,
    this.transactionType,
    this.amountMinor,
    this.transactionDate,
    this.categoryUuid,
    this.categoryName,
    this.paymentMethodUuid,
    this.paymentMethodName,
    this.merchant,
    this.note,
    this.reason,
    this.hasType = false,
    this.hasAmount = false,
    this.hasDate = false,
    this.hasCategory = false,
    this.hasPaymentMethod = false,
    this.hasMerchant = false,
    this.hasNote = false,
    this.isAdded = false,
    this.isIgnored = false,
  });

  FinanceAiActionType type;
  String? transactionId;
  String? from;
  String? to;
  String? keyword;
  FinanceTransactionType? transactionType;
  int? amountMinor;
  String? transactionDate;
  String? categoryUuid;
  String? categoryName;
  String? paymentMethodUuid;
  String? paymentMethodName;
  String? merchant;
  String? note;
  String? reason;
  bool hasType;
  bool hasAmount;
  bool hasDate;
  bool hasCategory;
  bool hasPaymentMethod;
  bool hasMerchant;
  bool hasNote;
  bool isAdded;
  bool isIgnored;

  bool get isQuery =>
      type == FinanceAiActionType.summary || type == FinanceAiActionType.list;

  bool get isMutation =>
      type == FinanceAiActionType.update || type == FinanceAiActionType.delete;

  String get actionName {
    switch (type) {
      case FinanceAiActionType.summary:
        return 'finance_summary';
      case FinanceAiActionType.list:
        return 'finance_list';
      case FinanceAiActionType.update:
        return 'update_finance';
      case FinanceAiActionType.delete:
        return 'delete_finance';
      case FinanceAiActionType.unknown:
        return 'unknown';
    }
  }

  Map<String, dynamic> toJson() => {
        'action': actionName,
        'transactionId': transactionId,
        'from': from,
        'to': to,
        'keyword': keyword,
        'type': transactionType?.name,
        'amount': amountMinor == null ? null : amountMinor! / 100,
        'transactionDate': transactionDate,
        'categoryUuid': categoryUuid,
        'category': categoryName,
        'paymentMethodUuid': paymentMethodUuid,
        'paymentMethod': paymentMethodName,
        'merchant': merchant,
        'note': note,
        'reason': reason,
        'hasType': hasType,
        'hasAmount': hasAmount,
        'hasDate': hasDate,
        'hasCategory': hasCategory,
        'hasPaymentMethod': hasPaymentMethod,
        'hasMerchant': hasMerchant,
        'hasNote': hasNote,
        'isAdded': isAdded,
        'isIgnored': isIgnored,
      };

  factory FinanceAiAction.fromJson(Map<String, dynamic> json) {
    final type = _parseActionType(json['action'] ?? json['actionType']);
    final rawTransactionType =
        json['transactionType'] ?? json['transaction_type'] ?? json['type'];
    final isMutationType = type == FinanceAiActionType.update ||
        type == FinanceAiActionType.delete;
    final hasType = json['hasType'] is bool
        ? json['hasType'] as bool
        : json.containsKey('transactionType') ||
            json.containsKey('transaction_type') ||
            (isMutationType && json.containsKey('type'));
    final amountValue = json.containsKey('amount_minor')
        ? _parseMinor(json['amount_minor'])
        : json.containsKey('amountMinor')
            ? _parseMinor(json['amountMinor'])
            : _parseYuan(json['amount'] ?? json['amount_yuan']);
    final hasAmount = json['hasAmount'] is bool
        ? json['hasAmount'] as bool
        : json.containsKey('amount') ||
            json.containsKey('amount_yuan') ||
            json.containsKey('amount_minor') ||
            json.containsKey('amountMinor');
    final categoryValue = json['category'] ?? json['categoryName'];
    final paymentValue = json['paymentMethod'] ??
        json['payment_method'] ??
        json['paymentMethodName'];
    final dateValue =
        json['transactionDate'] ?? json['transaction_date'] ?? json['date'];

    return FinanceAiAction(
      type: type,
      transactionId: _string(
        json['transactionId'] ??
            json['transaction_id'] ??
            json['transactionUuid'] ??
            json['transaction_uuid'] ??
            (isMutationType ? json['id'] : null),
      ),
      from: _string(json['from'] ?? json['startDate'] ?? json['start_date']),
      to: _string(json['to'] ?? json['endDate'] ?? json['end_date']),
      keyword: _string(json['keyword'] ?? json['query']),
      transactionType: _parseTransactionType(rawTransactionType),
      amountMinor: amountValue,
      transactionDate: _string(dateValue),
      categoryUuid: _string(json['categoryUuid'] ?? json['category_uuid']),
      categoryName: _string(categoryValue),
      paymentMethodUuid: _string(
        json['paymentMethodUuid'] ?? json['payment_method_uuid'],
      ),
      paymentMethodName: _string(paymentValue),
      merchant: _string(json['merchant'] ?? json['title']),
      note: _nullableString(json, 'note'),
      reason: _string(json['reason']),
      hasType: hasType,
      hasAmount: hasAmount,
      hasDate: json['hasDate'] is bool
          ? json['hasDate'] as bool
          : json.containsKey('transactionDate') ||
              json.containsKey('transaction_date') ||
              json.containsKey('date'),
      hasCategory: json['hasCategory'] is bool
          ? json['hasCategory'] as bool
          : json.containsKey('category') ||
              json.containsKey('categoryName') ||
              json.containsKey('categoryUuid') ||
              json.containsKey('category_uuid'),
      hasPaymentMethod: json['hasPaymentMethod'] is bool
          ? json['hasPaymentMethod'] as bool
          : json.containsKey('paymentMethod') ||
              json.containsKey('payment_method') ||
              json.containsKey('paymentMethodUuid') ||
              json.containsKey('payment_method_uuid'),
      hasMerchant: json['hasMerchant'] is bool
          ? json['hasMerchant'] as bool
          : json.containsKey('merchant') || json.containsKey('title'),
      hasNote: json['hasNote'] is bool
          ? json['hasNote'] as bool
          : json.containsKey('note'),
      isAdded: json['isAdded'] == true || json['is_added'] == true,
      isIgnored: json['isIgnored'] == true || json['is_ignored'] == true,
    );
  }

  /// Parses only the finance operations understood by the app.
  static FinanceAiAction? tryParse(Map<String, dynamic> json) {
    final action = FinanceAiAction.fromJson(json);
    if (action.type == FinanceAiActionType.unknown) return null;
    if (action.isMutation && (action.transactionId?.isNotEmpty != true)) {
      return null;
    }
    if (action.type == FinanceAiActionType.update &&
        !action.hasType &&
        !action.hasAmount &&
        !action.hasDate &&
        !action.hasCategory &&
        !action.hasPaymentMethod &&
        !action.hasMerchant &&
        !action.hasNote) {
      return null;
    }
    return action;
  }

  static FinanceAiActionType _parseActionType(dynamic raw) {
    switch (raw?.toString().trim().toLowerCase()) {
      case 'finance_summary':
      case 'summary_finance':
      case 'finance_query_summary':
        return FinanceAiActionType.summary;
      case 'finance_list':
      case 'list_finance':
      case 'finance_transactions':
        return FinanceAiActionType.list;
      case 'update_finance':
      case 'edit_finance':
      case 'update_transaction':
        return FinanceAiActionType.update;
      case 'delete_finance':
      case 'remove_finance':
      case 'delete_transaction':
        return FinanceAiActionType.delete;
      default:
        return FinanceAiActionType.unknown;
    }
  }

  static FinanceTransactionType? _parseTransactionType(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase();
    switch (value) {
      case 'expense':
      case '支出':
      case '消费':
        return FinanceTransactionType.expense;
      case 'income':
      case '收入':
      case '进账':
      case '收款':
        return FinanceTransactionType.income;
      case 'refund':
      case '退款':
        return FinanceTransactionType.refund;
      default:
        return null;
    }
  }

  static int? _parseMinor(dynamic value) {
    if (value is num) return value.toInt().abs();
    final parsed = int.tryParse(value?.toString().trim() ?? '');
    return parsed?.abs();
  }

  static int? _parseYuan(dynamic value) {
    if (value is num) return (value.toDouble().abs() * 100).round();
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final normalized = text
        .replaceAll(',', '')
        .replaceAll(RegExp(r'^[¥￥$€£]'), '')
        .replaceAll(RegExp(r'\s*(?:元|块|CNY)\s*$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^[-+]'), '');
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed <= 0) return null;
    return (parsed * 100).round();
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final result = value.toString().trim();
    return result.isEmpty || result == 'null' ? null : result;
  }

  static String? _nullableString(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value == null ? null : _string(value);
  }
}
