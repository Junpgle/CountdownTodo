import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../utils/time_utils.dart';

import '../models.dart';
import '../models/chat_message.dart';
import '../models/todo_create_save_result.dart';
import '../storage_service.dart';
import '../services/api_service.dart';
import '../services/todo_parser_service.dart';
import '../services/llm_service.dart';
import '../services/recognized_todo_adapter.dart';
import '../services/ai_recognition_chat_bridge.dart';
import '../services/database_helper.dart';
import '../screens/home_settings_screen.dart';
import '../services/todo_classification_service.dart';
import '../services/item_semantics_service.dart';
import '../utils/local_image_provider.dart';
import '../services/time_estimation_service.dart';
import '../services/time_estimation_repository.dart';
import '../widgets/time_estimation_hint.dart';
import '../widgets/ai_water_border.dart';
import '../services/suggestion_feedback_service.dart';
import '../services/feature_tip_service.dart';
import '../services/fixed_schedule_recurrence_service.dart';
import '../services/reminder_schedule_service.dart';
import 'fixed_schedule_related_todo_picker_screen.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/floating_bottom_bar.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import '../widgets/todo_group_picker_sheet.dart';
import '../utils/persistent_image_storage.dart';
import '../utils/page_transitions.dart';

import 'dart:async';

import '../utils/app_dialogs.dart';
import '../utils/semester_week_context.dart';
import '../utils/text_utils.dart';

part 'add_todo/add_todo_parsing.dart';
part 'add_todo/add_todo_saving_and_suggestions.dart';
part 'add_todo/add_todo_manual_tab.dart';
part 'add_todo/add_todo_ai_tab.dart';

final RegExp _latinKeywordPattern = RegExp(r'[a-z0-9]+');
final RegExp _cjkKeywordPattern = RegExp(r'[一-鿿]+');

enum _CaptureSaveTarget { todo, fixedSchedule, cancel }

enum _AddTodoExitAction { continueEditing, discard, save }

enum _ManualCaptureKind { todo, fixedSchedule }

enum AddTodoInitialMode { todo, fixedSchedule }

class AddTodoScreen extends StatefulWidget {
  final FutureOr<void> Function(TodoItem)? onTodoAdded;
  final FutureOr<TodoCreateSaveResult> Function(TodoItem)? onManualTodoSaved;
  final FutureOr<void> Function(List<TodoItem>)? onTodosBatchAdded;
  final Future<void> Function(FixedScheduleItem)? onFixedScheduleAdded;
  final Function(
    List<Map<String, dynamic>>,
    String?,
    String?,
    String?,
    String?,
  )?
  onLLMResultsParsed;
  final List<TodoGroup> todoGroups;
  final String? initialGroupId;
  final String? initialTeamUuid;
  final String? initialTeamName;
  final AddTodoInitialMode initialMode;
  final FixedScheduleItem? relatedFixedScheduleContext;
  final Future<TimeEstimationResult> Function(
    String title,
    String? groupId,
    String username,
  )?
  estimate;
  final String? username;
  final Set<String>? initialRelatedTodoIds;
  final FixedScheduleRelatedTodoPageLoader? loadRelatedTodoPage;
  final FixedScheduleRelatedTodoIdsLoader? loadSelectedRelatedTodos;

  const AddTodoScreen({
    super.key,
    this.username,
    this.initialRelatedTodoIds,
    this.loadRelatedTodoPage,
    this.loadSelectedRelatedTodos,
    this.onTodoAdded,
    this.onManualTodoSaved,
    this.onTodosBatchAdded,
    this.onFixedScheduleAdded,
    this.onLLMResultsParsed,
    this.todoGroups = const [],
    this.initialGroupId,
    this.initialTeamUuid,
    this.initialTeamName,
    this.initialMode = AddTodoInitialMode.todo,
    this.relatedFixedScheduleContext,
    this.estimate,
  });

  @override
  State<AddTodoScreen> createState() => _AddTodoScreenState();
}

