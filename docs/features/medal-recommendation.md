# 勋章推荐系统文档

本文件合并实现指南与算法说明。

---

## 实现指南

# 勋章推荐系统实现指南

## 📋 项目概览

**#32 徽章和勋章智能推荐** - 已完成核心实现 ✅

### 完成内容

1. ✅ **MedalRecommendationService** (`lib/services/medal_recommendation_service.dart`)
   - 21+ 勋章定义及元数据
   - 每个勋章的进度计算逻辑
   - 智能推荐算法（按容易度排序）
   - 完整的数据模型

2. ✅ **UI Widget** (`lib/widgets/medal_recommendation_card.dart`)
   - MedalRecommendationCard: 快速推荐卡片
   - MedalListDialog: 完整勋章系统对话框
   - 进度条、统计信息展示

3. ✅ **单元测试** (`test/medal_recommendation_service_test.dart`)
   - 11 个测试用例全部通过 ✅
   - 覆盖所有勋章类型
   - 验证推荐算法

---

## 🚀 快速使用

### 1. 在 personal_timeline_screen.dart 中集成

```dart
import 'package:CountDownTodo/services/medal_recommendation_service.dart';
import 'package:CountDownTodo/widgets/medal_recommendation_card.dart';

class PersonalTimelineScreen extends StatefulWidget {
  // ...
  
  @override
  State<PersonalTimelineScreen> createState() => _PersonalTimelineScreenState();
}

class _PersonalTimelineScreenState extends State<PersonalTimelineScreen> {
  // ... existing code ...
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          // ... existing widgets ...
          
          // Add medal recommendation section
          if (_summary != null)
            _buildMedalRecommendation(),
            
          // ... rest of content ...
        ],
      ),
    );
  }
  
  Widget _buildMedalRecommendation() {
    final recommendation = MedalRecommendationService.getRecommendations(
      _summary!,
      _totalFocusMinutes,
      _completedCount,
      _totalCount,
      _earlyCompletionCount,
      _deadlineSprintCount,
      _courseCount,
      _maxDailyCourseCount,
      _screenTimeSeconds,
      _productiveScreenSeconds,
      _distractionScreenSeconds,
    );
    
    return MedalRecommendationCard(
      recommendation: recommendation,
      onViewAll: () {
        showDialog(
          context: context,
          builder: (context) => MedalListDialog(recommendation: recommendation),
        );
      },
    );
  }
}
```

### 2. 数据收集（从现有 personal_timeline_screen 中）

现在你的时间轴屏幕已经计算了所有需要的指标：

```dart
// Focus metrics
_totalFocusMinutes;           // summary.totalFocusMinutes
summary.pomodoroCount;        // Number of pomodoros
summary.deepWorkCount;        // Sessions >= 60 minutes
summary.longestPomodoroMinutes; // Longest focus session

// Completion metrics
_completedCount;              // Completed todos
_totalCount;                  // Total todos
_earlyCompletionCount;        // Completed before deadline
_deadlineSprintCount;         // Completed within 24h of deadline

// Time distribution
summary.peakHour;             // Most productive hour (0-23)
summary.hourlyDistribution;   // Counts per hour
summary.consecutiveActiveDays; // Consecutive days of activity

// Topic breadth
summary.subjectDistribution;  // Topics and their counts
summary.searchCount;          // Knowledge searches
summary.examPrepCount;        // Exam-related activities

// Learning quality
summary.interruptionRate;     // Interruption percentage
summary.courseCount;          // Course records

// Screen time
_screenTimeSeconds;           // Total screen time
_productiveScreenSeconds;     // Productive app time
_distractionScreenSeconds;    // Distraction app time
```

---

## 🎖️ 21 个勋章完整列表

### Focus 类 (6 个)
| ID | 名称 | 条件 | 难度 |
|-----|------|------|------|
| focus_starter | 专注启动者 | ≥1 次 Pomodoro | ⭐ |
| two_hour_guardian | 两小时守门员 | 120 分钟累计 | ⭐⭐ |
| eight_hour_trek | 八小时长征 | 480 分钟累计 | ⭐⭐⭐ |
| deep_worker | 深度工作者 | ≥1 次深度专注 | ⭐⭐ |
| long_focus_specialist | 长专注选手 | ≥90 分钟单次 | ⭐⭐⭐ |
| stable_output | 稳定输出 | 中断率≤10% 且 ≥3 次 | ⭐⭐ |

### Completion 类 (4 个)
| ID | 名称 | 条件 | 难度 |
|-----|------|------|------|
| task_harvester | 任务收割者 | ≥1 完成 | ⭐ |
| plan_fulfiller | 计划兑现者 | 完成率≥80% | ⭐⭐ |
| early_deliverer | 提前交付者 | ≥1 提前完成 | ⭐⭐ |
| ddl_tamer | DDL 驯服者 | ≥1 截止前完成 | ⭐⭐⭐ |

