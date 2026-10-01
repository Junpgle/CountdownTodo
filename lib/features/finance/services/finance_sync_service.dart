import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../../services/sync_capability_service.dart';
import 'finance_storage.dart';

/// The client-side state captured immediately before a finance sync request.
///
/// Finance is not represented by the generic `op_logs` table yet. Its rows
/// carry their own version and timestamp, so this snapshot is also the race
/// guard that prevents a response from advancing the cursor over a local
/// write that happened while the request was in flight.
class FinanceSyncRequest {
  const FinanceSyncRequest({
    required this.username,
    required this.cursorKey,
    required this.bootstrapKey,
    required this.cursor,
    required this.fullSync,
    required this.bundle,
    required this.fingerprint,
    this.categoryNamesCapabilityKey = '',
    this.supportsCategoryNames = false,
    this.balanceCapabilityKey = '',
    this.balanceBootstrapKey = '',
    this.supportsBalances = false,
  });

  final String username;
  final String cursorKey;
  final String bootstrapKey;
  final int cursor;
  final bool fullSync;
  final Map<String, dynamic> bundle;
  final Map<String, String> fingerprint;
  final String categoryNamesCapabilityKey;
  final bool supportsCategoryNames;
  final String balanceCapabilityKey;
  final String balanceBootstrapKey;
  final bool supportsBalances;

  static bool _hasPaymentMethod(Map<String, dynamic> item) =>
      (item['payment_method_uuid'] ?? item['paymentMethodUuid'])
          ?.toString()
          .trim()
          .isNotEmpty ==
      true;

  List<Map<String, dynamic>> _changes(
    String key, {
    bool excludeSystem = false,
  }) {
    final raw = bundle[key];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).where((item) {
      if (excludeSystem &&
          (_asBool(item['is_system']) ||
              _isSystemFinanceUuid(item['uuid']?.toString()))) {
        return false;
      }
      // Built-in category rows are created locally on every device. Only
      // explicit user name/icon overrides are worth uploading; otherwise a
      // new device's initialization timestamp could overwrite a cloud value
      // during the first full sync.
      if (key == 'categories' &&
          _isSystemCategoryUuid(item['uuid']?.toString())) {
        final iconCustomized =
            _asBool(item['icon_customized'] ?? item['iconCustomized']);
        final nameCustomized =
            _asBool(item['name_customized'] ?? item['nameCustomized']);
        if (nameCustomized && !supportsCategoryNames) return false;
        if (!iconCustomized && !nameCustomized) return false;
      }
      if (fullSync) return true;
      // After schema V48 the marker is authoritative. This prevents a
      // downloaded row with a future device timestamp from being uploaded
      // again, while still allowing a locally edited old-timestamp row to be
      // sent.
      return _asBool(item['pending_sync'] ?? item['pendingSync']);
    }).toList(growable: false);
  }

  Map<String, dynamic> get payload => {
        'finance_categories_changes': _changes(
          'categories',
        ),
        'finance_payment_methods_changes': _changes(
          'payment_methods',
          excludeSystem: true,
        ),
        'finance_transactions_changes': _changes('transactions'),
        'finance_loans_changes': _changes('loans'),
        'finance_loan_installments_changes': _changes('loan_installments')
            .where((item) => !_hasPaymentMethod(item))
            .toList(),
        // Dedicated fields are ignored by older servers. A cached capability
        // must never let an old server turn a balance into an overall budget
        // or acknowledge a repayment after discarding its account.
        'finance_loan_account_changes':
            _changes('loan_installments').where(_hasPaymentMethod).toList(),
        'finance_budgets_changes': _changes('budgets')
            .where((item) => !_hasPaymentMethod(item))
            .toList(),
        'finance_balance_snapshots_changes':
            _changes('budgets').where(_hasPaymentMethod).toList(),
        'finance_recurring_rules_changes': _changes('recurring_rules'),
        'finance_entry_templates_changes': _changes('templates'),
        'finance_full_sync': fullSync,
        'finance_last_sync_time': cursor,
      };

  bool get hasPendingChanges => payload.values.any(
        (value) => value is List && value.isNotEmpty,
      );
}

class FinanceSyncResult {
  const FinanceSyncResult({
    required this.supported,
    required this.hasChanges,
    required this.localChangesDuringRequest,
    required this.cursorAdvanced,
    this.remoteChangesDeferred = false,
    this.remoteChangeCount = 0,
    this.acknowledgedChangeCount = 0,
    this.rejectedChanges = const [],
  });

