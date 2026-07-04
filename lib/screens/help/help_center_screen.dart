import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/help_article.dart';
import '../../services/feature_tip_service.dart';
import '../../update_service.dart';
import '../../utils/app_platform.dart';
import '../../utils/page_transitions.dart';
import '../feature_guide_screen.dart';
import '../pomodoro_screen.dart';
import '../add_todo_screen.dart';
import '../course_screens.dart';
import 'help_article_screen.dart';

class HelpCenterScreen extends StatefulWidget {
  final String? username;
  final bool isEmbedded;

  const HelpCenterScreen({super.key, this.username, this.isEmbedded = false});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('帮助与反馈'),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            scheme,
            Icons.rocket_launch_rounded,
            '快速上手',
            scheme.primary,
            [
              _HelpEntry(
                '重新显示功能提示',
                '重置所有情境提示，让其重新出现',
                Icons.tips_and_updates_rounded,
                Colors.amber,
                () => _resetTips(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            scheme,
            Icons.article_rounded,
            '功能介绍',
            Colors.teal,
            _buildArticleEntries(),
          ),
          const SizedBox(height: 16),
          _buildSection(
            scheme,
            Icons.settings_rounded,
            '更多',
            Colors.grey,
            [
              _HelpEntry(
                '查看更新日志',
                '查看历史版本更新内容',
                Icons.system_update_rounded,
                Colors.blueGrey,
                _showChangelog,
              ),
              _HelpEntry(
                '检查新版本',
                '手动检查应用更新',
                Icons.update_rounded,
                Colors.grey,
                () async {
                  final manifest =
                      await UpdateService.checkManifest(preferCache: false);
                  if (!mounted) return;
                  if (manifest != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('当前版本: ${manifest.versionName}')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('当前已是最新版本')),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_HelpEntry> _buildArticleEntries() {
    return [
      _HelpEntry(
        '待办与倒数日',
        '创建、管理和跟踪你的待办事项和重要日期',
        Icons.task_alt_rounded,
        Colors.indigo,
        () => _openArticle(HelpArticle(
          id: 'todos',
          title: '待办与倒数日',
          summary: '创建待办事项和倒数日，设置提醒和循环，轻松掌握进度。',
          icon: Icons.task_alt_rounded,
          iconColor: Colors.indigo,
          steps: [
            '点击首页右下角的 "+" 按钮选择"待办"。',
            '输入标题，可选择设置截止日期和提醒时间。',
            '保存后待办会出现在首页列表中。',
            '勾选待办左侧的圆圈即可标记完成。',
            '创建倒数日时输入标题和目标日期，首页会显示剩余天数。',
          ],
          actionLabel: '前往添加待办',
          onAction: () {
            Navigator.of(context, rootNavigator: true).push(
              PageTransitions.slideHorizontal(AddTodoScreen(
                onTodoAdded: (_) {},
              )),
            );
          },
        )),
      ),
      _HelpEntry(
        '课程表',
        '导入课程表，首页自动展示今日课程',
        Icons.calendar_month_rounded,
        Colors.teal,
        () => _openArticle(HelpArticle(
          id: 'courses',
          title: '课程表',
          summary: '导入或添加课程后，首页会自动展示今天和下一节课。',
          icon: Icons.calendar_month_rounded,
          iconColor: Colors.teal,
          steps: [
            '前往 设置 > 课表与学期 导入课程。',
            '支持教务系统导入或手动添加课程。',
            '设置学期起止日期可开启学期进度条。',
            '首页会自动展示今日课程和即将开始的课程。',
            '点击课程卡片可查看课程详情和上课时间。',
          ],
          actionLabel: '前往课程设置',
          onAction: () {
            Navigator.of(context, rootNavigator: true).push(
              PageTransitions.slideHorizontal(
                WeeklyCourseScreen(username: widget.username ?? ''),
              ),
            );
          },
        )),
      ),
      _HelpEntry(
        '专注计时',
        '使用番茄钟方法保持专注，提升效率',
        Icons.timer_rounded,
        Colors.deepOrange,
        () => _openArticle(HelpArticle(
          id: 'pomodoro',
          title: '专注计时',
          summary: '使用番茄工作法保持专注，可选绑定待办任务。',
          icon: Icons.timer_rounded,
          iconColor: Colors.deepOrange,
          steps: [
            '在首页点击"开始专注"按钮或底部导航栏的专注图标。',
            '选择专注时长（默认25分钟），可绑定一个待办任务。',
            '专注期间请保持应用在前台，或允许后台通知。',
            '专注结束后可查看本次统计，也可以继续下一轮。',
            '所有专注记录都会保存在时间轴中供回顾。',
          ],
          actionLabel: '前往专注页面',
          onAction: () {
            Navigator.of(context, rootNavigator: true).push(
              PageTransitions.slideHorizontal(
                  PomodoroScreen(username: widget.username ?? '')),
            );
          },
        )),
      ),
      _HelpEntry(
        '时间规划',
        '将待办安排到时间轴，规划你的一天',
        Icons.timeline_rounded,
        Colors.purple,
        () => _openArticle(HelpArticle(
          id: 'plan',
          title: '时间规划',
          summary: '将待办安排到时间轴，可以把"要做什么"变成"什么时候做"。',
          icon: Icons.timeline_rounded,
          iconColor: Colors.purple,
          steps: [
            '在待办详情页中选择"安排到时间轴"。',
            '拖动选择时间段，将任务分配到具体的时间块。',
            '可以在时间轴视图总览一天的计划。',
            '完成规划块后会自动关联到专注计时。',
            '支持按日、周视图查看你的时间安排。',
          ],
          actionLabel: '前往时间规划',
        )),
      ),
      _HelpEntry(
        '团队协作',
        '与团队成员共享任务，协同工作',
        Icons.groups_rounded,
        Colors.indigo,
        () => _openArticle(HelpArticle(
          id: 'team',
          title: '团队协作',
          summary: '团队成员可以共享协作内容，但个人内容不会自动共享。',
          icon: Icons.groups_rounded,
          iconColor: Colors.indigo,
          steps: [
            '在首页侧边栏选择"团队管理"。',
            '创建或加入一个团队。',
            '在团队中创建共享待办，所有成员可见。',
            '团队待办支持"各自独立完成"和"共同协作"两种模式。',
            '个人待办和团队待办在首页分开显示。',
          ],
          actionLabel: '前往团队管理',
        )),
      ),
      _HelpEntry(
        '跨设备同步',
        '在手机和电脑之间同步你的所有数据',
        Icons.sync_rounded,
        Colors.blue,
        () => _openArticle(HelpArticle(
          id: 'sync',
          title: '跨设备同步',
          summary: '登录同一账户即可在多个设备间自动同步数据。',
          icon: Icons.sync_rounded,
          iconColor: Colors.blue,
          steps: [
            '在每台设备上使用同一账户登录。',
            '待办、专注记录、课程等数据会自动同步。',
            '专注状态支持 WebSocket 实时同步。',
            '你可以在设置中查看同步状态和手动触发同步。',
            '局域网同步功能可用于不经过云端直连同步。',
          ],
          actionLabel: '前往同步设置',
        )),
      ),
      _HelpEntry(
        '小组件与桌面功能',
        '桌面小组件和系统集成功能',
        Icons.widgets_rounded,
        Colors.indigo,
        () => _openArticle(_buildPlatformArticle()),
      ),
      _HelpEntry(
        '权限设置',
        '管理应用需要的各种系统权限',
        Icons.security_rounded,
        Colors.red,
        () => _openArticle(HelpArticle(
          id: 'permissions',
          title: '权限设置',
          summary: '了解为什么需要各项权限，以及如何管理它们。',
          icon: Icons.security_rounded,
          iconColor: Colors.red,
          steps: [
            '通知权限：用于发送待办提醒和专注结束通知。',
            '精确闹钟权限：确保按时推送提醒（Android）。',
            if (!kIsWeb && AppPlatform.isAndroid) ...[
              '使用情况权限：用于屏幕时间统计（Android）。',
              '电池优化：防止专注时被系统杀后台（Android）。',
            ],
            if (!kIsWeb && AppPlatform.isMacOS) ...[
              '通知权限：macOS 系统通知。',
            ],
            '你可以在 设置 > 权限管理 中查看和管理所有权限。',
          ],
          actionLabel: '前往权限设置',
        )),
      ),
      _HelpEntry(
        '常见问题',
        '常见使用问题和解决方案',
        Icons.help_outline_rounded,
        Colors.grey,
        () => _openArticle(HelpArticle(
          id: 'faq',
          title: '常见问题',
          summary: '遇到问题？先看看这里。',
          icon: Icons.help_outline_rounded,
          iconColor: Colors.grey,
          steps: [
            '数据会丢失吗？所有数据都存储在本地 SQLite 和云端服务器，登录账户即可恢复。',
            '如何删除账户？在设置中点击"注销登录"可清除本地数据。',
            '忘记录制专注怎么办？可在专注页面查看历史记录，手动补录暂不支持。',
            '课程导入失败怎么办？确认教务系统课表格式正确，尝试手动添加。',
            '同步不成功？检查网络连接，在设置中手动触发同步。',
          ],
          actionLabel: '知道了',
        )),
      ),
    ];
  }

  HelpArticle _buildPlatformArticle() {
    if (kIsWeb) {
      return HelpArticle(
        id: 'widgets_web',
        title: '桌面小组件',
        summary: '浏览器通知和跨设备同步功能。',
        icon: Icons.widgets_rounded,
        iconColor: Colors.indigo,
        steps: [
          'Web 版支持浏览器通知（需要用户授权）。',
          '登录后数据可与移动端和桌面端同步。',
        ],
        actionLabel: '知道了',
      );
    }

    if (AppPlatform.isMacOS) {
      return HelpArticle(
        id: 'widgets_macos',
        title: 'macOS 桌面功能',
        summary: '专注期间可在 macOS 右上角菜单栏查看剩余分钟。',
        icon: Icons.widgets_rounded,
        iconColor: Colors.indigo,
        steps: [
          '专注开始后，macOS 菜单栏会显示剩余时间。',
          '支持桌面小组件，在主屏幕查看待办和专注状态。',
          '关闭窗口后应用会在后台继续运行，专注不会中断。',
          '通知将于系统通知中心统一管理。',
        ],
        actionLabel: '知道了',
      );
    }

    if (AppPlatform.isWindows) {
      return HelpArticle(
        id: 'widgets_windows',
        title: 'Windows 桌面功能',
        summary: '系统托盘、浮动窗口和屏幕时间集成。',
        icon: Icons.widgets_rounded,
        iconColor: Colors.indigo,
        steps: [
          '应用支持最小化到系统托盘，后台持续运行。',
          '浮动窗口（岛窗口）可显示专注状态。',
          '支持 Tai 屏幕时间数据汇总。',
          '通知将于 Windows 通知中心统一管理。',
        ],
        actionLabel: '知道了',
      );
    }

    if (AppPlatform.isAndroid) {
      return HelpArticle(
        id: 'widgets_android',
        title: 'Android 桌面小组件',
        summary: '在主屏直接查看课程、待办和专注状态。',
        icon: Icons.widgets_rounded,
        iconColor: Colors.indigo,
        steps: [
          '长按桌面空白处，选择"小部件"。',
          '找到 CountDownTodo，选择需要的小部件样式。',
          '拖拽到桌面合适位置即可。',
          '部分 ROM 需在桌面设置中开启小部件功能。',
        ],
        actionLabel: '知道了',
      );
    }

    return HelpArticle(
      id: 'widgets_other',
      title: '桌面小组件',
      summary: '小组件和桌面集成功能。',
      icon: Icons.widgets_rounded,
      iconColor: Colors.indigo,
      steps: [
        '查看平台专属设置了解可用功能。',
        '登录后数据可与其它设备同步。',
      ],
      actionLabel: '知道了',
    );
  }

  void _openArticle(HelpArticle article) {
    Navigator.push(
      context,
      PageTransitions.slideHorizontal(
        HelpArticleScreen(article: article, isEmbedded: widget.isEmbedded),
      ),
    );
  }

  Future<void> _resetTips(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置功能提示'),
        content: const Text('所有功能提示将重新出现，确定要重置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FeatureTipService.resetAllTips();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('功能提示已重置')),
        );
      }
    }
  }

  void _showChangelog() {
    Navigator.push(
      context,
      PageTransitions.slideHorizontal(
        FeatureGuideScreen(
          isManualReview: true,
          loggedInUser: widget.username,
          isEmbedded: widget.isEmbedded,
        ),
      ),
    );
  }

  Widget _buildSection(
    ColorScheme scheme,
    IconData icon,
    String title,
    Color color,
    List<_HelpEntry> entries,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Column(
            children:
                entries.map((entry) => _buildEntryTile(entry, scheme)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEntryTile(_HelpEntry entry, ColorScheme scheme) {
    return Column(
      children: [
        if (entry != _buildArticleEntries().first)
          Divider(height: 1, indent: 72, color: scheme.outlineVariant),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(entry.icon, color: entry.color, size: 20),
          ),
          title: Text(
            entry.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface,
            ),
          ),
          subtitle: entry.subtitle != null
              ? Text(
                  entry.subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                )
              : null,
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: entry.onTap,
        ),
      ],
    );
  }
}

class _HelpEntry {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HelpEntry(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.onTap,
  );
}
