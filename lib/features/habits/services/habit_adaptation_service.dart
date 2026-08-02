import '../models/habit_goal.dart';

/// 习惯的领域化适配信息。
///
/// 适配信息是产品内置的、可版本控制的知识，不写入习惯数据表，
/// 因此不会破坏旧数据和跨设备同步；习惯本身仍然由通用规则记录。
class HabitAdaptation {
  final HabitAdaptationKind kind;
  final String title;
  final String headline;
  final String explanation;
  final String safetyNote;
  final List<HabitTargetSuggestion> targetSuggestions;
  final List<int> suggestedQuickValues;
  final List<HabitCitation> citations;
  final String targetSuggestionTitle;
  final String targetUnit;

  const HabitAdaptation({
    required this.kind,
    required this.title,
    required this.headline,
    required this.explanation,
    required this.safetyNote,
    required this.targetSuggestions,
    required this.suggestedQuickValues,
    required this.citations,
    this.targetSuggestionTitle = '快速选择每日目标',
    this.targetUnit = 'ml',
  });

  String quickLabel(int value) {
    if (kind != HabitAdaptationKind.hydration) return '$value';
    return switch (value) {
      200 => '一杯 · 200 ml',
      300 => '小瓶 · 300 ml',
      500 => '一瓶 · 500 ml',
      _ => '$value ml',
    };
  }
}

enum HabitAdaptationKind { hydration, earlyWake, earlySleep }

class HabitTargetSuggestion {
  final String label;
  final String description;
  final int value;
  final String? displayValue;

  const HabitTargetSuggestion({
    required this.label,
    required this.description,
    required this.value,
    this.displayValue,
  });
}

class HabitCitation {
  final String title;
  final String publisher;
  final String url;
  final String takeaway;

  const HabitCitation({
    required this.title,
    required this.publisher,
    required this.url,
    required this.takeaway,
  });
}

/// 早睡 / 早起配对时，用于描述已有目标和反推结果。
class HabitSleepPairSuggestion {
  final HabitAdaptationKind sourceKind;
  final String sourceName;
  final int sourceMinute;
  final HabitAdaptationKind targetKind;
  final int recommendedMinute;
  final int rangeStartMinute;
  final int rangeEndMinute;

  const HabitSleepPairSuggestion({
    required this.sourceKind,
    required this.sourceName,
    required this.sourceMinute,
    required this.targetKind,
    required this.recommendedMinute,
    required this.rangeStartMinute,
    required this.rangeEndMinute,
  });
}

/// 将通用习惯映射到可解释的领域化体验。
abstract final class HabitAdaptationService {
  static const _hydration = HabitAdaptation(
    kind: HabitAdaptationKind.hydration,
    title: '科学饮水',
    headline: '温和气候、低活动成年人的饮水起点：约 1500–1700 ml/天',
    explanation:
        '这里说的是饮水量，不是总水摄入。食物、汤、粥和奶等也会提供水分；建议少量多次，单次约 200 ml。默认以 1600 ml 作为可编辑的中间值。',
    safetyNote:
        '高温、长时间运动、发热、呕吐或腹泻时需求会变化。孕期、哺乳期、儿童，以及有心脏、肾脏或肝脏疾病者，请按医生或营养专业人士建议调整，不要为了达标在短时间内强行大量饮水。',
    targetSuggestions: [
      HabitTargetSuggestion(
        label: '女性参考',
        description: '低活动、温和气候',
        value: 1500,
      ),
      HabitTargetSuggestion(
        label: '平衡起点',
        description: '不确定时可先从这里开始',
        value: 1600,
      ),
      HabitTargetSuggestion(
        label: '男性参考',
        description: '低活动、温和气候',
        value: 1700,
      ),
    ],
    suggestedQuickValues: [200, 300, 500],
    citations: [
      HabitCitation(
        title: '中国居民平衡膳食宝塔（2022）修订和解析',
        publisher: '中国营养学会 · 中国居民膳食指南',
        url: 'https://dg.cnsoc.org/article/04/RMAbPdrjQ6CGWTwmo62hQg.html',
        takeaway: '低活动水平成年男性每天至少饮水 1700 ml，女性 1500 ml；总水摄入还包括食物和汤水。',
      ),
      HabitCitation(
        title: 'Dietary reference values for water',
        publisher: 'European Food Safety Authority (EFSA)',
        url: 'https://www.efsa.europa.eu/en/press/news/nda100326',
        takeaway: 'EFSA 给出的是总水摄入参考值：成年女性 2.0 L、男性 2.5 L，包含来自食物和饮料的水。',
      ),
      HabitCitation(
        title: 'Dietary Reference Intakes for Water',
        publisher: 'National Academies of Sciences, Engineering, and Medicine',
        url: 'https://nap.nationalacademies.org/read/10925/chapter/2',
        takeaway: '总水摄入包括饮用水、其他饮料和食物水分；AI 是群体参考值，不应理解成每个人必须达到的精确数值。',
      ),
      HabitCitation(
        title: 'Water, drinks and hydration',
        publisher: 'NHS',
        url:
            'https://www.nhs.uk/live-well/eat-well/food-guidelines-and-food-labels/water-drinks-nutrition/',
        takeaway: '6–8 杯是一般性指南，炎热、长时间运动、怀孕哺乳或生病时可能需要更多。',
      ),
    ],
  );

