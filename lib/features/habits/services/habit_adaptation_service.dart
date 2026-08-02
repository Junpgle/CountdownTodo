import '../models/habit_goal.dart';

/// 习惯的领域化适配信息。
///
/// 适配信息是产品内置的、可版本控制的知识，不写入习惯数据表，
/// 因此不会破坏旧数据和跨设备同步；习惯本身仍然由通用的数量型规则记录。
class HabitAdaptation {
  final HabitAdaptationKind kind;
  final String title;
  final String headline;
  final String explanation;
  final String safetyNote;
  final List<HabitTargetSuggestion> targetSuggestions;
  final List<int> suggestedQuickValues;
  final List<HabitCitation> citations;

  const HabitAdaptation({
    required this.kind,
    required this.title,
    required this.headline,
    required this.explanation,
    required this.safetyNote,
    required this.targetSuggestions,
    required this.suggestedQuickValues,
    required this.citations,
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

enum HabitAdaptationKind { hydration }

class HabitTargetSuggestion {
  final String label;
  final String description;
  final int value;

  const HabitTargetSuggestion({
    required this.label,
    required this.description,
    required this.value,
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

  /// 为已有目标获取适配。旧数据没有 profile 字段，先通过名称识别，
  /// 让“喝水 / 每日喝水 / hydration”等已有习惯立即获得新体验。
  static HabitAdaptation? forHabit(HabitGoal goal) {
    return forDraft(sourceType: goal.sourceType, name: goal.name);
  }

  static HabitAdaptation? forDraft({
    required HabitSourceType sourceType,
    required String name,
  }) {
    if (sourceType != HabitSourceType.quantityCheckIn) return null;
    final normalized = name.trim().toLowerCase().replaceAll(' ', '');
    const waterWords = [
      '喝水',
      '饮水',
      '补水',
      '水分',
      'hydration',
      'water',
    ];
    if (waterWords.any(normalized.contains)) return _hydration;
    return null;
  }
}
