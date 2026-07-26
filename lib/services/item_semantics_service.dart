import '../models.dart';

enum CaptureIntentKind { todo, fixedSchedule, planBlock, needsConfirmation }

enum TodoDomainKind { standard, pickup }

/// 对用户输入做轻量、确定性的语义分类。
///
/// 这里只建立待办、固定日程和规划块的边界，不负责持久化固定日程。
/// 不确定时宁可要求确认，也不把硬时间约束静默降级为普通待办。
class ItemSemanticsService {
  static final RegExp _pickupCodeTokenPattern = RegExp(
    r'\b(?=[A-Za-z0-9-]*\d)[A-Za-z0-9-]{4,}\b',
    caseSensitive: false,
  );
  static final RegExp _clockPattern = RegExp(
    r'(?:上午|下午|早上|晚上|中午|凌晨)?\s*\d{1,2}(?:[:：]\d{2}|[点时](?:\d{1,2}分?)?)',
  );
  static final RegExp _timeRangePattern = RegExp(
    r'\d{1,2}(?:[:：]\d{2}|[点时](?:\d{1,2}分?)?)\s*(?:到|至|-|~|—)\s*(?:上午|下午|早上|晚上|中午|凌晨)?\s*\d{1,2}(?:[:：]\d{2}|[点时](?:\d{1,2}分?)?)',
  );

  static const _pickupKeywords = <String>[
    '取件',
    '取餐',
    '取药',
    '取票',
    '取报告',
    '领取',
    '签收',
    '取件码',
    '取餐码',
    '核销码',
    '驿站',
    '已出餐',
  ];

  static const _fixedScheduleKeywords = <String>[
    '考试',
    '课程',
    '上课',
    '会议',
    '例会',
    '面试',
    '航班',
    '飞机',
    '火车',
    '高铁',
    '演出',
    '电影',
    '比赛',
    '门诊',
  ];

  static const _preparationKeywords = <String>[
    '准备',
    '复习',
    '预习',
    '报名',
    '打印',
    '整理',
    '查询',
    '携带',
  ];

  static const _selfDirectedWorkKeywords = <String>[
    '复习',
    '预习',
    '写',
    '整理',
    '学习',
    '阅读',
    '背',
    '做题',
    '锻炼',
    '跑步',
  ];

  /// 识别需要用特殊待办样式展示的标题。
  ///
  /// “京东”本身也可能指京东健康等非物流业务，因此不单独作为
  /// 取件信号；“京东快递”或“京东取件”仍会由明确关键词命中。
  static String specialTodoTypeForTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (_containsAny(normalized, const [
      '快递',
      '取件',
      '顺丰',
      '菜鸟',
      '中通',
      '圆通',
      '韵达',
      '申通',
      '极兔',
      '德邦',
    ])) {
      return 'delivery';
    }
    if (_containsAny(normalized, const [
      '奶茶',
      '咖啡',
      '古茗',
      '茶百道',
      '蜜雪冰城',
      '瑞幸',
      '星巴克',
      '库迪',
      'coco',
      '一点点',
    ])) {
      return 'cafe';
    }
    if (_containsAny(normalized, const [
      '取餐',
      '外卖',
      '肯德基',
      '麦当劳',
      'kfc',
    ])) {
      return 'food';
    }
    if (_containsAny(normalized, const [
      '海底捞',
      '太二',
      '外婆家',
      '西贝',
      '必胜客',
      '堂食',
      '餐饮',
    ])) {
      return 'restaurant';
    }
    return 'default';
  }

  static TodoDomainKind domainKindForText(String text) {
    final normalized = text.trim().toLowerCase();
    return _containsAny(normalized, _pickupKeywords)
        ? TodoDomainKind.pickup
        : TodoDomainKind.standard;
  }

  static TodoDomainKind domainKindForTodo(TodoItem todo) {
    return domainKindForText('${todo.title} ${todo.remark ?? ''}');
  }

  /// 遮盖取用类待办中的码值，供锁屏通知、桌面组件等外露场景使用。
  static String maskPickupSensitiveText(
    String text, {
    bool forcePickupContext = false,
  }) {
    if (!forcePickupContext &&
        domainKindForText(text) != TodoDomainKind.pickup) {
      return text;
    }
    return text.replaceAllMapped(_pickupCodeTokenPattern, (match) {
      final value = match.group(0)!;
      if (value.length <= 2) return List.filled(value.length, '•').join();
      return '${List.filled(value.length - 2, '•').join()}${value.substring(value.length - 2)}';
    });
  }

  static CaptureIntentKind classifyCaptureIntent(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return CaptureIntentKind.todo;

    final isPickup = _containsAny(normalized, _pickupKeywords);
    final isPreparation = _containsAny(normalized, _preparationKeywords);
    final hasClock = _clockPattern.hasMatch(normalized);
    final hasTimeRange = _timeRangePattern.hasMatch(normalized);
    final isAppointment = normalized.contains('预约') && hasClock;
    final mustWaitForDelivery = hasTimeRange &&
        (normalized.contains('上门') || normalized.contains('必须在家'));

    if (hasTimeRange && _containsAny(normalized, _selfDirectedWorkKeywords)) {
      return CaptureIntentKind.planBlock;
    }
    if (isPreparation) return CaptureIntentKind.todo;
    if (isAppointment || mustWaitForDelivery) {
      return CaptureIntentKind.fixedSchedule;
    }
    if (isPickup) return CaptureIntentKind.todo;
    if (_containsAny(normalized, _fixedScheduleKeywords)) {
      return CaptureIntentKind.fixedSchedule;
    }
    if (hasTimeRange) return CaptureIntentKind.needsConfirmation;
    return CaptureIntentKind.todo;
  }

  static bool _containsAny(String text, Iterable<String> keywords) {
    return keywords.any(text.contains);
  }
}
