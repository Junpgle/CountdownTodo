import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../services/database_helper.dart';
import '../../../services/storage/app_settings_storage.dart';
import '../../../storage_service.dart';
import '../models/finance_models.dart';
import '../../../utils/json_value_parser.dart';
import '../../../utils/text_utils.dart';

part 'storage/finance_storage_transactions.dart';
part 'storage/finance_storage_loans.dart';
part 'storage/finance_storage_catalog.dart';
part 'storage/finance_storage_automation.dart';
part 'storage/finance_storage_sync_bundle.dart';
part 'storage/finance_storage_sync_merge.dart';
part 'storage/finance_storage_validation.dart';

/// 记账领域的本地 SQLite 存储。
///
/// 该类不依赖用户名参数：DatabaseHelper 会根据当前登录用户打开隔离的
/// `uni_sync_<username>.db`，因此记账数据天然按账号隔离。
abstract final class FinanceStorage {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  @visibleForTesting
  static Database? databaseOverride;

  static Future<void> ensureReady() => _ensureReady();

  static Future<List<FinanceTransaction>> getTransactions({
    bool includeDeleted = false,
    DateTime? from,
    DateTime? to,
    String? keyword,
    String? categoryUuid,
    FinanceTransactionType? type,
    int? limit,
  }) => _getTransactions(
    includeDeleted: includeDeleted,
    from: from,
    to: to,
    keyword: keyword,
    categoryUuid: categoryUuid,
    type: type,
    limit: limit,
  );

  static Future<List<FinanceTransaction>> getBalanceTransactions({
    required int snapshotAt,
    required DateTime before,
    required Iterable<String> paymentMethodUuids,
  }) => _getBalanceTransactions(
    snapshotAt: snapshotAt,
    before: before,
    paymentMethodUuids: paymentMethodUuids,
  );

  static Future<FinanceTransaction?> getTransaction(String uuid) =>
      _getTransaction(uuid);

  /// Reads only the requested transaction identities, including trash rows, so
  /// generated recurring bills are not shown twice in future commitments.
  static Future<Set<String>> getExistingTransactionUuids(
    Iterable<String> uuids,
  ) => _getExistingTransactionUuids(uuids);

  static Future<List<FinanceTransaction>> getRefundsForTransaction(
    String transactionUuid, {
    bool includeDeleted = false,
  }) => _getRefundsForTransaction(
    transactionUuid,
    includeDeleted: includeDeleted,
  );

  static Future<int> getRemainingRefundableMinor(
    String transactionUuid, {
    String? excludingRefundUuid,
  }) => _getRemainingRefundableMinor(
    transactionUuid,
    excludingRefundUuid: excludingRefundUuid,
  );

  static Future<List<FinanceTransaction>> getDeletedTransactions() =>
      _getDeletedTransactions();

  static Future<void> saveTransaction(
    FinanceTransaction transaction, {
    FinanceTransaction? original,
  }) => _saveTransaction(transaction, original: original);

  /// 批量保存多笔账单（例如账单导入），在单个数据库事务中完成写入并仅触发一次刷新。
  static Future<void> saveTransactionsBatch(
    List<FinanceTransaction> transactions,
  ) => _saveTransactionsBatch(transactions);

  /// 原子保存一组分期账单。
  ///
  /// 每一期都是正常的 transaction，因此月度统计、搜索、导出和同步都能
  /// 沿用现有路径；分期字段只负责把这些交易重新识别为同一组。
  static Future<List<FinanceTransaction>> saveInstallmentPlan({
    required FinanceTransaction transaction,
    FinanceTransaction? original,
    required int totalAmountMinor,
    required int installmentCount,
    required DateTime startDate,
    List<FinanceTransaction> existingInstallments = const [],
  }) => _saveInstallmentPlan(
    transaction: transaction,
    original: original,
    totalAmountMinor: totalAmountMinor,
    installmentCount: installmentCount,
    startDate: startDate,
    existingInstallments: existingInstallments,
  );

  static Future<List<FinanceTransaction>> getInstallmentGroup(
    String groupUuid, {
    bool includeDeleted = false,
  }) => _getInstallmentGroup(groupUuid, includeDeleted: includeDeleted);

  static Future<void> deleteInstallmentGroup(String groupUuid) =>
      _deleteInstallmentGroup(groupUuid);

  static Future<void> restoreInstallmentGroup(String groupUuid) =>
      _restoreInstallmentGroup(groupUuid);

  static Future<List<FinanceLoan>> getLoans({bool includeDeleted = false}) =>
      _getLoans(includeDeleted: includeDeleted);

