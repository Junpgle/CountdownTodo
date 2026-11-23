import 'package:countdown_todo/features/finance/services/finance_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> transaction({
    required String uuid,
    required int updatedAt,
    int version = 1,
    bool pendingSync = false,
  }) => {
    'uuid': uuid,
    'type': 'expense',
    'amount_minor': 1200,
    'transaction_date': '2026-08-27',
    'updated_at': updatedAt,
    'version': version,
    'pending_sync': pendingSync ? 1 : 0,
  };

  test('首次同步全量包含所有个人记录，但排除系统目录', () {
    final changes = FinanceSyncService.buildChangesForTest(
      {
        'categories': [
          {
            'uuid': 'finance-system-category-food',
            'name': '餐饮',
            'is_system': 1,
            'updated_at': 999,
          },
          {
            'uuid': 'category-custom',
            'name': '旅行',
            'is_system': 0,
            'updated_at': 10,
          },
        ],
        'payment_methods': const [],
        'transactions': [transaction(uuid: 'tx-1', updatedAt: 10)],
        'budgets': const [],
        'recurring_rules': const [],
        'templates': const [],
      },
      cursor: 100,
      fullSync: true,
    );

    expect(changes['categories']!.map((item) => item['uuid']), [
      'category-custom',
    ]);
    expect(changes['transactions']!.map((item) => item['uuid']), ['tx-1']);
  });

  test('增量同步只发送水位线之后的记录', () {
    final changes = FinanceSyncService.buildChangesForTest(
      {
        'categories': const [],
        'payment_methods': const [],
        'transactions': [
          transaction(uuid: 'old', updatedAt: 100),
          transaction(uuid: 'new', updatedAt: 101, pendingSync: true),
        ],
        'budgets': const [],
        'recurring_rules': const [],
        'templates': const [],
      },
      cursor: 100,
      fullSync: false,
    );

    expect(changes['transactions']!.map((item) => item['uuid']), ['new']);
  });

  test('pending 标记可以让旧时间戳的本地修改进入增量请求', () {
    final changes = FinanceSyncService.buildChangesForTest(
      {
        'categories': const [],
        'payment_methods': const [],
        'transactions': [
          transaction(uuid: 'clock-skewed', updatedAt: 10, pendingSync: true),
          transaction(uuid: 'remote-only', updatedAt: 10),
        ],
        'budgets': const [],
        'recurring_rules': const [],
        'templates': const [],
      },
      cursor: 100,
      fullSync: false,
    );

    expect(changes['transactions']!.map((item) => item['uuid']), [
      'clock-skewed',
    ]);
  });

  test('指纹变化会阻止本轮前移记账水位线', () {
    expect(
      FinanceSyncService.hasConcurrentChangesForTest(
        const {'transactions:tx-1': '{"updated_at":10}'},
        const {'transactions:tx-1': '{"updated_at":11}'},
      ),
      isTrue,
    );
    expect(
      FinanceSyncService.hasConcurrentChangesForTest(
        const {'transactions:tx-1': '{"updated_at":10}'},
        const {'transactions:tx-1': '{"updated_at":10}'},
      ),
      isFalse,
    );
  });

  test('请求期间本地修改时延后远端快照合并', () {
    expect(
      FinanceSyncService.shouldMergeRemoteSnapshot(
        localChangesDuringRequest: true,
      ),
      isFalse,
    );
    expect(
      FinanceSyncService.shouldMergeRemoteSnapshot(
        localChangesDuringRequest: false,
      ),
      isTrue,
    );
  });
}
