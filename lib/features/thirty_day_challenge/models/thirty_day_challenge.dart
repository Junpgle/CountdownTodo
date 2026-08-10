import 'dart:math';
import '../../../utils/json_value_parser.dart';

class ChallengeDraft {
  final String title;
  final List<String> taskTitles;

  const ChallengeDraft({
    required this.title,
    required this.taskTitles,
  });
}

/// 一次性挑战中的单项任务。
///
/// 任务可以按任意顺序完成，每项最多记录一次完成时间；感受记录与完成状态
/// 分开保存，用户可以先写下想法，再稍后完成任务。
class ThirtyDayChallengeTask {
  final int id;
  final String originalTitle;
  String? customTitle;
  bool isCompleted;
  DateTime? completedAt;
  String feeling;
  DateTime? feelingUpdatedAt;
  String? imageBase64;
  DateTime? imageUpdatedAt;

  ThirtyDayChallengeTask({
    required this.id,
    required this.originalTitle,
    this.customTitle,
    this.isCompleted = false,
    this.completedAt,
    this.feeling = '',
    this.feelingUpdatedAt,
    this.imageBase64,
    this.imageUpdatedAt,
  });

  String get title => customTitle?.trim().isNotEmpty == true
      ? customTitle!.trim()
      : originalTitle;

  bool get isCustomized =>
      customTitle?.trim().isNotEmpty == true &&
      customTitle!.trim() != originalTitle;

  Map<String, dynamic> toJson() => {
        'id': id,
        'original_title': originalTitle,
        'custom_title': customTitle,
        'is_completed': isCompleted,
        'completed_at': completedAt?.toIso8601String(),
        'feeling': feeling,
        'feeling_updated_at': feelingUpdatedAt?.toIso8601String(),
        'image_base64': imageBase64,
        'image_updated_at': imageUpdatedAt?.toIso8601String(),
      };

  factory ThirtyDayChallengeTask.fromJson(Map<String, dynamic> json) {
    return ThirtyDayChallengeTask(
      id: _parseInt(json['id']) ?? 0,
      originalTitle: json['original_title']?.toString() ?? '',
      customTitle: _parseNullableString(json['custom_title']),
      isCompleted: json['is_completed'] == true || json['is_completed'] == 1,
      completedAt: _parseDate(json['completed_at']),
      feeling: json['feeling']?.toString() ?? '',
      feelingUpdatedAt: _parseDate(json['feeling_updated_at']),
      imageBase64: _parseNullableString(json['image_base64']),
      imageUpdatedAt: _parseDate(json['image_updated_at']),
    );
  }

  static int? _parseInt(dynamic value) => JsonValueParser.toNullableInt(value);

  static String? _parseNullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _parseDate(dynamic value) {
    final text = value?.toString();
    return text == null ? null : DateTime.tryParse(text);
  }
}

class ThirtyDayChallengeState {
  static const int currentVersion = 2;
  static const String defaultTitle = '30天找到全新自我';

  final int version;
  final String challengeTitle;
  final DateTime startedAt;
  final List<ThirtyDayChallengeTask> tasks;

  ThirtyDayChallengeState({
    required this.startedAt,
    required this.tasks,
    this.challengeTitle = defaultTitle,
    this.version = currentVersion,
  });

  bool get isBuiltIn => challengeTitle == defaultTitle && tasks.length == 30;

  int get completedCount => tasks.where((task) => task.isCompleted).length;

  bool get isCompleted => completedCount == tasks.length;

  double get progress => tasks.isEmpty ? 0 : completedCount / tasks.length;

  List<ThirtyDayChallengeTask> get unfinishedTasks =>
      tasks.where((task) => !task.isCompleted).toList(growable: false);

  ThirtyDayChallengeTask? randomUnfinishedTask([Random? random]) {
    final unfinished = unfinishedTasks;
    if (unfinished.isEmpty) return null;
    return unfinished[(random ?? Random()).nextInt(unfinished.length)];
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'challenge_title': challengeTitle,
        'started_at': startedAt.toIso8601String(),
        'tasks': tasks.map((task) => task.toJson()).toList(),
      };

