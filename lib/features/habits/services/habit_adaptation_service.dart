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

  String quickLabel(int value, {String? unit}) {
    if (kind == HabitAdaptationKind.running && !_isDurationUnit(unit)) {
      final displayUnit = unit?.trim() ?? '';
      return displayUnit.isEmpty ? '$value' : '$value $displayUnit';
    }
    return switch (kind) {
      HabitAdaptationKind.hydration => switch (value) {
          200 => '一杯 · 200 ml',
          300 => '小瓶 · 300 ml',
          500 => '一瓶 · 500 ml',
          _ => '$value ml',
        },
      HabitAdaptationKind.pushUp => switch (value) {
          8 => '起步 · 8 个',
          12 => '标准组 · 12 个',
          16 => '挑战组 · 16 个',
          _ => '$value 个',
        },
      HabitAdaptationKind.running => switch (value) {
          20 => '入门 · 20 分钟',
          30 => '基础 · 30 分钟',
          45 => '进阶 · 45 分钟',
          60 => '耐力 · 60 分钟',
          _ => '$value 分钟',
        },
      HabitAdaptationKind.reading => switch (value) {
          15 => '轻量 · 15 分钟',
          25 => '专注 · 25 分钟',
          30 => '基础 · 30 分钟',
          45 => '深入 · 45 分钟',
          60 => '沉浸 · 60 分钟',
          _ => '$value 分钟',
        },
      HabitAdaptationKind.earlyWake ||
      HabitAdaptationKind.earlySleep =>
        '$value',
    };
  }

  static bool _isDurationUnit(String? unit) {
    final normalized = (unit ?? '').trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == '分钟' ||
        normalized == 'minute' ||
        normalized == 'minutes' ||
        normalized == 'min';
  }
}

