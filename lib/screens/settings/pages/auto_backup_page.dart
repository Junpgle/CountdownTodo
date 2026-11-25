import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/auto_backup_models.dart';
import '../../../services/auto_backup_service.dart';
import '../../../services/browser_file_service.dart';
import '../../../services/minor_mode_policy.dart';
import '../../../services/minor_mode_service.dart';
import '../../../utils/app_dialogs.dart';
import '../../../utils/page_transitions.dart';
import '../../../utils/time_utils.dart';
import '../../../widgets/floating_glass_control.dart';
import 'data_import_page.dart';

/// 定期自动备份设置与本地快照恢复页面。
class AutoBackupPage extends StatefulWidget {
  final bool isEmbedded;

  const AutoBackupPage({super.key, this.isEmbedded = false});

  @override
  State<AutoBackupPage> createState() => _AutoBackupPageState();
}

class _AutoBackupPageState extends State<AutoBackupPage> {
  AutoBackupConfig _config = const AutoBackupConfig();
  String _resolvedDir = '';
  List<AutoBackupEntry> _entries = const [];
  bool _isLoading = true;
  bool _isBackingUp = false;

  static const List<int> _intervalOptions = [1, 3, 7];
  static const List<int> _keepCountOptions = [3, 7, 14, 30];

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    if (!AutoBackupService.isSupported) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final config = await AutoBackupService.getConfig();
    final dir = await AutoBackupService.resolveBackupDirectoryPath(
      config: config,
    );
    final entries = await AutoBackupService.listBackups();
    if (!mounted) return;
    setState(() {
      _config = config;
      _resolvedDir = dir;
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _updateConfig(AutoBackupConfig next) async {
    await AutoBackupService.saveConfig(next);
    final dir = await AutoBackupService.resolveBackupDirectoryPath(
      config: next,
    );
    final entries = await AutoBackupService.listBackups();
    if (!mounted) return;
    setState(() {
      _config = next;
      _resolvedDir = dir;
      _entries = entries;
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colorScheme.error : null,
      ),
    );
  }

  Future<void> _pickDirectory() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: '选择自动备份保存文件夹',
      initialDirectory: _resolvedDir.isEmpty ? null : _resolvedDir,
    );
    if (selected == null || selected.trim().isEmpty) return;
    await _updateConfig(_config.copyWith(customDirectory: selected.trim()));
    if (!mounted) return;
    _showSnackBar('已更新自动备份目录');
  }

  Future<void> _resetDirectory() async {
    await _updateConfig(_config.copyWith(clearCustomDirectory: true));
    if (!mounted) return;
    _showSnackBar('已恢复默认备份目录');
  }

  Future<void> _backupNow() async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    final result = await AutoBackupService.performBackupNow();
    await _loadState();
    if (!mounted) return;
    setState(() => _isBackingUp = false);

