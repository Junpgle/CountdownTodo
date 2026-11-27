import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../models/data_export_models.dart';
import '../../../services/api_service.dart';
import '../../../services/data_import_service.dart';
import '../../../services/minor_mode_policy.dart';
import '../../../storage_service.dart';
import '../../../utils/text_file_reader.dart';
import '../../../utils/time_utils.dart';
import '../../../widgets/app_skeleton.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';
import '../../../utils/app_dialogs.dart';
import '../widgets/data_transfer_shared.dart';
import '../widgets/import_scope_selector.dart';
import '../widgets/import_restore_widgets.dart';

class DataImportPage extends StatefulWidget {
  final bool isEmbedded;
  final String? initialFilePath;
  final String? initialFileName;

  const DataImportPage({
    super.key,
    this.isEmbedded = false,
    this.initialFilePath,
    this.initialFileName,
  });

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
  Set<ImportDataScope> _selectedScopes = {};

  // 导入选项
  TeamDataStrategy _teamStrategy = TeamDataStrategy.skip;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialFile();
      });
    }
  }

  Future<void> _loadInitialFile() async {
    final filePath = widget.initialFilePath;
    if (filePath == null) return;
    try {
      final jsonString = await readTextFile(filePath);
      if (!mounted) return;
      final fallbackName = filePath.split(_rxCached17_1).last;
      await _loadJsonString(
        filePath: filePath,
        fileName: widget.initialFileName ?? fallbackName,
        jsonString: jsonString,
      );
    } catch (_) {
      // 文件不可读时保持空状态，用户可重新选择文件。
    }
  }

  Future<void> _pickFile() async {
    final pickedFile = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (pickedFile == null) return;

    final filePath = pickedFile.path;
    final fileName = pickedFile.name;
    List<int>? bytes;
    try {
      bytes = await pickedFile.readAsBytes();
    } catch (_) {
      // Fall back to the local file path on platforms that expose one.
    }
    final jsonString = bytes != null
        ? utf8.decode(bytes)
        : (filePath != null ? await readTextFile(filePath) : null);
    if (jsonString == null) return;
    await _loadJsonString(
      filePath: filePath,
      fileName: fileName,
      jsonString: jsonString,
    );
  }

  Future<void> _loadJsonString({
    required String? filePath,
    required String fileName,
    required String jsonString,
  }) async {
    setState(() {
      _filePath = filePath;
      _fileName = fileName;
      _fileContent = jsonString;
      _preview = null;
      _result = null;
      _isParsing = true;
      _isSameAccount = null;
      _selectedScopes = {};
    });

    try {
      final preview = await DataImportService.parseJsonString(jsonString);

      // 多重检测是否是同账号
      final currentUserId = ApiService.currentUserId;
      final currentUsername = await StorageService.getCurrentUsername();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final fileUserId = int.tryParse(json['userId']?.toString() ?? '');
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
          _selectedScopes = preview.scopes.map((scope) => scope.scope).toSet();
        });

        // 如果是不同账号，显示提示
        if (!isSameAccount) {
          _showDifferentAccountDialog(fileUserId, fileUsername);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isParsing = false);
        AppSnackBars.showSnackBar(
          context,
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

    showAppDialog(
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
                _selectedScopes = {};
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
    if ((_filePath == null && _fileContent == null) ||
        _preview == null ||
        _selectedScopes.isEmpty) {
      return;
    }

    final authorized = await authorizeMinorModeDataTransfer(
      context,
      MinorModeAction.dataImport,
    );
    if (!authorized || !mounted) return;

    final preview = _preview!;
    final selectedScopes = Set<ImportDataScope>.unmodifiable(_selectedScopes);
    final selectedTeamCount = teamScopedImportCount(preview, selectedScopes);
    final teamStrategy = _teamStrategy;
    final confirmed = await ImportRestoreReviewDialog.show(
      context: context,
      preview: preview,
      selectedScopes: selectedScopes,
      isSameAccount: _isSameAccount,
      teamStrategy: teamStrategy,
      selectedTeamCount: selectedTeamCount,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _isImporting = true;
      _result = null;
    });

    final username = await StorageService.getCurrentUsername();
    if (username == null || username.isEmpty) {
      if (mounted) {
        setState(() => _isImporting = false);
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('请先登录')),
        );
      }
      return;
    }

    final uuidStrategy = _isSameAccount == false
        ? UuidStrategy.regenerate
        : UuidStrategy.keepOriginal;
    final importOptions = ImportOptions(
      teamStrategy: teamStrategy,
      uuidStrategy: uuidStrategy,
      selectedScopes: selectedScopes,
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
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: const Text('恢复完成，详细结果已按数据域列出。'),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('导入失败: ${result.errorMessage}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final parsingOrPreview = <Widget>[
      if (_isParsing)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: AppSkeletonSettingsSection(rows: 3, showHeader: false),
        )
      else if (_preview != null)
        _buildPreviewSection(),
    ];
    final restoreActions = <Widget>[
      if (!_isParsing && _preview != null) ...[
        _buildImportOptionsCard(colorScheme),
        const SizedBox(height: 16),
        ImportRestoreRulesCard(
          selectedScopes: _selectedScopes,
          selectedTeamCount: _selectedTeamImportCount,
        ),
        const SizedBox(height: 24),
        _buildImportButton(),
      ],
    ];

    return DataTransferScaffold(
      title: '数据导入',
      isEmbedded: widget.isEmbedded,
      primaryChildren: [
        _buildFileSection(colorScheme),
        const SizedBox(height: 16),
        ...parsingOrPreview,
        if (_result != null) ...[
          const SizedBox(height: 16),
          _buildResultCard(colorScheme),
        ],
      ],
      secondaryChildren: restoreActions,
      narrowChildren: [
        _buildFileSection(colorScheme),
        const SizedBox(height: 16),
        ...parsingOrPreview,
        if (restoreActions.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...restoreActions,
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          _buildResultCard(colorScheme),
        ],
      ],
    );
  }

  Widget _buildFileSection(ColorScheme colorScheme) {
    return DataTransferSectionCard(
      icon: Icons.folder_open,
      title: '选择备份文件',
      titleFontSize: 16,
      children: [
        if (_filePath != null || _fileContent != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.description,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
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
            label: Text(
              (_filePath == null && _fileContent == null) ? '选择文件' : '更换文件',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    final preview = _preview!;

    return DataTransferSectionCard(
      icon: Icons.preview,
      title: '文件预览',
      titleFontSize: 16,
      children: [
        _buildInfoRow(
          '导出时间',
          AppTimeFormats.dateFormatter('yyyy-MM-dd HH:mm')
              .format(preview.exportedAt),
        ),
        if (preview.appVersion != null)
          _buildInfoRow('应用版本', preview.appVersion!),
        const Divider(height: 24),
        ImportScopeSelector(
          preview: preview,
          selectedScopes: _selectedScopes,
          onSelectionChanged: (scopes) => setState(() {
            _selectedScopes = scopes;
            _result = null;
          }),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildImportOptionsCard(ColorScheme colorScheme) {
    final totalTeamCount = _selectedTeamImportCount;

    return DataTransferSectionCard(
      icon: Icons.tune,
      title: '导入选项',
      headerSpacing: 0,
      children: [
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
                    _isSameAccount! ? '同账号数据，将保留原始 UUID' : '跨账号导入，将重新生成 UUID',
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
          const Text('团队数据处理:', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          RadioGroup<TeamDataStrategy>(
            groupValue: _teamStrategy,
            onChanged: (value) {
              if (value != null) {
                setState(() => _teamStrategy = value);
              }
            },
            child: const Column(
              children: [
                RadioListTile<TeamDataStrategy>(
                  title: Text('跳过'),
                  subtitle: Text('不导入团队数据'),
                  value: TeamDataStrategy.skip,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<TeamDataStrategy>(
                  title: Text('转为个人数据'),
                  subtitle: Text('去除团队绑定，作为个人数据导入'),
                  value: TeamDataStrategy.convertToPersonal,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImportButton() {
    return DataTransferPrimaryActionButton(
      onPressed: _isImporting || _selectedScopes.isEmpty ? null : _import,
      isBusy: _isImporting,
      icon: Icons.download,
      label: _selectedScopes.isEmpty ? '先选择恢复范围' : '复核并导入',
      busyLabel: '导入中...',
    );
  }

  int get _selectedTeamImportCount {
    final preview = _preview;
    if (preview == null) return 0;
    return teamScopedImportCount(preview, _selectedScopes);
  }

  Widget _buildResultCard(ColorScheme colorScheme) {
    final result = _result!;

    return OptionalLiquidGlassCard(
      borderRadius: 12,
      highContrast: true,
      tint:
          (result.success
                  ? colorScheme.tertiaryContainer
                  : colorScheme.errorContainer)
              .withValues(alpha: 0.16),
      fallbackDecoration: BoxDecoration(
        color: result.success
            ? colorScheme.tertiaryContainer
            : colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
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
              if (result.scopeSummaries.isNotEmpty)
                ImportScopeRestoreSummaryList(summaries: result.scopeSummaries)
              else
                Text(
                  '恢复已完成。',
                  style: TextStyle(color: colorScheme.onTertiaryContainer),
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

// Cached RegExp patterns
final RegExp _rxCached17_1 = RegExp(r'[/\\]');
