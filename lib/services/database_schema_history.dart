class DatabaseSchemaChange {
  final int version;
  final String title;
  final List<String> changes;

  const DatabaseSchemaChange({
    required this.version,
    required this.title,
    required this.changes,
  });
}

abstract final class DatabaseSchemaHistory {
  static const int currentVersion = 35;

  /// SQLite 架构版本记录，按新到旧排列。
  static const List<DatabaseSchemaChange> changes = [
    DatabaseSchemaChange(
      version: 35,
      title: '固定日程同步安全',
      changes: [
        '为 fixed_schedules 保存所有者标识，避免团队成员误操作团队归属。',
      ],
    ),
    DatabaseSchemaChange(
      version: 34,
      title: '固定日程自定义重复间隔',
      changes: [
        '为 fixed_schedules 新增 custom_interval_days，确保自定义重复规则可跨端编辑。',
      ],
    ),
    DatabaseSchemaChange(
      version: 33,
      title: '独立固定日程',
      changes: [
        '新增 fixed_schedules 表，独立保存固定日程、重复规则、提醒和关联待办。',
        '新增日期与外部来源索引，提升日程查询和外部日历匹配效率。',
      ],
    ),
    DatabaseSchemaChange(
      version: 32,
      title: '专注暂停详情',
      changes: [
        '为专注记录新增暂停总时长和暂停区间字段，保留完整暂停明细。',
      ],
    ),
    DatabaseSchemaChange(
      version: 31,
      title: '专注标签归档',
      changes: [
        '为专注标签新增归档状态，支持隐藏停用标签而不删除历史数据。',
      ],
    ),
    DatabaseSchemaChange(
      version: 30,
      title: '屏幕时间元数据',
      changes: [
        '为屏幕时间记录补充设备名称和应用分类字段。',
        '修复旧数据库的屏幕时间表结构并补齐日期索引。',
      ],
    ),
    DatabaseSchemaChange(
      version: 29,
      title: '专注记录备注',
      changes: [
        '为专注记录新增备注字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 28,
      title: '分类建议反馈',
      changes: [
        '新增建议反馈表和查询索引，用于学习关键词分类建议的采纳结果。',
      ],
    ),
    DatabaseSchemaChange(
      version: 27,
      title: '勋章智能推荐',
      changes: [
        '新增勋章推荐跟踪表，保存推荐次数、成功次数和模型参数。',
      ],
    ),
    DatabaseSchemaChange(
      version: 26,
      title: '专注冲突处理',
      changes: [
        '为专注标签和专注记录补充冲突标记与冲突快照字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 25,
      title: '待办规划块',
      changes: [
        '新增待办规划块表，保存计划时段、番茄钟配置、提醒和日历关联。',
        '为专注记录新增规划块关联字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 24,
      title: '课程结构自愈',
      changes: [
        '再次触发旧课程表字段检查，修复个别设备升级后仍缺少同步字段的问题。',
      ],
    ),
    DatabaseSchemaChange(
      version: 23,
      title: '旧课表兼容修复',
      changes: [
        '为旧课程表补齐删除状态、数据版本和创建/更新时间等同步字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 22,
      title: '远端条目忽略记录',
      changes: [
        '新增远端条目忽略表，记录无需再次拉取或恢复的云端数据。',
      ],
    ),
    DatabaseSchemaChange(
      version: 21,
      title: '屏幕时间记录',
      changes: [
        '新增屏幕时间表和日期索引，按日期、应用与设备保存使用时长。',
      ],
    ),
    DatabaseSchemaChange(
      version: 20,
      title: '同步错误字段修复',
      changes: [
        '再次检查并补齐操作日志的同步错误字段，避免旧库同步中断。',
      ],
    ),
    DatabaseSchemaChange(
      version: 19,
      title: '倒数日完成状态',
      changes: [
        '为倒数日新增完成状态，支持时间轴统计与历史状态展示。',
      ],
    ),
    DatabaseSchemaChange(
      version: 18,
      title: '搜索时段权重',
      changes: [
        '为搜索历史新增早晨、下午、晚间和深夜的分时计数字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 17,
      title: '搜索历史',
      changes: [
        '新增搜索历史表，记录关键词、最近搜索时间和使用频次。',
      ],
    ),
    DatabaseSchemaChange(
      version: 16,
      title: '课程同步元数据',
      changes: [
        '为课程补齐删除状态、数据版本和创建/更新时间字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 15,
      title: '同步失败原因',
      changes: [
        '为操作日志新增同步错误字段，保留失败原因以便重试和诊断。',
      ],
    ),
    DatabaseSchemaChange(
      version: 14,
      title: '时间日志协议对齐',
      changes: [
        '重建时间日志表，使标题、标签、备注、设备和团队字段与同步协议一致。',
      ],
    ),
    DatabaseSchemaChange(
      version: 13,
      title: '专注标签',
      changes: [
        '新增专注标签表，保存标签名称、颜色和同步状态。',
      ],
    ),
    DatabaseSchemaChange(
      version: 12,
      title: '时间日志',
      changes: [
        '新增时间日志表，开始持久化任务时段、分类和备注。',
      ],
    ),
    DatabaseSchemaChange(
      version: 11,
      title: '专注记录与课程',
      changes: [
        '新增专注记录表和课程表。',
      ],
    ),
    DatabaseSchemaChange(
      version: 10,
      title: '离线审计日志',
      changes: [
        '新增本地审计日志表，支持离线查看数据变更历史。',
      ],
    ),
    DatabaseSchemaChange(
      version: 9,
      title: '版本冲突元数据',
      changes: [
        '为待办、倒数日和待办组新增冲突标记与冲突快照。',
        '为待办新增全天状态。',
      ],
    ),
    DatabaseSchemaChange(
      version: 8,
      title: '循环任务与提醒',
      changes: [
        '为待办新增循环规则、自定义间隔、结束日期和提前提醒字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 7,
      title: '独立完成进度',
      changes: [
        '新增团队待办成员完成情况表，支持成员独立完成。',
      ],
    ),
    DatabaseSchemaChange(
      version: 6,
      title: '协作模式',
      changes: [
        '为待办新增协作类型字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 5,
      title: '核心字段与全文检索修复',
      changes: [
        '补齐待办和待办组的基础协作字段。',
        '重新检测并建立 FTS 全文检索结构。',
      ],
    ),
    DatabaseSchemaChange(
      version: 4,
      title: '预留版本',
      changes: [
        '该版本号未单独发布，没有独立的数据库结构迁移。',
      ],
    ),
    DatabaseSchemaChange(
      version: 3,
      title: '协作元数据',
      changes: [
        '为待办、倒数日和待办组补充创建者与团队名称字段。',
      ],
    ),
    DatabaseSchemaChange(
      version: 2,
      title: '团队字段与搜索索引',
      changes: [
        '为待办补充团队标识和团队名称。',
        '重建待办全文检索虚表与触发器。',
      ],
    ),
    DatabaseSchemaChange(
      version: 1,
      title: 'SQLite 基础架构',
      changes: [
        '引入待办、离线操作日志和 FTS 全文检索等本地 SQLite 基础结构。',
      ],
    ),
  ];
}
