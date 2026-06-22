import 'package:flutter/material.dart';

import '../../../models/data_export_models.dart';
import '../../../services/data_export_service.dart';
import '../../../storage_service.dart';

class DataExportPage extends StatefulWidget {
  final bool isEmbedded;

  const DataExportPage({super.key, this.isEmbedded = false});

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  List<ExportTypeOption> _types = [];
  final Set<String> _selectedTypes = {};
  bool _isLoading = true;
  bool _isExporting = false;
  bool _saveToFile = true;
  
  // 导出选项
  bool _removeTeamBinding = false;
  bool _removeImagePath = true;
  bool _removeConflictData = true;
  bool _removeDeviceId = true;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final username = await StorageService.getCurrentUsername();
    if (username == null || username.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final types = await DataExportService.getAvailableTypes(username);
    if (mounted) {
      setState(() {
        _types = types;
        _selectedTypes.addAll(types.where((t) => t.count > 0).map((t) => t.key));
        _isLoading = false;
      });
    }
  }

  void _toggleAll(bool? select) {
    if (select == null) return;
    setState(() {
      if (select) {
        _selectedTypes.addAll(_types.where((t) => t.count > 0).map((t) => t.key));
      } else {
        _selectedTypes.clear();
      }
    });
  }

  Future<void> _export() async {
    if (_selectedTypes.isEmpty) return;

    setState(() => _isExporting = true);

    final username = await StorageService.getCurrentUsername();
    if (username == null || username.isEmpty) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先登录')),
        );
      }
      return;
    }

    final result = await DataExportService.exportData(
      username: username,
      selectedTypes: _selectedTypes.toList(),
      saveToFile: _saveToFile,
      options: ExportOptions(
        removeTeamBinding: _removeTeamBinding,
        removeImagePath: _removeImagePath,
        removeConflictData: _removeConflictData,
        removeDeviceId: _removeDeviceId,
      ),
    );

    if (mounted) {
      setState(() => _isExporting = false);

      if (result.success) {
        String message = '导出成功，共 ${result.totalItems} 条数据';
        if (result.filePath != null) {
          message += '\n已保存到: ${result.filePath}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: ${result.errorMessage}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isWideScreen = screenWidth > 600;

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(title: const Text('数据导出')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(colorScheme, isLandscape || isWideScreen),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, bool isWide) {
    if (isWide) {
      return _buildWideLayout(colorScheme);
    }
    return _buildNarrowLayout(colorScheme);
  }

  Widget _buildNarrowLayout(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(colorScheme),
          const SizedBox(height: 16),
          _buildSelectAllRow(colorScheme),
          const SizedBox(height: 8),
          ..._types.map((type) => _buildTypeTile(type, colorScheme)),
          const SizedBox(height: 16),
          _buildExportOptionsCard(colorScheme),
          const SizedBox(height: 16),
          _buildExportMethodCard(colorScheme),
          const SizedBox(height: 24),
          _buildExportButton(),
        ],
      ),
    );
  }

  Widget _buildWideLayout(ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(colorScheme),
                const SizedBox(height: 16),
                _buildSelectAllRow(colorScheme),
                const SizedBox(height: 8),
                ..._types.map((type) => _buildTypeTile(type, colorScheme)),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildExportOptionsCard(colorScheme),
                const SizedBox(height: 16),
                _buildExportMethodCard(colorScheme),
                const SizedBox(height: 24),
                _buildExportButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '选择要导出的数据',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '导出的数据将保存为 JSON 格式文件，可用于备份或在其他设备上导入。',
              style: TextStyle(
                  fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectAllRow(ColorScheme colorScheme) {
    return Row(
      children: [
        Checkbox(
          value: _selectedTypes.length ==
                  _types.where((t) => t.count > 0).length &&
              _selectedTypes.isNotEmpty,
          tristate: true,
          onChanged: _toggleAll,
        ),
        const Text('全选', style: TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(
          '已选 ${_selectedTypes.length} 项',
          style: TextStyle(
              fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildExportMethodCard(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '导出方式',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            RadioListTile<bool>(
              title: const Text('保存到文件'),
              subtitle: const Text('保存到本地文档目录'),
              value: true,
              groupValue: _saveToFile,
              onChanged: (v) => setState(() => _saveToFile = v!),
              contentPadding: EdgeInsets.zero,
            ),
            RadioListTile<bool>(
              title: const Text('分享'),
              subtitle: const Text('通过系统分享发送给其他应用'),
              value: false,
              groupValue: _saveToFile,
              onChanged: (v) => setState(() => _saveToFile = v!),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOptionsCard(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '导出选项',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '选择要清理的数据，使导出文件更适合跨设备或跨账号使用',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text('去除团队绑定'),
              subtitle: const Text('导出的数据将不包含团队信息'),
              value: _removeTeamBinding,
              onChanged: (v) => setState(() => _removeTeamBinding = v!),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              title: const Text('去除图片路径'),
              subtitle: const Text('本地图片路径在其他设备上无效'),
              value: _removeImagePath,
              onChanged: (v) => setState(() => _removeImagePath = v!),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              title: const Text('去除冲突数据'),
              subtitle: const Text('同步冲突信息无需导出'),
              value: _removeConflictData,
              onChanged: (v) => setState(() => _removeConflictData = v!),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            CheckboxListTile(
              title: const Text('去除设备ID'),
              subtitle: const Text('设备标识在其他设备上无效'),
              value: _removeDeviceId,
              onChanged: (v) => setState(() => _removeDeviceId = v!),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _selectedTypes.isEmpty || _isExporting
            ? null
            : _export,
        icon: _isExporting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.upload_file),
        label: Text(_isExporting ? '导出中...' : '开始导出'),
      ),
    );
  }

  Widget _buildTypeTile(ExportTypeOption type, ColorScheme colorScheme) {
    final isSelected = _selectedTypes.contains(type.key);
    final hasData = type.count > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: hasData
            ? (v) {
                setState(() {
                  if (v == true) {
                    _selectedTypes.add(type.key);
                  } else {
                    _selectedTypes.remove(type.key);
                  }
                });
              }
            : null,
        secondary: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hasData
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            type.icon,
            color: hasData
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            size: 24,
          ),
        ),
        title: Text(
          type.label,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: hasData ? null : colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          '${type.count} 条${hasData ? '' : ' (无数据)'}',
          style: TextStyle(
            fontSize: 12,
            color: hasData ? colorScheme.onSurfaceVariant : colorScheme.error,
          ),
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }
}