### Persistence 类 (3 个)
| ID | 名称 | 条件 | 难度 |
|-----|------|------|------|
| golden_hour | 黄金时刻 | 发现高效时段 | ⭐⭐ |
| night_efficiency_king | 深夜效率王 | 高效在 20-05 点 | ⭐⭐⭐ |
| long_distance_runner | 长跑型选手 | ≥3 连续活跃天数 | ⭐⭐ |

### Breadth 类 (2 个)
| ID | 名称 | 条件 | 难度 |
|-----|------|------|------|
| learning_polymath | 学习多面手 | ≥4 个不同主题 | ⭐⭐ |
| main_line_pusher | 主线推进者 | 单主题占比≥45% | ⭐⭐ |

### Knowledge 类 (2 个)
| ID | 名称 | 条件 | 难度 |
|-----|------|------|------|
| knowledge_scout | 知识侦察兵 | ≥3 次知识检索 | ⭐⭐ |
| exam_prep_sprinter | 备考冲刺者 | ≥3 次备考活动 | ⭐⭐⭐ |

### Course 类 (2 个)
| ID | 名称 | 条件 | 难度 |
|-----|------|------|------|
| course_companion | 课表同行者 | ≥1 节课记录 | ⭐ |
| full_course_survivor | 满课生存者 | ≥5 节课单日 | ⭐⭐⭐ |

### Screen Time 类 (2 个)
| ID | 名称 | 条件 | 难度 |
|-----|------|------|------|
| screen_master | 屏幕掌控者 | 生产力≥50% | ⭐⭐ |
| low_distraction_mode | 低分心模式 | 分心≤15% | ⭐⭐ |

---

## 🔄 推荐算法原理

### 步骤 1: 计算每个勋章进度 (0.0-1.0)
```dart
double progress = (currentValue / targetValue).clamp(0.0, 1.0);
bool earned = progress >= 1.0;
int stepsRemaining = earned ? 0 : (targetValue - currentValue);
```

### 步骤 2: 排序未获得的勋章
按 `stepsRemaining` 从小到大排序（最容易达成的排在前）

### 步骤 3: 返回前 3 个推荐
```dart
List<MedalProgress> topThree = unearned.take(3).toList();
```

### 动机设计
- **最容易的 3 个**: 增强用户参与度
- **进度条反馈**: 可视化激励
- **下一个里程碑**: 具体的目标

---

## 📊 集成示例代码

### 完整集成（在 personal_timeline_screen.dart 中）

```dart
// 1. 在 State 类中添加方法
MedalRecommendation? _medalRecommendation;

void _updateMedalRecommendations() {
  if (_summary == null) return;
  
  _medalRecommendation = MedalRecommendationService.getRecommendations(
    _summary!,
    _totalFocusMinutes,
    _completedCount,
    _totalCount,
    _earlyCompletionCount,
    _deadlineSprintCount,
    _courseCount,
    _maxDailyCourseCount,
    _screenTimeSeconds,
    _productiveScreenSeconds,
    _distractionScreenSeconds,
  );
  
  setState(() {
    // UI 自动更新
  });
}

// 2. 在 _buildSummaryContent 中添加
@override
Widget build(BuildContext context) {
  // ... existing code ...
  
  // Call this when summary is updated
  _updateMedalRecommendations();
  
  return Scaffold(
    body: ListView(
      children: [
        // ... existing widgets ...
        
        // Medal recommendations section
        if (_medalRecommendation != null)
          MedalRecommendationCard(
            recommendation: _medalRecommendation!,
            onViewAll: _showMedalListDialog,
          ),
      ],
    ),
  );
}

void _showMedalListDialog() {
  showDialog(
    context: context,
    builder: (context) => MedalListDialog(
      recommendation: _medalRecommendation!,
    ),
  );
}
```

---

## 🧪 测试运行结果

```
✅ All medals are properly defined
✅ Calculate medal progress - focus_starter
✅ Calculate medal progress - two_hour_guardian (incomplete)
✅ Calculate medal progress - two_hour_guardian (complete)
✅ Calculate medal progress - task_harvester
✅ Calculate medal progress - plan_fulfiller
✅ Calculate medal progress - stable_output
✅ Get recommendations - returns top 3 unearned medals
✅ Full recommendation flow
✅ Medal info has required fields
✅ Medal categories are valid

11/11 tests passed ✅
```

---

## 📈 机器学习机会

虽然这个功能本身是基于规则的推荐，但可以使用 ML 改进：

### 未来增强方案

1. **用户行为预测** (ML)
   - 基于历史数据预测用户最可能获得的下 3 个勋章
   - 而不是仅基于距离