class _AddTodoScreenState extends State<AddTodoScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
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
  Set<String> _scheduleRelatedTodoIds = {};
  final GlobalKey _relatedTodosTileKey = GlobalKey();
  SemesterWeekContext? _semesterWeekContext;

  int _selectedTabIndex = 0;
  bool _isParsing = false;
  bool _isSaving = false;
  bool _allowExit = false;
  bool _exitPromptOpen = false;
  late String _initialDraftSnapshot;
  String? _pendingManualTodoId;
  List<ParsedTodoResult> _parsedResults = [];
  List<String> _parsedDraftIds = [];
  bool _parsedWithAi = false;
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
    final hasSeenCoachMarks = await FeatureTipService.hasTipBeenShown(
      'coach_add_todo',
    );
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

  String _draftSnapshot() => jsonEncode({
    'title': _titleCtrl.text,
    'location': _locationCtrl.text,
    'remark': _remarkCtrl.text,
    'aiInput': _aiInputCtrl.text,
    'createdAt': _createdAt.toIso8601String(),
    'dueDate': _dueDate?.toIso8601String(),
    'recurrence': _recurrence.name,
    'customDays': _customDays,
    'recurrenceEndDate': _recurrenceEndDate?.toIso8601String(),
    'allDay': _isAllDay,
    'groupId': _selectedGroupId,
    'reminderMinutes': _reminderMinutes,
    'scheduleDate': _scheduleDate.toIso8601String(),
    'scheduleStart': '${_scheduleStartTime.hour}:${_scheduleStartTime.minute}',
    'scheduleEnd': '${_scheduleEndTime.hour}:${_scheduleEndTime.minute}',
    'scheduleTimeTbd': _scheduleTimeTbd,
    'scheduleEndTimeTbd': _scheduleEndTimeTbd,
    'scheduleRelatedTodoIds': (_scheduleRelatedTodoIds.toList()..sort()),
    'selectedTeam': _selectedTeamUuid,
    'collabType': _collabType,
    'image': _selectedImagePath,
    'originalText': _currentOriginalText,
    'parsedResults': _parsedResults.map((result) => result.toMap()).toList(),
  });

  bool get _hasUnsavedDraft =>
      _titleCtrl.text.isNotEmpty ||
      _locationCtrl.text.isNotEmpty ||
      _remarkCtrl.text.isNotEmpty ||
      _aiInputCtrl.text.isNotEmpty ||
      _parsedResults.isNotEmpty ||
      _selectedImagePath != null ||
      _draftSnapshot() != _initialDraftSnapshot;

  late AnimationController _dotsController;

  // Time estimation state
  TimeEstimationResult? _estimationResult;
  TodoClassificationSuggestion? _classificationSuggestion;
  Timer? _estimationDebounce;
  int _estimateSequence = 0;
  late Future<String> _estimateAccount;
  bool _estimateAccountInvalid = false;
  DateTime? _suggestedDueDate;
  List<TodoGroup> _localTodoGroups = [];
  String _lastObservedTitleText = '';
  String _lastObservedRemarkText = '';
  String? _lastObservedGroupId;
  _ManualCaptureKind? _lastObservedCaptureKind;
  bool? _lastCanPop;

  String? get _relatedScheduleTeamUuid =>
      AppTextUtils.trimToNull(widget.relatedFixedScheduleContext?.teamUuid);

  @override
  void initState() {
    super.initState();
    _estimateAccount = TimeEstimationRepository.activeUsername();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(
      _validateEstimateAccount,
    );
    _manualCaptureKind = widget.initialMode == AddTodoInitialMode.fixedSchedule
        ? _ManualCaptureKind.fixedSchedule
        : _ManualCaptureKind.todo;
    if (widget.username != null && widget.username!.trim().isNotEmpty) {
      _username = widget.username!.trim();
    }
    _scheduleRelatedTodoIds = {
      ...?widget.initialRelatedTodoIds
          ?.map((id) => id.trim())
          .where((id) => id.isNotEmpty),
    };
    final now = DateTime.now();
    _scheduleDate = DateTime(now.year, now.month, now.day);
    _scheduleStartTime = const TimeOfDay(hour: 9, minute: 0);
    _scheduleEndTime = const TimeOfDay(hour: 10, minute: 0);
    _localTodoGroups = List.from(widget.todoGroups);
    if (_localTodoGroups.isEmpty) {
      _loadTodoGroups();
    }
    _loadSemesterWeekContext();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.relatedFixedScheduleContext != null) return;
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
    _selectedTeamUuid =
        _relatedScheduleTeamUuid ??
        (widget.relatedFixedScheduleContext == null
            ? widget.initialTeamUuid
            : null);
    _initialDraftSnapshot = _draftSnapshot();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _lastObservedTitleText = _titleCtrl.text;
    _lastObservedRemarkText = _remarkCtrl.text;
    _lastObservedGroupId = _selectedGroupId;
    _lastObservedCaptureKind = _manualCaptureKind;
    _titleCtrl.addListener(_onTitleChanged);
    _remarkCtrl.addListener(_onTitleChanged);
    _loadCategoryDefaults().then((_) {
      if (mounted &&
          _selectedGroupId != null &&
          _categoryReminderDefaults.containsKey(_selectedGroupId)) {
        final shouldRebaseDraft = !_hasUnsavedDraft;
        setState(() {
          _reminderMinutes = _categoryReminderDefaults[_selectedGroupId]!;
          if (shouldRebaseDraft) {
            _initialDraftSnapshot = _draftSnapshot();
          }
        });
      }
    });
    if (widget.relatedFixedScheduleContext == null) {
      _loadTeams();
      _loadPendingTodoConfirm();
    }
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
    if (widget.relatedFixedScheduleContext != null) return;
    final data = await StorageService.getPendingTodoConfirm();
    if (mounted && data != null) {
      final results = data['results'] as List<dynamic>?;
      if (results != null && results.isNotEmpty) {
        setState(() => _pendingTodoConfirm = data);
      }
    }
  }

  Future<void> _loadTeams() async {
    if (widget.relatedFixedScheduleContext != null) return;
    final rawTeams = await ApiService.fetchTeams();
    if (mounted) {
      setState(() {
        _teams = rawTeams.map((t) => Team.fromJson(t)).toList();
      });
    }
  }

  Future<void> _pickAttachmentImage() async {
    _unfocusActiveInput();
    try {
      final pickedFile = await FilePicker.pickFile(type: FileType.image);
      if (pickedFile == null) return;

      final filePath = pickedFile.path;
      List<int>? bytes;
      try {
        bytes = await pickedFile.readAsBytes();
      } catch (_) {
        // Keep using the selected local path if the platform cannot read bytes.
      }
      final imagePath = bytes != null && bytes.isNotEmpty
          ? _dataUrlFromPickedImage(pickedFile.name, bytes)
          : filePath;
      if (imagePath == null || imagePath.isEmpty) return;

      setState(() {
        _selectedImagePath = imagePath;
      });
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('选择图片失败: $e')));
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
    final username = await _estimateAccount;
    final session = await StorageService.getLoginSession();
    if (session == null || session != username) return;
    final defaults = await StorageService.getCategoryReminderMinutes(username);
    if (!mounted) return;
    final current = await TimeEstimationRepository.activeUsername();
    if (!mounted || current != username) return;
    setState(() {
      _username = session;
      _categoryReminderDefaults = defaults;
    });
  }

  @override
  void didUpdateWidget(covariant AddTodoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGroupId != widget.initialGroupId) {
      _selectedGroupId = widget.initialGroupId;
      _onTitleChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _validateEstimateAccount();
  }

  void _validateEstimateAccount() => unawaited(_checkEstimateAccount());
  Future<void> _checkEstimateAccount() async {
    final expected = await _estimateAccount;
    if (!mounted ||
        await TimeEstimationRepository.activeUsername() == expected) {
      return;
    }
    if (!mounted) return;
    _estimationDebounce?.cancel();
    ++_estimateSequence;
    setState(() {
      _estimateAccountInvalid = true;
      _estimationResult = null;
      _suggestedDueDate = null;
      _classificationSuggestion = null;
    });
  }

  @override
  void dispose() {
    ++_estimateSequence;
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(
      _validateEstimateAccount,
    );
    _titleCtrl.removeListener(_onTitleChanged);
    _remarkCtrl.removeListener(_onTitleChanged);
    _estimationDebounce?.cancel();
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _remarkCtrl.dispose();
    _aiInputCtrl.dispose();
    _customDaysCtrl.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final isRelatedScheduleTodo = widget.relatedFixedScheduleContext != null;
    final useCompactRelatedTodoTitle =
        isRelatedScheduleTodo &&
        (MediaQuery.sizeOf(context).width < 360 ||
            MediaQuery.textScalerOf(context).scale(16) >= 24);
    final theme = Theme.of(context);
    final bgColor = theme.brightness == Brightness.light
        ? const Color(0xFFF2F2F7)
        : theme.colorScheme.surface;
    final topBarHeight = floatingGlassTopBarHeight(context);
    final canPop = _allowExit || (!_isSaving && !_hasUnsavedDraft);
    _lastCanPop = canPop;

    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: bgColor,
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: isRelatedScheduleTodo
              ? Text(useCompactRelatedTodoTitle ? '新建待办' : '新建准备待办')
              : SizedBox(
                  width: 200,
                  child: KeyedSubtree(
                    key: _aiTabSwitchKey,
                    child: AiWaterRippleBorder(
                      enabled: _selectedTabIndex == 1,
                      isLight: Theme.of(context).brightness == Brightness.light,
                      borderRadius: BorderRadius.circular(18),
                      child: _buildCustomSegmentedControl(
                        labels: const ["手动创建", "AI 识别"],
                        selectedIndex: _selectedTabIndex,
                        onChanged: (idx) =>
                            setState(() => _selectedTabIndex = idx),
                      ),
                    ),
                  ),
                ),
          actions: [
            TextButton(
              key: _saveButtonKey,
              onPressed: _isSaving
                  ? null
                  : (_selectedTabIndex == 0 ? _addTodo : _addBatchTodos),
              child: const Text(
                "完成",
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar:
            _selectedTabIndex == 0 && widget.relatedFixedScheduleContext == null
            ? _buildManualKindBottomBar()
            : null,
        body: FloatingGlassTopBarContentFade(
          topBarHeight: topBarHeight,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) {
                  if (animation.value <= 0.001) {
                    return const SizedBox.shrink();
                  }
                  if (animation.value >= 0.999) {
                    return child!;
                  }
                  return FadeTransition(opacity: animation, child: child);
                },
              );
            },
            child: _selectedTabIndex == 0
                ? _buildManualInputTab(
                    key: const ValueKey('manual'),
                    topPadding: topBarHeight,
                  )
                : _buildAIRecognitionTab(
                    key: const ValueKey('ai'),
                    topPadding: topBarHeight,
                  ),
          ),
        ),
      ),
    );
  }
}
