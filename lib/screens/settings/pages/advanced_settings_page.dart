import 'dart:io';
import 'package:flutter/material.dart';

import '../../../services/llm_service.dart';
import '../../../storage_service.dart';
import '../../../utils/page_transitions.dart';
import '../llm_config_page.dart';
import '../calendar_sync_page.dart';
import '../../feature_guide_screen.dart';
import '../handlers/storage_management_handler.dart';
import '../dialogs/migration_dialog.dart';
import '../../../update_service.dart';

class AdvancedSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const AdvancedSettingsPage({super.key, this.initialTarget, this.isEmbedded = false});

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  final Map<String, GlobalKey> _itemKeys = {
    'llm_config': GlobalKey(),
    'llm_retry': GlobalKey(),
    'migration': GlobalKey(),
    'cache': GlobalKey(),
    'storage': GlobalKey(),
    'calendar_sync': GlobalKey(),
    'update': GlobalKey(),
    'feature_guide': GlobalKey(),
  };

  String? _highlightTarget;
  bool _isCheckingUpdate = false;
  String _cacheSizeStr = "计算中...";
  int _llmRetryCount = 3;

  late StorageManagementHandler _storageManagementHandler;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _storageManagementHandler = StorageManagementHandler(
      context: context,
      getUsername: () => '', // Will be updated if needed
      onUpdateCacheSize: (val) {
        if (mounted) setState(() => _cacheSizeStr = val);
      },
      showLoading: (msg) => _showLoadingDialog(context, msg),
      closeLoading: () => _closeLoadingDialog(context),
      showMessage: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
    );
    _storageManagementHandler.calculateCacheSize();

    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget(widget.initialTarget!);
      });
    }
  }

  Future<void> _loadSettings() async {
    int llmRetryCount = await StorageService.getLLMRetryCount();
    if (mounted) {
      setState(() {
        _llmRetryCount = llmRetryCount;
      });
    }
  }

  void _scrollToTarget(String target) {
    final key = _itemKeys[target];
    if (key?.currentContext != null) {
      setState(() => _highlightTarget = target);
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) setState(() => _highlightTarget = null);
      });
    }
  }

  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _closeLoadingDialog(BuildContext context) {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _showMigrationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MigrationDialog(
        onSuccess: () {},
      ),
    );
  }

  Future<void> _checkUpdatesAndNotices() async {
    setState(() => _isCheckingUpdate = true);
    await UpdateService.checkUpdateAndPrompt(context, isManual: true);
    if (mounted) setState(() => _isCheckingUpdate = false);
  }

  Widget _buildTile({required String targetId, required Widget child}) {
    final bool isHighlighted = _highlightTarget == targetId;
    return Container(
      key: _itemKeys[targetId],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(
        title: const Text('系统与高级'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 16.0),
            child: Text('AI 配置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          _buildTile(
            targetId: 'llm_config',
            child: ListTile(
              leading: const Icon(Icons.psychology_outlined, color: Colors.deepPurple),
              title: const Text('大模型API配置'),
              subtitle: FutureBuilder<LLMConfig?>(
                future: LLMService.getConfig(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('加载中...', style: TextStyle(fontSize: 12));
                  }
                  final config = snapshot.data;
                  if (config == null || !config.isConfigured) {
                    return const Text('未配置，用于AI智能解析待办', style: TextStyle(fontSize: 12, color: Colors.orange));
                  }
                  return Text('已配置: ${config.model}', style: const TextStyle(fontSize: 12, color: Colors.green));
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final result = await Navigator.push<bool>(
                  context,
                  PageTransitions.slideHorizontal(
                    LLMConfigPage(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '大模型API配置'),
                  ),
                );
                if (result == true) {
                  setState(() {});
                }
              },
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'llm_retry',
            child: ListTile(
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
          ),

          const Padding(
            padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
            child: Text('系统与存储', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          _buildTile(
            targetId: 'cache',
            child: ListTile(
              leading: const Icon(Icons.cleaning_services_outlined, color: Colors.brown),
              title: const Text('深度清理缓存与冗余'),
              subtitle: const Text('包含更新残留包与深度图片缓存'),
              trailing: Text(_cacheSizeStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              onTap: _storageManagementHandler.clearCache,
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'storage',
            child: ListTile(
              leading: const Icon(Icons.data_usage, color: Colors.orange),
              title: const Text('存储空间深度分析'),
              subtitle: const Text('找出占用数百MB的隐藏文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _storageManagementHandler.showStorageAnalysis,
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'update',
            child: ListTile(
              leading: const Icon(Icons.system_update_outlined, color: Colors.green),
              title: const Text('检查新版本'),
              trailing: _isCheckingUpdate ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right),
              onTap: _isCheckingUpdate ? null : _checkUpdatesAndNotices,
            ),
          ),

          const Padding(
            padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
            child: Text('其他工具', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          if (Platform.isAndroid) ...[
            _buildTile(
              targetId: 'calendar_sync',
              child: ListTile(
                leading: const Icon(Icons.edit_calendar_outlined, color: Colors.deepPurple),
                title: const Text('系统日历双向同步 (实验性)'),
                subtitle: const Text('将本App数据写入系统日历，或读取系统日历'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context, 
                    PageTransitions.slideHorizontal(
                      CalendarSyncPage(isEmbedded: widget.isEmbedded),
                      settings: const RouteSettings(name: '系统日历同步'),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, indent: 72),
          ],
          _buildTile(
            targetId: 'feature_guide',
            child: ListTile(
              leading: const Icon(Icons.school_outlined, color: Colors.indigo),
              title: const Text('重新查看新版教程与权限设置'),
              subtitle: const Text('可再次查看功能介绍与重新配置各项权限'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, PageTransitions.slideHorizontal(const FeatureGuideScreen(isManualReview: true)));
              },
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'migration',
            child: ListTile(
              leading: const Icon(Icons.move_up, color: Colors.teal),
              title: const Text('旧版本地数据一键迁移'),
              subtitle: const Text('包含待办、课程、课表与习惯数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showMigrationDialog,
            ),
          ),
        ],
      ),
    );
  }
}
