// macOS 原生菜单栏适配
// 仅在 macOS 平台启用 PlatformMenuBar，为应用提供系统级「文件 / 查看 / 窗口 / 帮助」菜单。
// Windows、Linux、Android、iOS、Web 不受影响。
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../services/api_service.dart';
import '../services/pomodoro_sync_service.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../screens/about_screen.dart';
import '../screens/add_todo_screen.dart';
import '../screens/feature_guide_screen.dart';
import '../utils/navigator_utils.dart';
import '../utils/page_transitions.dart';

/// macOS 原生菜单栏包裹组件。
/// 在 macOS 上为 MaterialApp 添加 PlatformMenuBar；其它平台原样返回 child。
class MacosMenuBar extends StatelessWidget {
  final Widget child;

  const MacosMenuBar({super.key, required this.child});

  static bool get _isMacOS {
    if (kIsWeb) return false;
    return Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMacOS) return child;

    return PlatformMenuBar(
      menus: [
        // ─── 应用菜单（系统自动提供「退出」等标准项） ───
        const PlatformMenu(
          label: 'CountDownTodo',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '关于 CountDownTodo',
                  onSelected: _onAbout,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '隐藏 CountDownTodo',
                  shortcut:
                      SingleActivator(LogicalKeyboardKey.keyH, meta: true),
                  onSelected: _onHideWindow,
                ),
              ],
            ),
          ],
        ),

        // ─── 文件 ───
        const PlatformMenu(
          label: '文件',
          menus: [
            PlatformMenuItem(
              label: '新建待办',
              shortcut: SingleActivator(LogicalKeyboardKey.keyN, meta: true),
              onSelected: _onNewTodo,
            ),
            PlatformMenuItem(
              label: '新建倒计时',
              shortcut: SingleActivator(LogicalKeyboardKey.keyN,
                  meta: true, shift: true),
              onSelected: _onNewCountdown,
            ),
          ],
        ),

        // ─── 查看 ───
        PlatformMenu(
          label: '查看',
          menus: [
            PlatformMenuItem(
              label: '同步一次',
              onSelected: _onSyncOnce,
            ),
            PlatformMenuItem(
              label: '刷新',
              shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyR, meta: true),
              onSelected: _onRefresh,
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '切换到浅色模式',
                  onSelected: _onLightMode,
                ),
                PlatformMenuItem(
                  label: '切换到深色模式',
                  onSelected: _onDarkMode,
                ),
                PlatformMenuItem(
                  label: '跟随系统主题',
                  onSelected: _onSystemTheme,
                ),
              ],
            ),
          ],
        ),

        // ─── 窗口 ───
        const PlatformMenu(
          label: '窗口',
          menus: [
            PlatformMenuItem(
              label: '显示主窗口',
              onSelected: _onShowWindow,
            ),
            PlatformMenuItem(
              label: '隐藏窗口',
              shortcut: SingleActivator(LogicalKeyboardKey.keyW, meta: true),
              onSelected: _onHideWindow,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '最小化',
                  shortcut:
                      SingleActivator(LogicalKeyboardKey.keyM, meta: true),
                  onSelected: _onMinimize,
                ),
                PlatformMenuItem(
                  label: '居中窗口',
                  onSelected: _onCenterWindow,
                ),
                PlatformMenuItem(
                  label: '进入/退出全屏',
                  shortcut: SingleActivator(
                      LogicalKeyboardKey.keyF, meta: true, control: true),
                  onSelected: _onToggleFullScreen,
                ),
              ],
            ),
          ],
        ),

        // ─── 帮助 ───
        const PlatformMenu(
          label: '帮助',
          menus: [
            PlatformMenuItem(
              label: '使用指南',
              onSelected: _onUsageGuide,
            ),
            PlatformMenuItem(
              label: '检查更新',
              onSelected: _onCheckUpdate,
            ),
            PlatformMenuItem(
              label: '打开 GitHub 项目页',
              onSelected: _onOpenGitHub,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '关于 CountDownTodo',
                  onSelected: _onAbout,
                ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }

  // ──────────────────── 文件菜单 ────────────────────

  /// 新建待办：直接打开 AddTodoScreen，使用自包含的回调保存数据。
  static void _onNewTodo() async {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    final username = await StorageService.getCurrentUsername();
    if (username == null || username.isEmpty) {
      _showSnackBar('请先登录');
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTodoScreen(
          onTodoAdded: (todo) async {
            final allTodos = await StorageService.getTodos(username);
            allTodos.add(todo);
            await StorageService.saveTodos(username, allTodos);
            if (todo.teamUuid != null) {
              PomodoroSyncService.instance
                  .sendTeamUpdateSignal(todo.teamUuid);
            }
          },
          onTodosBatchAdded: (todos) async {
            final allTodos = await StorageService.getTodos(username);
            allTodos.addAll(todos);
            await StorageService.saveTodos(username, allTodos);
          },
        ),
      ),
    );
  }

  /// 新建倒计时：弹出独立对话框，创建 CountdownItem 并保存。
  static void _onNewCountdown() async {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    final username = await StorageService.getCurrentUsername();
    if (username == null || username.isEmpty) {
      _showSnackBar('请先登录');
      return;
    }

    // 获取团队列表
    List<Team> teams = [];
    try {
      final teamData = await ApiService.fetchTeams();
      teams = teamData.map((t) => Team.fromJson(t)).toList();
    } catch (_) {
      // 获取团队失败时仍可创建个人倒计时
    }

    if (!context.mounted) return;

    final titleCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    String? selectedTeamUuid;
    String? selectedTeamName;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加重要日'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '事项名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  title: Text(
                    '目标日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                      initialDate: selectedDate,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: selectedTeamUuid,
                  decoration: InputDecoration(
                    labelText: '关联团队 (可选)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.groups_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('仅自己可见')),
                    ...teams.map((t) => DropdownMenuItem(
                          value: t.uuid,
                          child: Text(t.name),
                        )),
                  ],
                  onChanged: (val) {
                    setDialogState(() {
                      selectedTeamUuid = val;
                      selectedTeamName = val != null
                          ? teams
                              .where((t) => t.uuid == val)
                              .firstOrNull
                              ?.name
                          : null;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                final countdown = CountdownItem(
                  title: titleCtrl.text.trim(),
                  targetDate: selectedDate,
                  teamUuid: selectedTeamUuid,
                  teamName: selectedTeamName,
                );
                _saveCountdown(username, countdown, selectedTeamUuid);
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 保存倒计时到 StorageService 并触发刷新/同步
  static void _saveCountdown(
      String username, CountdownItem countdown, String? teamUuid) async {
    final allCountdowns = await StorageService.getCountdowns(username);
    allCountdowns.add(countdown);
    await StorageService.saveCountdowns(username, allCountdowns);
    if (teamUuid != null) {
      PomodoroSyncService.instance.sendTeamUpdateSignal(teamUuid);
    }
    _showSnackBar('倒计时已创建');
  }

  static void _onImportData() {
    // TODO: macOS 菜单 - 导入数据。项目暂无通用数据导入功能（仅有课程导入）。
    _showSnackBar('导入数据功能即将推出');
    debugPrint('[MacosMenuBar] 导入数据 - TODO: 通用数据导入功能尚未实现');
  }

  static void _onExportData() {
    // TODO: macOS 菜单 - 导出数据。项目暂无通用数据导出功能（仅有时间轴图片导出）。
    _showSnackBar('导出数据功能即将推出');
    debugPrint('[MacosMenuBar] 导出数据 - TODO: 通用数据导出功能尚未实现');
  }

  // ──────────────────── 查看菜单 ────────────────────

  static void _onSyncOnce() async {
    final username = await StorageService.getCurrentUsername();
    if (username != null && username.isNotEmpty) {
      StorageService.requestSync(username);
      _showSnackBar('正在同步...');
    } else {
      _showSnackBar('未登录，无法同步');
    }
  }

  static void _onRefresh() {
    StorageService.triggerRefresh();
    _showSnackBar('已刷新');
  }

  static void _onLightMode() {
    StorageService.saveAppSetting(StorageService.KEY_THEME_MODE, 'light');
  }

  static void _onDarkMode() {
    StorageService.saveAppSetting(StorageService.KEY_THEME_MODE, 'dark');
  }

  static void _onSystemTheme() {
    StorageService.saveAppSetting(StorageService.KEY_THEME_MODE, 'system');
  }

  // ──────────────────── 窗口菜单 ────────────────────

  static void _onShowWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  static void _onHideWindow() async {
    await windowManager.hide();
  }

  static void _onMinimize() async {
    await windowManager.minimize();
  }

  static void _onCenterWindow() async {
    await windowManager.center();
  }

  static void _onToggleFullScreen() async {
    final isFullScreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullScreen);
  }

  // ──────────────────── 帮助菜单 ────────────────────

  static void _onUsageGuide() {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    Navigator.of(context).push(
      PageTransitions.slideHorizontal(
        const FeatureGuideScreen(isManualReview: true),
      ),
    );
  }

  static void _onCheckUpdate() async {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    await UpdateService.checkUpdateAndPrompt(context);
  }

  static void _onOpenGitHub() async {
    final uri = Uri.parse('https://github.com/Junpgle/CountdownTodo');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static void _onAbout() {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    Navigator.of(context).push(
      PageTransitions.slideHorizontal(const AboutScreen()),
    );
  }

  // ──────────────────── 工具方法 ────────────────────

  /// 通过全局 Navigator 显示 SnackBar
  static void _showSnackBar(String message) {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