enum HabitAdaptationKind {
  hydration,
  pushUp,
  running,
  reading,
  earlyWake,
  earlySleep,
}

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

  static const _pushUp = HabitAdaptation(
    kind: HabitAdaptationKind.pushUp,
    title: '科学俯卧撑',
    headline: '把俯卧撑当作力量训练：每周 2–3 次，每次分 2–3 组完成',
    explanation:
        '俯卧撑属于自重抗阻训练。对健康成年人，可以先用每组约 8–12 个、每次 2–3 组作为可编辑起点；目标数量表示一次训练的总次数，不要求每天做到。做不到标准俯卧撑时，可先用斜板或跪姿版本，保持动作质量后再逐步增加。',
    safetyNote:
        '动作时保持躯干稳定、下放和撑起都要受控，不要为了凑数牺牲姿势。肩、腕、肘或背部出现明显疼痛，或出现头晕、胸闷、异常气短时请立即停止；已有伤病或慢性病，先向医生或运动专业人士确认合适的变式和负荷。',
    targetSuggestions: [
      HabitTargetSuggestion(
        label: '入门',
        description: '1 组 × 8 个，先熟悉动作',
        value: 8,
        displayValue: '8 个/次',
      ),
      HabitTargetSuggestion(
        label: '基础',
        description: '2 组 × 8 个，适合逐步建立习惯',
        value: 16,
        displayValue: '16 个/次',
      ),
      HabitTargetSuggestion(
        label: '平衡',
        description: '2 组 × 12 个，作为通用起点',
        value: 24,
        displayValue: '24 个/次',
      ),
      HabitTargetSuggestion(
        label: '进阶',
        description: '3 组 × 12 个，已有基础后再选',
        value: 36,
        displayValue: '36 个/次',
      ),
    ],
    suggestedQuickValues: [8, 12, 16],
    citations: [
      HabitCitation(
        title: 'Resistance Training for Health',
        publisher: 'American College of Sports Medicine (ACSM)',
        url:
            'https://www.acsm.org/docs/default-source/files-for-resource-library/resistance-training-for-health.pdf',
        takeaway:
            'ACSM 的通用抗阻训练建议包括每个动作 2–3 组、每组 8–12 次、动作保持良好形式，并每周训练 2–3 次；应随能力逐步增加挑战。',
      ),
      HabitCitation(
        title:
            '5 Things to Know About Creating an Effective Resistance Training Plan',
        publisher: 'American College of Sports Medicine (ACSM)',
        url:
            'https://www.acsm.org/wp-content/uploads/2026/03/Resistance-Training-Position-Stand-infographic.pdf',
        takeaway:
            '2026 年 ACSM 更新强调，徒手训练和居家训练也能有效，最重要的是持续训练、覆盖主要肌群并逐步增加负荷，不必追求复杂技巧。',
      ),
      HabitCitation(
        title: 'Physical Activity Guidelines for Americans, 2nd edition',
        publisher: 'U.S. Department of Health and Human Services',
        url:
            'https://health.gov/paguidelines/second-edition/pdf/Physical_Activity_Guidelines_2nd_edition.pdf',
        takeaway: '指南把俯卧撑列为自重肌力训练示例，建议成年人每周至少 2 天进行覆盖主要肌群的肌力活动；数量和难度应随个人能力调整。',
      ),
      HabitCitation(
        title: 'Weight training: Do’s and don’ts of proper technique',
        publisher: 'Mayo Clinic Orthopedics & Sports Medicine',
        url:
            'https://sportsmedicine.mayoclinic.org/news/weight-training-dos-and-donts-of-proper-technique/',
        takeaway:
            '正确姿势、完整且受控的动作、充分热身和逐步增加训练量有助于降低不必要的损伤风险；出现疼痛应停止并降低负荷或寻求专业建议。',
      ),
      HabitCitation(
        title: 'Push-up Assessment Protocol',
        publisher: 'American Council on Exercise (ACE)',
        url:
            'https://www.acefitness.org/images/webcontent/assets/certification/ace-answers/forms/pt/36_Push-up_Assessment_Protocol.pdf',
        takeaway: '标准俯卧撑评估强调身体保持稳定、肘部充分伸展、完成完整动作；当无法保持正确技术时应停止计数或改用合适的变式。',
      ),
    ],
    targetSuggestionTitle: '快速选择每次训练目标',
    targetUnit: '个',
  );

  static const _running = HabitAdaptation(
    kind: HabitAdaptationKind.running,
    title: '科学跑步',
    headline: '把跑步按时间累计：先从每次 30 分钟、每周 3 次起步',
    explanation:
        '跑步通常属于高强度有氧活动，但同样的配速对不同人强度不同。以时间而不是公里数记录，更容易和权威指南对齐：成年人每周可先以 75 分钟高强度活动为起点，或以 150 分钟中等强度活动为起点；当前每次目标和训练日都可以按体能调整。',
    safetyNote:
        '新开始或久未运动时，先用跑走交替和舒适配速，逐步增加时间与强度；每次先热身、结束后放慢走几分钟。出现胸痛、晕厥、异常气短、关节明显疼痛，或已有心肺/关节疾病、孕期等情况，请停止并先咨询医生或运动专业人士。',
    targetSuggestions: [
      HabitTargetSuggestion(
        label: '入门',
        description: '跑走交替或轻松慢跑',
        value: 20,
        displayValue: '20 分钟/次',
      ),
      HabitTargetSuggestion(
        label: '基础',
        description: '每周 3 次约 90 分钟',
        value: 30,
        displayValue: '30 分钟/次',
      ),
      HabitTargetSuggestion(
        label: '进阶',
        description: '已有基础后逐步增加',
        value: 45,
        displayValue: '45 分钟/次',
      ),
      HabitTargetSuggestion(
        label: '耐力',
        description: '适合已有稳定跑量的人',
        value: 60,
        displayValue: '60 分钟/次',
      ),
    ],
    suggestedQuickValues: [20, 30, 45],
    citations: [
      HabitCitation(
        title: 'Physical activity',
        publisher: 'World Health Organization (WHO)',
        url:
            'https://www.who.int/health-topics/noncommunicable-diseases/physical-activity',
        takeaway:
            '成年人每周至少进行 150 分钟中等强度，或 75 分钟高强度有氧活动；WHO 将跑步列为高强度活动示例，并强调不活动者应从少量开始、逐步增加。',
      ),
      HabitCitation(
        title: '最新版中国居民膳食指南（2022）发布——吃动平衡 养成健康生活方式',
        publisher: '国家体育总局 · 中国居民膳食指南（2022）',
        url:
            'https://www.sport.gov.cn/n20001280/n20001265/n20066978/c24291669/content.html',
        takeaway: '建议每周至少 5 天中等强度身体活动，累计 150 分钟以上；同时鼓励适当高强度有氧和每周 2–3 天抗阻运动。',
      ),
      HabitCitation(
        title: 'Physical Activity Guidelines for Americans, 2nd edition',
        publisher: 'U.S. Department of Health and Human Services (HHS)',
        url:
            'https://health.gov/paguidelines/second-edition/pdf/Physical_Activity_Guidelines_2nd_edition.pdf',
        takeaway: '指南强调任何活动都比不活动好，应根据能力逐步增加；中等强度通常可以说话但不能唱歌，高强度时只能说几句话就需要换气。',
      ),
      HabitCitation(
        title: 'Couch to 5K running plan',
        publisher: 'National Health Service (NHS)',
        url:
            'https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan/',
        takeaway:
            '面向初跑者的计划采用每周 3 次、跑走交替、跑步日之间安排休息日的渐进方式，并建议每次先 5 分钟热身走、结束后 5 分钟放松走。',
      ),
    ],
    targetSuggestionTitle: '快速选择每次跑步目标',
    targetUnit: '分钟',
  );

  static const _reading = HabitAdaptation(
    kind: HabitAdaptationKind.reading,
    title: '科学阅读',
    headline: '阅读不只看时长：先用每次 25–30 分钟建立专注，再把理解留下来',
    explanation:
        '没有适合所有人的统一“每日阅读分钟数”。这里把 30 分钟作为可编辑的行为起点：读前明确一个问题，读中少量标记，读后用自己的话回忆要点；学习型阅读再通过间隔复习巩固，而不是只追求翻页速度。',
    safetyNote:
        '阅读时保持舒适的光线、距离和坐姿；屏幕阅读可每 20 分钟看向远处约 20 秒，眼睛疲劳或干涩时先休息。不要为了完成时长熬夜，也不要把页数或速度当成理解程度的替代品。',
    targetSuggestions: [
      HabitTargetSuggestion(
        label: '轻量',
        description: '适合刚开始建立阅读习惯',
        value: 15,
        displayValue: '15 分钟/天',
      ),
      HabitTargetSuggestion(
        label: '专注',
        description: '一个完整专注块，适合忙碌日',
        value: 25,
        displayValue: '25 分钟/天',
      ),
      HabitTargetSuggestion(
        label: '基础',
        description: '默认可编辑起点',
        value: 30,
        displayValue: '30 分钟/天',
      ),
      HabitTargetSuggestion(
        label: '深入',
        description: '适合需要连续理解的内容',
        value: 45,
        displayValue: '45 分钟/天',
      ),
      HabitTargetSuggestion(
        label: '沉浸',
        description: '已有稳定阅读节奏后再选',
        value: 60,
        displayValue: '60 分钟/天',
      ),
    ],
    suggestedQuickValues: [15, 25, 30],
    citations: [
      HabitCitation(
        title: 'Cognitive Health and Older Adults',
        publisher: 'National Institute on Aging (NIH)',
        url:
            'https://www.nia.nih.gov/health/brain-health/cognitive-health-and-older-adults',
        takeaway:
            '有意义的认知活动可能有助于保持脑健康，但长期效果的证据仍不确定；因此阅读目标应当是可持续的行为锚点，而不是保证认知收益的医学承诺。',
      ),
      HabitCitation(
        title: 'Review of learning: spaced retrieval practice',
        publisher: 'NSW Department of Education',
        url:
            'https://education.nsw.gov.au/teaching-and-learning/curriculum/explicit-teaching/explicit-teaching-strategies/connecting-learning/review-learning',
        takeaway: '主动从记忆中回忆并把复习间隔开，比单纯重复阅读更有利于长期保留；阅读后用自己的话回忆要点可以形成一个轻量的理解闭环。',
      ),
      HabitCitation(
        title: 'Computer Vision Syndrome',
        publisher: 'American Academy of Ophthalmology EyeWiki',
        url:
            'https://eyewiki.aao.org/Computer_Vision_Syndrome_%28Digital_Eye_Strain%29',
        takeaway: '长时间屏幕阅读可配合定期远眺、眨眼和短暂休息来减少视觉疲劳；出现持续不适时应减少负荷并寻求眼科建议。',
      ),
      HabitCitation(
        title: 'Reading and cognitive processing challenges',
        publisher:
            'U.S. Department of Health and Human Services · Health Literacy Online',
        url:
            'https://odphp.health.gov/healthliteracyonline/what-we-know/section-1-1/',
        takeaway: '阅读同时涉及文字解码和理解，内容过密会增加认知负担；将目标拆成可完成的阅读块，有助于把注意力放在理解而不是硬撑时长上。',
      ),
    ],
    targetSuggestionTitle: '快速选择每日阅读目标',
    targetUnit: '分钟',
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
        const pushUpWords = [
          '俯卧撑',
          '俯卧支撑',
          'pushup',
          'push-up',
          'pushups',
          'pressup',
          'press-up',
        ];
        if (pushUpWords.any(normalized.contains)) return _pushUp;
        const runningWords = [
          '跑步',
          '慢跑',
          '跑走',
          'running',
          'jogging',
          'jog',
        ];
        if (runningWords.any(normalized.contains)) return _running;
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
        const readingWords = [
          '阅读',
          '读书',
          '看书',
          '书籍',
          '读文献',
          'reading',
          'read',
          'book',
        ];
        if (readingWords.any(normalized.contains)) return _reading;
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
