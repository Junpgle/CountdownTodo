import '../models.dart';

typedef HomeBannerTodoTypeClassifier = String Function(String title);
typedef HomeBannerTodoVisitor = void Function(
  TodoItem todo,
  String specialType,
);

void forEachEligibleHomeBannerTodo({
  required Iterable<TodoItem> todos,
  required HomeBannerTodoTypeClassifier classifyTodoType,
  required HomeBannerTodoVisitor visit,
}) {
  for (final todo in todos) {
    if (todo.isDone || todo.isDeleted || todo.dueDate == null) continue;

    visit(todo, classifyTodoType(todo.title));
  }
}
