part of 'search_service.dart';

class SearchNavigationHandler {
  static Future<void> handle(
    BuildContext context,
    SearchResult result, {
    required GlobalKey sourceKey,
  }) async {
    final data = result.extraData;
    if (data == null) return;

    final route = data['route'] as String?;
    final action = data['action'] as String?;
    final query = data['query'] as String?;

    if (action != null) {
      if ((action == 'ai_query' || action == 'apply_query') && query != null) {
        // 交给 UI 层处理：重新设置 Search Bar 的文本并触发搜索
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text("正在搜索: $query"),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (action == 'new_todo') {
        await _executeAction(context, action, sourceKey);
      } else if (action == 'navigate') {
        await _navigateByRoute(context, route ?? '', data, sourceKey);
      } else if (action == 'filter_overdue') {
        final username = await StorageService.getLoginSession() ?? 'default';
        final results = await Future.wait<dynamic>([
          StorageService.getTodos(username),
          HabitRepository.getHabitOnlyRecurringTodoSeriesIds(),
        ]);
        final overdue = SearchService._filterOverdueTodos(
          todos: results[0] as List<TodoItem>,
          excludedRecurrenceSeriesIds: results[1] as Set<String>,
          before: DateTime.now(),
        );
        if (!context.mounted) return;
        await _push(
          context,
          sourceKey,
          SearchRecordDetailScreen(
            result: SearchResult(
              id: result.id,
              title: result.title,
              subtitle: '${overdue.length} 项待办逾期',
              icon: result.icon,
              type: result.type,
              extraData: {
                'detail_label': '逾期待办',
                'fields': {'待办': overdue.map((item) => item.title).join('\n')},
              },
            ),
          ),
        );
      }
      return;
    }

    if (route != null) {
      await _navigateByRoute(context, route, data, sourceKey);
    } else if (result.type == SearchResultType.todo) {
      await _handleTodoEdit(context, result, sourceKey);
    } else if (result.type == SearchResultType.course ||
        data['type'] == 'course_detail') {
      await _handleCourseNavigation(context, result, sourceKey);
    } else if (result.type == SearchResultType.log) {
      final uuid = data['uuid']?.toString();
      final table = data['table']?.toString();
      if (uuid == null) {
        _showMissingRecord(context);
        return;
      }
      final tags = await PomodoroService.getTags();
      if (table == 'pomodoro_records') {
        final records = await PomodoroService.getRecords();
        if (!context.mounted) return;
        for (final record in records) {
          if (record.uuid == uuid) {
            await _push(
              context,
              sourceKey,
              PomodoroDetailScreen(record: record, tags: tags),
            );
            return;
          }
        }
      } else {
        final username = await StorageService.getLoginSession() ?? 'default';
        final logs = await StorageService.getTimeLogs(username);
        if (!context.mounted) return;
        for (final log in logs) {
          if (log.id == uuid) {
            await _push(
              context,
              sourceKey,
              TimeLogDetailScreen(log: log, tags: tags),
            );
            return;
          }
        }
      }
      _showMissingRecord(context);
    } else if (result.type == SearchResultType.journal &&
        data['record'] is JournalEntry) {
      final username = await StorageService.getLoginSession() ?? 'default';
      if (!context.mounted) return;
      await _push(
        context,
        sourceKey,
        JournalDetailScreen(
          accountId: username,
          entry: data['record'] as JournalEntry,
        ),
      );
    } else if (result.type == SearchResultType.fixedSchedule &&
        data['record'] is FixedScheduleItem) {
      final username = await StorageService.getLoginSession() ?? 'default';
      if (!context.mounted) return;
      await _push(
        context,
        sourceKey,
        FixedScheduleEditorScreen(
          username: username,
          item: data['record'] as FixedScheduleItem,
          onSave: (item) => StorageService.saveFixedSchedules(username, [item]),
        ),
      );
    } else if (result.type == SearchResultType.finance &&
        data['record'] is FinanceTransaction) {
      await _push(
        context,
        sourceKey,
        FinanceTransactionDetailScreen(
          transaction: data['record'] as FinanceTransaction,
          category: data['finance_category'] as FinanceCategory?,
          paymentMethod: data['finance_payment'] as FinancePaymentMethod?,
        ),
      );
    } else if (result.type == SearchResultType.finance &&
        data['record'] is FinanceLoan) {
      await _push(
        context,
        sourceKey,
        FinanceLoanDetailScreen(loan: data['record'] as FinanceLoan),
      );
    } else if (result.type == SearchResultType.finance &&
        data['record'] is FinanceBudget) {
      final budget = data['record'] as FinanceBudget;
      final month = DateTime.tryParse('${budget.monthKey}-01');
      if (month != null) {
        await _push(
          context,
          sourceKey,
          FinanceBudgetEntryScreen(month: month, budget: budget),
        );
      }
    } else if (result.type == SearchResultType.todoGroup) {
      final username = await StorageService.getLoginSession() ?? 'default';
      final todos = await StorageService.getTodos(username);
      final groups = await StorageService.getTodoGroups(username);
      final groupId = data['uuid']?.toString();
      if (!context.mounted) return;
      await _push(
        context,
        sourceKey,
        FolderManageScreen(
          username: username,
          todoGroups: groups,
          allTodos: todos,
          initialGroupId: groupId,
          onGroupsChanged: (items) async =>
              StorageService.saveTodoGroups(username, items),
          onTodosChanged: (items) async =>
              StorageService.saveTodos(username, items),
          onManualTodoSaved: (todo) async {
            final allTodos = await StorageService.getTodos(username);
            final existingIndex = allTodos.indexWhere(
              (item) => item.id == todo.id,
            );
            if (existingIndex < 0) {
              allTodos.add(todo);
            } else {
              allTodos[existingIndex] = todo;
            }
            await StorageService.saveTodos(username, allTodos);
            return const TodoCreateSaveResult();
          },
        ),
      );
    } else {
      await _push(context, sourceKey, SearchRecordDetailScreen(result: result));
    }
  }

  static Future<void> _push(
    BuildContext context,
    GlobalKey sourceKey,
    Widget page, {
    RouteSettings? settings,
  }) async {
    if (!context.mounted) return;
    await PageTransitions.pushFromRect(
      context: context,
      page: page,
      sourceKey: sourceKey,
      settings: settings,
    );
  }

  static void _showMissingRecord(BuildContext context) {
    if (!context.mounted) return;
    AppSnackBars.showSnackBar(
      context,
      const SnackBar(content: Text('这条记录已不存在，请重新搜索')),
    );
  }

  static Future<void> _handleTodoEdit(
    BuildContext context,
    SearchResult result,
    GlobalKey sourceKey,
  ) async {
    try {
      final uuid = result.extraData?['uuid'];
      if (uuid == null) {
        _showMissingRecord(context);
        return;
      }

      final db = DatabaseHelper.instance;
      final todoMap = await db.getTodoByUuid(uuid);
      if (todoMap == null) {
        if (!context.mounted) return;
        _showMissingRecord(context);
        return;
      }

      final username = await StorageService.getLoginSession();
      if (username == null) {
        if (!context.mounted) return;
        _showMissingRecord(context);
        return;
      }

      // 🚀 核心修复：due_date 在 DB 中是 TEXT (jsonType)，需要安全转 int
      int? toInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v == 0 ? null : v;
        final parsed = int.tryParse(v.toString());
        return (parsed == null || parsed == 0) ? null : parsed;
      }

      final todo = TodoItem(
        id: todoMap['uuid']?.toString(),
        title: todoMap['content']?.toString() ?? '',
        isDone: todoMap['is_completed'] == 1,
        completedAt: toInt(todoMap['completed_at']),
        isDeleted: todoMap['is_deleted'] == 1,
        version: (todoMap['version'] is int)
            ? todoMap['version']
            : int.tryParse(todoMap['version'].toString()) ?? 1,
        updatedAt: (todoMap['updated_at'] is int)
            ? todoMap['updated_at']
            : int.tryParse(todoMap['updated_at'].toString()),
        createdAt: (todoMap['created_at'] is int)
            ? todoMap['created_at']
            : int.tryParse(todoMap['created_at'].toString()),
        createdDate: toInt(todoMap['created_date']),
        dueDate: toInt(todoMap['due_date']) != null
            ? DateTime.fromMillisecondsSinceEpoch(toInt(todoMap['due_date'])!)
            : null,
        remark: todoMap['remark']?.toString(),
        groupId: todoMap['group_id']?.toString(),
        teamUuid: todoMap['team_uuid']?.toString(),
        teamName: todoMap['team_name']?.toString(),
        collabType: (todoMap['collab_type'] is int)
            ? todoMap['collab_type']
            : int.tryParse(todoMap['collab_type'].toString()) ?? 0,
        reminderMinutes: toInt(todoMap['reminder_minutes']),
      );

      final allTodos = await StorageService.getTodos(username);
      final allGroups = await StorageService.getTodoGroups(username);
      final canonicalTodo =
          allTodos.cast<TodoItem?>().firstWhere(
            (candidate) => candidate?.id == todo.id,
            orElse: () => null,
          ) ??
          todo;

      if (context.mounted) {
        await _push(
          context,
          sourceKey,
          TodoEditScreen(
            // 使用完整存储模型，保留循环规则和 recurrenceSeriesId，
            // 这样从全局搜索进入编辑页也能访问同系列的其他期次。
            todo: canonicalTodo,
            todos: allTodos,
            onTodosChanged: (newList) async {
              await StorageService.saveTodos(username, newList);
              if (context.mounted) {
                AppSnackBars.showSnackBar(
                  context,
                  const SnackBar(
                    content: Text("待办已更新"),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            onEditorSave:
                (
                  changedTodos,
                  baselines, {
                  expectedSeriesMembership,
                  expectedFixedScheduleTodoIds,
                  expectedFixedScheduleBaselines,
                }) async {
                  final result = await TodoEditorSaveService.save(
                    username: username,
                    changedTodos: changedTodos,
                    baselines: baselines,
                    expectedSeriesMembership: expectedSeriesMembership,
                    expectedFixedScheduleTodoIds: expectedFixedScheduleTodoIds,
                    expectedFixedScheduleBaselines:
                        expectedFixedScheduleBaselines,
                  );
                  if (context.mounted && result.warnings.isEmpty) {
                    AppSnackBars.showSnackBar(
                      context,
                      const SnackBar(
                        content: Text('待办已更新'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  return result;
                },
            onEditorGroupsSave: (changedGroups, baselines) =>
                TodoEditorSaveService.saveGroups(
                  username: username,
                  changedGroups: changedGroups,
                  baselines: baselines,
                ),
            todoGroups: allGroups,
            onGroupsChanged: (newGroups) async {
              await StorageService.saveTodoGroups(username, newGroups);
            },
            username: username,
          ),
        );
      }
    } catch (e) {
      debugPrint('Open searched todo failed: $e');
      if (!context.mounted) return;
      _showMissingRecord(context);
    }
  }

  static Future<void> _handleCourseNavigation(
    BuildContext context,
    SearchResult result,
    GlobalKey sourceKey,
  ) async {
    try {
      final username = await StorageService.getLoginSession() ?? 'default';
      final adjusted = result.extraData?['course_record'];
      if (adjusted is CourseItem) {
        if (!context.mounted) return;
        await _push(
          context,
          sourceKey,
          CourseDetailScreen(course: adjusted, username: username),
        );
        return;
      }
      final uuid = result.extraData?['uuid'];
      if (uuid == null) {
        if (!context.mounted) return;
        _showMissingRecord(context);
        return;
      }

      final courses = await CourseService.getAllCourses(username);
      if (!context.mounted) return;
      for (final course in courses) {
        if (course.uuid == uuid.toString()) {
          await _push(
            context,
            sourceKey,
            CourseDetailScreen(course: course, username: username),
          );
          return;
        }
      }
      _showMissingRecord(context);
    } catch (e) {
      debugPrint('Open searched course failed: $e');
      _showMissingRecord(context);
    }
  }

  static Future<void> _navigateByRoute(
    BuildContext context,
    String route,
    Map<String, dynamic> data,
    GlobalKey sourceKey,
  ) async {
    final target = data['target'] as String?;
    Widget? page;
    final username = await StorageService.getLoginSession() ?? 'default';
    if (!context.mounted) return;

    if (route == '/time_log/tag') {
      final tagUuid = data['tag_uuid'];
      if (tagUuid != null) {
        await _push(
          context,
          sourceKey,
          TimeLogScreen(username: username, initialTagUuid: tagUuid),
        );
      }
      return;
    }

    if (route == '/screen_time/app') {
      final appName = data['app_name'];
      if (appName != null) {
        final history = await StorageService.getScreenTimeHistory();
        final todayKey = AppTimeFormats.dateFormatter('yyyy-MM-dd')
            .format(DateTime.now());
        if (history[todayKey] == null || history[todayKey]!.isEmpty) {
          final cachedToday = await StorageService.getScreenTimeCache();
          if (cachedToday.isNotEmpty) {
            history[todayKey] = cachedToday;
          }
        }
        if (!context.mounted) return;
        final searchDateMs = data['search_date_ms'] as int?;
        await _push(
          context,
          sourceKey,
          AppDetailScreen(
            appName: appName,
            historyStats: history,
            filter: DeviceFilter.all,
            range: ScreenTimeRange.day,
            anchorDate: searchDateMs == null
                ? DateTime.now()
                : DateTime.fromMillisecondsSinceEpoch(searchDateMs),
          ),
        );
      }
      return;
    }

    switch (route) {
      case '/pomodoro/stats':
        final dim = data['initialDimension'] as int? ?? 0;
        page = PomodoroScreen(
          username: username,
          initialTab: 1,
          initialDimension: dim,
        );
        break;
      case '/personal_timeline':
        final dimIndex = data['initialDimension'] as int? ?? 0;
        final dim = dimIndex >= 0 && dimIndex < TimelineDimension.values.length
            ? TimelineDimension.values[dimIndex]
            : TimelineDimension.daily;
        page = PersonalTimelineScreen(
          username: username,
          initialDimension: dim,
        );
        break;
      case '/time_log/manual':
        page = TimeLogScreen(username: username);
        break;
      case '/settings':
        if (target == null) {
          page = const SettingsPage();
          break;
        }
        final settingsPage = AiSettingsNavigation.pageFor(
          target,
          username: username,
        );
        if (settingsPage == null) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(content: Text('这项设置当前不可用，请重新搜索')),
          );
          return;
        }
        final destination = AppSettingsCatalog.available.firstWhere(
          (item) => item.id == target,
        );
        await _push(
          context,
          sourceKey,
          settingsPage,
          settings: RouteSettings(name: destination.path),
        );
        return;
      case '/about':
        page = const AboutScreen();
        break;
      case '/login':
        page = const LoginScreen();
        break;
      case '/teams':
        if (target == 'messages' ||
            target == 'announcements' ||
            target == 'members') {
          final rawTeams = await ApiService.fetchTeams();
          final teams = rawTeams
              .whereType<Map>()
              .map((raw) => Team.fromJson(Map<String, dynamic>.from(raw)))
              .toList();
          if (target == 'messages') {
            page = TeamMessageCenterScreen(
              managedTeams: teams
                  .where((team) => team.userRole == TeamRole.admin)
                  .toList(),
            );
          } else if (teams.isNotEmpty) {
            page = target == 'announcements'
                ? TeamAnnouncementScreen(team: teams.first)
                : TeamMembersSearchScreen(team: teams.first);
          }
        }
        page ??= TeamManagementScreen(username: username);
        break;
      case '/today':
        page = WeeklyCourseScreen(username: username);
        break;
      case '/course/weekly':
        page = WeeklyCourseScreen(username: username);
        break;
      case '/plan':
        page = TodoPlanScreen(username: username);
        break;
      case '/finance':
        page = FinanceHomeScreen(username: username);
        break;
      case '/journal':
        page = JournalHomeScreen(username: username);
        break;
      case '/tomorrow':
        page = WeeklyCourseScreen(username: username);
        break;
      case '/screen_time':
        final cache = await StorageService.getScreenTimeCache();
        page = ScreenTimeDetailScreen(todayStats: cache);
        break;
      case '/habits':
        final habitUuid = data['habit_uuid']?.toString();
        if (habitUuid != null && habitUuid.isNotEmpty) {
          final goals = await HabitRepository.getGoals();
          HabitGoal? goal;
          for (final candidate in goals) {
            if (candidate.uuid == habitUuid) {
              goal = candidate;
              break;
            }
          }
          page = goal == null
              ? HabitCenterScreen(username: username)
              : HabitDetailScreen(goal: goal, username: username);
        } else {
          page = HabitCenterScreen(username: username);
        }
        break;
      case '/challenge':
        page = const ChallengeCenterScreen();
        break;
      case '/feature_explorer':
        page = FeatureExplorerScreen(username: username);
        break;
      case '/historical_todos':
        page = HistoricalTodosScreen(username: username);
        break;
      case '/ai_tutorial':
        page = const AiAssistantTutorialScreen();
        break;
      case '/conflicts':
        page = ConflictInboxScreen(username: username);
        break;
      case '/math_quiz':
        page = MathMenuScreen(username: username);
        break;
    }

    if (page != null && context.mounted) {
      await _push(context, sourceKey, page);
    }
  }

  static Future<void> _executeAction(
    BuildContext context,
    String action,
    GlobalKey sourceKey,
  ) async {
    if (action == 'new_todo') {
      final username = await StorageService.getLoginSession() ?? 'default';
      final groups = await StorageService.getTodoGroups(username);
      if (!context.mounted) return;
      await _push(
        context,
        sourceKey,
        AddTodoScreen(
          todoGroups: groups,
          onTodoAdded: (todo) async {
            final todos = await StorageService.getTodos(username);
            final existingIndex = todos.indexWhere(
              (item) => item.id == todo.id,
            );
            if (existingIndex < 0) {
              todos.add(todo);
            } else {
              todos[existingIndex] = todo;
            }
            await StorageService.saveTodos(username, todos);
          },
          onManualTodoSaved: (todo) async {
            final todos = await StorageService.getTodos(username);
            final existingIndex = todos.indexWhere(
              (item) => item.id == todo.id,
            );
            if (existingIndex < 0) {
              todos.add(todo);
            } else {
              todos[existingIndex] = todo;
            }
            await StorageService.saveTodos(username, todos);
            return const TodoCreateSaveResult();
          },
          onTodosBatchAdded: (added) async {
            final todos = await StorageService.getTodos(username);
            final indexById = <String, int>{};
            for (var index = 0; index < todos.length; index++) {
              indexById.putIfAbsent(todos[index].id, () => index);
            }
            for (final todo in added) {
              final index = indexById[todo.id];
              if (index == null) {
                indexById[todo.id] = todos.length;
                todos.add(todo);
              } else {
                todos[index] = todo;
              }
            }
            await StorageService.saveTodos(username, todos);
          },
          onFixedScheduleAdded: (item) =>
              StorageService.saveFixedSchedules(username, [item]),
        ),
      );
    }
  }
}
