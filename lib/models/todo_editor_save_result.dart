/// Describes the result of the local write made by the todo editor.
/// Follow-up platform integrations can warn without claiming the todo failed
/// to save when the database transaction has already committed.
class TodoEditorSaveResult {
  const TodoEditorSaveResult({this.warnings = const []});

  final List<String> warnings;
}
