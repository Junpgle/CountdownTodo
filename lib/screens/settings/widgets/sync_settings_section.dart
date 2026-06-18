import 'package:flutter/material.dart';
import '../../../storage_service.dart';
import '../../../utils/page_transitions.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_state_views.dart';
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
        StorageService.KEY_CONFLICT_DETECTION_ENABLED, enabled);
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
        ListTile(
          leading:
              Icon(Icons.warning_amber_outlined, color: colorScheme.cdtWarning),
          title: const Text('冲突检测'),
          subtitle: const Text('检测待办时间重叠；关闭后首页不弹冲突提醒'),
          trailing: Switch(
            value: _conflictDetectionEnabled,
            activeThumbColor: colorScheme.cdtWarning,
            onChanged: _setConflictDetectionEnabled,
          ),
        ),
        const AppSettingsDivider(),
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
              StorageService.KEY_SYNC_INTERVAL, selected);
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
}
