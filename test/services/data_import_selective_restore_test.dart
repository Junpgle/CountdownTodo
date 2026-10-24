import 'dart:convert';

import 'package:countdown_todo/models/data_export_models.dart';
import 'package:countdown_todo/services/data_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _backupJson(Map<String, dynamic> data) => jsonEncode({
  'version': 2,
  'exportedAt': DateTime(2026, 10, 24).millisecondsSinceEpoch,
  'data': data,
});

void main() {
  group('selective backup restore', () {
    test(
      'preview groups related records and counts soft deletes and finance rows',
      () async {
        final preview = await DataImportService.parseJsonString(
          _backupJson({
            'todos': [
              {'uuid': 'todo-a', 'team_uuid': 'team-a'},
              {'uuid': 'todo-deleted', 'is_deleted': 1},
            ],
            'todo_plan_blocks': [
              {'uuid': 'plan-a'},
            ],
            'pomodoro_tags': [
              {'uuid': 'tag-a'},
            ],
            'pomodoro_records': [
              {'uuid': 'record-a', 'team_uuid': 'not-team-strategy-aware'},
            ],
            'courses': <Object?>[],
            'finance': {
              'categories': [
                {'uuid': 'category-a'},
                {'uuid': 'category-deleted', 'is_deleted': 1},
              ],
              'payment_methods': [
                {'uuid': 'method-a'},
              ],
              'transactions': [
                {'uuid': 'transaction-a'},
                {'uuid': 'transaction-deleted', 'is_deleted': 1},
              ],
              'budgets': [
                {'uuid': 'budget-a'},
              ],
              'recurring_rules': <Object?>[],
              'templates': <Object?>[],
              'loans': <Object?>[],
              'loan_installments': [
                {'uuid': 'installment-a'},
              ],
            },
            'habits': {
              'goals': [
                {'uuid': 'goal-a', 'is_deleted': true},
              ],
              'rules': <Object?>[],
              'check_ins': [
                {'uuid': 'checkin-a'},
              ],
              'sleep_coaching_plans': <Object?>[],
            },
            'thirty_day_challenge': {
              'state': {
                'tasks': [
                  {'id': 1},
                  {'id': 2, 'is_deleted': true},
                ],
              },
            },
            'settings': {'theme': 'dark', 'notify': true},
            'future_domain': [
              {'uuid': 'future-a'},
            ],
          }),
        );

        final productivity = preview.scopes.singleWhere(
          (scope) => scope.scope == ImportDataScope.productivity,
        );
        expect(productivity.count, 5);
        expect(productivity.deletedCount, 1);
        expect(productivity.teamCount, 1);
        expect(
          teamScopedImportCount(preview, {ImportDataScope.productivity}),
          1,
        );
        expect(teamScopedImportCount(preview, {ImportDataScope.finance}), 0);
        expect(
          productivity.types.map((type) => type.key),
          containsAll([
            'todos',
            'todo_plan_blocks',
            'pomodoro_tags',
            'pomodoro_records',
          ]),
        );

        final finance = preview.scopes.singleWhere(
          (scope) => scope.scope == ImportDataScope.finance,
        );
        expect(finance.count, 7);
        expect(finance.deletedCount, 2);

        final habits = preview.scopes.singleWhere(
          (scope) => scope.scope == ImportDataScope.habits,
        );
        expect(habits.count, 2);
        expect(habits.deletedCount, 1);
        expect(
          preview.scopes
              .singleWhere((scope) => scope.scope == ImportDataScope.settings)
              .count,
          2,
        );
        expect(preview.unsupportedKeys, ['future_domain']);
        expect(
          preview.scopes.map((scope) => scope.scope),
          containsAll(ImportDataScope.values),
        );
      },
    );

    test('selection passes only the chosen bundle and keeps linked productivity data together', () {
      final source = <String, dynamic>{
        'todo_groups': <Object?>[],
        'todos': <Object?>[],
        'todo_plan_blocks': <Object?>[],
        'fixed_schedules': <Object?>[],
        'time_logs': <Object?>[],
        'pomodoro_tags': <Object?>[],
        'pomodoro_records': <Object?>[],
        'courses': <Object?>[],
        'finance': <String, Object?>{'transactions': <Object?>[]},
        'settings': <String, Object?>{'theme': 'dark'},
        'future_domain': <Object?>[],
      };

      final productivity = DataImportService.filterDataByScopes(source, {
        ImportDataScope.productivity,
      });
      expect(
        productivity.keys,
        containsAll([
          'todo_groups',
          'todos',
          'todo_plan_blocks',
          'fixed_schedules',
          'time_logs',
          'pomodoro_tags',
          'pomodoro_records',
        ]),
      );
      expect(productivity.keys, isNot(contains('finance')));
      expect(productivity.keys, isNot(contains('settings')));
      expect(productivity.keys, isNot(contains('future_domain')));

      final financeOnly = DataImportService.filterDataByScopes(source, {
        ImportDataScope.finance,
      });
      expect(financeOnly.keys.toList(), ['finance']);
      expect(financeOnly['finance'], same(source['finance']));
    });

    test('default API selection remains all supported scopes and skips unknown sections', () {
      final filtered = DataImportService.filterDataByScopes({
        'todos': <Object?>[],
        'finance': <String, Object?>{},
        'settings': <String, Object?>{},
        'future_domain': <Object?>[],
      }, null);

      expect(filtered.keys.toList(), ['todos', 'finance', 'settings']);
    });

    test(
      'empty selection is rejected without parsing or importing the file',
      () async {
        final result = await DataImportService.importDataFromJsonString(
          username: 'default',
          jsonString: 'not json',
          options: const ImportOptions(selectedScopes: <ImportDataScope>{}),
        );

        expect(result.success, isFalse);
        expect(result.errorMessage, '请至少选择一个要导入的数据域');
        expect(result.importedCount, 0);
        expect(result.updatedCount, 0);
        expect(result.skippedCount, 0);
      },
    );
  });
}