  static Future<FinanceLoan?> getLoan(
    String uuid, {
    bool includeDeleted = false,
  }) => _getLoan(uuid, includeDeleted: includeDeleted);

  static Future<List<FinanceLoanInstallment>> getLoanInstallments(
    String loanUuid, {
    bool includeDeleted = false,
    String? fromDueDate,
    String? toDueDate,
  }) => _getLoanInstallments(
    loanUuid,
    includeDeleted: includeDeleted,
    fromDueDate: fromDueDate,
    toDueDate: toDueDate,
  );

  /// Loads scheduled installments for all active loans with one indexed join.
  /// The term bound matches [getLoanInstallments]' default behavior.
  static Future<Map<String, List<FinanceLoanInstallment>>>
  getLoanInstallmentsForActiveLoans({String? fromDueDate, String? toDueDate}) =>
      _getLoanInstallmentsForActiveLoans(
        fromDueDate: fromDueDate,
        toDueDate: toDueDate,
      );

  static Future<FinanceLoanInstallment?> getLoanInstallment(
    String uuid, {
    bool includeDeleted = false,
  }) => _getLoanInstallment(uuid, includeDeleted: includeDeleted);

  /// 保存贷款并在同一事务中生成或重算整套还款计划。
  static Future<void> saveLoan(FinanceLoan loan, {FinanceLoan? original}) =>
      _saveLoan(loan, original: original);

  /// Cash movements are stored on repayment records, separately from interest
  /// expenses, so even a zero-interest repayment changes the account balance.
  /// Recycling a loan or its plan does not undo an actual payment.
  static Future<List<FinanceLoanInstallment>> getPaidLoanInstallments() =>
      _getPaidLoanInstallments();

  /// Includes recycled and canceled repayments so their interest bills remain
  /// managed through the repayment even after its current bill pointer clears.
  static Future<FinanceLoanInstallment?> getRepaymentForInterestTransaction(
    String transactionUuid,
  ) => _getRepaymentForInterestTransaction(transactionUuid);

  /// Only interest enters consumption statistics. The full repayment amount
  /// reduces the selected account at paidAt through getPaidLoanInstallments.
  static Future<void> setLoanInstallmentPaid(
    String installmentUuid,
    bool paid, {
    String? paymentMethodUuid,
    DateTime? paidAt,
  }) => _setLoanInstallmentPaid(
    installmentUuid,
    paid,
    paymentMethodUuid: paymentMethodUuid,
    paidAt: paidAt,
  );

  static Future<void> deleteLoan(String uuid) => _deleteLoan(uuid);

  static Future<void> restoreLoan(String uuid) => _restoreLoan(uuid);

  static Future<void> deleteTransaction(String uuid) =>
      _deleteTransaction(uuid);

  static Future<void> restoreTransaction(String uuid) =>
      _restoreTransaction(uuid);

  static Future<List<FinanceCategory>> getCategories({
    FinanceCategoryType? type,
    bool includeArchived = false,
    bool includeDeleted = false,
  }) => _getCategories(
    type: type,
    includeArchived: includeArchived,
    includeDeleted: includeDeleted,
  );

  static Future<void> saveCategory(
    FinanceCategory category, {
    FinanceCategory? original,
  }) => _saveCategory(category, original: original);

  static Future<void> archiveCategory(String uuid) => _archiveCategory(uuid);

  static Future<bool> unarchiveCategory(String uuid) =>
      _unarchiveCategory(uuid);

  static Future<bool> hasTransactionsForCategory(String uuid) =>
      _hasTransactionsForCategory(uuid);

  static Future<List<FinancePaymentMethod>> getPaymentMethods({
    bool includeArchived = false,
    bool includeDeleted = false,
  }) => _getPaymentMethods(
    includeArchived: includeArchived,
    includeDeleted: includeDeleted,
  );

  static Future<void> savePaymentMethod(
    FinancePaymentMethod method, {
    FinancePaymentMethod? original,
  }) => _savePaymentMethod(method, original: original);

  static Future<void> archivePaymentMethod(String uuid) =>
      _archivePaymentMethod(uuid);

  static Future<void> unarchivePaymentMethod(String uuid) =>
      _unarchivePaymentMethod(uuid);

  static Future<List<FinanceBudget>> getBudgets({
    String? monthKey,
    bool includeDeleted = false,
  }) => _getBudgets(monthKey: monthKey, includeDeleted: includeDeleted);

  static Future<FinanceBudget?> getBudget(String uuid) => _getBudget(uuid);

