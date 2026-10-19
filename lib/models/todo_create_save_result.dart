/// Follow-up device work can fail after the local todo write has committed.
/// Keep those warnings separate from save failures so retrying cannot create a
/// duplicate todo.
class TodoCreateSaveResult {
  const TodoCreateSaveResult({this.warnings = const []});

  final List<String> warnings;
}
