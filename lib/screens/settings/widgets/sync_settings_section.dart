import 'package:flutter/material.dart';
import '../../../storage_service.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/page_transitions.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_state_views.dart';
import '../../../widgets/floating_glass_control.dart';
import '../server_choice_page.dart';

class SyncSettingsSection extends StatefulWidget {
  final String username;
  const SyncSettingsSection({super.key, required this.username});

  @override
  State<SyncSettingsSection> createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection> {
  bool _isLoading = true;
  int _syncInterval = 0;
  bool _conflictDetectionEnabled = false;
  String _serverChoice = 'aliyun';
  int _llmRetryCount = 3;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    int interval = await StorageService.getSyncInterval();
    bool conflict = await StorageService.getConflictDetectionEnabled();
    String server = await StorageService.getServerChoice();
    int llmRetryCount = await StorageService.getLLMRetryCount();

    if (mounted) {
      setState(() {
        _syncInterval = interval;
        _conflictDetectionEnabled = conflict;
        _serverChoice = server;
        _llmRetryCount = llmRetryCount;
        _isLoading = false;
      });
    }
  }

  Future<void> _setConflictDetectionEnabled(bool enabled) async {
    setState(() => _conflictDetectionEnabled = enabled);
    await StorageService.saveAppSetting(
        StorageService.keyConflictDetectionEnabled, enabled);
    if (!enabled && widget.username.isNotEmpty && widget.username != '加载中...') {
      await StorageService.clearLocalTodoScheduleConflicts(widget.username);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const AppLoadingView();
    }

    return AppSettingsSection(
      title: '同步与数据策略',
      headerPadding: const EdgeInsets.only(left: 8, bottom: 8, top: 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sync, color: colorScheme.primary, size: 22),
                  const SizedBox(width: 12),
                  const Text('自动同步频率',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildFrequencyCard(5, '5 分钟', Icons.timer_outlined),
                  const SizedBox(width: 8),
                  _buildFrequencyCard(10, '10 分钟', Icons.timer),
                  const SizedBox(width: 8),
                  _buildFrequencyCard(60, '1 小时', Icons.hourglass_bottom),
                  const SizedBox(width: 8),
                  _buildFrequencyCard(0, '仅启动时', Icons.power_settings_new),
                ],
              ),
            ],
          ),
        ),
        const AppSettingsDivider(),
        _buildToggleCard(
          title: '冲突检测',
          subtitle: '检测待办时间重叠；关闭后首页不弹冲突提醒',
          icon: Icons.warning_amber_outlined,
          value: _conflictDetectionEnabled,
          onChanged: (val) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _setConflictDetectionEnabled(val ?? false);
            });
          },
        ),
        const AppSettingsDivider(),
        if (AppPlatform.isWeb)
          ListTile(
            leading: Icon(Icons.cloud_queue, color: colorScheme.secondary),
            title: const Text('云端数据接口线路'),
            subtitle: const Text(
              '网页版固定通过 Cloudflare Zero Trust 代理访问 API',
              style: TextStyle(fontSize: 12),
            ),
          )
        else
          ListTile(
            leading: Icon(Icons.cloud_queue, color: colorScheme.secondary),
            title: const Text('云端数据接口线路'),
            subtitle: Text(
              _serverChoice == 'cloudflare'
                  ? '当前: Cloudflare'
                  : '当前: 阿里云ECS (更快)',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                PageTransitions.slideHorizontal(
                  ServerChoicePage(
                    initialServerChoice: _serverChoice,
                    isEmbedded: false,
                  ),
                  settings: const RouteSettings(name: '云端数据接口线路'),
                ),
              ).then((_) {
                _loadSettings();
              });
            },
          ),
        const AppSettingsDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.refresh_outlined,
                      color: colorScheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('图片识别重试次数',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        Text('识别超时后自动重试的次数（后台异步执行）',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildRetryCard(0, '不重试'),
                  const SizedBox(width: 8),
                  _buildRetryCard(1, '1 次'),
                  const SizedBox(width: 8),
                  _buildRetryCard(2, '2 次'),
                  const SizedBox(width: 8),
                  _buildRetryCard(3, '3 次'),
                  const SizedBox(width: 8),
                  _buildRetryCard(5, '5 次'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFrequencyCard(int value, String title, IconData icon) {
    return Expanded(
      child: AppSettingsChoiceCard<int>(
        value: value,
        groupValue: _syncInterval,
        title: title,
        icon: icon,
        onSelected: (selected) {
          setState(() => _syncInterval = selected);
          StorageService.saveAppSetting(
              StorageService.keySyncInterval, selected);
        },
      ),
    );
  }

  Widget _buildRetryCard(int value, String title) {
    return Expanded(
      child: AppSettingsChoiceCard<int>(
        value: value,
        groupValue: _llmRetryCount,
        title: title,
        padding: const EdgeInsets.symmetric(vertical: 8),
        onSelected: (selected) {
          setState(() => _llmRetryCount = selected);
          StorageService.setLLMRetryCount(selected);
        },
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = value;
    final iconWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInBack,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return ScaleTransition(
          scale: animation,
          child: RotationTransition(
            turns: Tween<double>(begin: -0.1, end: 0.0).animate(animation),
            child: child,
          ),
        );
      },
      child: Icon(
        icon,
        key: ValueKey<bool>(isSelected),
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
    final switchWidget = SizedBox(
      height: 24,
      child: FittedBox(
        fit: BoxFit.fill,
        child: LiquidGlassSwitch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: colorScheme.primary,
        ),
      ),
    );
    final titleWidget = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: isSelected
            ? colorScheme.primary
            : theme.textTheme.bodyMedium?.color,
        fontFamily: theme.textTheme.bodyMedium?.fontFamily,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: Text(title),
    );
    final subtitleWidget = Text(
      subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
    );

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.1)
              : (theme.brightness == Brightness.dark
                  ? Colors.grey.shade900
                  : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [iconWidget, switchWidget],
            ),
            const SizedBox(height: 8),
            titleWidget,
            const SizedBox(height: 2),
            subtitleWidget,
          ],
        ),
      ),
    );
  }
}
