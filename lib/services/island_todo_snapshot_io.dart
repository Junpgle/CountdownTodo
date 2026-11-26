import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../utils/async_json.dart';
import '../utils/time_utils.dart';

const bool _kDisableWindowsIsland = bool.fromEnvironment(
  'countdown.disable_windows_island',
  defaultValue: false,
);

Future<void>? _inFlightIslandTodoWrite;
List<TodoItem>? _pendingIslandTodoSnapshot;

Future<void> saveIslandTodoSnapshot(List<TodoItem> todos) async {
  if (!Platform.isWindows || _kDisableWindowsIsland) return;

  _pendingIslandTodoSnapshot = todos;
  final inFlight = _inFlightIslandTodoWrite;
  if (inFlight != null) {
    return inFlight;
  }

  final task = () async {
    while (_pendingIslandTodoSnapshot != null) {
      final batch = _pendingIslandTodoSnapshot!;
      _pendingIslandTodoSnapshot = null;
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/island_todos.json');
      final todosJson = batch
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
          .toList(growable: false);
      final encoded = await encodeJsonOffload(
        todosJson,
        estimatedItemCount: todosJson.length,
      );
      await file.writeAsString(encoded);
    }
  }();

  _inFlightIslandTodoWrite = task;
  try {
    await task;
  } finally {
    if (identical(_inFlightIslandTodoWrite, task)) {
      _inFlightIslandTodoWrite = null;
    }
  }
}
