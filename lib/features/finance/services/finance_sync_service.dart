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
  });

  final String username;
  final String cursorKey;
  final String bootstrapKey;
  final int cursor;
  final bool fullSync;
  final Map<String, dynamic> bundle;
  final Map<String, String> fingerprint;

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
          excludeSystem: true,
        ),
        'finance_payment_methods_changes': _changes(
          'payment_methods',
          excludeSystem: true,
        ),
        'finance_transactions_changes': _changes('transactions'),
        'finance_budgets_changes': _changes('budgets'),
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
    this.remoteChangeCount = 0,
    this.acknowledgedChangeCount = 0,
    this.rejectedChanges = const [],
  });

  final bool supported;
  final bool hasChanges;
  final bool localChangesDuringRequest;
  final bool cursorAdvanced;
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
  static const String _scopePrefix = 'finance_sync_v1_';

  static Future<FinanceSyncRequest> prepare({
    required String username,
    required bool forceFullSync,
  }) async {
    await FinanceStorage.ensureReady();
    final prefs = await SharedPreferences.getInstance();
    final scope = _serverScope(ApiService.effectiveBaseUrl);
    final bootstrapKey = '$_scopePrefix${scope}_$username';
    final cursorKey =
        'finance_last_sync_time_${ApiService.syncServerKey}_$username';
    final initialized = prefs.getBool(bootstrapKey) == true;
    final cursor = forceFullSync ? 0 : (prefs.getInt(cursorKey) ?? 0);
    final bundle = await FinanceStorage.getExportBundle();

    return FinanceSyncRequest(
      username: username,
      cursorKey: cursorKey,
      bootstrapKey: bootstrapKey,
      cursor: cursor,
      fullSync: forceFullSync || !initialized,
      bundle: bundle,
      fingerprint: _fingerprint(bundle),
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
    if (!supported || !hasProtocolPayload) {
      return FinanceSyncResult(
        supported: false,
        hasChanges: false,
        localChangesDuringRequest: false,
        cursorAdvanced: false,
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
      'budgets': response['server_finance_budgets'] ?? const [],
      'recurring_rules': response['server_finance_recurring_rules'] ?? const [],
      'templates': response['server_finance_entry_templates'] ?? const [],
    };
    final conflictKeys = _conflictKeys(response['finance_conflicts']);
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
    if (!localChanged && serverCursor > 0) {
      final prefs = await SharedPreferences.getInstance();
      final nextCursor =
          serverCursor > request.cursor ? serverCursor : request.cursor;
      await prefs.setInt(request.cursorKey, nextCursor);
      await prefs.setBool(request.bootstrapKey, true);
      cursorAdvanced = true;
    }

    return FinanceSyncResult(
      supported: true,
      hasChanges: remoteChangeCount > 0,
      localChangesDuringRequest: localChanged,
      cursorAdvanced: cursorAdvanced,
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
  }) {
    final request = FinanceSyncRequest(
      username: 'test',
      cursorKey: 'test',
      bootstrapKey: 'test',
      cursor: cursor,
      fullSync: fullSync,
      bundle: bundle,
      fingerprint: const {},
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
      'budgets':
          List<Map<String, dynamic>>.from(payload['finance_budgets_changes']),
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
        if ((section == 'categories' || section == 'payment_methods') &&
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