  static const _sleepCitations = <HabitCitation>[
    HabitCitation(
      title: 'Recommended Amount of Sleep for a Healthy Adult',
      publisher: 'American Academy of Sleep Medicine · Sleep Research Society',
      url:
          'https://aasm.org/resources/pdf/pressroom/adult-sleep-duration-consensus.pdf',
      takeaway: '健康成年人应规律地每晚睡 7 小时或以上；个体需求会因年龄和情况而异。',
    ),
    HabitCitation(
      title: 'About Sleep',
      publisher: 'U.S. Centers for Disease Control and Prevention (CDC)',
      url: 'https://www.cdc.gov/sleep/about/index.html',
      takeaway: '18–60 岁成年人通常建议每晚至少睡 7 小时；不同年龄段的需求不同。',
    ),
    HabitCitation(
      title: 'Sleep timing, sleep consistency, and health in adults',
      publisher: 'Applied Physiology, Nutrition, and Metabolism · PubMed',
      url: 'https://pubmed.ncbi.nlm.nih.gov/33054339/',
      takeaway: '系统综述提示，较规律的入睡和起床时间与更好的健康结果相关，但目前不能据此规定统一的“最佳”钟点。',
    ),
    HabitCitation(
      title: 'The importance of sleep regularity',
      publisher: 'National Sleep Foundation consensus panel · PubMed',
      url: 'https://pubmed.ncbi.nlm.nih.gov/37684151/',
      takeaway: '专家共识认为，保持睡眠开始和结束时间的一致性对健康、安全和表现很重要。',
    ),
    HabitCitation(
      title: 'How Sleep Works: Your Sleep/Wake Cycle',
      publisher: 'National Heart, Lung, and Blood Institute (NIH)',
      url: 'https://www.nhlbi.nih.gov/health/sleep/sleep-wake-cycle',
      takeaway: '光暗线索会影响昼夜节律；固定节奏、减少临睡前强光有助于配合睡眠—觉醒周期。',
    ),
  ];

  static const _earlyWake = HabitAdaptation(
    kind: HabitAdaptationKind.earlyWake,
    title: '科学早起',
    headline: '早起不是越早越好：先保证每晚 7–9 小时，再固定起床时间',
    explanation:
        '这里的目标是“最晚在这个时间起床”，不是要求所有人都在同一个钟点醒来。07:00 只是可编辑的起点；更重要的是选一个能长期执行、并且能反推出足够睡眠时间的起床时间。',
    safetyNote:
        '不要为了追求更早起床而长期压缩睡眠。如果持续失眠、白天异常困倦、打鼾伴随憋气，或需要靠闹钟反复挣扎才能起床，建议咨询医生或睡眠专业人士。儿童、青少年、孕期及轮班人群的睡眠需求和作息可能不同。',
    targetSuggestions: [
      HabitTargetSuggestion(
        label: '可持续起点',
        description: '常见的可编辑起点',
        value: 390,
        displayValue: '06:30',
      ),
      HabitTargetSuggestion(
        label: '平衡起点',
        description: '常见的可编辑起点',
        value: 420,
        displayValue: '07:00',
      ),
      HabitTargetSuggestion(
        label: '温和起点',
        description: '常见的可编辑起点',
        value: 450,
        displayValue: '07:30',
      ),
      HabitTargetSuggestion(
        label: '充足缓冲',
        description: '适合需要晚一些起床的人',
        value: 480,
        displayValue: '08:00',
      ),
    ],
    suggestedQuickValues: [],
    citations: _sleepCitations,
    targetSuggestionTitle: '快速选择起床时间（可编辑起点）',
    targetUnit: '',
  );

