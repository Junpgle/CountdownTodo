import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cloud_challenge.dart';
import '../models/thirty_day_challenge.dart';
import '../services/challenge_text_parser.dart';
import 'cloud_challenge_picker_screen.dart';

class NewChallengeScreen extends StatefulWidget {
  final ChallengeDraft? initialDraft;

  const NewChallengeScreen({super.key, this.initialDraft});

  @override
  State<NewChallengeScreen> createState() => _NewChallengeScreenState();
}

class _NewChallengeScreenState extends State<NewChallengeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _tasksController = TextEditingController();
  bool _isImporting = false;

  List<String> get _taskTitles =>
      ChallengeTextParser.parseTaskTitles(_tasksController.text);

  @override
  void initState() {
    super.initState();
    final initialDraft = widget.initialDraft;
    if (initialDraft != null) {
      _titleController.text = initialDraft.title;
      _tasksController.text = initialDraft.taskTitles.join('\n');
    }
    _tasksController.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tasksController
      ..removeListener(_refreshPreview)
      ..dispose();
    super.dispose();
  }

  void _refreshPreview() => setState(() {});

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    _tasksController.text = text;
    _tasksController.selection = TextSelection.collapsed(
      offset: _tasksController.text.length,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已从剪贴板粘贴任务清单')),
    );
  }

  Future<void> _importTextFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'csv'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;

      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('文件内容为空或当前平台无法读取文件');
      }
      _tasksController.text = utf8.decode(bytes, allowMalformed: true);
      _tasksController.selection = TextSelection.collapsed(
        offset: _tasksController.text.length,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${_taskTitles.length} 项任务')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文本导入失败，请选择 UTF-8 编码的文本文件')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _openCloudChallenges() async {
    final selected = await Navigator.of(context).push<CloudChallengeTemplate>(
      MaterialPageRoute(builder: (_) => const CloudChallengePickerScreen()),
    );
    if (selected == null || !mounted) return;

    _titleController.text = selected.title;
    _tasksController.text = selected.tasks.join('\n');
    _tasksController.selection = TextSelection.collapsed(
      offset: _tasksController.text.length,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已填入云端挑战「${selected.title}」')),
    );
  }

  void _createChallenge() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final titles = _taskTitles;
    if (titles.isEmpty) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(
      ChallengeDraft(
        title: _titleController.text.trim(),
        taskTitles: titles,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final taskTitles = _taskTitles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新建打卡挑战'),
        actions: [
          TextButton(
            onPressed: _isImporting ? null : _createChallenge,
            child: const Text('开始挑战'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                '把任何想完成的事情做成一场自己的挑战',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '输入或导入任务清单，每一行就是一项任务。任务数量和内容都不受 30 项限制。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _isImporting ? null : _openCloudChallenges,
                icon: const Icon(Icons.cloud_download_rounded),
                label: const Text('从 GitHub 获取云端挑战'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '挑战名称',
                  hintText: '例如：我的阅读挑战',
                  prefixIcon: Icon(Icons.title_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.trim().isEmpty == true ? '请给这场挑战起个名字' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tasksController,
                minLines: 10,
                maxLines: 18,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: '任务清单（每行一项）',
                  hintText: '读完一本书\n跑步 3 公里\n给朋友写一封信',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 150),
                    child: Icon(Icons.format_list_bulleted_rounded),
                  ),
                  suffixIcon: IconButton(
                    tooltip: '清空',
                    onPressed: _tasksController.text.isEmpty
                        ? null
                        : _tasksController.clear,
                    icon: const Icon(Icons.clear_rounded),
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (_) => taskTitles.isEmpty ? '至少输入一行任务' : null,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _pasteText,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('从剪贴板粘贴'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _importTextFile,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_rounded),
                    label: Text(_isImporting ? '导入中…' : '导入文本文件'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.preview_rounded, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '任务预览 · ${taskTitles.length} 项',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      if (taskTitles.isEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          '还没有任务，输入内容后会在这里预览。',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        ...taskTitles.take(6).toList().asMap().entries.map(
                              (entry) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${entry.key + 1}.',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(entry.value)),
                                  ],
                                ),
                              ),
                            ),
                        if (taskTitles.length > 6)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '还有 ${taskTitles.length - 6} 项任务…',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isImporting ? null : _createChallenge,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('创建并开始'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
