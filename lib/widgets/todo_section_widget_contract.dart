part of 'todo_section_widget.dart';

// 各职责分片共享的成员契约，为 Dart 提供跨 mixin 的静态类型信息。
// 具体实现仍位于 lifecycle/capture/recurrence/view 分片中。
// ignore_for_file: unused_element, unused_element_parameter
mixin _TodoSectionContract {
  Future<void> _fetchTeamRoles();

  Future<void> _loadSettings();

  _TodoFolderDisplayMode _parseFolderDisplayMode(String modeName);

  GlobalKey _getTodoCardKey(String todoId);

  Key _getTodoDismissKey(String idPrefix, String todoId);

  Future<void> openAiAssistant({GlobalKey? sourceKey});

  bool _isHistoricalTodo(TodoItem t);

  void showAddTodoDialog();

  void showAddTodoDialogWithData(
    List<Map<String, dynamic>> llmResults, [
    String? imagePath,
    String? originalText,
  ]);

  void _showAddTodoDialogWithData(
    List<Map<String, dynamic>>? llmResults,
    String? imagePath,
    String? originalText,
  );

  Future<_QuickCaptureTarget> _confirmQuickCaptureIntent(
    String sourceText, {
    String? declaredKind,
    String? semanticText,
  });

  Future<bool> _saveQuickFixedSchedule(ParsedTodoResult parsed);

  void _showFullImage(BuildContext context, String imagePath);

  Widget _buildExampleText(String text);

  Widget _buildParseResultItem(String label, String value);

  String _getRecurrenceText(RecurrenceType type);

  RecurrenceType _parseRecurrenceType(String? value);

  ParsedTimeSemantics _parseTimeSemantics(
    dynamic raw, {
    required bool isAllDay,
    required DateTime? startTime,
    required DateTime? endTime,
  });

  CaptureIntentKind _quickCaptureIntentFor(ParsedTodoResult result);

  String _quickCaptureKindLabel(ParsedTodoResult result);

  String _quickCaptureTimeLabel(ParsedTodoResult result);

  String _quickCaptureDetailLabel(ParsedTodoResult result);

  void _applyParsedResult(
    ParsedTodoResult result,
    void Function(void Function()) setDialogState,
    TextEditingController titleCtrl,
    TextEditingController remarkCtrl,
    Function(DateTime) setCreatedAt,
    Function(DateTime?) setDueDate,
    Function(bool) setIsAllDay,
    Function(RecurrenceType) setRecurrence,
    Function(int?) setCustomDays,
    Function(DateTime?) setRecurrenceEndDate,
    Function(int) setReminderMinutes,
    TextEditingController customDaysCtrl,
  );

  void _editTodo(TodoItem todo, BuildContext cardCtx);

  void _openTodoEditor(
    TodoItem todo, {
    bool applyToFutureOccurrences = false,
  });

  String _buildTimeLabel(
    TodoItem todo,
    DateTime cDate,
    bool isPast,
    bool isFuture,
    DateTime now,
  );

  Color _getProgressFillColor(double progress, bool isPast);

  Widget _buildRecurrenceProgress(TodoItem todo, DateTime now);

  Future<void> _handleRecurrenceNodeTap(
    TodoItem current,
    TodoRecurrenceProgressNode node,
  );

  Future<void> _showRecurrenceOccurrenceActions(
    TodoItem occurrence,
    DateTime occurrenceDate,
  );

  void _setTodoCompletion(TodoItem todo, bool isDone);

  Future<void> _showRecurrenceManagement(TodoItem todo);

  DateTime _nextRecurrenceStart(DateTime current, TodoItem todo);

  Widget _buildTodoItemCard(
    TodoItem todo, {
    required bool isPast,
    required bool isFuture,
    Key? key,
  });

  Widget _buildAnimatedSection({required bool expanded, required Widget child});

  Widget _buildGroupLabel({
    required String text,
    required bool expanded,
    required VoidCallback onTap,
    Color? color,
    IconData? icon,
  });

  Widget _buildTodoList();

  _TodoSectionViewModel _computeViewModel();

  int _computeViewModelSignature(DateTime today);

  Widget _buildGroupWidget(TodoGroup g, List<TodoItem> gTodos);

  Widget _buildTeamFilterTabs();

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool useDarkUI,
  });

  Future<_AiAssistantContext> _loadAiAssistantContext();

  void _showIndependentTodoStatus(TodoItem todo);
}