  static const _earlySleep = HabitAdaptation(
    kind: HabitAdaptationKind.earlySleep,
    title: '科学早睡',
    headline: '早睡的核心是稳定的入睡窗口，并为自己留出 7–9 小时睡眠',
    explanation:
        '这里的目标是“最晚在这个时间准备入睡”，不是把 23:30 当成统一标准。23:30 只是可编辑的起点；系统会根据目标入睡时间反推出建议起床窗口，帮助你检查作息是否压缩了睡眠。',
    safetyNote:
        '如果躺下后经常超过 30 分钟仍无法入睡、夜间反复醒来、白天异常困倦，或持续依赖酒精/药物入睡，请咨询医生或睡眠专业人士。不要为了达成早睡目标在床上长时间清醒，也不要强行减少实际需要的睡眠。',
    targetSuggestions: [
      HabitTargetSuggestion(
        label: '提前起点',
        description: '常见的可编辑起点',
        value: 1320,
        displayValue: '22:00',
      ),
      HabitTargetSuggestion(
        label: '温和起点',
        description: '常见的可编辑起点',
        value: 1350,
        displayValue: '22:30',
      ),
      HabitTargetSuggestion(
        label: '平衡起点',
        description: '常见的可编辑起点',
        value: 1380,
        displayValue: '23:00',
      ),
      HabitTargetSuggestion(
        label: '默认起点',
        description: '常见的可编辑起点',
        value: 1410,
        displayValue: '23:30',
      ),
      HabitTargetSuggestion(
        label: '午夜起点',
        description: '需要开启跨午夜归属',
        value: 0,
        displayValue: '00:00',
      ),
    ],
    suggestedQuickValues: [],
    citations: _sleepCitations,
    targetSuggestionTitle: '快速选择入睡时间（可编辑起点）',
    targetUnit: '',
  );

  /// 为已有目标获取适配。旧数据没有 profile 字段，先通过名称识别，
  /// 让“喝水 / 每日喝水 / hydration”等已有习惯立即获得新体验。
  static HabitAdaptation? forHabit(HabitGoal goal) {
    return forDraft(sourceType: goal.sourceType, name: goal.name);
  }

  static HabitAdaptation? forDraft({
    required HabitSourceType sourceType,
    required String name,
  }) {
    final normalized = name.trim().toLowerCase().replaceAll(' ', '');
    switch (sourceType) {
      case HabitSourceType.quantityCheckIn:
        const waterWords = [
          '喝水',
          '饮水',
          '补水',
          '水分',
          'hydration',
          'water',
        ];
        if (waterWords.any(normalized.contains)) return _hydration;
      case HabitSourceType.timeCheckIn:
        const sleepWords = [
          '早睡',
          '早点睡',
          '睡觉',
          '入睡',
          '上床',
          '就寝',
          'bedtime',
          'sleep',
        ];
        if (sleepWords.any(normalized.contains)) return _earlySleep;
        const wakeWords = [
          '早起',
          '起床',
          '早醒',
          '唤醒',
          'wake',
          'getup',
          'wakeup',
          'morning',
        ];
        if (wakeWords.any(normalized.contains)) return _earlyWake;
      case HabitSourceType.pomodoroTag:
      case HabitSourceType.recurringTodo:
        break;
    }
    return null;
  }

  /// 从已有的早睡或早起目标反推出对应目标。
  ///
  /// 8 小时用于自动预填，7–9 小时作为可解释的建议区间；这不是固定的
  /// 医学标准，用户仍然可以在目标页修改。
  static HabitSleepPairSuggestion? pairSuggestionFor({
    required HabitAdaptationKind sourceKind,
    required String sourceName,
    required int sourceMinute,
  }) {
    if (sourceKind == HabitAdaptationKind.earlySleep) {
      return HabitSleepPairSuggestion(
        sourceKind: sourceKind,
        sourceName: sourceName,
        sourceMinute: sourceMinute,
        targetKind: HabitAdaptationKind.earlyWake,
        recommendedMinute: _normalizeMinute(sourceMinute + 8 * 60),
        rangeStartMinute: _normalizeMinute(sourceMinute + 7 * 60),
        rangeEndMinute: _normalizeMinute(sourceMinute + 9 * 60),
      );
    }
    if (sourceKind == HabitAdaptationKind.earlyWake) {
      return HabitSleepPairSuggestion(
        sourceKind: sourceKind,
        sourceName: sourceName,
        sourceMinute: sourceMinute,
        targetKind: HabitAdaptationKind.earlySleep,
        recommendedMinute: _normalizeMinute(sourceMinute - 8 * 60),
        rangeStartMinute: _normalizeMinute(sourceMinute - 9 * 60),
        rangeEndMinute: _normalizeMinute(sourceMinute - 7 * 60),
      );
    }
    return null;
  }

  static int _normalizeMinute(int minute) {
    final normalized = minute % (24 * 60);
    return normalized < 0 ? normalized + 24 * 60 : normalized;
  }
}
