import 'package:flutter/material.dart';
import '../../../storage_service.dart';
import '../../../utils/page_transitions.dart';
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
    await StorageService.saveAppSetting(StorageService.KEY_CONFLICT_DETECTION_ENABLED, enabled);
    if (!enabled && widget.username.isNotEmpty && widget.username != '加载中...') {
      await StorageService.clearLocalTodoScheduleConflicts(widget.username);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 24.0),
          child: Text('同步与数据策略', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.sync, color: Colors.blue),
                title: const Text('自动同步频率'),
                trailing: DropdownButton<int>(
                  value: _syncInterval,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('每 5 分钟')),
                    DropdownMenuItem(value: 10, child: Text('每 10 分钟')),
                    DropdownMenuItem(value: 60, child: Text('每小时')),
                    DropdownMenuItem(value: 0, child: Text('每次启动')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _syncInterval = val);
                      StorageService.saveAppSetting(StorageService.KEY_SYNC_INTERVAL, val);
                    }
                  },
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
                title: const Text('冲突检测'),
                subtitle: const Text('检测待办时间重叠；关闭后首页不弹冲突提醒'),
                trailing: Switch(
                  value: _conflictDetectionEnabled,
                  activeThumbColor: Colors.orange,
                  onChanged: _setConflictDetectionEnabled,
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.cloud_queue, color: Colors.indigo),
                title: const Text('云端数据接口线路'),
                subtitle: Text(
                  _serverChoice == 'cloudflare' ? '当前: Cloudflare' : '当前: 阿里云ECS (更快)',
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
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.refresh_outlined, color: Colors.deepPurple),
                title: const Text('图片识别重试次数'),
                subtitle: const Text('识别超时后自动重试的次数（后台异步执行）'),
                trailing: DropdownButton<int>(
                  value: _llmRetryCount,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('不重试')),
                    DropdownMenuItem(value: 1, child: Text('1 次')),
                    DropdownMenuItem(value: 2, child: Text('2 次')),
                    DropdownMenuItem(value: 3, child: Text('3 次')),
                    DropdownMenuItem(value: 5, child: Text('5 次')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _llmRetryCount = val);
                      StorageService.setLLMRetryCount(val);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