  factory ThirtyDayChallengeState.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'];
    final tasks = rawTasks is List
        ? rawTasks
            .whereType<Map>()
            .map((item) => ThirtyDayChallengeTask.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .where((task) => task.originalTitle.isNotEmpty)
            .toList()
        : <ThirtyDayChallengeTask>[];

    // v1 没有挑战标题，且任务列表可能只有用户修改过的部分；继续按旧逻辑
    // 合并默认的 30 项任务，避免升级后丢失已有进度。v2 起任务清单完全由
    // 保存内容决定，可以是任意数量。
    final hasCustomSchema = json.containsKey('challenge_title');
    final normalizedTasks =
        hasCustomSchema ? _normalizeTaskIds(tasks) : _restoreLegacyTasks(tasks);
    final safeTasks = normalizedTasks.isEmpty
        ? ThirtyDayChallengeState.initial().tasks
        : normalizedTasks;
    final rawTitle = json['challenge_title']?.toString().trim();

    return ThirtyDayChallengeState(
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse(json['version']?.toString() ?? '') ?? currentVersion,
      challengeTitle:
          rawTitle == null || rawTitle.isEmpty ? defaultTitle : rawTitle,
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? '') ??
          DateTime.now(),
      tasks: safeTasks,
    );
  }

  /// 创建一份完全自定义的挑战。空白行由调用方或文本解析器过滤后再传入。
  static ThirtyDayChallengeState custom({
    required String title,
    required Iterable<String> taskTitles,
    DateTime? startedAt,
  }) {
    final normalizedTitle = title.trim();
    final normalizedTasks = taskTitles
        .map((task) => task.trim())
        .where((task) => task.isNotEmpty)
        .toList(growable: false);
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', '挑战标题不能为空');
    }
    if (normalizedTasks.isEmpty) {
      throw ArgumentError.value(taskTitles, 'taskTitles', '至少需要一项任务');
    }

    return ThirtyDayChallengeState(
      challengeTitle: normalizedTitle,
      startedAt: startedAt ?? DateTime.now(),
      tasks: [
        for (var index = 0; index < normalizedTasks.length; index++)
          ThirtyDayChallengeTask(
            id: index + 1,
            originalTitle: normalizedTasks[index],
          ),
      ],
    );
  }

  static List<ThirtyDayChallengeTask> _normalizeTaskIds(
    List<ThirtyDayChallengeTask> tasks,
  ) {
    return [
      for (var index = 0; index < tasks.length; index++)
        _copyTaskWithId(tasks[index], index + 1),
    ];
  }

  static List<ThirtyDayChallengeTask> _restoreLegacyTasks(
    List<ThirtyDayChallengeTask> tasks,
  ) {
    final defaults = ThirtyDayChallengeState.initial().tasks;
    final tasksById = <int, ThirtyDayChallengeTask>{
      for (final task in tasks) task.id: task,
    };
    return defaults
        .map((defaultTask) => tasksById[defaultTask.id] ?? defaultTask)
        .toList();
  }

  static ThirtyDayChallengeTask _copyTaskWithId(
    ThirtyDayChallengeTask task,
    int id,
  ) {
    return ThirtyDayChallengeTask(
      id: id,
      originalTitle: task.originalTitle,
      customTitle: task.customTitle,
      isCompleted: task.isCompleted,
      completedAt: task.completedAt,
      feeling: task.feeling,
      feelingUpdatedAt: task.feelingUpdatedAt,
      imageBase64: task.imageBase64,
      imageUpdatedAt: task.imageUpdatedAt,
    );
  }

  static ThirtyDayChallengeState initial({DateTime? startedAt}) {
    const titles = [
      '去一间从来没去过的餐厅',
      '换一个平时不常用的交通工具回家',
      '跟一个一年（以及以上）没联系的老友聊天',
      '一口气读完一本新的书',
      '选一天，离开网络',
      '比平常早起一个小时，吃丰盛的早餐',
      '请家人外出吃饭（自己做一顿大餐）',
      '点一杯从来没喝过的饮料',
      '一个人看一场电影',
      '看隔壁桌吃什么自己就点什么',
      '写一封信给三年后的自己',
      '做一项手工（折纸、乐高、编织等）',
      '去海边或者森林亲近大自然',
      '和一个陌生人聊 3 句',
      '翻看老照片、旧日记',
      '整理房间',
      '慢跑 30 分钟',
      '十点半睡觉',
      '跟家人说“我爱你”',
      '买一束花放在家里',
      '和好朋友去野餐',
      '拒绝别人',
      '跟朋友一起唱一场主题限定 KTV',
      '不加班',
      '认识一个新朋友',
      '给好朋友/家人送一个礼物',
      '在好朋友家过夜聊八卦',
      '一个人逛街大采购',
      '化一个最完美的妆 + 拍照',
      '把这 30 天的感受记下来',
    ];

    return ThirtyDayChallengeState(
      challengeTitle: defaultTitle,
      startedAt: startedAt ?? DateTime.now(),
      tasks: [
        for (var index = 0; index < titles.length; index++)
          ThirtyDayChallengeTask(id: index + 1, originalTitle: titles[index]),
      ],
    );
  }
}
