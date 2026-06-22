import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../models/data_export_models.dart';
import '../../../services/data_import_service.dart';
import '../../../storage_service.dart';

class DataImportPage extends StatefulWidget {
  final bool isEmbedded;

  const DataImportPage({super.key, this.isEmbedded = false});

  @override
  State<DataImportPage> createState() => _DataImportPageState();
}

class _DataImportPageState extends State<DataImportPage> {
  String? _filePath;
  ImportPreview? _preview;
  bool _isParsing = false;
  bool _isImporting = false;
  ImportResult? _result;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    setState(() {
      _filePath = filePath;
      _preview = null;
      _result = null;
      _isParsing = true;
    });

    try {
      final preview = await DataImportService.parseFile(filePath);
      if (mounted) {
        setState(() {
          _preview = preview;
          _isParsing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isParsing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件解析失败: $e')),
        );
      }
    }
  }

  Future<void> _import() async {
    if (_filePath == null) return;

    setState(() => _isImporting = true);

    final username = await StorageService.getCurrentUsername();
    if (username == null || username.isEmpty) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先登录')),
        );
      }
      return;
    }

    final result = await DataImportService.importData(
      username: username,
      filePath: _filePath!,
    );

    if (mounted) {
      setState(() {
        _isImporting = false;
        _result = result;
      });

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导入成功: 新增 ${result.importedCount} 条，更新 ${result.updatedCount} 条，跳过 ${result.skippedCount} 条',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: ${result.errorMessage}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(title: const Text('数据导入')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFileSection(colorScheme),
            const SizedBox(height: 16),
            if (_isParsing) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_preview != null) ...[
              _buildPreviewSection(colorScheme),
              const SizedBox(height: 16),
              _buildMergeInfoCard(colorScheme),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isImporting ? null : _import,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download),
                  label: Text(_isImporting ? '导入中...' : '开始导入'),
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _buildResultCard(colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileSection(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '选择备份文件',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_filePath != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description,
                        color: colorScheme.onSurfaceVariant, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _filePath!.split('/').last,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _filePath = null;
                          _preview = null;
                          _result = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isParsing ? null : _pickFile,
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(_filePath == null ? '选择文件' : '更换文件'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection(ColorScheme colorScheme) {
    final preview = _preview!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '文件预览',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('导出时间',
                DateFormat('yyyy-MM-dd HH:mm').format(preview.exportedAt)),
            if (preview.appVersion != null)
              _buildInfoRow('应用版本', preview.appVersion!),
            const Divider(height: 24),
            const Text(
              '包含数据:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            ...preview.types.map((type) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 6),
                      const SizedBox(width: 8),
                      Text(type.label),
                      const Spacer(),
                      Text(
                        '${type.count} 条',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildMergeInfoCard(ColorScheme colorScheme) {
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.merge_type,
                    color: colorScheme.onPrimaryContainer, size: 20),
                const SizedBox(width: 8),
                Text(
                  '智能合并',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• 本地不存在的数据将被导入\n• 冲突数据将保留最新版本\n• 已删除的数据也会被导入',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onPrimaryContainer,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ColorScheme colorScheme) {
    final result = _result!;

    return Card(
      color: result.success
          ? colorScheme.tertiaryContainer
          : colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.success ? Icons.check_circle : Icons.error,
                  color: result.success
                      ? colorScheme.onTertiaryContainer
                      : colorScheme.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  result.success ? '导入完成' : '导入失败',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: result.success
                        ? colorScheme.onTertiaryContainer
                        : colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            if (result.success) ...[
              const SizedBox(height: 8),
              Text(
                '新增: ${result.importedCount} 条\n'
                '更新: ${result.updatedCount} 条\n'
                '跳过: ${result.skippedCount} 条',
                style: TextStyle(
                  color: colorScheme.onTertiaryContainer,
                  height: 1.5,
                ),
              ),
            ] else if (result.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                result.errorMessage!,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
