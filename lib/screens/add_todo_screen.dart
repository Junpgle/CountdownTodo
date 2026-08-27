import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/api_service.dart';
import '../services/todo_parser_service.dart';
import '../services/llm_service.dart';
import '../services/database_helper.dart';
import '../screens/home_settings_screen.dart';
import '../services/todo_classification_service.dart';
import '../services/item_semantics_service.dart';
import '../utils/time_utils.dart';
import '../utils/local_image_provider.dart';
import '../services/time_estimation_service.dart';
import '../services/suggestion_feedback_service.dart';
import '../services/feature_tip_service.dart';
import '../services/fixed_schedule_recurrence_service.dart';
import '../services/reminder_schedule_service.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/floating_bottom_bar.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import '../utils/persistent_image_storage.dart';
import '../utils/page_transitions.dart';
import 'dart:async';

enum _CaptureSaveTarget { todo, fixedSchedule, cancel }

enum _ManualCaptureKind { todo, fixedSchedule }

enum AddTodoInitialMode { todo, fixedSchedule }

class AddTodoScreen extends StatefulWidget {
  final Function(TodoItem) onTodoAdded;
  final Function(List<TodoItem>)? onTodosBatchAdded;
  final Future<void> Function(FixedScheduleItem)? onFixedScheduleAdded;
  final Function(
          List<Map<String, dynamic>>, String?, String?, String?, String?)?
      onLLMResultsParsed;
  final List<TodoGroup> todoGroups;
  final String? initialGroupId;
  final String? initialTeamUuid;
  final String? initialTeamName;
  final AddTodoInitialMode initialMode;

