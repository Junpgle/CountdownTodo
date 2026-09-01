import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/floating_glass_control.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';
import '../models/cloud_challenge.dart';
import '../models/thirty_day_challenge.dart';
import '../services/challenge_share_codec.dart';
import '../services/clipboard_share_detector.dart';
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

  void _applyDraft(ChallengeDraft draft) {
    _titleController.text = draft.title;
    _tasksController.text = draft.taskTitles.join('\n');
    _tasksController.selection = TextSelection.collapsed(
      offset: _tasksController.text.length,
    );
  }

  Future<void> _shareChallenge() async {
    final title = _titleController.text.trim();
    final tasks = _taskTitles;
    if (title.isEmpty || tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写挑战名称和至少一项任务，再分享挑战')),
      );
      return;
    }

    try {
      final sharedText = ChallengeShareCodec.encode(
        ChallengeDraft(title: title, taskTitles: tasks),
      );
      await Clipboard.setData(
        ClipboardData(text: sharedText),
      );
      await ClipboardSharePayload.markLocallyGenerated(sharedText);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制分享内容，朋友可在新建挑战页点击“识别剪贴板”导入'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享内容复制失败，请稍后再试')),
      );
    }
  }

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;

    final sharedDraft = ChallengeShareCodec.tryDecode(text);
    if (sharedDraft != null) {
      _applyDraft(sharedDraft);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已识别并导入挑战「${sharedDraft.title}」')),
      );
      return;
    }

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
        allowedExtensions: ['txt', 'md', 'csv', 'json'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;

      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('文件内容为空或当前平台无法读取文件');
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final sharedDraft = ChallengeShareCodec.tryDecode(text);
      if (sharedDraft != null) {
        _applyDraft(sharedDraft);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入挑战「${sharedDraft.title}」')),
        );
      } else {
        _tasksController.text = text;
        _tasksController.selection = TextSelection.collapsed(
          offset: _tasksController.text.length,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${_taskTitles.length} 项任务')),
        );
      }
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
    final result = await Navigator.of(context).push<CloudChallengePickerResult>(
      MaterialPageRoute(builder: (_) => const CloudChallengePickerScreen()),
    );
    final selected = result?.challenge;
    if (selected == null || !mounted) return;

    _applyDraft(selected.toDraft());
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

  InputDecoration _editorDecoration(
    ColorScheme scheme, {
    required String labelText,
    required String hintText,
    required IconData icon,
  }) {
    final fillColor = scheme.surfaceContainerHighest.withValues(alpha: 0.46);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: Icon(icon, color: scheme.onSurfaceVariant),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
    );
  }

  Widget _buildTaskEditor(
    ColorScheme scheme, {
    required List<String> taskTitles,
    required bool isWide,
  }) {
    final labelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w900,
        );
    final hintStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
          height: 1.45,
        );
    final fillColor = scheme.surfaceContainerHighest.withValues(alpha: 0.46);

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 15, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.format_list_bulleted_rounded,
                color: scheme.primary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('任务清单', style: labelStyle),
                    const SizedBox(height: 2),
                    Text('每行一项任务', style: hintStyle),
                  ],
                ),
              ),
              IconButton(
                tooltip: '清空任务',
                onPressed: taskTitles.isEmpty ? null : _tasksController.clear,
                style: floatingGlassPlainIconButtonStyle(),
                icon: const Icon(Icons.clear_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _tasksController,
            minLines: isWide ? 7 : 6,
            maxLines: isWide ? 12 : 11,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: '读完一本书\n跑步 3 公里\n给朋友写一封信',
              hintStyle: hintStyle,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
            ),
            validator: (_) => taskTitles.isEmpty ? '至少输入一行任务' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCreationHero(ColorScheme scheme) {
    final heroText = scheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.onPrimary,
                  size: 27,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'CUSTOM CHALLENGE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: heroText,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '把想做的事，\n变成一场挑战',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: heroText,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                  letterSpacing: -0.8,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            '从一件小事开始，任务数量、顺序和节奏都由你决定。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: heroText.withValues(alpha: 0.8),
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeroBadge('不受 30 项限制', scheme),
              _buildHeroBadge('顺序自由安排', scheme),
              _buildHeroBadge('随时可以编辑', scheme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge(String label, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildCloudSourceCard(ColorScheme scheme) {
    return Card(
      elevation: 0,
      color: scheme.secondaryContainer.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.cloud_download_rounded,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已有一个想法？',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: scheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '从云端挑战库挑一份模板，再按你的节奏修改。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSecondaryContainer
                                  .withValues(alpha: 0.78),
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _isImporting ? null : _openCloudChallenges,
                icon: const Icon(Icons.explore_rounded),
                label: const Text('浏览云端挑战库'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeading(
    ColorScheme scheme, {
    required String eyebrow,
    required String title,
    String? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
      ],
    );
  }

  Widget _buildTaskPreview(
    List<String> taskTitles,
    ColorScheme scheme,
  ) {
    return OptionalLiquidGlassCard(
      borderRadius: 26,
      highContrast: true,
      tint: scheme.tertiary,
      fallbackDecoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.view_list_rounded,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '任务预览',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Text(
                  '${taskTitles.length} 项',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (taskTitles.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '还没有任务，输入内容后会在这里预览。',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              for (final entry in taskTitles.take(6).toList().asMap().entries)
                _buildPreviewTask(entry.key, entry.value, scheme),
              if (taskTitles.length > 6)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '还有 ${taskTitles.length - 6} 项任务，创建后可以继续查看。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTask(
    int index,
    String title,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final taskTitles = _taskTitles;

    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('新建打卡挑战'),
        actions: [
          IconButton(
            tooltip: '分享挑战',
            onPressed: _isImporting ? null : _shareChallenge,
            style: floatingGlassPlainIconButtonStyle(),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          TextButton(
            onPressed: _isImporting ? null : _createChallenge,
            child: const Text('开始挑战'),
          ),
        ],
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: kToolbarHeight,
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                final horizontalPadding = isWide ? 28.0 : 16.0;
                final maxWidth = isWide ? 860.0 : constraints.maxWidth;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    floatingGlassTopBarHeight(context) + 16,
                    horizontalPadding,
                    32,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCreationHero(scheme),
                            const SizedBox(height: 26),
                            _buildSectionHeading(
                              scheme,
                              eyebrow: 'QUICK START',
                              title: '从灵感开始',
                            ),
                            const SizedBox(height: 12),
                            _buildCloudSourceCard(scheme),
                            const SizedBox(height: 28),
                            _buildSectionHeading(
                              scheme,
                              eyebrow: 'BUILD YOUR OWN',
                              title: '定义这场挑战',
                              trailing: taskTitles.isEmpty
                                  ? '待填写'
                                  : '${taskTitles.length} 项任务',
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _titleController,
                              textInputAction: TextInputAction.next,
                              decoration: _editorDecoration(
                                scheme,
                                labelText: '挑战名称',
                                hintText: '例如：我的阅读挑战',
                                icon: Icons.title_rounded,
                              ),
                              validator: (value) =>
                                  value?.trim().isEmpty == true
                                      ? '请给这场挑战起个名字'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            _buildTaskEditor(
                              scheme,
                              taskTitles: taskTitles,
                              isWide: isWide,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _isImporting ? null : _pasteText,
                                  icon: const Icon(Icons.content_paste_rounded),
                                  label: const Text('识别剪贴板'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      _isImporting ? null : _importTextFile,
                                  icon: _isImporting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.upload_file_rounded),
                                  label: Text(
                                    _isImporting ? '导入中…' : '导入挑战文件',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      _isImporting ? null : _shareChallenge,
                                  icon: const Icon(Icons.ios_share_rounded),
                                  label: const Text('分享挑战'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '分享内容会自动识别标题和任务；普通文本仍会按行导入。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildTaskPreview(taskTitles, scheme),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _isImporting ? null : _createChallenge,
                              icon: const Icon(Icons.bolt_rounded),
                              label: const Text('创建并开始挑战'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(58),
                                textStyle:
                                    theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
