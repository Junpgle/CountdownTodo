part of '../finance_models.dart';

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
      case FinanceTransactionType.transfer:
        return '互转';
    }
  }

  String get signedPrefix => switch (this) {
    FinanceTransactionType.expense => '-',
    FinanceTransactionType.income || FinanceTransactionType.refund => '+',
    FinanceTransactionType.transfer => '',
  };
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
      'uuid': 'finance-system-category-food-breakfast',
      'name': '早餐',
      'icon': '🥐',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 11,
    },
    {
      'uuid': 'finance-system-category-food-lunch',
      'name': '午餐',
      'icon': '🍱',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 12,
    },
    {
      'uuid': 'finance-system-category-food-dinner',
      'name': '晚餐',
      'icon': '🍛',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 13,
    },
    {
      'uuid': 'finance-system-category-food-takeout',
      'name': '外卖',
      'icon': '🥡',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 14,
    },
    {
      'uuid': 'finance-system-category-food-coffee',
      'name': '咖啡',
      'icon': '☕',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 15,
    },
    {
      'uuid': 'finance-system-category-food-milk-tea',
      'name': '奶茶',
      'icon': '🧋',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 16,
    },
    {
      'uuid': 'finance-system-category-food-snacks',
      'name': '零食',
      'icon': '🍿',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 17,
    },
    {
      'uuid': 'finance-system-category-food-groceries',
      'name': '买菜',
      'icon': '🥬',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 18,
    },
    {
      'uuid': 'finance-system-category-food-online-shopping',
      'name': '网购',
      'icon': '🛒',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-food',
      'sort_order': 19,
    },
    {
      'uuid': 'finance-system-category-transport',
      'name': '交通',
      'icon': '🚇',
      'type': 'expense',
      'sort_order': 20,
    },
    {
      'uuid': 'finance-system-category-transport-public',
      'name': '公交地铁',
      'icon': '🚇',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-transport',
      'sort_order': 21,
    },
    {
      'uuid': 'finance-system-category-transport-taxi',
      'name': '打车',
      'icon': '🚕',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-transport',
      'sort_order': 22,
    },
    {
      'uuid': 'finance-system-category-transport-fuel',
      'name': '加油',
      'icon': '⛽',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-transport',
      'sort_order': 23,
    },
    {
      'uuid': 'finance-system-category-transport-parking',
      'name': '停车',
      'icon': '🅿️',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-transport',
      'sort_order': 24,
    },
    {
      'uuid': 'finance-system-category-transport-train-flight',
      'name': '火车飞机',
      'icon': '✈️',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-transport',
      'sort_order': 25,
    },
    {
      'uuid': 'finance-system-category-transport-cycling',
      'name': '骑行',
      'icon': '🚲',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-transport',
      'sort_order': 26,
    },
    {
      'uuid': 'finance-system-category-shopping',
      'name': '购物',
      'icon': '🛍️',
      'type': 'expense',
      'sort_order': 30,
    },
    {
      'uuid': 'finance-system-category-shopping-daily',
      'name': '日用品',
      'icon': '🧴',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-shopping',
      'sort_order': 31,
    },
    {
      'uuid': 'finance-system-category-shopping-clothes',
      'name': '服饰鞋包',
      'icon': '👕',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-shopping',
      'sort_order': 32,
    },
    {
      'uuid': 'finance-system-category-shopping-digital',
      'name': '数码',
      'icon': '📱',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-shopping',
      'sort_order': 33,
    },
    {
      'uuid': 'finance-system-category-shopping-home',
      'name': '家居家电',
      'icon': '🛋️',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-shopping',
      'sort_order': 34,
    },
    {
      'uuid': 'finance-system-category-shopping-beauty',
      'name': '美妆个护',
      'icon': '💄',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-shopping',
      'sort_order': 35,
    },
    {
      'uuid': 'finance-system-category-shopping-pet',
      'name': '宠物用品',
      'icon': '🐾',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-shopping',
      'sort_order': 36,
    },
    {
      'uuid': 'finance-system-category-housing',
      'name': '居住',
      'icon': '🏠',
      'type': 'expense',
      'sort_order': 40,
    },
    {
      'uuid': 'finance-system-category-housing-rent',
      'name': '房租',
      'icon': '🔑',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-housing',
      'sort_order': 41,
    },
    {
      'uuid': 'finance-system-category-housing-utilities',
      'name': '水电燃气',
      'icon': '💡',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-housing',
      'sort_order': 42,
    },
    {
      'uuid': 'finance-system-category-housing-property',
      'name': '物业',
      'icon': '🏢',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-housing',
      'sort_order': 43,
    },
    {
      'uuid': 'finance-system-category-housing-network',
      'name': '通讯网络',
      'icon': '📶',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-housing',
      'sort_order': 44,
    },
    {
      'uuid': 'finance-system-category-housing-maintenance',
      'name': '家庭维修',
      'icon': '🔧',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-housing',
      'sort_order': 45,
    },
    {
      'uuid': 'finance-system-category-learning',
      'name': '学习',
      'icon': '📚',
      'type': 'expense',
      'sort_order': 50,
    },
    {
      'uuid': 'finance-system-category-learning-books',
      'name': '书籍',
      'icon': '📖',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-learning',
      'sort_order': 51,
    },
    {
      'uuid': 'finance-system-category-learning-course',
      'name': '课程培训',
      'icon': '🎓',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-learning',
      'sort_order': 52,
    },
    {
      'uuid': 'finance-system-category-learning-stationery',
      'name': '文具',
      'icon': '✏️',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-learning',
      'sort_order': 53,
    },
    {
      'uuid': 'finance-system-category-learning-exam',
      'name': '考试报名',
      'icon': '📝',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-learning',
      'sort_order': 54,
    },
    {
      'uuid': 'finance-system-category-entertainment',
      'name': '娱乐',
      'icon': '🎮',
      'type': 'expense',
      'sort_order': 60,
    },
    {
      'uuid': 'finance-system-category-entertainment-movie',
      'name': '电影演出',
      'icon': '🎬',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-entertainment',
      'sort_order': 61,
    },
    {
      'uuid': 'finance-system-category-entertainment-game',
      'name': '游戏',
      'icon': '🎮',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-entertainment',
      'sort_order': 62,
    },
    {
      'uuid': 'finance-system-category-entertainment-travel',
      'name': '旅行',
      'icon': '🧳',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-entertainment',
      'sort_order': 63,
    },
    {
      'uuid': 'finance-system-category-entertainment-music',
      'name': '音乐',
      'icon': '🎧',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-entertainment',
      'sort_order': 64,
    },
    {
      'uuid': 'finance-system-category-health',
      'name': '健康',
      'icon': '💊',
      'type': 'expense',
      'sort_order': 70,
    },
    {
      'uuid': 'finance-system-category-health-medical',
      'name': '医疗就诊',
      'icon': '🩺',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-health',
      'sort_order': 71,
    },
    {
      'uuid': 'finance-system-category-health-medicine',
      'name': '药品',
      'icon': '💊',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-health',
      'sort_order': 72,
    },
    {
      'uuid': 'finance-system-category-health-checkup',
      'name': '体检',
      'icon': '🩻',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-health',
      'sort_order': 73,
    },
    {
      'uuid': 'finance-system-category-health-fitness',
      'name': '健身',
      'icon': '🏋️',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-health',
      'sort_order': 74,
    },
    {
      'uuid': 'finance-system-category-social',
      'name': '社交',
      'icon': '🎁',
      'type': 'expense',
      'sort_order': 80,
    },
    {
      'uuid': 'finance-system-category-social-gift',
      'name': '礼物',
      'icon': '🎁',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-social',
      'sort_order': 81,
    },
    {
      'uuid': 'finance-system-category-social-red-envelope',
      'name': '红包',
      'icon': '🧧',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-social',
      'sort_order': 82,
    },
    {
      'uuid': 'finance-system-category-social-dining',
      'name': '聚餐',
      'icon': '🍻',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-social',
      'sort_order': 83,
    },
    {
      'uuid': 'finance-system-category-social-ceremony',
      'name': '随礼',
      'icon': '💌',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-social',
      'sort_order': 84,
    },
    {
      'uuid': 'finance-system-category-subscription',
      'name': '订阅',
      'icon': '🔔',
      'type': 'expense',
      'sort_order': 90,
    },
    {
      'uuid': 'finance-system-category-subscription-video',
      'name': '视频会员',
      'icon': '📺',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-subscription',
      'sort_order': 91,
    },
    {
      'uuid': 'finance-system-category-subscription-music',
      'name': '音乐会员',
      'icon': '🎵',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-subscription',
      'sort_order': 92,
    },
    {
      'uuid': 'finance-system-category-subscription-software',
      'name': '软件服务',
      'icon': '🧩',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-subscription',
      'sort_order': 93,
    },
    {
      'uuid': 'finance-system-category-subscription-cloud',
      'name': '云存储',
      'icon': '☁️',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-subscription',
      'sort_order': 94,
    },
    {
      'uuid': 'finance-system-category-ai-service',
      'name': 'AI 服务',
      'icon': '✨',
      'type': 'expense',
      'sort_order': 95,
    },
    {
      'uuid': 'finance-system-category-ai-service-subscription',
      'name': 'AI 订阅',
      'icon': '✨',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-ai-service',
      'sort_order': 96,
    },
    {
      'uuid': 'finance-system-category-ai-service-api',
      'name': 'API 调用',
      'icon': '🔌',
      'type': 'expense',
      'parent_uuid': 'finance-system-category-ai-service',
      'sort_order': 97,
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
      'uuid': 'finance-system-category-salary-base',
      'name': '基本工资',
      'icon': '💼',
      'type': 'income',
      'parent_uuid': 'finance-system-category-salary',
      'sort_order': 11,
    },
    {
      'uuid': 'finance-system-category-salary-overtime',
      'name': '加班费',
      'icon': '⏱️',
      'type': 'income',
      'parent_uuid': 'finance-system-category-salary',
      'sort_order': 12,
    },
    {
      'uuid': 'finance-system-category-salary-allowance',
      'name': '津贴补贴',
      'icon': '🧾',
      'type': 'income',
      'parent_uuid': 'finance-system-category-salary',
      'sort_order': 13,
    },
    {
      'uuid': 'finance-system-category-pocket-money',
      'name': '零花钱',
      'icon': '💰',
      'type': 'income',
      'sort_order': 20,
    },
    {
      'uuid': 'finance-system-category-pocket-money-family',
      'name': '家庭支持',
      'icon': '🏡',
      'type': 'income',
      'parent_uuid': 'finance-system-category-pocket-money',
      'sort_order': 21,
    },
    {
      'uuid': 'finance-system-category-pocket-money-living',
      'name': '生活费',
      'icon': '💰',
      'type': 'income',
      'parent_uuid': 'finance-system-category-pocket-money',
      'sort_order': 22,
    },
    {
      'uuid': 'finance-system-category-bonus',
      'name': '奖金',
      'icon': '🏆',
      'type': 'income',
      'sort_order': 30,
    },
    {
      'uuid': 'finance-system-category-bonus-year-end',
      'name': '年终奖',
      'icon': '🏆',
      'type': 'income',
      'parent_uuid': 'finance-system-category-bonus',
      'sort_order': 31,
    },
    {
      'uuid': 'finance-system-category-bonus-project',
      'name': '项目奖金',
      'icon': '🎯',
      'type': 'income',
      'parent_uuid': 'finance-system-category-bonus',
      'sort_order': 32,
    },
    {
      'uuid': 'finance-system-category-bonus-competition',
      'name': '竞赛奖励',
      'icon': '🥇',
      'type': 'income',
      'parent_uuid': 'finance-system-category-bonus',
      'sort_order': 33,
    },
    {
      'uuid': 'finance-system-category-refund',
      'name': '退款',
      'icon': '↩️',
      'type': 'expense',
      'sort_order': 40,
    },
    {
      'uuid': 'finance-system-category-other-income',
      'name': '其他',
      'icon': '➕',
      'type': 'income',
      'sort_order': 100,
    },
    {
      'uuid': 'finance-system-category-other-income-interest',
      'name': '利息收益',
      'icon': '💹',
      'type': 'income',
      'parent_uuid': 'finance-system-category-other-income',
      'sort_order': 101,
    },
    {
      'uuid': 'finance-system-category-other-income-investment',
      'name': '理财收益',
      'icon': '📈',
      'type': 'income',
      'parent_uuid': 'finance-system-category-other-income',
      'sort_order': 102,
    },
    {
      'uuid': 'finance-system-category-other-income-resale',
      'name': '二手闲置',
      'icon': '📦',
      'type': 'income',
      'parent_uuid': 'finance-system-category-other-income',
      'sort_order': 103,
    },
    {
      'uuid': 'finance-system-category-other-income-side-job',
      'name': '兼职收入',
      'icon': '🧑‍💻',
      'type': 'income',
      'parent_uuid': 'finance-system-category-other-income',
      'sort_order': 104,
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

  /// Only system categories need this marker. Their built-in rows are seeded
  /// locally and must not be uploaded as user edits until a name or icon
  /// override is explicitly customized.
  bool iconCustomized;
  bool nameCustomized;
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
    this.iconCustomized = false,
    this.nameCustomized = false,
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
    'type': type.name,
    'icon': icon,
    'icon_customized': iconCustomized ? 1 : 0,
    'name_customized': nameCustomized ? 1 : 0,
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
      iconCustomized: _bool(map['icon_customized'] ?? map['iconCustomized']),
      nameCustomized: _bool(map['name_customized'] ?? map['nameCustomized']),
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

/// Returns a readable, unambiguous category path such as `餐饮 - 奶茶`.
///
/// The parent is resolved by UUID instead of by its display name so duplicate
/// names remain unambiguous and old transactions can keep their stored UUID.
String financeCategoryDisplayName(
  FinanceCategory category,
  Iterable<FinanceCategory> categories, {
  String separator = ' - ',
}) {
  final allCategories = categories.toList();
  final byUuid = <String, FinanceCategory>{
    for (final item in allCategories) item.uuid: item,
  };
  final names = <String>[];
  final visited = <String>{};
  FinanceCategory? current = category;
  while (current != null && visited.add(current.uuid)) {
    names.insert(0, financeCategorySiblingDisplayName(current, allCategories));
    final parentUuid = current.parentUuid?.trim();
    if (parentUuid == null || parentUuid.isEmpty) break;
    final parent = byUuid[parentUuid];
    if (parent == null || parent.type != current.type) break;
    current = parent;
  }
  return names.join(separator);
}

String financeCategoryReferenceDisplayName(
  String? categoryUuid,
  Iterable<FinanceCategory> categories,
) {
  final normalizedUuid = categoryUuid?.trim();
  if (normalizedUuid == null || normalizedUuid.isEmpty) return '未分类';
  final allCategories = categories.toList();
  final byUuid = {
    for (final category in allCategories) category.uuid: category,
  };
  var current = byUuid[normalizedUuid];
  if (current == null) return '分类已删除或不可用';

  final names = <String>[];
  final visited = <String>{};
  while (current != null && visited.add(current.uuid)) {
    final name = financeCategorySiblingDisplayName(current, allCategories);
    names.insert(0, current.isDeleted ? '$name（已删除）' : name);
    final parentUuid = current.parentUuid?.trim();
    if (parentUuid == null || parentUuid.isEmpty) break;
    final parent = byUuid[parentUuid];
    if (parent == null || parent.type != current.type) break;
    current = parent;
  }
  return names.join(' - ');
}

/// Adds a stable ordinal when a category has a same-type sibling with the
/// same normalized name. Use this in lists where the surrounding hierarchy is
/// already visible.
String financeCategorySiblingDisplayName(
  FinanceCategory category,
  Iterable<FinanceCategory> categories,
) {
  final normalizedName = _normalizeFinanceCategoryName(category.name);
  final parentUuid = category.parentUuid?.trim() ?? '';
  final siblings =
      categories
          .where(
            (item) =>
                !item.isDeleted &&
                item.type == category.type &&
                (item.parentUuid?.trim() ?? '') == parentUuid &&
                _normalizeFinanceCategoryName(item.name) == normalizedName,
          )
          .toList()
        ..sort((left, right) {
          final sortOrder = left.sortOrder.compareTo(right.sortOrder);
          return sortOrder != 0 ? sortOrder : left.uuid.compareTo(right.uuid);
        });
  if (siblings.length < 2) return category.name;
  final index = siblings.indexWhere((item) => item.uuid == category.uuid);
  if (index < 0) return category.name;
  return '${category.name}（同名分类 ${index + 1}/${siblings.length}）';
}

String _normalizeFinanceCategoryName(String value) =>
    value.replaceAll(_financeDisplayWhitespacePattern, '').trim().toLowerCase();

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

String financePaymentMethodDisplayName(
  FinancePaymentMethod paymentMethod,
  Iterable<FinancePaymentMethod> paymentMethods,
) {
  final normalizedName = _normalizeFinancePaymentMethodName(paymentMethod.name);
  final sameNameMethods =
      paymentMethods
          .where(
            (item) =>
                !item.isDeleted &&
                _normalizeFinancePaymentMethodName(item.name) == normalizedName,
          )
          .toList()
        ..sort((left, right) {
          final sortOrder = left.sortOrder.compareTo(right.sortOrder);
          return sortOrder != 0 ? sortOrder : left.uuid.compareTo(right.uuid);
        });
  if (sameNameMethods.length < 2) return paymentMethod.name;
  final index = sameNameMethods.indexWhere(
    (item) => item.uuid == paymentMethod.uuid,
  );
  if (index < 0) return paymentMethod.name;
  final duplicateNumber = '${index + 1}/${sameNameMethods.length}';
  return '${paymentMethod.name}（同名账户 $duplicateNumber）';
}

/// Builds payment-method display names in one grouping pass.
Map<String, String> financePaymentMethodDisplayNames(
  Iterable<FinancePaymentMethod> paymentMethods,
) {
  final methodsByName = <String, List<FinancePaymentMethod>>{};
  for (final method in paymentMethods) {
    if (method.isDeleted) continue;
    (methodsByName[_normalizeFinancePaymentMethodName(method.name)] ??= []).add(
      method,
    );
  }

  final namesByUuid = <String, String>{};
  for (final sameNameMethods in methodsByName.values) {
    if (sameNameMethods.length > 1) {
      sameNameMethods.sort((left, right) {
        final sortOrder = left.sortOrder.compareTo(right.sortOrder);
        return sortOrder != 0 ? sortOrder : left.uuid.compareTo(right.uuid);
      });
    }
    for (var index = 0; index < sameNameMethods.length; index++) {
      final method = sameNameMethods[index];
      final displayName = sameNameMethods.length < 2
          ? method.name
          : '${method.name}（同名账户 ${index + 1}/${sameNameMethods.length}）';
      namesByUuid.putIfAbsent(method.uuid, () => displayName);
    }
  }
  return namesByUuid;
}

String _normalizeFinancePaymentMethodName(String value) {
  return value
      .replaceAll(_financePaymentLeadingPunctuationPattern, '')
      .replaceAll(_financeDisplayWhitespacePattern, '')
      .trim()
      .toLowerCase();
}
