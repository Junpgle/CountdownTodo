import 'dart:convert';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首次全量同步只上传系统分类的图标覆盖项', () {
    final defaultSystem = FinanceCategory(
      uuid: 'finance-system-category-food',
      name: '餐饮',
      icon: '🍜',
      isSystem: true,
    ).toMap();
    final customizedSystem = FinanceCategory(
      uuid: 'finance-system-category-transport',
      name: '交通',
      icon: '🚲',
      isSystem: true,
      iconCustomized: true,
      pendingSync: true,
    ).toMap();
    final custom = FinanceCategory(
      uuid: 'custom-category',
      name: '宠物',
      icon: '🐾',
    ).toMap();

    final changes = FinanceSyncService.buildChangesForTest(
      {
        'categories': [defaultSystem, customizedSystem, custom],
      },
      cursor: 0,
      fullSync: true,
      supportsCategoryIcons: true,
    );

    expect(
      changes['categories']!.map((item) => item['uuid']),
      containsAll(<String>{
        'finance-system-category-transport',
        'custom-category',
      }),
    );
    expect(
      changes['categories']!.map((item) => item['uuid']),
      isNot(contains('finance-system-category-food')),
    );
  });

  test('系统分类图标编辑会被请求期间并发检测捕获', () {
    final before = FinanceCategory(
      uuid: 'finance-system-category-food',
      name: '餐饮',
      icon: '🍜',
      isSystem: true,
      iconCustomized: true,
      updatedAt: 10,
    ).toMap();
    final after = {...before, 'icon': '🥗', 'icon_customized': 1};

    expect(
      FinanceSyncService.hasConcurrentChangesForTest(
        {'categories:food': jsonEncode(before)},
        {'categories:food': jsonEncode(after)},
      ),
      isTrue,
    );
  });
}