    if (result.success) {
      _showSnackBar('备份成功（共 ${result.totalItems} 项）');
    } else {
      _showSnackBar('备份失败：${result.errorMessage ?? '未知错误'}', isError: true);
    }
  }

  Future<void> _restoreEntry(AutoBackupEntry entry) async {
    await Navigator.of(context).push(
      PageTransitions.slideHorizontal(
        DataImportPage(
          initialFilePath: entry.filePath,
          initialFileName: entry.fileName,
        ),
      ),
    );
    if (mounted) {
      await _loadState();
    }
  }

  Future<void> _shareEntry(AutoBackupEntry entry) async {
    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.dataExport,
    );
    if (!authorized) {
      if (mounted) {
        _showSnackBar(
          MinorModeService.instance.authorizationFailureMessage(
            MinorModeAction.dataExport,
          ),
          isError: true,
        );
      }
      return;
    }

    final content = await AutoBackupService.readBackupContent(entry.filePath);
    if (content == null) {
      if (mounted) {
        _showSnackBar('无法读取备份文件', isError: true);
      }
      return;
    }
    await BrowserFileService.shareTextFile(
      content,
      entry.fileName,
      subject: 'CountDownTodo 自动备份快照',
      mimeType: 'application/json;charset=utf-8',
    );
  }

  Future<void> _deleteEntry(AutoBackupEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('删除备份快照'),
          content: Text('确定删除 ${entry.fileName} 吗？删除后无法恢复该本地快照。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: colorScheme.error),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final ok = await AutoBackupService.deleteBackup(entry.filePath);
    if (!mounted) return;
    if (ok) {
      await _loadState();
      if (mounted) _showSnackBar('已删除备份快照');
    } else {
      _showSnackBar('删除失败', isError: true);
    }
  }

  String _formatDateTime(int? timestampMs) {
    if (timestampMs == null) return '尚未备份';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return AppTimeFormats.fullDateTime(dt);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _intervalLabel(int days) {
    switch (days) {
      case 1:
        return '每天';
      case 3:
        return '每 3 天';
      case 7:
        return '每周';
      default:
        return '每 $days 天';
    }
  }

  Widget _buildSectionCard({
    required ColorScheme colorScheme,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    double borderRadius = 16,
  }) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWideScreen = screenWidth > 600;
    final standalone = !widget.isEmbedded && !isWideScreen;

    return Scaffold(
      extendBodyBehindAppBar: standalone,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('定期自动备份'),
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: standalone,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : !AutoBackupService.isSupported
            ? _buildWebUnsupportedView(colorScheme)
            : _buildContent(colorScheme, standalone: standalone),
      ),
    );
  }

  Widget _buildWebUnsupportedView(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildSectionCard(
          colorScheme: colorScheme,
          borderRadius: 20,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Web 端暂不支持静默本地自动备份',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '受浏览器文件访问安全限制，网页版无法自动写入本地文件夹。请使用「数据导出」手动下载 JSON 备份文件。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme, {required bool standalone}) {
    final topPadding = standalone
        ? floatingGlassSettingsContentTopInset(context)
        : 16.0;

    return RefreshIndicator(
      onRefresh: _loadState,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
        children: [
          _buildOverviewCard(colorScheme),
          if (_config.lastBackupError != null &&
              _config.lastBackupError!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(colorScheme, _config.lastBackupError!),
          ],
          const SizedBox(height: 16),
          _buildPolicyCard(colorScheme),
          const SizedBox(height: 16),
          _buildDirectoryCard(colorScheme),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isBackingUp ? null : _backupNow,
            icon: _isBackingUp
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup_rounded),
            label: Text(_isBackingUp ? '正在创建全量快照...' : '立即创建备份快照'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                '本地备份快照（${_entries.length}）',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_entries.isNotEmpty)
                Text(
                  '点击「恢复」可预览并选择恢复范围',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_entries.isEmpty)
            _buildEmptySnapshots(colorScheme)
          else
            ..._entries.map((entry) => _buildSnapshotCard(colorScheme, entry)),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(ColorScheme colorScheme) {
    return _buildSectionCard(
      colorScheme: colorScheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(
                  Icons.shield_outlined,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '开启定期自动备份',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '在应用启动或回到前台时静默检查，生成完整离线 JSON 快照',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _config.enabled,
                onChanged: (value) =>
                    _updateConfig(_config.copyWith(enabled: value)),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '上次备份：${_formatDateTime(_config.lastBackupAt)}',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ColorScheme colorScheme, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '上次自动备份失败：$error',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCard(ColorScheme colorScheme) {
    return _buildSectionCard(
      colorScheme: colorScheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '备份策略',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            '备份频率',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _intervalOptions.map((days) {
              final selected = _config.intervalDays == days;
              return ChoiceChip(
                label: Text(_intervalLabel(days)),
                selected: selected,
                onSelected: _config.enabled
                    ? (_) => _updateConfig(_config.copyWith(intervalDays: days))
                    : null,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            '最多保留快照数量（超出后自动清理最早的备份）',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _keepCountOptions.map((count) {
              final selected = _config.maxKeepCount == count;
              return ChoiceChip(
                label: Text('最近 $count 份'),
                selected: selected,
                onSelected: (_) =>
                    _updateConfig(_config.copyWith(maxKeepCount: count)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryCard(ColorScheme colorScheme) {
    final isCustom =
        _config.customDirectory != null &&
        _config.customDirectory!.trim().isNotEmpty;

    return _buildSectionCard(
      colorScheme: colorScheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '备份保存位置',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCustom ? '自定义目录' : '默认目录',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            _resolvedDir.isEmpty ? '正在获取路径...' : _resolvedDir,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            '提示：可将目录选在桌面、文档或网盘同步文件夹（如 iCloud Drive / OneDrive），避免卸载应用时随沙盒一起被清理。',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickDirectory,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('选择文件夹'),
              ),
              if (isCustom) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _resetDirectory,
                  child: const Text('恢复默认'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySnapshots(ColorScheme colorScheme) {
    return _buildSectionCard(
      colorScheme: colorScheme,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 36,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '当前目录下还没有自动备份快照',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '点击上方「立即创建备份快照」可马上生成一份完整备份',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotCard(ColorScheme colorScheme, AutoBackupEntry entry) {
    final timeStr = AppTimeFormats.format(
      entry.createdAt,
      'yyyy-MM-dd HH:mm:ss',
    );
    final sizeStr = _formatFileSize(entry.sizeBytes);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _buildSectionCard(
        colorScheme: colorScheme,
        borderRadius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.description_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.fileName} · $sizeStr',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _restoreEntry(entry),
              child: const Text('恢复'),
            ),
            IconButton(
              tooltip: '分享或另存备份',
              icon: const Icon(Icons.share_outlined, size: 20),
              onPressed: () => _shareEntry(entry),
            ),
            IconButton(
              tooltip: '删除快照',
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: colorScheme.error,
              ),
              onPressed: () => _deleteEntry(entry),
            ),
          ],
        ),
      ),
    );
  }
}