  static Future<void> saveBudget(
    FinanceBudget budget, {
    FinanceBudget? original,
    bool resetBalanceSnapshot = false,
    int? balanceSnapshotAt,
  }) => _saveBudget(
    budget,
    original: original,
    resetBalanceSnapshot: resetBalanceSnapshot,
    balanceSnapshotAt: balanceSnapshotAt,
  );

  static Future<void> deleteBudget(String uuid) => _deleteBudget(uuid);

  static Future<void> restoreBudget(String uuid) => _restoreBudget(uuid);

  static Future<List<FinanceRecurringRule>> getRecurringRules({
    bool includeDeleted = false,
    bool enabledOnly = false,
  }) => _getRecurringRules(
    includeDeleted: includeDeleted,
    enabledOnly: enabledOnly,
  );

  static Future<FinanceRecurringRule?> getRecurringRule(String uuid) =>
      _getRecurringRule(uuid);

  static Future<void> saveRecurringRule(
    FinanceRecurringRule rule, {
    FinanceRecurringRule? original,
  }) => _saveRecurringRule(rule, original: original);

  static Future<void> deleteRecurringRule(String uuid) =>
      _deleteRecurringRule(uuid);

  static Future<void> restoreRecurringRule(String uuid) =>
      _restoreRecurringRule(uuid);

  static Future<void> setRecurringRuleEnabled(String uuid, bool enabled) =>
      _setRecurringRuleEnabled(uuid, enabled);

  static Future<bool> materializeRecurringRule(
    FinanceRecurringRule rule, {
    required DateTime dueAt,
    required String periodKey,
  }) => _materializeRecurringRule(rule, dueAt: dueAt, periodKey: periodKey);

  static Future<List<FinanceEntryTemplate>> getTemplates({
    bool includeDeleted = false,
  }) => _getTemplates(includeDeleted: includeDeleted);

  static Future<FinanceEntryTemplate?> getTemplate(String uuid) =>
      _getTemplate(uuid);

  static Future<void> saveTemplate(
    FinanceEntryTemplate template, {
    FinanceEntryTemplate? original,
  }) => _saveTemplate(template, original: original);

  static Future<void> deleteTemplate(String uuid) => _deleteTemplate(uuid);

  static Future<void> restoreTemplate(String uuid) => _restoreTemplate(uuid);

  static Future<void> markTemplateUsed(String uuid) => _markTemplateUsed(uuid);

  static Future<FinanceSummary> getSummary({
    required DateTime from,
    required DateTime to,
  }) => _getSummary(from: from, to: to);

  static Future<Map<String, dynamic>> getExportBundle() => _getExportBundle();

  static void removeDeviceIdsFromExportBundle(Map<String, dynamic> bundle) =>
      _removeDeviceIdsFromExportBundle(bundle);

  /// 导入 JSON 备份中的记账数据。所有记录仍然写入当前用户的本地库，
  /// 不携带团队归属，也不会写入同步操作日志。
  static Future<Map<String, int>> importBundle(
    Map<String, dynamic> bundle, {
    String Function(String value)? remapUuid,
  }) => _importBundle(bundle, remapUuid: remapUuid);

  /// 将服务端返回的个人记账快照按 updated_at/version 合并到本地。
  ///
  /// 记账没有通用 op_logs，因此同步源必须使用一笔 SQLite 事务完成整批
  /// upsert。系统分类的类型/层级仍由客户端内置定义，用户自定义名称和
  /// 图标则作为个人覆盖项接受云端合并；系统付款方式仍保持本地默认。
  static Future<int> mergeRemoteBundle(
    Map<String, dynamic> bundle, {
    Set<String> forceRemoteKeys = const {},
    Set<String>? deferredTransactionUuids,
    Set<String>? changedSections,
  }) => _mergeRemoteBundle(
    bundle,
    forceRemoteKeys: forceRemoteKeys,
    deferredTransactionUuids: deferredTransactionUuids,
    changedSections: changedSections,
  );

  /// Clears pending markers only for rows that were part of the request and
  /// are still at the same local version. A later local edit therefore keeps
  /// its marker even when the earlier request finishes afterwards.
  static Future<int> acknowledgePendingChanges(
    Map<String, dynamic> requestPayload,
    List<dynamic> acknowledgements,
  ) => _acknowledgePendingChanges(requestPayload, acknowledgements);
}

final RegExp _monthKeyPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

const int _maxDateTimeMillis = 8640000000000000;

const int _maxFinanceTimezoneOffsetMinutes = 14 * 60;

const int _maxTemplateUseCount = 0x7fffffff;

Database? _readyDatabase;

Future<void>? _readyFuture;

