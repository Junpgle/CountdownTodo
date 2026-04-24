import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/api_service.dart';
import '../services/todo_parser_service.dart';
import '../services/llm_service.dart';
import '../screens/home_settings_screen.dart';
import '../utils/page_transitions.dart';

class AddTodoScreen extends StatefulWidget {
  final Function(TodoItem) onTodoAdded;
  final Function(List<TodoItem>)? onTodosBatchAdded;
  final Function(List<Map<String, dynamic>>, String?, String?, String?, String?)?
  onLLMResultsParsed;
  final List<TodoGroup> todoGroups;
  final String? initialGroupId;
  final String? initialTeamUuid;
  final String? initialTeamName;

  const AddTodoScreen({
    super.key,
    required this.onTodoAdded,
    this.onTodosBatchAdded,
    this.onLLMResultsParsed,
    this.todoGroups = const [],
    this.initialGroupId,
    this.initialTeamUuid,
    this.initialTeamName,
  });

  @override
  State<AddTodoScreen> createState() => _AddTodoScreenState();
}

class _AddTodoScreenState extends State<AddTodoScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();
  final TextEditingController _aiInputCtrl = TextEditingController();
  final TextEditingController _customDaysCtrl = TextEditingController();

  DateTime _createdAt = DateTime.now();
  DateTime? _dueDate;
  RecurrenceType _recurrence = RecurrenceType.none;
  int? _customDays;
  DateTime? _recurrenceEndDate;
  bool _isAllDay = false;
  String? _selectedGroupId;
  int _reminderMinutes = 5;

  int _selectedTabIndex = 0;
  bool _isParsing = false;
  List<ParsedTodoResult> _parsedResults = [];
  int _currentParseIndex = 0;
  String? _llmRawResponse;
  String? _currentOriginalText;
  String? _selectedImagePath;

  Map<String, int> _categoryReminderDefaults = {};
  String? _username;
  List<Team> _teams = [];
  String? _selectedTeamUuid;
  String? _selectedTeamName;
  int _collabType = 0;

  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.initialGroupId;
    _selectedTeamUuid = widget.initialTeamUuid;
    _selectedTeamName = widget.initialTeamName;
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
    _loadCategoryDefaults().then((_) {
      if (_selectedGroupId != null &&
          _categoryReminderDefaults.containsKey(_selectedGroupId)) {
        setState(() {
          _reminderMinutes = _categoryReminderDefaults[_selectedGroupId]!;
        });
      }
    });
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final rawTeams = await ApiService.fetchTeams();
    if (mounted) {
      setState(() {
        _teams = rawTeams.map((t) => Team.fromJson(t)).toList();
      });
    }
  }

  Future<void> _pickAttachmentImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null || filePath.isEmpty) return;

      setState(() {
        _selectedImagePath = filePath;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败: $e')),
      );
    }
  }

  Future<String?> _persistAttachmentImageIfNeeded() async {
    final sourcePath = _selectedImagePath;
    if (sourcePath == null || sourcePath.isEmpty) return null;

    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return null;

      final appDir = await getApplicationSupportDirectory();
      final imageDir = Directory('${appDir.path}/todo_attachments');
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }

      if (p.normalize(sourcePath).startsWith(p.normalize(imageDir.path))) {
        return sourcePath;
      }

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}';
      final targetPath = '${imageDir.path}/$fileName';
      await sourceFile.copy(targetPath);
      setState(() {
        _selectedImagePath = targetPath;
      });
      return targetPath;
    } catch (e) {
      debugPrint('❌ 持久化待办图片失败: $e');
      return null;
    }
  }

  Future<void> _loadCategoryDefaults() async {
    final username = await StorageService.getLoginSession();
    if (username != null) {
      final defaults =
      await StorageService.getCategoryReminderMinutes(username);
      setState(() {
        _username = username;
        _categoryReminderDefaults = defaults;
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _remarkCtrl.dispose();
    _aiInputCtrl.dispose();
    _customDaysCtrl.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  RecurrenceType _parseRecurrenceType(String? type) {
    switch (type) {
      case 'daily': return RecurrenceType.daily;
      case 'weekly': return RecurrenceType.weekly;
      case 'monthly': return RecurrenceType.monthly;
      case 'yearly': return RecurrenceType.yearly;
      case 'customDays': return RecurrenceType.customDays;
      default: return RecurrenceType.none;
    }
  }

  String _getRecurrenceLabel(RecurrenceType r) {
    switch (r) {
      case RecurrenceType.none: return "不循环";
      case RecurrenceType.daily: return "每天重复";
      case RecurrenceType.weekly: return "每周重复";
      case RecurrenceType.monthly: return "每月重复";
      case RecurrenceType.yearly: return "每年重复";
      case RecurrenceType.weekdays: return "工作日";
      case RecurrenceType.customDays: return "间隔 ${_customDays ?? '?'} 天";
      default: return "不循环";
    }
  }

  String _getReminderText(int minutes) {
    switch(minutes) {
      case 0: return "不提醒";
      case 5: return "提前 5 分钟";
      case 10: return "提前 10 分钟";
      case 15: return "提前 15 分钟";
      case 30: return "提前 30 分钟";
      case 45: return "提前 45 分钟";
      case 60: return "提前 1 小时";
      case 120: return "提前 2 小时";
      case 1440: return "提前 1 天";
      default: return "提前 $minutes 分钟";
    }
  }

  void _applyParsedResult(ParsedTodoResult result) {
    setState(() {
      _titleCtrl.text = result.title;
      _remarkCtrl.text = result.remark ?? "";
      if (result.startTime != null) {
        _createdAt = result.startTime!;
        if (result.isAllDay) {
          _createdAt = DateTime(_createdAt.year, _createdAt.month, _createdAt.day, 0, 0);
        }
      }
      if (result.endTime != null) {
        _dueDate = result.endTime;
      } else if (result.startTime != null && result.isAllDay) {
        _dueDate = DateTime(_createdAt.year, _createdAt.month, _createdAt.day, 23, 59);
      }
      _isAllDay = result.isAllDay;
      _recurrence = result.recurrence;
      _customDays = result.customIntervalDays;
      if (_customDays != null) {
        _customDaysCtrl.text = _customDays.toString();
      }
      _reminderMinutes = result.reminderMinutes ?? 5;
    });
  }

  Future<void> _doSmartParse() async {
    if (_aiInputCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请输入待办内容")));
      return;
    }
    setState(() => _isParsing = true);
    await Future.delayed(const Duration(milliseconds: 150));

    final results = TodoParserService.parseMulti(_aiInputCtrl.text);
    setState(() {
      _parsedResults = results;
      _currentParseIndex = 0;
      _isParsing = false;
      _currentOriginalText = _aiInputCtrl.text;
    });

    if (_parsedResults.isNotEmpty) {
      if (widget.onLLMResultsParsed != null && _parsedResults.length > 1) {
        final maps = _parsedResults.map((e) => e.toMap()).toList();
        final currentTeamName = _selectedTeamUuid != null ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name : null;
        widget.onLLMResultsParsed!(maps, null, _aiInputCtrl.text, _selectedTeamUuid, currentTeamName);
        return;
      }

      _applyParsedResult(_parsedResults[0]);
      setState(() => _selectedTabIndex = 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("解析成功，共${_parsedResults.length}个待办"), duration: const Duration(seconds: 2)));
      }
    }
  }

  Future<void> _doLLMParse() async {
    if (_aiInputCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请输入待办内容")));
      return;
    }

    final config = await LLMService.getConfig();
    if (config == null || !config.isConfigured) {
      if (!mounted) return;
      final goToSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("未配置大模型"),
          content: const Text("使用大模型识别需要先配置API地址和密钥，是否前往设置？"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("取消")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("去配置")),
          ],
        ),
      );
      if (goToSettings == true && mounted) {
        Navigator.of(context).push(PageTransitions.slideHorizontal(const SettingsPage()));
      }
      return;
    }

    setState(() => _isParsing = true);

    try {
      final results = await LLMService.parseTodoWithLLM(_aiInputCtrl.text);

      if (widget.onLLMResultsParsed != null && results.length > 1) {
        setState(() {
          _isParsing = false;
          _currentOriginalText = _aiInputCtrl.text;
        });
        final currentTeamName = _selectedTeamUuid != null ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name : null;
        widget.onLLMResultsParsed!(results, null, _aiInputCtrl.text, _selectedTeamUuid, currentTeamName);
        return;
      }

      final parsedResultsList = results.map((result) {
        return ParsedTodoResult(
          title: result['title'] ?? _aiInputCtrl.text,
          remark: result['remark'],
          isAllDay: result['isAllDay'] ?? false,
          startTime: result['startTime'] != null ? DateTime.tryParse(result['startTime']) : null,
          endTime: result['endTime'] != null ? DateTime.tryParse(result['endTime']) : null,
          recurrence: _parseRecurrenceType(result['recurrence']),
          customIntervalDays: result['customIntervalDays'],
          reminderMinutes: result['reminderMinutes'],
        );
      }).toList();

      setState(() {
        _parsedResults = parsedResultsList;
        _currentParseIndex = 0;
        _isParsing = false;
        _llmRawResponse = const JsonEncoder.withIndent('  ').convert(results);
        _currentOriginalText = _aiInputCtrl.text;
      });

      if (_parsedResults.isNotEmpty) {
        _applyParsedResult(_parsedResults[0]);
        setState(() => _selectedTabIndex = 0);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("大模型解析成功，共${_parsedResults.length}个待办"), duration: const Duration(seconds: 2)));
        }
      }
    } catch (e) {
      setState(() => _isParsing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("大模型解析失败: $e")));
      }
    }
  }

  Future<void> _addTodo() async {
    if (_titleCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请输入待办内容")));
      return;
    }

    final persistentImagePath = await _persistAttachmentImageIfNeeded();
    final selectedTeam = _selectedTeamUuid != null ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull : null;

    final todo = TodoItem(
      title: _titleCtrl.text,
      recurrence: _recurrence,
      customIntervalDays: _customDays,
      recurrenceEndDate: _recurrenceEndDate,
      dueDate: _dueDate,
      createdDate: _createdAt.millisecondsSinceEpoch,
      remark: _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
      originalText: _currentOriginalText,
      imagePath: persistentImagePath,
      groupId: _selectedGroupId,
      reminderMinutes: _reminderMinutes,
      teamUuid: _selectedTeamUuid,
      teamName: selectedTeam?.name,
      creatorName: _username,
      collabType: _collabType,
    );

    widget.onTodoAdded(todo);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _addBatchTodos() async {
    if (_parsedResults.isEmpty) return;

    final persistentImagePath = await _persistAttachmentImageIfNeeded();
    final selectedTeam = _selectedTeamUuid != null ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull : null;

    final List<TodoItem> todos = _parsedResults.map((r) {
      return TodoItem(
        title: r.title,
        recurrence: r.recurrence,
        customIntervalDays: r.customIntervalDays,
        recurrenceEndDate: r.recurrenceEndDate,
        dueDate: r.endTime,
        createdDate: (r.startTime ?? DateTime.now()).millisecondsSinceEpoch,
        remark: r.remark,
        originalText: _currentOriginalText,
        imagePath: persistentImagePath,
        reminderMinutes: r.reminderMinutes ?? _reminderMinutes,
        teamUuid: _selectedTeamUuid,
        teamName: selectedTeam?.name,
        creatorName: _username,
        collabType: _collabType,
      );
    }).toList();

    if (widget.onTodosBatchAdded != null) {
      widget.onTodosBatchAdded!(todos);
    } else {
      for (var t in todos) {
        widget.onTodoAdded(t);
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  // ================= 自定义统一分段控制器 (替代容易崩溃的原生 SegmentedButton) =================
  Widget _buildCustomSegmentedControl({
    required List<String> labels,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (index) {
          final isSelected = selectedIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isSelected ? [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))
                  ] : [],
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ================= 网格化组件 (N*N Array UI Helpers) =================

  Widget _buildSquareTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 105,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.01),
                blurRadius: 10,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 26),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupSquareTile<T>({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required T value,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
  }) {
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: _buildSquareTile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        onTap: null, // Let PopupMenu handle it
      ),
    );
  }

  // 时间选择助手
  Future<void> _pickStartTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _createdAt,
    );
    if (pickedDate != null) {
      if (_isAllDay) {
        setState(() => _createdAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 0, 0));
      } else {
        if (!mounted) return;
        final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_createdAt));
        if (pickedTime != null) {
          setState(() => _createdAt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
        }
      }
    }
  }

  Future<void> _pickEndTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _dueDate ?? _createdAt,
    );
    if (pickedDate != null) {
      if (_isAllDay) {
        setState(() => _dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 23, 59));
      } else {
        if (!mounted) return;
        final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()));
        if (pickedTime != null) {
          setState(() => _dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.brightness == Brightness.light ? const Color(0xFFF2F2F7) : theme.colorScheme.surface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: SizedBox(
          width: 200,
          child: _buildCustomSegmentedControl(
            labels: const ["手动创建", "AI 识别"],
            selectedIndex: _selectedTabIndex,
            onChanged: (idx) => setState(() => _selectedTabIndex = idx),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _selectedTabIndex == 0 ? _addTodo : _addBatchTodos,
            child: const Text("完成", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _selectedTabIndex == 0
            ? _buildManualInputTab(key: const ValueKey('manual'))
            : _buildAIRecognitionTab(key: const ValueKey('ai')),
      ),
    );
  }

  Widget _buildManualInputTab({Key? key}) {
    return SingleChildScrollView(
      key: key,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 1. 核心标题与附件区 ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleCtrl,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(hintText: "准备做些什么？", border: InputBorder.none),
                ),
                const Divider(height: 1),
                TextField(
                  controller: _remarkCtrl,
                  style: const TextStyle(fontSize: 15),
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: "补充细节或备注...",
                    hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.8)),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                // 🚀 将附件功能融合进输入卡片内部
                if (_selectedImagePath == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextButton.icon(
                      onPressed: _pickAttachmentImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                      label: const Text("添加图片"),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.grey.shade600,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, top: 4),
                    child: Stack(
                      children: [
                        InkWell(
                          onTap: _pickAttachmentImage,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_selectedImagePath!),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                height: 80,
                                alignment: Alignment.center,
                                color: Colors.grey.shade100,
                                child: const Text('图片不可用，请重新选择'),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton.filled(
                            onPressed: () => setState(() => _selectedImagePath = null),
                            icon: const Icon(Icons.close, size: 16),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black45,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(4),
                              minimumSize: Size.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- 2. 时间与提醒网格 (2x2) ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("时间与提醒", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  const Text("全天事件", style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 24, // 紧凑的Switch
                    child: Switch(
                      value: _isAllDay,
                      onChanged: (val) {
                        setState(() {
                          _isAllDay = val;
                          if (_isAllDay) {
                            _createdAt = DateTime(_createdAt.year, _createdAt.month, _createdAt.day, 0, 0);
                            if (_dueDate != null) {
                              _dueDate = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day, 23, 59);
                            } else {
                              _dueDate = DateTime(_createdAt.year, _createdAt.month, _createdAt.day, 23, 59);
                            }
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSquareTile(
                title: "开始时间",
                subtitle: DateFormat(_isAllDay ? 'MM-dd' : 'MM-dd HH:mm').format(_createdAt),
                icon: Icons.play_circle_fill,
                color: Colors.blueAccent,
                onTap: _pickStartTime,
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildSquareTile(
                title: "截止时间",
                subtitle: _dueDate == null ? "未设置" : DateFormat(_isAllDay ? 'MM-dd' : 'MM-dd HH:mm').format(_dueDate!),
                icon: Icons.stop_circle_rounded,
                color: Colors.deepOrangeAccent,
                onTap: _pickEndTime,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildPopupSquareTile<int>(
                title: "任务提醒",
                subtitle: _getReminderText(_reminderMinutes),
                icon: Icons.notifications_active_rounded,
                color: Colors.purpleAccent,
                value: _reminderMinutes,
                items: [0, 5, 10, 15, 30, 45, 60, 120, 1440].map((m) =>
                    PopupMenuItem(value: m, child: Text(_getReminderText(m)))
                ).toList(),
                onSelected: (v) => setState(() => _reminderMinutes = v),
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildPopupSquareTile<RecurrenceType>(
                title: "循环规则",
                subtitle: _getRecurrenceLabel(_recurrence),
                icon: Icons.replay_rounded,
                color: Colors.teal,
                value: _recurrence,
                items: [RecurrenceType.none, RecurrenceType.daily, RecurrenceType.weekly, RecurrenceType.monthly, RecurrenceType.yearly, RecurrenceType.weekdays, RecurrenceType.customDays].map((r) =>
                    PopupMenuItem(value: r, child: Text(_getRecurrenceLabel(r)))
                ).toList(),
                onSelected: (v) => setState(() => _recurrence = v),
              )),
            ],
          ),

          // --- 循环附加选项 (条件显示) ---
          if (_recurrence == RecurrenceType.customDays || _recurrence != RecurrenceType.none)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
              ),
              child: Column(
                children: [
                  if (_recurrence == RecurrenceType.customDays) ...[
                    Row(
                      children: [
                        const Text("每隔"),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _customDaysCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onChanged: (val) => setState(() => _customDays = int.tryParse(val)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text("天重复"),
                      ],
                    ),
                    const Divider(height: 24),
                  ],
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _recurrenceEndDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _recurrenceEndDate = picked);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("循环截止日期"),
                        Row(
                          children: [
                            Text(
                              _recurrenceEndDate == null ? "未指定" : DateFormat('yyyy-MM-dd').format(_recurrenceEndDate!),
                              style: TextStyle(color: _recurrenceEndDate == null ? Colors.grey : Theme.of(context).colorScheme.primary),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // --- 3. 组织归属网格 (2xN) ---
          if (widget.todoGroups.isNotEmpty || _teams.isNotEmpty) ...[
            const Text("组织与协作", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.todoGroups.isNotEmpty)
                  Expanded(child: _buildPopupSquareTile<String>(
                    title: "归属文件夹",
                    subtitle: _selectedGroupId == null ? "未分类" : (widget.todoGroups.where((g) => g.id == _selectedGroupId).firstOrNull?.name ?? '未知'),
                    icon: Icons.folder_rounded,
                    color: Colors.amber.shade600,
                    // 🚀 核心修复：使用 "__none__" 避免 Menu 返回 null 而被忽略
                    value: _selectedGroupId ?? "__none__",
                    items: [
                      const PopupMenuItem<String>(value: "__none__", child: Text("未分类")),
                      ...widget.todoGroups.where((g) => !g.isDeleted).map((g) => PopupMenuItem(value: g.id, child: Text(g.name)))
                    ],
                    onSelected: (v) => setState(() {
                      _selectedGroupId = v == "__none__" ? null : v;
                      if (_selectedGroupId != null && _categoryReminderDefaults.containsKey(_selectedGroupId)) {
                        _reminderMinutes = _categoryReminderDefaults[_selectedGroupId]!;
                      } else if (_selectedGroupId == null) {
                        _reminderMinutes = 5;
                      }
                    }),
                  )),
                if (widget.todoGroups.isNotEmpty && _teams.isNotEmpty)
                  const SizedBox(width: 12),
                if (_teams.isNotEmpty)
                  Expanded(child: _buildPopupSquareTile<String>(
                    title: "团队归属",
                    subtitle: _selectedTeamUuid == null ? "个人私有" : (_teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name ?? '未知'),
                    icon: Icons.groups_rounded,
                    color: Colors.indigoAccent,
                    // 🚀 核心修复：使用 "__none__" 避免 Menu 返回 null 而被忽略
                    value: _selectedTeamUuid ?? "__none__",
                    items: [
                      const PopupMenuItem<String>(value: "__none__", child: Text("个人私有 (仅自己可见)")),
                      ..._teams.map((t) => PopupMenuItem(value: t.uuid, child: Text(t.name)))
                    ],
                    onSelected: (v) => setState(() {
                      _selectedTeamUuid = v == "__none__" ? null : v;
                      _selectedTeamName = _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name;
                    }),
                  )),
              ],
            ),
            if (_selectedTeamUuid != null)
              _buildCompactTeamSection(),
            const SizedBox(height: 24),
          ],

          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildCompactTeamSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("完成规则", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          SizedBox(
            width: 160,
            child: _buildCustomSegmentedControl(
              labels: const ["全队同步", "各自独立"],
              selectedIndex: _collabType,
              onChanged: (idx) => setState(() => _collabType = idx),
            ),
          ),
        ],
      ),
    );
  }

  // ================= AI 识别界面 (保持卡片风格) =================
  Widget _buildAIRecognitionTab({Key? key}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text("用自然语言描述你的计划", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _aiInputCtrl,
                    maxLines: 4,
                    minLines: 3,
                    decoration: const InputDecoration(
                      hintText: "例如：明天下午3点开会\n每周一早上9点做周报\n每天早上8点喝水，下午2点开会",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isParsing ? null : _doSmartParse,
                        icon: const Icon(Icons.bolt, size: 18),
                        label: _isParsing ? _buildBouncingDots() : const Text("本地速认"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isParsing ? null : _doLLMParse,
                        icon: const Icon(Icons.memory, size: 18),
                        label: _isParsing ? _buildBouncingDots() : const Text("大模型深思"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_parsedResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "解析结果 (${_currentParseIndex + 1}/${_parsedResults.length})",
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios, size: 16),
                            onPressed: _currentParseIndex > 0 ? () {
                              setState(() => _currentParseIndex--);
                              _applyParsedResult(_parsedResults[_currentParseIndex]);
                            } : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, size: 16),
                            onPressed: _currentParseIndex < _parsedResults.length - 1 ? () {
                              setState(() => _currentParseIndex++);
                              _applyParsedResult(_parsedResults[_currentParseIndex]);
                            } : null,
                          ),
                        ],
                      )
                    ],
                  ),
                  const Divider(),
                  _buildParseResultRow("待办", _parsedResults[_currentParseIndex].title),
                  _buildParseResultRow("时间", _parsedResults[_currentParseIndex].startTime != null
                      ? DateFormat('MM-dd HH:mm').format(_parsedResults[_currentParseIndex].startTime!)
                      : "未指定"),
                  _buildParseResultRow("重复", _getRecurrenceLabel(_parsedResults[_currentParseIndex].recurrence)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParseResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildBouncingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _dotsController,
          builder: (context, child) {
            final double value = _dotsController.value;
            final double delay = index * 0.2;
            final double animationValue = (value + delay) % 1.0;
            final double scale = 0.5 + 0.5 * (1.0 - (animationValue - 0.5).abs() * 2.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}