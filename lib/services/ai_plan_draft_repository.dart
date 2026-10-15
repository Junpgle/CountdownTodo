import 'dart:convert';

import '../models.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'storage/user_session_storage.dart';

/// Persists new planning subjects and their blocks together, only after the
/// user presses the operation card. A failed write leaves neither orphan todos
/// nor partial plan blocks, and both tables receive sync operations.
abstract final class AiPlanDraftRepository {
  static Future<void> save({
    required String username,
    required List<TodoItem> newTodos,
    required List<TodoPlanBlock> blocks,
    bool sync = true,
  }) async {
    final session = await UserSessionStorage.captureSession(username);
    Future<bool> isCurrentAccount() async => session != null
        ? UserSessionStorage.isCurrentSession(session)
        : (await UserSessionStorage.getCurrentUsername() ?? 'default') ==
              username;
    if (!await isCurrentAccount()) throw StateError('账号已切换，请重新打开规划');
    final db = await DatabaseHelper.instance.databaseForUser(username);
    await db.transaction((txn) async {
      if (!await isCurrentAccount()) {
        throw StateError('账号已切换，请重新打开规划');
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      Future<void> log(String table, String id, Map<String, dynamic> data) =>
          txn
              .insert('op_logs', {
                'op_type': 'UPSERT',
                'target_table': table,
                'target_uuid': id,
                'data_json': jsonEncode(data),
                'timestamp': timestamp,
                'is_synced': 0,
                'sync_error': '',
              })
              .then((_) {});
      for (final todo in newTodos) {
        if (!blocks.any((block) => block.todoId == todo.id) ||
            todo.recurrence != RecurrenceType.none ||
            todo.isDeleted ||
            todo.isDone) {
          throw StateError('待建待办与规划不匹配，请重新生成');
        }
        final sameTitle = await txn.query(
          'todos',
          where: 'content = ? AND is_deleted = 0',
          whereArgs: [todo.title],
        );
        if (sameTitle.any((row) => row['uuid'] != todo.id)) {
          throw StateError('同名待办已存在，请重新生成规划以关联已有待办');
        }
        final existing = await txn.query(
          'todos',
          where: 'uuid = ?',
          whereArgs: [todo.id],
        );
        if (existing.isNotEmpty) continue;
        await txn.insert('todos', {
          'uuid': todo.id,
          'content': todo.title,
          'remark': todo.remark,
          'created_at': todo.createdAt,
          'created_date': 0,
          'updated_at': todo.updatedAt,
          'version': todo.version,
          'due_date': 0,
          'is_completed': 0,
          'is_deleted': 0,
        });
        await log('todos', todo.id, todo.toJson());
        await txn.insert('local_audit_logs', {
          'user_id': session?.userId ?? 0,
          'target_table': 'todos',
          'target_uuid': todo.id,
          'op_type': 'INSERT',
          'after_data': jsonEncode(todo.toJson()),
          'timestamp': timestamp,
          'operator_name': username,
        });
      }
      for (final block in blocks) {
        final todos = await txn.query(
          'todos',
          where: 'uuid = ?',
          whereArgs: [block.todoId],
        );
        if (todos.isEmpty ||
            todos.single['is_deleted'] == 1 ||
            todos.single['is_completed'] == 1 ||
            block.endTime <= block.startTime) {
          throw StateError('规划关联待办或时段已无效，请重新生成');
        }
        final existing = await txn.query(
          'todo_plan_blocks',
          where: 'uuid = ?',
          whereArgs: [block.id],
        );
        if (existing.isNotEmpty) {
          if (jsonEncode(TodoPlanBlock.fromJson(existing.single).toDbJson()) !=
              jsonEncode(block.toDbJson())) {
            throw StateError('规划已变化，请重新读取后操作');
          }
          continue;
        }
        final data = block.toDbJson();
        await txn.insert('todo_plan_blocks', data);
        await log('todo_plan_blocks', block.id, data);
      }
      if (!await isCurrentAccount()) {
        throw StateError('账号已切换，请重新打开规划');
      }
    });
    if (sync) StorageService.requestSync(username);
    StorageService.triggerRefresh(const {
      DataRefreshDomain.todos,
      DataRefreshDomain.planBlocks,
    });
  }
}