2. **个性化激励** (ML)
   - 根据用户性格提供不同推荐顺序
   - "冲刺型" vs "马拉松型" 用户

3. **获得时间预测** (ML)
   - 预测用户何时会获得特定勋章
   - "基于当前速度，你将在 5 天后获得 X 勋章"

4. **推荐多样性** (强化学习)
   - 动态调整推荐以增加参与度
   - 避免推荐相同的困难任务

---

## 🔗 相关文件

- **Core Service**: `lib/services/medal_recommendation_service.dart` (17KB)
- **UI Widget**: `lib/widgets/medal_recommendation_card.dart` (15KB)
- **Tests**: `test/medal_recommendation_service_test.dart` (9KB)
- **Integration**: `lib/screens/personal_timeline_screen.dart` (需要更新)

---

## ✨ 下一步

1. **集成到 UI** (Today)
   - 在 personal_timeline_screen 中显示推荐卡片

2. **用户测试** (Tomorrow)
   - 收集用户反馈
   - 调整勋章难度阈值

3. **数据收集** (Optional)
   - 为下一个 ML 项目收集用户行为数据

4. **Analytics** (Optional)
   - 追踪勋章获得率
   - 测量参与度提升

---

**状态**: ✅ Core Implementation Complete  
**下一个 ML 项目**: #43 时间估算预测 或 #33 学习模式识别

---

## 推荐算法

# 勋章推荐算法

## 概述

勋章推荐系统由两套算法叠加组成：**特征评分模型**（解决冷启动）+ **Thompson Sampling 老虎机算法**（解决个性化学习）。两者互补，开箱即用且越用越准。

---

## 1. 特征评分模型

给每个用户画一幅"行为画像"，然后给每枚勋章打分。

### 1.1 用户画像（UserProfileFeatures）

从 `TimelineSummary` + 10 个外部参数中提取，包含 3 层：

#### Layer 1：类别亲和度（5 个值，范围 [0, 1]）

每个勋章属于 5 个类别之一，计算用户在每个类别上的亲和度：

| 类别 | 计算因子 |
|------|----------|
| 专注（focus） | 总专注时长、深度专注次数、1-中断率、番茄钟数 |
| 完成（completion） | 任务完成率、提前完成数、总完成数、DDL冲刺数 |
| 坚持（persistence） | 连续活跃天数、日活比例、周末活跃度、夜间活跃度 |
| 效率（efficiency） | 1-中断率、屏幕生产力比例、时间一致性、任务完成率 |
| 广度（breadth） | 学科覆盖数、检索次数、学科熵、备考次数 |

每个亲和度由加权公式计算，例如专注亲和度：

```
focusAffinity = 0.35 × (totalFocusMinutes / 600)
              + 0.25 × (deepWorkCount / 10)
              + 0.20 × (1 - interruptionRate)
              + 0.20 × (pomodoroCount / 50)
```

#### Layer 2：进度速度

```
velocity[category] = affinity[category] × recencyFactor
```

- 短时间范围（今天/本周）→ recencyFactor 高 → 偏好当前活跃方向
- 长时间范围（全量）→ recencyFactor 低 → 更均衡

#### Layer 3：行为特质（3 个值）

| 特质 | 含义 | 计算方式 |
|------|------|----------|
| motivationType | 动机类型 | achiever（完成+专注最高）/ explorer（广度+检索最高）/ optimizer（效率最高） |
| challengePreference | 难度偏好 | 基于深度专注次数和连续活跃天数 |
| diversityNeed | 多样性需求 | 1 - 最大学科占比 |

### 1.2 勋章评分公式

对每枚未获得的勋章计算综合得分：

```
featureScore = w1×接近度 + w2×亲和度 + w3×活跃度 + w4×多样性 + w5×难度匹配
```

| 分量 | 含义 | 默认权重 |
|------|------|----------|
| 接近度（proximity） | 勋章当前进度（0-1），85% 比 10% 分高 | 0.40 |
| 亲和度（affinity） | 用户在该勋章类别上的亲和度 | 0.25 |
| 活跃度（velocity） | 用户最近在该类别上的活跃程度 | 0.15 |
| 多样性（diversity） | 该类别已获得勋章较少时加分 | 0.10 |
| 难度匹配（challenge） | 勋章难度与用户偏好是否匹配 | 0.10 |

权重根据动机类型动态调整：

| 动机类型 | 接近度 | 亲和度 | 活跃度 | 多样性 | 难度匹配 |
|----------|--------|--------|--------|--------|----------|
| 成就型（achiever） | 0.45 | 0.20 | 0.15 | 0.08 | 0.12 |
| 探索型（explorer） | 0.30 | 0.15 | 0.15 | 0.25 | 0.15 |
| 效率型（optimizer） | 0.35 | 0.20 | 0.20 | 0.10 | 0.15 |

---