  const AddTodoScreen({
    super.key,
    required this.onTodoAdded,
    this.onTodosBatchAdded,
    this.onFixedScheduleAdded,
    this.onLLMResultsParsed,
    this.todoGroups = const [],
    this.initialGroupId,
    this.initialTeamUuid,
    this.initialTeamName,
    this.initialMode = AddTodoInitialMode.todo,
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
  _ManualCaptureKind _manualCaptureKind = _ManualCaptureKind.todo;
  late DateTime _scheduleDate;
  late TimeOfDay _scheduleStartTime;
  late TimeOfDay _scheduleEndTime;
  bool _scheduleTimeTbd = false;
  bool _scheduleEndTimeTbd = false;

  int _selectedTabIndex = 0;
  bool _isParsing = false;
  List<ParsedTodoResult> _parsedResults = [];
  int _currentParseIndex = 0;
  String? _currentOriginalText;
  String? _selectedImagePath;
  Map<String, dynamic>? _pendingTodoConfirm; // 🚀 待确认的图片识别事项

  final GlobalKey _aiTabSwitchKey = GlobalKey();
  final GlobalKey _attachmentKey = GlobalKey();
  final GlobalKey _allDayKey = GlobalKey();
  final GlobalKey _saveButtonKey = GlobalKey();
  bool _showCoachMarks = false;

  Future<void> _checkCoachMarks() async {
    if (_showCoachMarks || !mounted) return;
    final hasSeenCoachMarks =
        await FeatureTipService.hasTipBeenShown('coach_add_todo');
    if (hasSeenCoachMarks) return;
    if (mounted) {
      _showCoachMarks = true;
      CoachMarkOverlay.show(
        context: context,
        steps: [
          CoachMarkStep(
            targetKey: _aiTabSwitchKey,
            title: 'AI 智能识别',
            description: '除了手动创建外，您还可以切换到 AI 识别，通过文字、语音或截图提取事项，并区分待办、日程和规划块。',
          ),
          CoachMarkStep(
            targetKey: _attachmentKey,
            title: '添加图片附件',
            description: '可以为待办事项附带一张相关的图片。请注意：图片不会上传到云端，仅在本地展示。',
          ),
          CoachMarkStep(
            targetKey: _allDayKey,
            title: '日期待办与灵动岛',
            description: '没有具体时刻的待办会在目标日期集中展示。取餐、取件等事项会按“待领取”状态展示，不需要伪装成全天事件。',
          ),
          CoachMarkStep(
            targetKey: _saveButtonKey,
            title: '保存事项',
            description: '所有的信息都填写完毕后，点击这里就能将其保存到您的计划中了！',
          ),
        ],
        onFinish: _dismissCoachMarks,
        onSkip: _dismissCoachMarks,
      );
    }
  }

  Future<void> _dismissCoachMarks() async {
    if (!mounted) return;
    await FeatureTipService.markTipShown('coach_add_todo');
    _showCoachMarks = false;
  }

  Map<String, int> _categoryReminderDefaults = {};
  String? _username;
  List<Team> _teams = [];
  String? _selectedTeamUuid;
  int _collabType = 0;

  late AnimationController _dotsController;

  // Time estimation state
  TimeEstimationResult? _estimationResult;
  TodoClassificationSuggestion? _classificationSuggestion;
  Timer? _estimationDebounce;
  DateTime? _suggestedDueDate;
  List<TodoGroup> _localTodoGroups = [];

  @override
  void initState() {
    super.initState();
    _manualCaptureKind = widget.initialMode == AddTodoInitialMode.fixedSchedule
        ? _ManualCaptureKind.fixedSchedule
        : _ManualCaptureKind.todo;
    final now = DateTime.now();
    _scheduleDate = DateTime(now.year, now.month, now.day);
    _scheduleStartTime = const TimeOfDay(hour: 9, minute: 0);
    _scheduleEndTime = const TimeOfDay(hour: 10, minute: 0);
    _localTodoGroups = List.from(widget.todoGroups);
    if (_localTodoGroups.isEmpty) {
      _loadTodoGroups();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context);
      if (route != null && route.animation != null) {
        if (route.animation!.isCompleted) {
          _checkCoachMarks();
        } else {
          void listener(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              _checkCoachMarks();
              route.animation!.removeStatusListener(listener);
            }
          }

          route.animation!.addStatusListener(listener);
        }
      } else {
        _checkCoachMarks();
      }
    });
    _selectedGroupId = widget.initialGroupId;
    _selectedTeamUuid = widget.initialTeamUuid;
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
    _titleCtrl.addListener(_onTitleChanged);
    _remarkCtrl.addListener(_onTitleChanged);
    _loadCategoryDefaults().then((_) {
      if (_selectedGroupId != null &&
          _categoryReminderDefaults.containsKey(_selectedGroupId)) {
        setState(() {
          _reminderMinutes = _categoryReminderDefaults[_selectedGroupId]!;
        });
      }
    });
    _loadTeams();
    _loadPendingTodoConfirm();
  }

  Future<void> _loadTodoGroups() async {
    try {
      final groups = await DatabaseHelper.instance.getTodoGroups();
      if (mounted) {
        setState(() {
          _localTodoGroups = groups;
        });
      }
    } catch (e) {
      // debugPrint('[AddTodoScreen] Failed to load todo groups: $e');
    }
  }

  Future<void> _loadPendingTodoConfirm() async {
    final data = await StorageService.getPendingTodoConfirm();
    if (mounted && data != null) {
      final results = data['results'] as List<dynamic>?;
      if (results != null && results.isNotEmpty) {
        setState(() => _pendingTodoConfirm = data);
      }
    }
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
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.single;
      final filePath = pickedFile.path;
      final bytes = pickedFile.bytes;
      final imagePath = bytes != null
          ? _dataUrlFromPickedImage(pickedFile.name, bytes)
          : filePath;
      if (imagePath == null || imagePath.isEmpty) return;

      setState(() {
        _selectedImagePath = imagePath;
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
      final targetPath = await persistImagePath(sourcePath, 'todo_attachments');
      if (targetPath != null) {
        setState(() {
          _selectedImagePath = targetPath;
        });
      }
      return targetPath;
    } catch (e) {
      // debugPrint('❌ 持久化待办图片失败: $e');
      return null;
    }
  }

  String _dataUrlFromPickedImage(String name, List<int> bytes) {
    final ext = name.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
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
    _titleCtrl.removeListener(_onTitleChanged);
    _remarkCtrl.removeListener(_onTitleChanged);
    _estimationDebounce?.cancel();
    _titleCtrl.dispose();
    _remarkCtrl.dispose();
    _aiInputCtrl.dispose();
    _customDaysCtrl.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    _estimationDebounce?.cancel();
    if (_manualCaptureKind == _ManualCaptureKind.fixedSchedule) return;
    final text = _titleCtrl.text.trim();
    if (text.length < 2) {
      if (mounted &&
          (_estimationResult != null || _classificationSuggestion != null)) {
        setState(() {
          _estimationResult = null;
          _suggestedDueDate = null;
          _classificationSuggestion = null;
        });
      }
      return;
    }
    _estimationDebounce = Timer(const Duration(milliseconds: 500), () async {
      final result = await TimeEstimationService.estimate(
        text,
        groupId: _selectedGroupId,
      );
      if (mounted) {
        final classification = await TodoClassificationService.recommendForText(
          title: text,
          remark: _remarkCtrl.text,
          groups: _localTodoGroups,
          categoryReminderDefaults: _categoryReminderDefaults,
          dueDate: _dueDate,
        );
        setState(() {
          _estimationResult = result;
          _classificationSuggestion = classification;
          // Suggest due date (don't auto-fill)
          if (!_isAllDay) {
            _suggestedDueDate =
                _createdAt.add(Duration(minutes: result.estimatedMinutes));
          }
        });
      }
    });
  }

  RecurrenceType _parseRecurrenceType(String? type) {
    switch (type) {
      case 'daily':
        return RecurrenceType.daily;
      case 'weekly':
        return RecurrenceType.weekly;
      case 'monthly':
        return RecurrenceType.monthly;
      case 'yearly':
        return RecurrenceType.yearly;
      case 'weekdays':
        return RecurrenceType.weekdays;
      case 'customDays':
        return RecurrenceType.customDays;
      default:
        return RecurrenceType.none;
    }
  }

  ParsedTimeSemantics _parseTimeSemantics(
    dynamic raw, {
    required bool isAllDay,
    required DateTime? startTime,
    required DateTime? endTime,
  }) {
    if (isAllDay) return ParsedTimeSemantics.dateOnly;
    final name = raw?.toString();
    return ParsedTimeSemantics.values.firstWhere(
      (value) => value.name == name,
      orElse: () => startTime != null && endTime != null
          ? ParsedTimeSemantics.range
          : ParsedTimeSemantics.unscheduled,
    );
  }

  String _getRecurrenceLabel(RecurrenceType r) {
    switch (r) {
      case RecurrenceType.none:
        return "不循环";
      case RecurrenceType.daily:
        return "每天重复";
      case RecurrenceType.weekly:
        return "每周重复";
      case RecurrenceType.monthly:
        return "每月重复";
      case RecurrenceType.yearly:
        return "每年重复";
      case RecurrenceType.weekdays:
        return "工作日";
      case RecurrenceType.customDays:
        return "间隔 ${_customDays ?? '?'} 天";
    }
  }

  CaptureIntentKind _captureIntentForParsed(ParsedTodoResult result) {
    return ItemSemanticsService.classifyCaptureIntent(
      result.itemKind == null
          ? result.originalText ?? result.title
          : '${result.title} ${result.remark ?? ''}',
      declaredKind: result.itemKind,
    );
  }

  String _parsedKindLabel(ParsedTodoResult result) {
    return switch (_captureIntentForParsed(result)) {
      CaptureIntentKind.todo => '待办',
      CaptureIntentKind.fixedSchedule => '固定日程',
      CaptureIntentKind.planBlock => '规划块',
      CaptureIntentKind.needsConfirmation => '待确认',
    };
  }

  String _parsedTimeLabel(ParsedTodoResult result) {
    final intent = _captureIntentForParsed(result);
    if (intent == CaptureIntentKind.fixedSchedule) {
      if (result.isAllDay) {
        return result.startTime == null
            ? '日期待确认 · 时间待定'
            : '${DateFormat('MM-dd').format(result.startTime!)} · 时间待定';
      }
      if (result.startTime != null && result.endTime != null) {
        return '${DateFormat('MM-dd HH:mm').format(result.startTime!)}–${DateFormat('HH:mm').format(result.endTime!)}';
      }
      if (result.startTime != null) {
        return '${DateFormat('MM-dd HH:mm').format(result.startTime!)}开始 · 结束待定';
      }
      return '日期和时间待确认';
    }
    if (intent == CaptureIntentKind.planBlock) {
      return result.startTime != null && result.endTime != null
          ? '${DateFormat('MM-dd HH:mm').format(result.startTime!)}–${DateFormat('HH:mm').format(result.endTime!)}'
          : '规划时段待确认';
    }
    if (result.isAllDay && result.startTime != null) {
      return '${DateFormat('MM-dd').format(result.startTime!)}内完成';
    }
    if (result.endTime != null) {
      return '${DateFormat('MM-dd HH:mm').format(result.endTime!)}前完成';
    }
    return '未安排';
  }

  String _getReminderText(int minutes) {
    switch (minutes) {
      case 0:
        return "不提醒";
      case 5:
        return "提前 5 分钟";
      case 10:
        return "提前 10 分钟";
      case 15:
        return "提前 15 分钟";
      case 30:
        return "提前 30 分钟";
      case 45:
        return "提前 45 分钟";
      case 60:
        return "提前 1 小时";
      case 120:
        return "提前 2 小时";
      case 1440:
        return "提前 1 天";
      default:
        return "提前 $minutes 分钟";
    }
  }

  void _applyParsedResult(ParsedTodoResult result) {
    setState(() {
      _titleCtrl.text = result.title;
      _remarkCtrl.text = result.remark ?? "";
      _dueDate = null;
      if (result.startTime != null) {
        _createdAt = result.startTime!;
        if (result.isAllDay) {
          _createdAt =
              DateTime(_createdAt.year, _createdAt.month, _createdAt.day, 0, 0);
        }
      }
      if (result.endTime != null) {
        _dueDate = result.endTime;
      } else if (result.startTime != null && result.isAllDay) {
        _dueDate =
            DateTime(_createdAt.year, _createdAt.month, _createdAt.day, 23, 59);
      }
      _isAllDay = result.isAllDay;
      _recurrence = result.recurrence;
      _customDays = result.customIntervalDays;
      _recurrenceEndDate = result.recurrenceEndDate;
      if (_customDays != null) {
        _customDaysCtrl.text = _customDays.toString();
      } else {
        _customDaysCtrl.clear();
      }
      _reminderMinutes = result.reminderMinutes ??
          (result.itemKind == 'fixedSchedule' ? 15 : 5);
    });
  }

  Future<void> _doSmartParse() async {
    if (_aiInputCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("请输入事项内容")));
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
        final currentTeamName = _selectedTeamUuid != null
            ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name
            : null;
        widget.onLLMResultsParsed!(
            maps, null, _aiInputCtrl.text, _selectedTeamUuid, currentTeamName);
        return;
      }

      _applyParsedResult(_parsedResults[0]);
      setState(() => _selectedTabIndex = 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("解析成功，共${_parsedResults.length}个事项"),
            duration: const Duration(seconds: 2)));
      }
    }
  }

  Future<void> _doLLMParse() async {
    if (_aiInputCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("请输入事项内容")));
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("取消")),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("去配置")),
          ],
        ),
      );
      if (goToSettings == true && mounted) {
        Navigator.of(context)
            .push(PageTransitions.slideHorizontal(const SettingsPage()));
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
        final currentTeamName = _selectedTeamUuid != null
            ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull?.name
            : null;
        widget.onLLMResultsParsed!(results, null, _aiInputCtrl.text,
            _selectedTeamUuid, currentTeamName);
        return;
      }

      final parsedResultsList = results.map((result) {
        final startTime = result['startTime'] != null
            ? DateTime.tryParse(result['startTime'])
            : null;
        final endTime = result['endTime'] != null
            ? DateTime.tryParse(result['endTime'])
            : null;
        final isAllDay = result['isAllDay'] ?? false;
        return ParsedTodoResult(
          title: result['title'] ?? _aiInputCtrl.text,
          remark: result['remark'],
          location: result['location']?.toString(),
          isAllDay: isAllDay,
          startTime: startTime,
          endTime: endTime,
          timeSemantics: _parseTimeSemantics(
            result['timeMode'],
            isAllDay: isAllDay,
            startTime: startTime,
            endTime: endTime,
          ),
          recurrence: _parseRecurrenceType(result['recurrence']),
          customIntervalDays: result['customIntervalDays'],
          recurrenceEndDate: DateTime.tryParse(
            (result['recurrenceEndDate'] ?? result['recurrence_end_date'] ?? '')
                .toString(),
          ),
          reminderMinutes: result['reminderMinutes'],
          itemKind: result['itemKind']?.toString(),
          originalText: _aiInputCtrl.text,
        );
      }).toList();

      setState(() {
        _parsedResults = parsedResultsList;
        _currentParseIndex = 0;
        _isParsing = false;
        _currentOriginalText = _aiInputCtrl.text;
      });

      if (_parsedResults.isNotEmpty) {
        _applyParsedResult(_parsedResults[0]);
        setState(() => _selectedTabIndex = 0);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("大模型解析成功，共${_parsedResults.length}个事项"),
              duration: const Duration(seconds: 2)));
        }
      }
    } catch (e) {
      setState(() => _isParsing = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("大模型解析失败: $e")));
      }
    }
  }

  void _selectManualCaptureKind(int index) {
    final next =
        index == 1 ? _ManualCaptureKind.fixedSchedule : _ManualCaptureKind.todo;
    if (next == _ManualCaptureKind.fixedSchedule &&
        widget.onFixedScheduleAdded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前入口暂不支持保存日程')),
      );
      return;
    }
    _estimationDebounce?.cancel();
    setState(() {
      _manualCaptureKind = next;
      if (next == _ManualCaptureKind.fixedSchedule) {
        _estimationResult = null;
        _suggestedDueDate = null;
        _classificationSuggestion = null;
      }
    });
  }

  DateTime _scheduleAt(TimeOfDay time) => DateTime(
        _scheduleDate.year,
        _scheduleDate.month,
        _scheduleDate.day,
        time.hour,
        time.minute,
      );

  Future<void> _pickScheduleDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _scheduleDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _scheduleDate = picked;
      if (_recurrenceEndDate != null &&
          _recurrenceEndDate!.isBefore(_scheduleDate)) {
        _recurrenceEndDate = _scheduleDate;
      }
    });
  }

  Future<void> _pickScheduleStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduleStartTime,
    );
    if (picked != null && mounted) {
      setState(() => _scheduleStartTime = picked);
    }
  }

  Future<void> _pickScheduleEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduleEndTime,
    );
    if (picked != null && mounted) {
      setState(() => _scheduleEndTime = picked);
    }
  }

  Future<bool> _saveManualFixedSchedule() async {
    final start = _scheduleTimeTbd ? null : _scheduleAt(_scheduleStartTime);
    final end = _scheduleTimeTbd || _scheduleEndTimeTbd
        ? null
        : _scheduleAt(_scheduleEndTime);
    if (start != null && end != null && !end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return false;
    }

    final parsed = ParsedTodoResult(
      title: _titleCtrl.text.trim(),
      remark: _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
      isAllDay: _scheduleTimeTbd,
      startTime: _scheduleTimeTbd ? _scheduleDate : start,
      endTime: end,
      timeSemantics: _scheduleTimeTbd
          ? ParsedTimeSemantics.dateOnly
          : ParsedTimeSemantics.range,
      recurrence: _recurrence,
      customIntervalDays: _customDays,
      recurrenceEndDate: _recurrenceEndDate,
      reminderMinutes: _reminderMinutes,
      originalText: _currentOriginalText,
    );
    return _saveFixedScheduleFromText(
      _currentOriginalText ?? _titleCtrl.text,
      parsedResult: parsed,
      source: FixedScheduleSource.manual,
    );
  }

  Future<void> _addTodo() async {
    if (_titleCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _manualCaptureKind == _ManualCaptureKind.fixedSchedule
              ? '请输入日程名称'
              : '请输入待办内容',
        ),
      ));
      return;
    }
    if (_manualCaptureKind == _ManualCaptureKind.fixedSchedule) {
      final saved = await _saveManualFixedSchedule();
      if (saved && mounted) Navigator.pop(context);
      return;
    }
    final sourceText = _currentOriginalText ?? _titleCtrl.text;
    final currentParsed =
        _parsedResults.isEmpty ? null : _parsedResults[_currentParseIndex];
    final saveTarget = await _confirmCaptureIntent(
      sourceText,
      declaredKind: currentParsed?.itemKind,
      semanticText: '${_titleCtrl.text} ${_remarkCtrl.text}',
    );
    if (saveTarget == _CaptureSaveTarget.cancel) return;
    if (saveTarget == _CaptureSaveTarget.fixedSchedule) {
      final hasParsedDate = currentParsed?.startTime != null ||
          currentParsed?.endTime != null ||
          _isAllDay ||
          _dueDate != null;
      final editedParsed = currentParsed == null
          ? null
          : ParsedTodoResult(
              title: _titleCtrl.text.trim(),
              remark: _remarkCtrl.text.trim().isEmpty
                  ? null
                  : _remarkCtrl.text.trim(),
              location: currentParsed.location,
              isAllDay: _isAllDay,
              startTime: hasParsedDate ? _createdAt : null,
              endTime: _dueDate,
              timeSemantics: currentParsed.timeSemantics,
              recurrence: _recurrence,
              customIntervalDays: _customDays,
              recurrenceEndDate: _recurrenceEndDate,
              reminderMinutes: _reminderMinutes,
              itemKind: currentParsed.itemKind,
              originalText: sourceText,
            );
      final saved = await _saveFixedScheduleFromText(
        sourceText,
        parsedResult: editedParsed,
      );
      if (saved && mounted) Navigator.pop(context);
      return;
    }

    final normalizedTime = TodoItem.normalizeTimeForWrite(
      selectedDate: _createdAt,
      dueDate: _dueDate,
      isDateOnly: _isAllDay,
    );
    if (_recurrence != RecurrenceType.none && normalizedTime.start == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重复待办需要先设置首次完成日期')),
      );
      return;
    }

    final persistentImagePath = await _persistAttachmentImageIfNeeded();
    final selectedTeam = _selectedTeamUuid != null
        ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull
        : null;

    final todo = TodoItem(
      title: _titleCtrl.text,
      recurrence: _recurrence,
      customIntervalDays: _customDays,
      recurrenceEndDate: _recurrenceEndDate,
      dueDate: normalizedTime.due,
      createdDate: normalizedTime.start?.millisecondsSinceEpoch,
      remark: _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
      originalText: _currentOriginalText,
      imagePath: persistentImagePath,
      groupId: _selectedGroupId,
      reminderMinutes: _reminderMinutes,
      teamUuid: _selectedTeamUuid,
      teamName: selectedTeam?.name,
      creatorName: _username,
      collabType: _collabType,
      isAllDay: _isAllDay,
    );

    widget.onTodoAdded(todo);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<_CaptureSaveTarget> _confirmCaptureIntent(
    String sourceText, {
    String? declaredKind,
    String? semanticText,
  }) async {
    final intent = ItemSemanticsService.classifyCaptureIntent(
      declaredKind == null ? sourceText : semanticText ?? sourceText,
      declaredKind: declaredKind,
    );
    if (intent == CaptureIntentKind.todo || !mounted) {
      return _CaptureSaveTarget.todo;
    }

    final (title, message) = switch (intent) {
      CaptureIntentKind.fixedSchedule => (
          '识别为固定日程',
          widget.onFixedScheduleAdded == null
              ? '考试、会议或预约属于不可自由移动的固定日程。当前入口尚未连接固定日程存储，继续会暂存为待办。'
              : '考试、会议或预约属于不可自由移动的固定日程，可以直接按固定日程保存。',
        ),
      CaptureIntentKind.planBlock => (
          '识别为规划时段',
          '这个时间段更适合关联到待办的规划块。现在继续只会保存待办，不会占用规划日历。',
        ),
      CaptureIntentKind.needsConfirmation => (
          '需要确认时间性质',
          '无法确定这是外部固定日程，还是你可以调整的规划时段。现在继续会暂存为待办。',
        ),
      CaptureIntentKind.todo => ('', ''),
    };

    return await showDialog<_CaptureSaveTarget>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _CaptureSaveTarget.cancel),
                child: const Text('返回调整'),
              ),
              if (intent == CaptureIntentKind.fixedSchedule &&
                  widget.onFixedScheduleAdded != null)
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _CaptureSaveTarget.fixedSchedule,
                  ),
                  child: const Text('保存为固定日程'),
                ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _CaptureSaveTarget.todo),
                child: const Text('暂存为待办'),
              ),
            ],
          ),
        ) ??
        _CaptureSaveTarget.cancel;
  }

  Future<bool> _saveFixedScheduleFromText(
    String sourceText, {
    ParsedTodoResult? parsedResult,
    FixedScheduleSource? source,
  }) async {
    final callback = widget.onFixedScheduleAdded;
    if (callback == null) return false;
    final parsed = parsedResult ?? TodoParserService.parse(sourceText);
    final dateSource = parsed.startTime ?? parsed.endTime ?? _dueDate;
    if (dateSource == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('固定日程需要先确认日期')),
        );
      }
      return false;
    }
    DateTime? start = parsed.startTime;
    DateTime? end = parsed.endTime;
    if (parsed.isAllDay) {
      start = null;
      end = null;
    } else if (parsed.timeSemantics == ParsedTimeSemantics.deadline &&
        end != null) {
      // 单一时刻在待办解析中表示截止点；对固定日程则表示开始时刻，
      // 结束时间保持待定，不能静默补出一小时。
      start = end;
      end = null;
    } else if (start == null && _dueDate != null) {
      start = _dueDate;
    }

    final reminderMinutes = parsed.reminderMinutes ?? _reminderMinutes;
    final resolvedSource = source ??
        (parsedResult == null
            ? FixedScheduleSource.manual
            : FixedScheduleSource.ai);
    final item = FixedScheduleItem(
      title: parsed.title.trim().isEmpty ? _titleCtrl.text : parsed.title,
      date: DateFormat('yyyy-MM-dd').format(dateSource),
      startTime: start?.millisecondsSinceEpoch,
      endTime: end?.millisecondsSinceEpoch,
      source: resolvedSource,
      location: parsed.location,
      remark: _remarkCtrl.text.trim().isNotEmpty
          ? _remarkCtrl.text.trim()
          : (parsed.remark?.trim().isNotEmpty == true
              ? parsed.remark!.trim()
              : null),
      reminderMinutes: reminderMinutes < 0 ||
              (resolvedSource == FixedScheduleSource.manual &&
                  reminderMinutes == 0)
          ? const []
          : [reminderMinutes],
      timezone: DateTime.now().timeZoneName,
      recurrence: parsed.recurrence,
      recurrenceSeriesId: null,
      teamUuid: _selectedTeamUuid,
    );
    if (item.recurrence != RecurrenceType.none) {
      item.recurrenceSeriesId = item.id;
    }
    if (item.recurrence == RecurrenceType.none) {
      await callback(item);
      final username = _username ?? await StorageService.getLoginSession();
      if (username != null) {
        await ReminderScheduleService.scheduleFromStorage(
          username,
          force: true,
        );
      }
      return true;
    }
    final recurrenceEnd = parsed.recurrenceEndDate ??
        FixedScheduleRecurrenceService.defaultEndDate(
          startDate: dateSource,
          recurrence: item.recurrence,
          customIntervalDays: parsed.customIntervalDays ?? 1,
        );
    late final ({
      List<FixedScheduleItem> active,
      List<FixedScheduleItem> changes,
    }) series;
    try {
      series = FixedScheduleRecurrenceService.rebuildSeries(
        template: item,
        existingSeries: const [],
        recurrence: item.recurrence,
        recurrenceEndDate: recurrenceEnd,
        customIntervalDays: parsed.customIntervalDays ?? 1,
      );
    } on FixedScheduleRecurrenceLimitException catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return false;
    }
    final username = _username ?? await StorageService.getLoginSession();
    if (username != null) {
      await StorageService.saveFixedSchedules(username, series.changes);
      await callback(series.active.first);
    } else {
      for (final occurrence in series.active) {
        await callback(occurrence);
      }
    }
    final reminderUsername =
        _username ?? await StorageService.getLoginSession();
    if (reminderUsername != null) {
      await ReminderScheduleService.scheduleFromStorage(
        reminderUsername,
        force: true,
      );
    }
    return true;
  }

  Future<void> _addBatchTodos() async {
    if (_parsedResults.isEmpty) return;

    final todoResults = <ParsedTodoResult>[];
    for (final result in _parsedResults) {
      final sourceText = result.originalText ?? result.title;
      final saveTarget = await _confirmCaptureIntent(
        sourceText,
        declaredKind: result.itemKind,
        semanticText: '${result.title} ${result.remark ?? ''}',
      );
      if (saveTarget == _CaptureSaveTarget.cancel) return;
      if (saveTarget == _CaptureSaveTarget.fixedSchedule) {
        await _saveFixedScheduleFromText(
          sourceText,
          parsedResult: result,
        );
      } else {
        todoResults.add(result);
      }
    }

    final persistentImagePath = await _persistAttachmentImageIfNeeded();
    final selectedTeam = _selectedTeamUuid != null
        ? _teams.where((t) => t.uuid == _selectedTeamUuid).firstOrNull
        : null;

    final List<TodoItem> todos = [];
    for (final r in todoResults) {
      final parsedDueDate = r.endTime ??
          (r.isAllDay && r.startTime != null
              ? DateTime(
                  r.startTime!.year,
                  r.startTime!.month,
                  r.startTime!.day,
                  23,
                  59,
                )
              : null);
      final normalizedTime = TodoItem.normalizeTimeForWrite(
        selectedDate: r.startTime,
        dueDate: parsedDueDate,
        isDateOnly: r.isAllDay,
      );
      if (r.recurrence != RecurrenceType.none && normalizedTime.start == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('“${r.title}”是重复待办，请先设置首次完成日期')),
        );
        return;
      }
      final classification = await TodoClassificationService.recommendForText(
        title: r.title,
        remark: r.remark ?? '',
        groups: _localTodoGroups,
        categoryReminderDefaults: _categoryReminderDefaults,
        dueDate: parsedDueDate,
      );
      final suggestedGroupId =
          classification.confidence >= 0.20 ? classification.groupId : null;
      todos.add(TodoItem(
        title: r.title,
        recurrence: r.recurrence,
        customIntervalDays: r.customIntervalDays,
        recurrenceEndDate: r.recurrenceEndDate,
        dueDate: normalizedTime.due,
        createdDate: normalizedTime.start?.millisecondsSinceEpoch,
        remark: r.remark,
        originalText: _currentOriginalText,
        imagePath: persistentImagePath,
        groupId: suggestedGroupId,
        reminderMinutes: r.reminderMinutes ??
            (suggestedGroupId != null
                ? classification.reminderMinutes
                : _reminderMinutes),
        teamUuid: _selectedTeamUuid,
        teamName: selectedTeam?.name,
        creatorName: _username,
        collabType: _collabType,
        isAllDay: r.isAllDay,
      ));
    }

    if (todos.isNotEmpty) {
      if (widget.onTodosBatchAdded != null) {
        widget.onTodosBatchAdded!(todos);
      } else {
        for (var t in todos) {
          widget.onTodoAdded(t);
        }
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
    bool floating = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: floating
            ? colorScheme.surface.withValues(alpha: 0)
            : colorScheme.onSurface.withValues(alpha: 0.08),
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
                  color: isSelected
                      ? (floating
                          ? colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.72)
                          : colorScheme.surface)
                      : colorScheme.surface.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isSelected && !floating
                      ? [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1))
                        ]
                      : [],
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.6),
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
        setState(() {
          _createdAt =
              DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 0, 0);
          _dueDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            23,
            59,
          );
        });
      } else {
        if (!mounted) return;
        final pickedTime = await showTimePicker(
            context: context, initialTime: TimeOfDay.fromDateTime(_createdAt));
        if (pickedTime != null) {
          setState(() {
            _createdAt = DateTime(pickedDate.year, pickedDate.month,
                pickedDate.day, pickedTime.hour, pickedTime.minute);
            _updateSuggestedDueDate();
          });
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
        setState(() {
          _dueDate = DateTime(
              pickedDate.year, pickedDate.month, pickedDate.day, 23, 59);
          _suggestedDueDate = null;
        });
      } else {
        if (!mounted) return;
        final pickedTime = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()));
        if (pickedTime != null) {
          setState(() {
            _dueDate = DateTime(pickedDate.year, pickedDate.month,
                pickedDate.day, pickedTime.hour, pickedTime.minute);
            _suggestedDueDate = null;
          });
        }
      }
    }
  }

  /// Re-compute suggested due date when start time changes
  void _updateSuggestedDueDate() {
    if (_estimationResult != null && !_isAllDay) {
      _suggestedDueDate = _createdAt
          .add(Duration(minutes: _estimationResult!.estimatedMinutes));
    }
  }

  bool get _hasAISuggestions =>
      _estimationResult != null || _classificationSuggestion != null;

  void _acceptDueDateSuggestion() {
    if (_suggestedDueDate != null) {
      setState(() {
        _dueDate = _suggestedDueDate;
        _suggestedDueDate = null;
      });
    }
  }

  Widget _buildAISuggestionCard() {
    if (!_hasAISuggestions) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    final est = _estimationResult;
    final clsSug = _classificationSuggestion;
    final hasDueDate = _suggestedDueDate != null && !_isAllDay;

    // Check if classification suggestion is meaningful
    final hasNewGroup =
        clsSug != null && clsSug.hasGroup && clsSug.groupId != _selectedGroupId;
    final hasClassification =
        hasNewGroup || (clsSug != null && clsSug.tags.isNotEmpty);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.4),
            cs.primaryContainer.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: cs.primary.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with a "Pro" feel
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.secondary],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'AI INSIGHT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '智能建议',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _recordNegativeClassificationFeedback();
                  setState(() {
                    _estimationResult = null;
                    _suggestedDueDate = null;
                    _classificationSuggestion = null;
                  });
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '忽略',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Duration suggestion
          if (est != null)
            _buildSuggestionItem(
              icon: Icons.timer_outlined,
              label: '预估耗时: ~${formatMinutesChinese(est.estimatedMinutes)}',
              sub: _estimationConfidenceLabel(est),
              subColor: _estimationConfidenceColor(est),
              showAccept: false,
            ),

          // Due date suggestion
          if (hasDueDate)
            _buildSuggestionItem(
              icon: Icons.calendar_today_rounded,
              label:
                  "建议截止: ${DateFormat('MM-dd HH:mm').format(_suggestedDueDate!)}",
              showAccept: true,
              onAccept: _acceptDueDateSuggestion,
              accentColor: Colors.deepOrangeAccent,
            ),

          // Classification suggestion
          if (hasClassification) ...[
            _buildSuggestionItem(
              icon: Icons.auto_graph_rounded,
              label: '分类与标签建议',
              showAccept: true,
              onAccept: _applyClassificationSuggestion,
              accentColor: cs.primary,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (hasNewGroup)
                    _buildMiniChip(
                      Icons.folder_special_rounded,
                      clsSug.groupName ?? '未分类',
                      Colors.amber.shade700,
                    ),
                  _buildMiniChip(
                    Icons.priority_high_rounded,
                    clsSug.priorityLabel,
                    clsSug.priority >= 4 ? Colors.redAccent : Colors.blueGrey,
                  ),
                  ...clsSug.tags.map(
                    (tag) => _buildMiniChip(Icons.tag_rounded, tag, cs.primary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionItem({
    required IconData icon,
    required String label,
    String? sub,
    Color? subColor,
    required bool showAccept,
    VoidCallback? onAccept,
    Color? accentColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: (accentColor ?? cs.primary).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: accentColor ?? cs.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color:
                              subColor?.withValues(alpha: 0.7) ?? Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (showAccept)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAccept,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (accentColor ?? cs.primary).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (accentColor ?? cs.primary).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '采纳',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: accentColor ?? cs.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  String _estimationConfidenceLabel(TimeEstimationResult est) {
    final pct = (est.confidence * 100).round();
    if (est.confidence >= 0.6) return '高置信度 $pct%';
    if (est.confidence >= 0.35) return '中置信度 $pct%';
    return '低置信度 $pct%';
  }

  Color _estimationConfidenceColor(TimeEstimationResult est) {
    if (est.confidence >= 0.6) return Colors.green;
    if (est.confidence >= 0.35) return Colors.orange;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.brightness == Brightness.light
        ? const Color(0xFFF2F2F7)
        : theme.colorScheme.surface;
    final useFloatingBottomBar = floatingBottomBarShouldFloat(context);

    return Scaffold(
      extendBody: useFloatingBottomBar,
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: SizedBox(
          width: 200,
          child: KeyedSubtree(
            key: _aiTabSwitchKey,
            child: _buildCustomSegmentedControl(
              labels: const ["手动创建", "AI 识别"],
              selectedIndex: _selectedTabIndex,
              onChanged: (idx) => setState(() => _selectedTabIndex = idx),
            ),
          ),
        ),
        actions: [
          KeyedSubtree(
            key: _saveButtonKey,
            child: TextButton(
              onPressed: _selectedTabIndex == 0 ? _addTodo : _addBatchTodos,
              child: const Text("完成",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: useFloatingBottomBar && _selectedTabIndex == 0
          ? _buildManualKindBottomBar()
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _selectedTabIndex == 0
            ? _buildManualInputTab(key: const ValueKey('manual'))
            : _buildAIRecognitionTab(key: const ValueKey('ai')),
      ),
    );
  }

  List<String> _extractKeywords() {
    final text = _titleCtrl.text.trim().toLowerCase();
    final tokens = <String>[];
    for (final m in RegExp(r'[a-z0-9]+').allMatches(text)) {
      if (m.group(0)!.length >= 2) tokens.add(m.group(0)!);
    }
    for (final m in RegExp(r'[一-鿿]+').allMatches(text)) {
      final seg = m.group(0)!;
      for (int i = 0; i < seg.length; i++) {
        tokens.add(seg[i]);
      }
      for (int i = 0; i < seg.length - 1; i++) {
        tokens.add(seg.substring(i, i + 2));
      }
    }
    return tokens;
  }

  void _applyClassificationSuggestion() {
    final suggestion = _classificationSuggestion;
    if (suggestion == null) return;
    final kws = _extractKeywords();
    // Record positive feedback
    if (suggestion.hasGroup) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: suggestion.groupId!,
        accepted: true,
      );
    }
    SuggestionFeedbackService.record(
      keywords: kws,
      suggestionType: 'priority',
      suggestedValue: '${suggestion.priority}',
      accepted: true,
    );
    for (final tag in suggestion.tags) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'tag',
        suggestedValue: tag,
        accepted: true,
      );
    }
    setState(() {
      if (suggestion.hasGroup) {
        _selectedGroupId = suggestion.groupId;
      }
      if (suggestion.reminderMinutes != null) {
        _reminderMinutes = suggestion.reminderMinutes!;
      }
      _classificationSuggestion = null;
    });
  }

  void _recordNegativeClassificationFeedback() {
    final suggestion = _classificationSuggestion;
    if (suggestion == null) return;
    final kws = _extractKeywords();
    if (suggestion.hasGroup) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: suggestion.groupId!,
        accepted: false,
      );
    }
    SuggestionFeedbackService.record(
      keywords: kws,
      suggestionType: 'priority',
      suggestedValue: '${suggestion.priority}',
      accepted: false,
    );
    for (final tag in suggestion.tags) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'tag',
        suggestedValue: tag,
        accepted: false,
      );
    }
  }

  /// Record user's manual group selection as positive feedback,
  /// and negative feedback for the AI-suggested group if different.
  void _recordUserGroupChoice(String? chosenGroupId) {
    if (chosenGroupId == null) return;
    final kws = _extractKeywords();
    if (kws.isEmpty) return;

    // Positive feedback for user's choice
    SuggestionFeedbackService.record(
      keywords: kws,
      suggestionType: 'group',
      suggestedValue: chosenGroupId,
      accepted: true,
    );

    // Negative feedback for AI suggestion if user chose differently
    final suggestion = _classificationSuggestion;
    if (suggestion != null &&
        suggestion.hasGroup &&
        suggestion.groupId != chosenGroupId) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: suggestion.groupId!,
        accepted: false,
      );
    }
  }

  Widget _buildResponsiveGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = MediaQuery.of(context).size.width > 600;
        if (!isWide) {
          List<Widget> colChildren = [];
          for (int i = 0; i < children.length; i++) {
            colChildren.add(children[i]);
            if (i < children.length - 1) {
              colChildren.add(const Divider(height: 1));
            }
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: colChildren);
        } else {
          return Wrap(
            children: children
                .map((c) => SizedBox(width: constraints.maxWidth / 2, child: c))
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildManualInputTab({Key? key}) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final useFloatingBottomBar = floatingBottomBarShouldFloat(context);
      return SingleChildScrollView(
        key: key,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type Switcher
            if (!useFloatingBottomBar) ...[
              Center(
                child: SizedBox(
                  width: 200,
                  child: _buildCustomSegmentedControl(
                    labels: const ["待办", "日程"],
                    selectedIndex:
                        _manualCaptureKind == _ManualCaptureKind.todo ? 0 : 1,
                    onChanged: _selectManualCaptureKind,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Input Section
            OptionalLiquidGlassCard(
              borderRadius: 16,
              highContrast: true,
              fallbackDecoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.fromBorderSide(BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: _manualCaptureKind == _ManualCaptureKind.todo
                            ? "准备做些什么？"
                            : "要记录什么日程？",
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                    if (_manualCaptureKind == _ManualCaptureKind.todo)
                      _buildAISuggestionCard(),
                    const Divider(height: 24),
                    TextField(
                      controller: _remarkCtrl,
                      style: const TextStyle(fontSize: 15),
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: "补充细节或备注...",
                        border: InputBorder.none,
                        isDense: true,
                        hintStyle: TextStyle(
                            color: Colors.grey.withValues(alpha: 0.8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_manualCaptureKind == _ManualCaptureKind.todo &&
                        _selectedImagePath == null)
                      KeyedSubtree(
                        key: _attachmentKey,
                        child: TextButton.icon(
                          onPressed: _pickAttachmentImage,
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 20),
                          label: const Text("添加图片"),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            visualDensity: VisualDensity.compact,
                            foregroundColor: colors.primary,
                          ),
                        ),
                      )
                    else if (_manualCaptureKind == _ManualCaptureKind.todo)
                      Stack(
                        children: [
                          InkWell(
                            onTap: _pickAttachmentImage,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: localImageWidget(
                                _selectedImagePath!,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton.filled(
                              onPressed: () =>
                                  setState(() => _selectedImagePath = null),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Properties
            ...[
              // Todo Properties
              OptionalLiquidGlassCard(
                borderRadius: 16,
                highContrast: true,
                fallbackDecoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.fromBorderSide(BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: _buildResponsiveGrid(
                    [
                      if (_manualCaptureKind == _ManualCaptureKind.todo) ...[
                        SwitchListTile(
                          title: const Text("某天内完成"),
                          subtitle: const Text("不指定具体时刻"),
                          value: _isAllDay,
                          secondary: KeyedSubtree(
                              key: _allDayKey,
                              child: const Icon(Icons.calendar_today)),
                          onChanged: (val) {
                            setState(() {
                              final wasDateOnlyRange = _dueDate != null &&
                                  TodoItem.looksLikeLegacyDateOnlyRange(
                                      _createdAt, _dueDate!);
                              _isAllDay = val;
                              if (_isAllDay) {
                                _createdAt = DateTime(_createdAt.year,
                                    _createdAt.month, _createdAt.day, 0, 0);
                                if (_dueDate != null) {
                                  _dueDate = DateTime(_dueDate!.year,
                                      _dueDate!.month, _dueDate!.day, 23, 59);
                                } else {
                                  _dueDate = DateTime(_createdAt.year,
                                      _createdAt.month, _createdAt.day, 23, 59);
                                }
                              } else if (wasDateOnlyRange) {
                                final now = DateTime.now();
                                _createdAt = DateTime(
                                    _createdAt.year,
                                    _createdAt.month,
                                    _createdAt.day,
                                    now.hour,
                                    now.minute);
                                _dueDate = null;
                              }
                            });
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.event),
                          title: Text(_isAllDay ? "完成日期" : "截止时间"),
                          subtitle: Text(_isAllDay
                              ? DateFormat('MM-dd').format(_createdAt)
                              : (_dueDate == null
                                  ? "未安排"
                                  : "${DateFormat('MM-dd HH:mm').format(_dueDate!)} 前完成")),
                          trailing: _dueDate != null && !_isAllDay
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _dueDate = null),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: _isAllDay ? _pickStartTime : _pickEndTime,
                        ),
                      ] else ...[
                        ListTile(
                          key: const ValueKey('fixed-schedule-date'),
                          leading: const Icon(Icons.calendar_today_rounded),
                          title: Text(_recurrence == RecurrenceType.none
                              ? '日期'
                              : '首次日期'),
                          subtitle: Text(
                              DateFormat('yyyy-MM-dd').format(_scheduleDate)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('时间待定'),
                              const SizedBox(width: 6),
                              Switch(
                                key: const ValueKey('fixed-schedule-time-tbd'),
                                value: _scheduleTimeTbd,
                                onChanged: (value) =>
                                    setState(() => _scheduleTimeTbd = value),
                              ),
                            ],
                          ),
                          onTap: _pickScheduleDate,
                        ),
                        if (!_scheduleTimeTbd) ...[
                          ListTile(
                            key: const ValueKey('fixed-schedule-start-time'),
                            leading:
                                const Icon(Icons.play_circle_outline_rounded),
                            title: const Text('开始时间'),
                            subtitle: Text(_scheduleStartTime.format(context)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _pickScheduleStartTime,
                          ),
                          ListTile(
                            key: const ValueKey('fixed-schedule-end-time'),
                            leading: const Icon(Icons.stop_circle_outlined),
                            title: const Text('结束时间'),
                            subtitle: Text(_scheduleEndTimeTbd
                                ? '待定'
                                : _scheduleEndTime.format(context)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('待定'),
                                const SizedBox(width: 6),
                                Switch(
                                  key: const ValueKey(
                                      'fixed-schedule-end-time-tbd'),
                                  value: _scheduleEndTimeTbd,
                                  onChanged: (value) => setState(
                                      () => _scheduleEndTimeTbd = value),
                                ),
                              ],
                            ),
                            onTap: _scheduleEndTimeTbd
                                ? null
                                : _pickScheduleEndTime,
                          ),
                        ],
                      ],
                      ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text("提醒"),
                        subtitle: Text(_getReminderText(_reminderMinutes)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final val = await showMenu<int>(
                            context: context,
                            position:
                                const RelativeRect.fromLTRB(100, 400, 0, 0),
                            items: [0, 5, 10, 15, 30, 45, 60, 120, 1440]
                                .map((m) => PopupMenuItem(
                                    value: m, child: Text(_getReminderText(m))))
                                .toList(),
                          );
                          if (val != null) {
                            setState(() => _reminderMinutes = val);
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.repeat),
                        title: const Text("重复规则"),
                        subtitle: Text(_getRecurrenceLabel(_recurrence)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final val = await showMenu<RecurrenceType>(
                            context: context,
                            position:
                                const RelativeRect.fromLTRB(100, 500, 0, 0),
                            items: [
                              RecurrenceType.none,
                              RecurrenceType.daily,
                              RecurrenceType.weekly,
                              RecurrenceType.monthly,
                              RecurrenceType.yearly,
                              RecurrenceType.weekdays,
                              RecurrenceType.customDays
                            ]
                                .map((r) => PopupMenuItem(
                                    value: r,
                                    child: Text(_getRecurrenceLabel(r))))
                                .toList(),
                          );
                          if (val != null) setState(() => _recurrence = val);
                        },
                      ),
                      if (_recurrence == RecurrenceType.customDays ||
                          _recurrence != RecurrenceType.none)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 8),
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                        ),
                                        onChanged: (val) => setState(() =>
                                            _customDays = int.tryParse(val)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text("天重复"),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        _recurrenceEndDate ?? DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() => _recurrenceEndDate = picked);
                                  }
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("重复结束日期"),
                                      Row(
                                        children: [
                                          Text(
                                            _recurrenceEndDate == null
                                                ? "未指定"
                                                : DateFormat('yyyy-MM-dd')
                                                    .format(
                                                        _recurrenceEndDate!),
                                            style: TextStyle(
                                                color:
                                                    _recurrenceEndDate == null
                                                        ? Colors.grey
                                                        : colors.primary),
                                          ),
                                          const Icon(Icons.chevron_right,
                                              color: Colors.grey, size: 20),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Group and Team
            if ((_manualCaptureKind == _ManualCaptureKind.todo &&
                    _localTodoGroups.isNotEmpty) ||
                _teams.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text("组织与协作",
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
              OptionalLiquidGlassCard(
                borderRadius: 16,
                highContrast: true,
                fallbackDecoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.fromBorderSide(BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.5))),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: _buildResponsiveGrid(
                    [
                      if (_manualCaptureKind == _ManualCaptureKind.todo &&
                          _localTodoGroups.isNotEmpty)
                        ListTile(
                          leading: Icon(Icons.folder_outlined,
                              color: colors.primary),
                          title: const Text("归属文件夹"),
                          subtitle: Text(_selectedGroupId == null
                              ? "未分类"
                              : (_localTodoGroups
                                      .where((g) => g.id == _selectedGroupId)
                                      .firstOrNull
                                      ?.name ??
                                  '未知')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final val = await showMenu<String>(
                              context: context,
                              position:
                                  const RelativeRect.fromLTRB(100, 600, 0, 0),
                              items: [
                                const PopupMenuItem<String>(
                                    value: "__none__", child: Text("未分类")),
                                ..._localTodoGroups
                                    .where((g) => !g.isDeleted)
                                    .map((g) => PopupMenuItem(
                                        value: g.id, child: Text(g.name)))
                              ],
                            );
                            if (val != null) {
                              final newGroupId = val == "__none__" ? null : val;
                              _recordUserGroupChoice(newGroupId);
                              setState(() {
                                _selectedGroupId = newGroupId;
                                if (_selectedGroupId != null &&
                                    _categoryReminderDefaults
                                        .containsKey(_selectedGroupId)) {
                                  _reminderMinutes = _categoryReminderDefaults[
                                      _selectedGroupId]!;
                                } else if (_selectedGroupId == null) {
                                  _reminderMinutes = 5;
                                }
                              });
                            }
                          },
                        ),
                      if (_teams.isNotEmpty)
                        ListTile(
                          leading: Icon(Icons.groups_outlined,
                              color: colors.secondary),
                          title: const Text("团队归属"),
                          subtitle: Text(_selectedTeamUuid == null
                              ? "个人私有"
                              : (_teams
                                      .where((t) => t.uuid == _selectedTeamUuid)
                                      .firstOrNull
                                      ?.name ??
                                  '未知')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final val = await showMenu<String>(
                              context: context,
                              position:
                                  const RelativeRect.fromLTRB(100, 650, 0, 0),
                              items: [
                                const PopupMenuItem<String>(
                                    value: "__none__",
                                    child: Text("个人私有 (仅自己可见)")),
                                ..._teams.map((t) => PopupMenuItem(
                                    value: t.uuid, child: Text(t.name)))
                              ],
                            );
                            if (val != null) {
                              setState(() => _selectedTeamUuid =
                                  val == "__none__" ? null : val);
                            }
                          },
                        ),
                      if (_manualCaptureKind == _ManualCaptureKind.todo &&
                          _selectedTeamUuid != null)
                        ListTile(
                          leading: const Icon(Icons.sync_alt_rounded),
                          title: const Text("完成规则"),
                          trailing: SizedBox(
                            width: 140,
                            child: _buildCustomSegmentedControl(
                              labels: const ["全队同步", "各自独立"],
                              selectedIndex: _collabType,
                              onChanged: (idx) =>
                                  setState(() => _collabType = idx),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 60),
          ],
        ),
      );
    });
  }

  Widget _buildManualKindBottomBar() {
    return FloatingBottomNavigationBar(
      items: const [
        FloatingBottomNavigationItem(
          icon: Icons.check_circle_outline_rounded,
          label: '待办',
        ),
        FloatingBottomNavigationItem(
          icon: Icons.event_note_outlined,
          label: '日程',
        ),
      ],
      selectedIndex: _manualCaptureKind == _ManualCaptureKind.todo ? 0 : 1,
      onTabSelected: _selectManualCaptureKind,
    );
  }

  // ================= 待确认图片识别事项卡片 =================
  Widget _buildPendingTodoCard() {
    final imagePath = _pendingTodoConfirm!['imagePath'] as String?;
    final results = _pendingTodoConfirm!['results'] as List<dynamic>?;
    final todoCount = results?.length ?? 0;
    if (todoCount == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (results == null || results.isEmpty) return;
            final typedResults = results
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            setState(() => _pendingTodoConfirm = null);
            StorageService.clearPendingTodoConfirm();
            if (widget.onLLMResultsParsed != null) {
              widget.onLLMResultsParsed!(
                  typedResults, imagePath, null, null, null);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (localImageExists(imagePath))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: localImageWidget(
                      imagePath!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.checklist_rounded,
                        color: Theme.of(context).colorScheme.primary, size: 24),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI识别完成',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '发现 $todoCount 个事项，点击查看',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20),
              ],
            ),
          ),
        ),
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
          // 🚀 待确认的图片识别事项入口
          if (_pendingTodoConfirm != null) _buildPendingTodoCard(),
          OptionalLiquidGlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 16,
            highContrast: true,
            fallbackDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text("用自然语言描述你的计划",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
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
                        label: _isParsing
                            ? _buildBouncingDots()
                            : const Text("本地速认"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isParsing ? null : _doLLMParse,
                        icon: const Icon(Icons.memory, size: 18),
                        label: _isParsing
                            ? _buildBouncingDots()
                            : const Text("大模型深思"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_parsedResults.isNotEmpty)
            OptionalLiquidGlassCard(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              highContrast: true,
              fallbackDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10)
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "解析结果 (${_currentParseIndex + 1}/${_parsedResults.length})",
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios, size: 16),
                            onPressed: _currentParseIndex > 0
                                ? () {
                                    setState(() => _currentParseIndex--);
                                    _applyParsedResult(
                                        _parsedResults[_currentParseIndex]);
                                  }
                                : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, size: 16),
                            onPressed:
                                _currentParseIndex < _parsedResults.length - 1
                                    ? () {
                                        setState(() => _currentParseIndex++);
                                        _applyParsedResult(
                                            _parsedResults[_currentParseIndex]);
                                      }
                                    : null,
                          ),
                        ],
                      )
                    ],
                  ),
                  const Divider(),
                  _buildParseResultRow(
                    '类型',
                    _parsedKindLabel(_parsedResults[_currentParseIndex]),
                  ),
                  _buildParseResultRow(
                    '内容',
                    _parsedResults[_currentParseIndex].title,
                  ),
                  _buildParseResultRow(
                    '时间',
                    _parsedTimeLabel(_parsedResults[_currentParseIndex]),
                  ),
                  _buildParseResultRow(
                      "重复",
                      _getRecurrenceLabel(
                          _parsedResults[_currentParseIndex].recurrence)),
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
          SizedBox(
              width: 60,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
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
            final double scale =
                0.5 + 0.5 * (1.0 - (animationValue - 0.5).abs() * 2.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
