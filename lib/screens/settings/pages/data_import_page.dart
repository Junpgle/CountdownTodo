import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../models/data_export_models.dart';
import '../../../services/api_service.dart';
import '../../../services/data_import_service.dart';
import '../../../storage_service.dart';
import '../../../utils/text_file_reader.dart';

class DataImportPage extends StatefulWidget {
  final bool isEmbedded;

  const DataImportPage({super.key, this.isEmbedded = false});

  @override
  State<DataImportPage> createState() => _DataImportPageState();
}

class _DataImportPageState extends State<DataImportPage> {
  String? _filePath;
  String? _fileName;
  String? _fileContent;
  ImportPreview? _preview;
  bool _isParsing = false;
  bool _isImporting = false;
  ImportResult? _result;
  bool? _isSameAccount;

  // 导入选项
  TeamDataStrategy _teamStrategy = TeamDataStrategy.skip;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final pickedFile = result.files.single;
    final filePath = pickedFile.path;
    final fileName = pickedFile.name;
    final bytes = pickedFile.bytes;
    final jsonString = bytes != null
        ? utf8.decode(bytes)
        : (filePath != null ? await readTextFile(filePath) : null);
    if (jsonString == null) return;

    setState(() {
      _filePath = filePath;
      _fileName = fileName;
      _fileContent = jsonString;
      _preview = null;
      _result = null;
      _isParsing = true;
      _isSameAccount = null;
    });

    try {
      final preview = await DataImportService.parseJsonString(jsonString);

      // 多重检测是否是同账号
      final currentUserId = ApiService.currentUserId;
      final currentUsername = await StorageService.getCurrentUsername();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final fileUserId = json['userId'] as int?;
      final fileUsername = json['username']?.toString();

      // 判断逻辑（优先使用 userId）
      final bool isSameAccount;
      if (fileUserId != null && fileUserId > 0) {
        // 有 userId，直接比较
        isSameAccount = fileUserId == currentUserId;
      } else if (fileUsername != null) {
        // 没有 userId，用 username 比较
        isSameAccount = fileUsername == currentUsername;
      } else {
        // 旧版本导出的文件，无法判断，默认同账号
        isSameAccount = true;
      }

      if (mounted) {
        setState(() {
          _preview = preview;
          _isParsing = false;
          _isSameAccount = isSameAccount;
        });

        // 如果是不同账号，显示提示
        if (!isSameAccount) {
          _showDifferentAccountDialog(fileUserId, fileUsername);
        }
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

  void _showDifferentAccountDialog(int? sourceUserId, String? sourceUsername) {
    String message = '';
    if (sourceUsername != null) {
      message = '检测到备份文件来自账号 "$sourceUsername"';
      if (sourceUserId != null) {
        message += ' (ID: $sourceUserId)';
      }
      message += '，导入时将自动重新生成所有数据的 UUID 以避免冲突。';
    } else {
      message = '检测到备份文件来自不同账号，导入时将自动重新生成所有数据的 UUID 以避免冲突。';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跨账号导入'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _filePath = null;
                _fileName = null;
                _fileContent = null;
                _preview = null;
                _isSameAccount = null;
              });
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    if (_filePath == null && _fileContent == null) return;

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

    final uuidStrategy = _isSameAccount == false
        ? UuidStrategy.regenerate
        : UuidStrategy.keepOriginal;
    final importOptions = ImportOptions(
      teamStrategy: _teamStrategy,
      uuidStrategy: uuidStrategy,
    );
    final result = _fileContent != null
        ? await DataImportService.importDataFromJsonString(
            username: username,
            jsonString: _fileContent!,
            options: importOptions,
          )
        : await DataImportService.importData(
            username: username,
            filePath: _filePath!,
            options: importOptions,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isWideScreen = screenWidth > 600;

    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(title: const Text('数据导入')),
      body: _buildBody(colorScheme, isLandscape || isWideScreen),
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
            _buildImportOptionsCard(colorScheme),
            const SizedBox(height: 16),
            _buildMergeInfoCard(colorScheme),
            const SizedBox(height: 24),
            _buildImportButton(),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(colorScheme),
          ],
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
                ],
                if (_result != null) ...[
                  const SizedBox(height: 16),
                  _buildResultCard(colorScheme),
                ],
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
                if (_preview != null) ...[
                  _buildImportOptionsCard(colorScheme),
                  const SizedBox(height: 16),
                  _buildMergeInfoCard(colorScheme),
                  const SizedBox(height: 24),
                  _buildImportButton(),
                ],
              ],
            ),
          ),
        ),
      ],
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
                Icon(Icons.folder_open, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '选择备份文件',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_filePath != null || _fileContent != null) ...[
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
                        _fileName ?? _filePath!.split('/').last,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _filePath = null;
                          _fileName = null;
                          _fileContent = null;
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
                label: Text((_filePath == null && _fileContent == null)
                    ? '选择文件'
                    : '更换文件'),
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
                Icon(Icons.preview, color: colorScheme.primary, size: 20),
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

  Widget _buildImportOptionsCard(ColorScheme colorScheme) {
    // 计算团队数据总数
    int totalTeamCount = 0;
    if (_preview != null) {
      for (final type in _preview!.types) {
        totalTeamCount += type.teamCount;
      }
    }

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
                  '导入选项',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (_isSameAccount != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSameAccount!
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSameAccount! ? Icons.check_circle : Icons.swap_horiz,
                      color: _isSameAccount!
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onErrorContainer,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isSameAccount!
                            ? '同账号数据，将保留原始 UUID'
                            : '跨账号导入，将重新生成 UUID',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _isSameAccount!
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (totalTeamCount > 0) ...[
              const SizedBox(height: 16),
              const Text(
                '团队数据处理:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              RadioListTile<TeamDataStrategy>(
                title: const Text('跳过'),
                subtitle: const Text('不导入团队数据'),
                value: TeamDataStrategy.skip,
                groupValue: _teamStrategy,
                onChanged: (v) => setState(() => _teamStrategy = v!),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              RadioListTile<TeamDataStrategy>(
                title: const Text('转为个人数据'),
                subtitle: const Text('去除团队绑定，作为个人数据导入'),
                value: TeamDataStrategy.convertToPersonal,
                groupValue: _teamStrategy,
                onChanged: (v) => setState(() => _teamStrategy = v!),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    return SizedBox(
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