Future<Database> get _database async =>
    FinanceStorage.databaseOverride ?? await DatabaseHelper.instance.database;

/// All writes originating from this device stay pending until the server
/// acknowledges the exact request snapshot. Remote merges use
/// [_remoteValues] so a downloaded row can never become a new local upload.
Map<String, dynamic> _localValues(Map<String, dynamic> values) => {
  ...values,
  'pending_sync': 1,
};

Map<String, dynamic> _remoteValues(Map<String, dynamic> values) => {
  ...values,
  'pending_sync': 0,
};

Future<void> _ensureReady() async {
  final db = await _database;
  if (identical(_readyDatabase, db)) {
    await _readyFuture;
    return;
  }

  final ready = _ensureReadyFor(db);
  _readyDatabase = db;
  _readyFuture = ready;
  try {
    await ready;
  } catch (_) {
    if (identical(_readyDatabase, db) && identical(_readyFuture, ready)) {
      _readyDatabase = null;
      _readyFuture = null;
    }
    rethrow;
  }
}

Future<void> _ensureReadyFor(Database db) async {
  await db.transaction((txn) async {
    for (final raw in FinanceDefaults.categories) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.insert('finance_categories', {
        'uuid': raw['uuid'],
        'name': raw['name'],
        'type': raw['type'],
        'icon': raw['icon'],
        'icon_customized': 0,
        'name_customized': 0,
        'parent_uuid': raw['parent_uuid'],
        'is_system': 1,
        'is_archived': 0,
        'is_deleted': 0,
        'sort_order': raw['sort_order'],
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'pending_sync': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.rawUpdate(
        '''
        UPDATE finance_categories
        SET name = CASE WHEN name_customized = 1 THEN name ELSE ? END,
            type = ?,
            parent_uuid = ?,
            is_archived = 0,
            is_deleted = 0,
            sort_order = ?
        WHERE uuid = ? AND is_system = 1
        ''',
        [
          raw['name'],
          raw['type'],
          raw['parent_uuid'],
          raw['sort_order'],
          raw['uuid'],
        ],
      );
    }
    for (final raw in FinanceDefaults.paymentMethods) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.insert('finance_payment_methods', {
        'uuid': raw['uuid'],
        'name': raw['name'],
        'icon': raw['icon'],
        'is_system': 1,
        'is_archived': 0,
        'is_deleted': 0,
        'sort_order': raw['sort_order'],
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'pending_sync': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  });
  // Keep the migration inside the shared readiness future so concurrent
  // readers cannot proceed after catalog setup but before legacy repair.
  if (await _repairLegacyRefundCategories(db) > 0) _notifyChanged();
}

Future<int> _repairLegacyRefundCategories(Database db) async {
  final migrationNow = DateTime.now().millisecondsSinceEpoch;
  final repairedCount = await db.rawUpdate(
    '''
    UPDATE finance_transactions
    SET category_uuid = ?,
        version = version + 1,
        updated_at = CASE
          WHEN updated_at >= ? THEN updated_at + 1
          ELSE ?
        END,
        pending_sync = 1
    WHERE type = 'refund'
      AND category_uuid IN (
        SELECT uuid FROM finance_categories WHERE type = 'income'
      )
    ''',
    ['finance-system-category-refund', migrationNow, migrationNow],
  );
  return repairedCount;
}

bool _isSystemUuid(String uuid) => uuid.startsWith('finance-system-');

final Set<String> _systemCategoryUuids = FinanceDefaults.categories
    .map((category) => category['uuid'])
    .whereType<String>()
    .toSet();

bool _isSystemCategoryUuid(String uuid) => _systemCategoryUuids.contains(uuid);

int _asInt(dynamic value) => JsonValueParser.toInt(value);

Future<Map<String, dynamic>?> _findByUuid(
  DatabaseExecutor db,
  String table,
  String uuid,
) async {
  final rows = await db.query(
    table,
    where: 'uuid = ?',
    whereArgs: [uuid],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

String? _remapNullable(String? value, String Function(String value) remap) {
  if (value == null || value.isEmpty) return value;
  if (value.startsWith('finance-system-')) return value;
  return remap(value);
}

void _notifyChanged({bool requestSync = true}) {
  FinanceStorage.revision.value++;
  StorageService.triggerRefresh(const {DataRefreshDomain.finance});
  if (requestSync) unawaited(_requestSync());
}

Future<void> _requestSync() async {
  final username = await StorageService.getCurrentUsername();
  if (username != null &&
      username.isNotEmpty &&
      await AppSettingsStorage.isFinanceCloudSyncEnabled(username)) {
    StorageService.requestSync(username);
  }
}