  final bool supported;
  final bool hasChanges;
  final bool localChangesDuringRequest;
  final bool cursorAdvanced;
  final bool remoteChangesDeferred;
  final int remoteChangeCount;
  final int acknowledgedChangeCount;
  final List<dynamic> rejectedChanges;
}

/// Preparation and response handling for the personal finance sync slice.
///
/// This service intentionally does not call the network. The existing
/// `StorageService.syncData` request remains the single authenticated sync
/// transaction, which keeps rate limiting and old-server compatibility in one
/// place.
abstract final class FinanceSyncService {
  // Pull once in full to recover deletions and active budget replacements
  // that an older merge discarded before advancing its cursor.
  static const String _scopePrefix = 'finance_sync_v3_';

  static String _balanceCapabilityKey(String username) =>
      'finance_account_balances_v1_${_serverScope(ApiService.effectiveBaseUrl)}_$username';

  static Future<bool?> balanceSyncSupport() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_login_user') ?? 'default';
    return prefs.getBool(_balanceCapabilityKey(username));
  }

  static Future<FinanceSyncRequest> prepare({
    required String username,
    required bool forceFullSync,
  }) async {
    await FinanceStorage.ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final scope = _serverScope(ApiService.effectiveBaseUrl);
    final bootstrapKey = '$_scopePrefix${scope}_$username';
    final categoryNamesCapabilityKey =
        'finance_category_names_v1_${scope}_$username';
    final cursorKey =
        'finance_last_sync_time_${ApiService.syncServerKey}_$username';
    final initialized = prefs.getBool(bootstrapKey) == true;
    final balanceCapabilityKey = _balanceCapabilityKey(username);
    final balanceBootstrapKey = '${balanceCapabilityKey}_initialized';
    final supportsBalances = prefs.getBool(balanceCapabilityKey) == true;
    final cursor = forceFullSync ? 0 : (prefs.getInt(cursorKey) ?? 0);
    final bundle = await FinanceStorage.getExportBundle();

    return FinanceSyncRequest(
      username: username,
      cursorKey: cursorKey,
      bootstrapKey: bootstrapKey,
      cursor: cursor,
      fullSync: forceFullSync ||
          !initialized ||
          (supportsBalances && prefs.getBool(balanceBootstrapKey) != true),
      bundle: bundle,
      fingerprint: _fingerprint(bundle),
      categoryNamesCapabilityKey: categoryNamesCapabilityKey,
      supportsCategoryNames: prefs.getBool(categoryNamesCapabilityKey) ?? false,
      balanceCapabilityKey: balanceCapabilityKey,
      balanceBootstrapKey: balanceBootstrapKey,
      supportsBalances: supportsBalances,
    );
  }

  static Future<FinanceSyncResult> finish({
    required FinanceSyncRequest request,
    required Map<String, dynamic> response,
    required bool supported,
  }) async {
    // A capability alone is not enough: require the response fields as well,
    // so an intermediary or partially deployed old server cannot make the
    // client acknowledge a payload it did not actually return.
    final hasProtocolPayload = _hasProtocolPayload(response);
    final supportsBalances = supported &&
        hasProtocolPayload &&
        SyncCapabilityService.supportsFinanceAccountBalances(
          response['sync_capabilities'],
        );
    if (request.balanceCapabilityKey.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getBool(request.balanceCapabilityKey);
      await prefs.setBool(request.balanceCapabilityKey, supportsBalances);
      if (!supportsBalances && request.balanceBootstrapKey.isNotEmpty) {
        await prefs.remove(request.balanceBootstrapKey);
      }
      if (previous != supportsBalances) FinanceStorage.revision.value++;
    }
    if (!supported || !hasProtocolPayload) {
      return FinanceSyncResult(
        supported: false,
        hasChanges: false,
        localChangesDuringRequest: false,
        cursorAdvanced: false,
      );
    }

    if (request.categoryNamesCapabilityKey.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        request.categoryNamesCapabilityKey,
        SyncCapabilityService.supportsFinanceCategoryNames(
          response['sync_capabilities'],
        ),
      );
    }

    final currentBundle = await FinanceStorage.getExportBundle();
    final localChanged = !_sameFingerprint(
      request.fingerprint,
      _fingerprint(currentBundle),
    );
    final remoteBundle = <String, dynamic>{
      'categories': response['server_finance_categories'] ?? const [],
      'payment_methods': response['server_finance_payment_methods'] ?? const [],
      'transactions': response['server_finance_transactions'] ?? const [],
      'loans': response['server_finance_loans'] ?? const [],
      'loan_installments':
          response['server_finance_loan_installments'] ?? const [],
      'budgets': response['server_finance_budgets'] ?? const [],
      'recurring_rules': response['server_finance_recurring_rules'] ?? const [],
      'templates': response['server_finance_entry_templates'] ?? const [],
    };
    if (!supportsBalances) {
      final localAccountRepayments =
          (currentBundle['loan_installments'] as List? ?? [])
              .whereType<Map>()
              .where((item) => item['payment_method_uuid'] != null)
              .map((item) => item['uuid']?.toString())
              .toSet();
      remoteBundle['loan_installments'] =
          (remoteBundle['loan_installments'] as List)
              .whereType<Map>()
              .where(
                (item) =>
                    !localAccountRepayments.contains(item['uuid']?.toString()),
              )
              .toList(growable: false);
    }
    if (!request.supportsCategoryNames) {
      final localNameOverrides = (currentBundle['categories'] as List? ?? [])
          .whereType<Map>()
          .where((item) =>
              _isSystemCategoryUuid(item['uuid']?.toString()) &&
              _asBool(item['name_customized'] ?? item['nameCustomized']))
          .map((item) => item['uuid']?.toString())
          .whereType<String>()
          .toSet();
      if (localNameOverrides.isNotEmpty) {
        remoteBundle['categories'] = (remoteBundle['categories'] as List? ??
                const [])
            .whereType<Map>()
            .where((item) => !localNameOverrides
                .contains(item['uuid']?.toString() ?? item['id']?.toString()))
            .toList(growable: false);
      }
    }
    final conflictKeys = _conflictKeys(response['finance_conflicts']);
    final deferredTransactionUuids = <String>{};
    // If a local write happened while the request was in flight, defer the
    // whole remote snapshot to the next round. Otherwise a newer server clock
    // could make an unrelated response win over the just-created local row
    // before that row has ever been uploaded.
    final remoteChangeCount = shouldMergeRemoteSnapshot(
      localChangesDuringRequest: localChanged,
    )
        ? await FinanceStorage.mergeRemoteBundle(
            remoteBundle,
            forceRemoteKeys: conflictKeys,
            deferredTransactionUuids: deferredTransactionUuids,
          )
        : 0;

    final rawAcknowledgements = response['finance_acknowledged_changes'];
    final acknowledgedChangeCount =
        await FinanceStorage.acknowledgePendingChanges(
      request.payload,
      rawAcknowledgements is List
          ? List<dynamic>.from(rawAcknowledgements)
          : const [],
    );

    final rawCursor = response['new_finance_sync_time'];
    final serverCursor = _asInt(rawCursor);
    var cursorAdvanced = false;
    final remoteChangesDeferred = deferredTransactionUuids.isNotEmpty;
    if (remoteChangesDeferred) {
      // A missing original or a still-active local refund can temporarily
      // block a valid remote row. Pull its dependencies in full next round,
      // keeping the cursor behind the row until it can actually be applied.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(request.bootstrapKey);
    }
    if (!localChanged && !remoteChangesDeferred && serverCursor > 0) {
      final prefs = await SharedPreferences.getInstance();
      final nextCursor =
          serverCursor > request.cursor ? serverCursor : request.cursor;
      await prefs.setInt(request.cursorKey, nextCursor);
      await prefs.setBool(request.bootstrapKey, true);
      if (supportsBalances &&
          request.fullSync &&
          request.balanceBootstrapKey.isNotEmpty) {
        await prefs.setBool(request.balanceBootstrapKey, true);
      }
      cursorAdvanced = true;
    }

    return FinanceSyncResult(
      supported: true,
      hasChanges: remoteChangeCount > 0,
      localChangesDuringRequest: localChanged,
      cursorAdvanced: cursorAdvanced,
      remoteChangesDeferred: remoteChangesDeferred,
      remoteChangeCount: remoteChangeCount,
      acknowledgedChangeCount: acknowledgedChangeCount,
      rejectedChanges: response['finance_conflicts'] is List
          ? List<dynamic>.from(response['finance_conflicts'] as List)
          : const [],
    );
  }

  static bool supports(dynamic rawCapabilities) =>
      SyncCapabilityService.supportsFinance(rawCapabilities);

  static bool shouldAcknowledge({
    required bool syncEnabled,
    required dynamic rawCapabilities,
  }) =>
      SyncCapabilityService.shouldAcknowledgeFinanceChanges(
        syncEnabled: syncEnabled,
        rawCapabilities: rawCapabilities,
      );

  /// Exposed for focused tests without opening a platform database.
  static Map<String, List<Map<String, dynamic>>> buildChangesForTest(
    Map<String, dynamic> bundle, {
    required int cursor,
    required bool fullSync,
    bool supportsCategoryNames = false,
  }) {
    final request = FinanceSyncRequest(
      username: 'test',
      cursorKey: 'test',
      bootstrapKey: 'test',
      cursor: cursor,
      fullSync: fullSync,
      bundle: bundle,
      fingerprint: const {},
      supportsCategoryNames: supportsCategoryNames,
    );
    final payload = request.payload;
    return {
      'categories': List<Map<String, dynamic>>.from(
          payload['finance_categories_changes']),
      'payment_methods': List<Map<String, dynamic>>.from(
        payload['finance_payment_methods_changes'],
      ),
      'transactions': List<Map<String, dynamic>>.from(
        payload['finance_transactions_changes'],
      ),
      'loans': List<Map<String, dynamic>>.from(
        payload['finance_loans_changes'],
      ),
      'loan_installments': List<Map<String, dynamic>>.from([
        ...payload['finance_loan_installments_changes'],
        ...payload['finance_loan_account_changes'],
      ]),
      'budgets': List<Map<String, dynamic>>.from([
        ...payload['finance_budgets_changes'],
        ...payload['finance_balance_snapshots_changes'],
      ]),
      'balance_snapshots': List<Map<String, dynamic>>.from(
        payload['finance_balance_snapshots_changes'],
      ),
      'recurring_rules': List<Map<String, dynamic>>.from(
        payload['finance_recurring_rules_changes'],
      ),
      'templates': List<Map<String, dynamic>>.from(
        payload['finance_entry_templates_changes'],
      ),
    };
  }

  static bool hasConcurrentChangesForTest(
    Map<String, String> before,
    Map<String, String> after,
  ) =>
      !_sameFingerprint(before, after);

  /// A request-time local write defers the response snapshot until the next
  /// request, so the just-created local value is never overwritten before it
  /// has had a chance to upload.
  static bool shouldMergeRemoteSnapshot({
    required bool localChangesDuringRequest,
  }) =>
      !localChangesDuringRequest;

  static String _serverScope(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  static bool _hasProtocolPayload(Map<String, dynamic> response) =>
      response.containsKey('server_finance_categories') &&
      response.containsKey('server_finance_payment_methods') &&
      response.containsKey('server_finance_transactions') &&
      response.containsKey('server_finance_budgets') &&
      response.containsKey('server_finance_recurring_rules') &&
      response.containsKey('server_finance_entry_templates') &&
      response['finance_acknowledged_changes'] is List &&
      response['new_finance_sync_time'] != null;

  static Set<String> _conflictKeys(dynamic raw) {
    if (raw is! List) return const {};
    const sections = <String>{
      'categories',
      'payment_methods',
      'transactions',
      'loans',
      'loan_installments',
      'budgets',
      'recurring_rules',
      'templates',
    };
    final keys = <String>{};
    for (final value in raw.whereType<Map>()) {
      final table = value['table']?.toString();
      final item = value['item'];
      if (table == null || !sections.contains(table) || item is! Map) {
        continue;
      }
      final uuid = item['uuid']?.toString() ?? item['id']?.toString() ?? '';
      if (uuid.isNotEmpty) keys.add('$table:$uuid');
    }
    return keys;
  }

  static Map<String, String> _fingerprint(Map<String, dynamic> bundle) {
    const sections = <String>[
      'categories',
      'payment_methods',
      'transactions',
      'loans',
      'loan_installments',
      'budgets',
      'recurring_rules',
      'templates',
    ];
    final result = <String, String>{};
    for (final section in sections) {
      final raw = bundle[section];
      if (raw is! List) continue;
      for (final item in raw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        if (section == 'payment_methods' &&
            (_asBool(map['is_system']) ||
                _isSystemFinanceUuid(map['uuid']?.toString()))) {
          continue;
        }
        final uuid = map['uuid']?.toString() ?? map['id']?.toString() ?? '';
        if (uuid.isEmpty) continue;
        result['$section:$uuid'] = jsonEncode(map);
      }
    }
    return result;
  }

  static bool _sameFingerprint(
    Map<String, String> before,
    Map<String, String> after,
  ) {
    if (before.length != after.length) return false;
    for (final entry in before.entries) {
      if (after[entry.key] != entry.value) return false;
    }
    return true;
  }
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value?.toString().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

bool _isSystemFinanceUuid(String? uuid) =>
    uuid?.startsWith('finance-system-') == true;

bool _isSystemCategoryUuid(String? uuid) =>
    uuid?.startsWith('finance-system-category-') == true;