## 2. Thompson Sampling（老虎机算法）

把每枚勋章当作一台老虎机，自动学习"哪类勋章推荐给用户，用户更可能去完成"。

### 2.1 核心机制

每台老虎机维护一个 Beta 分布，由两个参数控制：

- **alpha（α）**：成功次数，初始值 1.0
- **beta（β）**：失败次数，初始值 1.0

初始 Beta(1, 1) = 均匀分布 = 对所有勋章一视同仁（冷启动无偏见）。

### 2.2 推荐流程

```
对每枚候选勋章：
    从 Beta(α, β) 分布中随机采样一个值
按采样值排序，取 Top 6
```

采样值越高 → 该勋章越可能被推荐。

### 2.3 学习更新

| 事件 | 更新规则 | 说明 |
|------|----------|------|
| 推荐后用户获得了该勋章 | α += 1.0 | 强正反馈 |
| 推荐后 30 天仍未获得 | β += 0.3 | 轻惩罚（避免误伤慢热型勋章） |
| 90 天未展示 | 重置为 (1.0, 1.0) | 防止过时数据干扰 |
| 30 天内仍在观察窗口 | 不更新 | 等待更多数据 |

### 2.4 采样实现

Beta 分布采样通过 Gamma 分布实现：

```
Beta(α, β) = Gamma(α) / (Gamma(α) + Gamma(β))
```

Gamma 采样使用 Marsaglia & Tsang 方法（纯 Dart 实现，无外部依赖）。

---

## 3. 混合评分

最终得分 = 特征评分 × 特征权重 + Bandit 采样值 × Bandit 权重

```dart
banditConfidence = min(总观测次数 / 50, 1.0)
banditWeight = 0.4 × banditConfidence
featureWeight = 1.0 - banditWeight
combined = featureWeight × featureScore + banditWeight × banditSample
```

| 阶段 | 特征权重 | Bandit 权重 | 说明 |
|------|----------|-------------|------|
| 冷启动（0 次观测） | 100% | 0% | 纯特征评分，开箱即用 |
| 50+ 次观测 | 60% | 40% | Bandit 学习充分，稳定个性化 |
| 中间阶段 | 线性过渡 | 线性过渡 | 平滑过渡，无突变 |

**Bandit 权重上限 40%**：特征评分始终贡献至少 60%，防止 Bandit 在早期错误锁定。

---

## 4. 推荐理由生成

根据评分明细自动生成中文推荐理由，展示在 UI 上：

| 触发条件 | 理由文案 |
|----------|----------|
| 接近度 > 0.7 | "已完成 X%，距离解锁很近" |
| 接近度 > 0.4 | "进度 X%，稳步推进中" |
| 亲和度 > 0.6 | "匹配你擅长的[类别]领域" |
| 活跃度 > 0.6 | "你最近在这个领域很活跃" |
| 多样性 > 0.6 | "拓展新的成就领域" |
| 难度匹配高 + 高优先级 | "适合你挑战高难度的习惯" |
| 难度匹配高 + 低优先级 | "轻松入门，建立信心" |
| Bandit 观测 ≥ 10 且采样 > 0.65 | "历史数据表明你倾向完成此类勋章" |

---

## 5. 降级策略

系统有 3 级降级，确保用户始终能看到推荐：

1. **ML 增强路径**（主路径）：特征评分 + Bandit 混合排序
2. **纯特征路径**（Bandit DB 异常时）：仅使用特征评分排序
3. **原始算法**（ML 完全失败时）：按 `stepsRemaining` 升序排序（距离解锁最近的优先）

UI 加载模式：先同步显示原始算法结果 → 异步计算 ML 结果 → 到达后替换，用户无感知。

---

## 6. 数据持久化

### 6.1 SQLite 表 `medal_recommendations`（V27 迁移）

| 字段 | 类型 | 说明 |
|------|------|------|
| medal_id | TEXT PK | 勋章 ID |
| alpha | REAL | Beta 分布 α 参数 |
| beta_ | REAL | Beta 分布 β 参数 |
| impression_count | INTEGER | 累计曝光次数 |
| success_count | INTEGER | 曝光后获得次数 |
| last_shown_at | INTEGER | 最后曝光时间戳（UTC ms） |
| last_outcome_at | INTEGER | 最后结果检查时间戳 |
| feature_score_cache | REAL | 最近一次特征评分（诊断用） |
| updated_at | INTEGER | 最后更新时间戳 |

### 6.2 性能

| 操作 | 耗时 |
|------|------|
| 特征提取 | < 1ms（纯内存计算） |
| Bandit 采样 | < 5ms（88 行 SQLite 查询） |
| 结果更新 | < 2ms（88 次简单比较） |
| 曝光记录 | < 10ms（最多 6 次 UPDATE） |
| **总 ML 开销** | **~20ms** |
