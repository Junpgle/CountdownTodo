import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../utils/time_utils.dart';

Future<void> saveIslandTodoSnapshot(List<TodoItem> todos) async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/island_todos.json');
  final todosJson = todos
      .map(
        (t) => {
          'id': t.id,
          'title': t.title,
          'remark': t.remark,
          'dueDate': AppTimeFormats.toNullableServerTimestamp(t.dueDate),
          'createdDate': t.createdDate,
          'createdAt': t.createdAt,
          'isDone': t.isDone,
          'isDeleted': t.isDeleted,
        },
      )
      .toList();
  await file.writeAsString(jsonEncode(todosJson));
}
