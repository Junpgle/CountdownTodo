part of 'search_service.dart';

extension _SearchServiceDatabase on SearchService {
  Future<List<SearchResult>> _searchHabitsAndChallenges(
    List<String> searchTerms,
    SearchScope scope,
    SearchSourceObserver? onSourceQueried, {
    bool Function()? shouldContinue,
  }) async {
    final results = <SearchResult>[];

    if (scope.includes(SearchResultType.habit)) {
      if (shouldContinue?.call() == false) return results;
      onSourceQueried?.call('habits');
      try {
        final goals = await HabitRepository.getGoals();
        if (shouldContinue?.call() == false) return results;
        for (final goal in goals) {
          if (goal.isDeleted) continue;
          final sourceLabel = switch (goal.sourceType) {
            HabitSourceType.recurringTodo => '完成型',
            HabitSourceType.pomodoroTag => '专注时长型',
            HabitSourceType.quantityCheckIn => '数量型',
            HabitSourceType.timeCheckIn => '时间点型',
            HabitSourceType.durationCheckIn => '独立时长型',
          };
          final searchable =
              '${goal.name} 习惯 $sourceLabel'
              '${goal.isArchived ? ' 已归档 归档习惯' : ''}';
          if (!_matchesAllTerms(searchable, searchTerms)) continue;

          results.add(
            SearchResult(
              id: 'db_habit_${goal.uuid}',
              title: goal.name.isEmpty ? '未命名习惯' : goal.name,
              subtitle: '习惯 · $sourceLabel${goal.isArchived ? ' · 已归档' : ''}',
              icon: Icons.track_changes_rounded,
              type: SearchResultType.habit,
              extraData: {'route': '/habits', 'habit_uuid': goal.uuid},
            ),
          );
        }
      } catch (_) {}
    }

    if (scope.includes(SearchResultType.challenge)) {
      if (shouldContinue?.call() == false) return results;
      onSourceQueried?.call('challenges');
      try {
        // 未开始挑战时，静态“挑战中心”入口已经足够；避免每次输入关键词
        // 都为用户创建一份默认挑战状态。
        if (!await ThirtyDayChallengeRepository.hasStarted()) return results;
        if (shouldContinue?.call() == false) return results;
        final state = await ThirtyDayChallengeRepository.load();
        if (shouldContinue?.call() == false) return results;
        final taskTitles = state.tasks.map((task) => task.title).toList();
        final searchable = [
          state.challengeTitle,
          '挑战',
          '挑战中心',
          '30天',
          ...taskTitles,
        ].join(' ');

        if (_matchesAllTerms(searchable, searchTerms)) {
          final matchedTasks = state.tasks
              .where((task) {
                final title = task.title.toLowerCase();
                return searchTerms.any((term) => title.contains(term));
              })
              .take(2)
              .map((task) => task.title)
              .join('、');
          final progress = '${state.completedCount}/${state.tasks.length} 项已完成';
          results.add(
            SearchResult(
              id: 'db_challenge_current',
              title: state.challengeTitle,
              subtitle: matchedTasks.isEmpty
                  ? '挑战 · $progress'
                  : '挑战 · $progress · 相关任务：$matchedTasks',
              icon: Icons.auto_awesome_rounded,
              type: SearchResultType.challenge,
              extraData: {'route': '/challenge'},
            ),
          );
        }
      } catch (_) {}
    }

    return results;
  }

  Future<List<SearchResult>> _searchDatabase(
    String query,
    List<String> searchTerms,
    SearchScope scope,
    SearchSourceObserver? onSourceQueried, {
    required Future<String?> usernameFuture,
    required DateTime? targetDate,
    required DateTime now,
    bool Function()? shouldContinue,
  }) async {
    final dbItems = <SearchResult>[];
    if (shouldContinue?.call() == false) return dbItems;
    final db = DatabaseHelper.instance;
    final username = await usernameFuture ?? 'default';
    if (shouldContinue?.call() == false) return dbItems;
    final q = query.toLowerCase().trim();

    final isDateQuery = targetDate != null;
    final dateRange = targetDate == null
        ? null
        : SearchService.dateRangeForSearch(targetDate);
    final startOfDay = dateRange?.start;
    final endOfDay = dateRange?.end;
    final targetDateValue = targetDate;
    final isTodayQuery =
        isDateQuery &&
        targetDateValue != null &&
        targetDateValue.year == now.year &&
        targetDateValue.month == now.month &&
        targetDateValue.day == now.day;
    final dateQueryHint = isDateQuery && startOfDay != null
        ? '搜索到${_searchDateFormat('yyyy年M月d日').format(startOfDay)}的结果'
        : null;

    if (scope.includes(SearchResultType.todo)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('todos');
      // ── 待办事项 ──────────────────────────────────────────────────────────
      List<Map<String, dynamic>> todos = [];
      try {
        if (isDateQuery) {
          // Keep recurrence behavior on a cold cache, then use indexed date
          // columns once recurrence instances have already been materialized.
          final matchedTodos = await StorageService.getTodosForSearchDateRange(
            username,
            from: startOfDay!,
            to: endOfDay!,
          );
          if (shouldContinue?.call() == false) return dbItems;
          todos = matchedTodos
              .map(
                (t) => {
                  'uuid': t.id,
                  'content': t.title,
                  'is_completed': t.isDone ? 1 : 0,
                  'is_skipped': t.isSkipped ? 1 : 0,
                  'is_deleted': 0,
                  'due_date': t.dueDate?.millisecondsSinceEpoch,
                  'created_date': t.createdDate,
                  'team_name': t.teamName,
                  'remark': t.remark,
                },
              )
              .toList();
        } else {
          final candidates = await db.searchTodosByTerms(searchTerms);
          if (shouldContinue?.call() == false) return dbItems;
          todos = candidates.where((t) {
            final content = t['content']?.toString() ?? '';
            final remark = t['remark']?.toString() ?? '';
            final teamName = t['team_name']?.toString() ?? '';
            final haystack = '$content $remark $teamName';
            return _matchesAllTerms(haystack, searchTerms);
          }).toList();
        }
      } catch (e) {
        // debugPrint('Todo search error: $e');
      }

      final todoDateFormat = _searchDateFormat('MM/dd');
      for (var t in todos) {
        // 构建副标题：备注（优先）+ 截止时间 + 归属团队
        // 🚀 修复：备注始终显示在副标题第一行，而非仅作兜底
        final metaParts = <String>[];
        final dueDateMs = t['due_date'];
        if (dueDateMs != null && dueDateMs != 0) {
          final dueDate = DateTime.fromMillisecondsSinceEpoch(
            dueDateMs is int
                ? dueDateMs
                : int.tryParse(dueDateMs.toString()) ?? 0,
          );
          metaParts.add('截止 ${todoDateFormat.format(dueDate)}');
        }
        final createdDateMs = t['created_date'];
        if (createdDateMs != null && createdDateMs != 0) {
          final createdDate = DateTime.fromMillisecondsSinceEpoch(
            createdDateMs is int
                ? createdDateMs
                : int.tryParse(createdDateMs.toString()) ?? 0,
          );
          metaParts.add('开始 ${todoDateFormat.format(createdDate)}');
        }
        if (t['team_name'] != null && (t['team_name'] as String).isNotEmpty) {
          metaParts.add('团队: ${t['team_name']}');
        }
        final remarkStr = t['remark']?.toString().trim();
        // subtitle = 备注（若有）＋元信息（若有）
        final subtitle = [
          if (remarkStr != null && remarkStr.isNotEmpty) remarkStr,
          if (metaParts.isNotEmpty) metaParts.join(' · '),
        ].join('  |  ');
        final displaySubtitle = subtitle.isNotEmpty ? subtitle : '个人待办';
        final isSkipped = t['is_skipped'] == 1 || t['is_skipped'] == true;
        dbItems.add(
          SearchResult(
            id: 'db_todo_${t['uuid']}',
            title: t['content'] ?? '未命名任务',
            subtitle: displaySubtitle,
            icon: isSkipped
                ? Icons.skip_next_rounded
                : t['is_completed'] == 1
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            type: SearchResultType.todo,
            extraData: {
              'uuid': t['uuid'],
              'table': 'todos',
              'is_completed': t['is_completed'],
              'is_skipped': isSkipped ? 1 : 0,
              'due_date': dueDateMs,
              'team_name': t['team_name'],
              'remark': remarkStr,
              'date_query_hint': ?dateQueryHint,
            },
          ),
        );
      }
    }

    if (scope.includes(SearchResultType.course)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('courses');
      // ── 课程 ─────────────────────────────────────────────────────────────
      try {
        final courseMap = <String, Map<String, dynamic>>{};
        if (isDateQuery) {
          final dateCourses = await CourseService.getCoursesForDateRange(
            username,
            from: startOfDay!,
            to: endOfDay!,
          );
          if (shouldContinue?.call() == false) return dbItems;
          for (final course in dateCourses) {
            courseMap[course.uuid] = {
              'uuid': course.uuid,
              'course_name': course.courseName,
              'teacher_name': course.teacherName,
              'room_name': course.roomName,
              'week_index': course.weekIndex,
              'weekday': course.weekday,
              'start_time': course.startTime,
              'end_time': course.endTime,
              'course_record': course,
            };
          }
        } else {
          final rows = await db.searchCoursesByTerms(searchTerms);
          if (shouldContinue?.call() == false) return dbItems;
          for (final row in rows) {
            courseMap[row['uuid'].toString()] = row;
          }
        }
        final courses = courseMap.values.where((c) {
          if (isDateQuery) return true;
          final courseName = c['course_name']?.toString() ?? '';
          final teacherName = c['teacher_name']?.toString() ?? '';
          final roomName = c['room_name']?.toString() ?? '';
          final haystack = '$courseName $teacherName $roomName';
          return _matchesAllTerms(haystack, searchTerms);
        }).toList();
        for (var c in courses) {
          // 构建时间描述：第几周 + 星期几 + 第几节
          final weekIdx = c['week_index'];
          final weekday = c['weekday'];
          const weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
          final weekdayStr = (weekday != null && weekday >= 1 && weekday <= 7)
              ? weekdayNames[weekday]
              : '';
          final startSlot = c['start_time'];
          final endSlot = c['end_time'];
          final timePart = (startSlot != null && endSlot != null)
              ? '第 $startSlot-$endSlot 节'
              : '';
          final weekPart = weekIdx != null ? '第 $weekIdx 周' : '';
          final subtitle = [
            weekPart,
            weekdayStr,
            timePart,
            c['room_name'] ?? '',
          ].where((s) => s.isNotEmpty).join(' · ');

          dbItems.add(
            SearchResult(
              id: 'db_course_${c['uuid']}',
              title: c['course_name'] ?? '未知课程',
              subtitle: subtitle.isNotEmpty
                  ? subtitle
                  : (c['teacher_name'] ?? '未知教师'),
              icon: Icons.school,
              type: SearchResultType.course,
              extraData: {
                'uuid': c['uuid'],
                'table': 'courses',
                'teacher_name': c['teacher_name'],
                'room_name': c['room_name'],
                'week_index': weekIdx,
                'weekday': weekday,
                if (c['course_record'] != null)
                  'course_record': c['course_record'],
                'date_query_hint': ?dateQueryHint,
              },
            ),
          );
        }
      } catch (e) {
        // debugPrint('Course search error: $e');
      }
    }

    if (scope.includes(SearchResultType.countdown)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('countdowns');
      // ── 倒计时 ────────────────────────────────────────────────────────────
      try {
        final countdownMap = <String, Map<String, dynamic>>{};
        if (isDateQuery) {
          final items = await StorageService.getCountdowns(
            username,
            from: startOfDay!,
            to: endOfDay!,
          );
          if (shouldContinue?.call() == false) return dbItems;
          for (final item in items) {
            if (item.isDeleted) continue;
            countdownMap[item.id] = item.toJson();
          }
        } else {
          final rows = await db.searchCountdownsByTerms(searchTerms);
          if (shouldContinue?.call() == false) return dbItems;
          for (final row in rows) {
            countdownMap[row['uuid'].toString()] = row;
          }
        }
        final countdowns = countdownMap.values.where((cd) {
          if (isDateQuery) return true;
          final title = cd['title']?.toString() ?? '';
          final teamName = cd['team_name']?.toString() ?? '';
          final haystack = '$title $teamName';
          return _matchesAllTerms(haystack, searchTerms);
        }).toList();
        for (var cd in countdowns) {
          String subtitle = '未设置日期';
          final targetMs = cd['target_time'];
          if (targetMs != null) {
            final target = DateTime.fromMillisecondsSinceEpoch(
              targetMs is int
                  ? targetMs
                  : int.tryParse(targetMs.toString()) ?? 0,
            );
            final diff = CalendarDateMath.daysBetween(now, target);
            final dateStr = _searchDateFormat('yyyy/MM/dd').format(target);
            subtitle = diff >= 0
                ? '还有 $diff 天 · $dateStr'
                : '已过 ${-diff} 天 · $dateStr';
          }
          dbItems.add(
            SearchResult(
              id: 'db_countdown_${cd['uuid']}',
              title: cd['title'] ?? '未命名倒计时',
              subtitle: subtitle,
              icon: Icons.timer_outlined,
              type: SearchResultType.countdown,
              extraData: {
                'uuid': cd['uuid'],
                'table': 'countdowns',
                'fields': {
                  '目标日期': targetMs == null ? '' : subtitle,
                  '所属团队': cd['team_name']?.toString() ?? '',
                },
                'detail_label': '倒计时',
                'date_query_hint': ?dateQueryHint,
              },
            ),
          );
        }
      } catch (e) {
        // debugPrint('Countdown search error: $e');
      }
    }

    if (scope.includes(SearchResultType.log)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('timeLogs');
      // ── 时间日志 ──────────────────────────────────────────────────────────
      try {
        // Keep the legacy SharedPreferences-to-SQL migration guarantee while
        // all actual search filtering stays inside SQLite.
        await _prepareTimeLogs();
        if (shouldContinue?.call() == false) return dbItems;
        List<Map<String, dynamic>> matchedLogs;
        if (isDateQuery) {
          matchedLogs = await db.searchTimeLogsByDate(
            startOfDay!.millisecondsSinceEpoch,
            endOfDay!.millisecondsSinceEpoch,
          );
          if (shouldContinue?.call() == false) return dbItems;
        } else {
          final logMap = <String, Map<String, dynamic>>{};
          final rows = await db.searchTimeLogsByTerms(searchTerms);
          if (shouldContinue?.call() == false) return dbItems;
          for (final row in rows) {
            logMap[row['uuid'].toString()] = row;
          }
          matchedLogs = logMap.values.where((log) {
            final rawTitle = log['title'];
            final rawRemark = log['remark'];
            final title = rawTitle is String ? rawTitle : '';
            final remark = rawRemark is String ? rawRemark : '';
            final haystack = '$title $remark';
            return _matchesAllTerms(haystack, searchTerms);
          }).toList();
        }

        final logDateFormat = _searchDateFormat('MM/dd HH:mm');
        for (final log in matchedLogs) {
          final startMs = (log['start_time'] as num?)?.toInt() ?? 0;
          final endMs = (log['end_time'] as num?)?.toInt() ?? startMs;
          final start = DateTime.fromMillisecondsSinceEpoch(startMs);
          final end = DateTime.fromMillisecondsSinceEpoch(endMs);
          final mins = end.difference(start).inMinutes;
          final title = log['title']?.toString() ?? '';
          final remark = log['remark']?.toString();
          dbItems.add(
            SearchResult(
              id: 'db_log_${log['uuid']}',
              title: title.isNotEmpty ? title : '未命名专注',
              subtitle:
                  '$mins 分钟 · ${logDateFormat.format(start)}'
                  '${remark?.isNotEmpty == true ? ' · $remark' : ''}',
              icon: Icons.history_edu_rounded,
              type: SearchResultType.log,
              extraData: {
                'uuid': log['uuid'],
                'table': 'time_logs',
                'date_query_hint': ?dateQueryHint,
              },
            ),
          );
        }
      } catch (e) {
        // debugPrint('Time log search error: $e');
      }
    }

    if (scope.includes(SearchResultType.tag)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('tags');
      // ── 时间日志标签 ─────────────────────────────────────────────────────
      // 搜索标签名，点击可跳转到该标签的折线图统计界面
      try {
        final allTags = await PomodoroService.getTags();
        if (shouldContinue?.call() == false) return dbItems;
        final matchedTags = allTags.where(
          (t) => _matchesAllTerms(t.name, searchTerms),
        );
        for (var tag in matchedTags) {
          dbItems.add(
            SearchResult(
              id: 'db_tag_${tag.uuid}',
              title: tag.name,
              subtitle: '专注标签 · 点击查看折线图统计',
              icon: Icons.label_rounded,
              type: SearchResultType.tag,
              extraData: {
                'tag_uuid': tag.uuid,
                'tag_name': tag.name,
                'tag_color': tag.color,
                'route': '/time_log/tag',
              },
            ),
          );
        }
      } catch (e) {
        // debugPrint('Tag search error: $e');
      }
    }

    if (scope.includes(SearchResultType.app)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('screenTime');
      // ── 屏幕使用时间 (App 搜索) ─────────────────────────────────────────
      // 日期查询时：直接展示目标日期的聚合屏幕时间；普通关键词查询时：按应用名匹配历史缓存。
      if (isDateQuery) {
        try {
          final seenApps = <String>{};

          void addScreenTimeApps(
            List<dynamic> stats, {
            required bool includeAll,
          }) {
            for (var item in stats) {
              if (item is! Map) continue;
              final appName = item['app_name']?.toString().trim() ?? '';
              if (appName.isEmpty) continue;

              final normalized = appName.toLowerCase();
              if (seenApps.contains(normalized)) continue;

              final matchesQuery =
                  includeAll || _matchesAllTerms(appName, searchTerms);
              if (!matchesQuery) continue;

              seenApps.add(normalized);
              final subtitle = '屏幕使用时间 · 点击查看应用详情';

              dbItems.add(
                SearchResult(
                  id: 'db_app_$normalized',
                  title: appName,
                  subtitle: subtitle,
                  icon: Icons.smartphone_rounded,
                  type: SearchResultType.app,
                  extraData: {
                    'app_name': appName,
                    'route': '/screen_time/app',
                    'search_date_ms': startOfDay!.millisecondsSinceEpoch,
                    'date_query_hint': ?dateQueryHint,
                  },
                ),
              );
            }
          }

          final history = await StorageService.getScreenTimeHistory();
          if (shouldContinue?.call() == false) return dbItems;
          final targetDateKey = _searchDateFormat('yyyy-MM-dd')
              .format(startOfDay!);
          final targetDayStats = history[targetDateKey];

          if (targetDayStats != null && targetDayStats.isNotEmpty) {
            addScreenTimeApps(targetDayStats, includeAll: true);
          } else if (isTodayQuery) {
            final screenTimeCache = await StorageService.getScreenTimeCache();
            if (shouldContinue?.call() == false) return dbItems;
            if (screenTimeCache.isNotEmpty) {
              addScreenTimeApps(screenTimeCache, includeAll: true);
            }
          }
        } catch (e) {
          // debugPrint('Screen time search error: $e');
        }
      } else {
        try {
          final seenApps = <String>{};

          void addScreenTimeApps(List<dynamic> stats) {
            for (var item in stats) {
              if (item is! Map) continue;
              final appName = item['app_name']?.toString().trim() ?? '';
              if (appName.isEmpty) continue;

              final normalized = appName.toLowerCase();
              if (seenApps.contains(normalized)) continue;
              if (!normalized.contains(q)) continue;

              seenApps.add(normalized);
              dbItems.add(
                SearchResult(
                  id: 'db_app_$normalized',
                  title: appName,
                  subtitle: '屏幕使用时间 · 点击查看应用详情',
                  icon: Icons.smartphone_rounded,
                  type: SearchResultType.app,
                  extraData: {'app_name': appName, 'route': '/screen_time/app'},
                ),
              );
            }
          }

          final screenTimeCache = await StorageService.getScreenTimeCache();
          if (shouldContinue?.call() == false) return dbItems;
          if (screenTimeCache.isNotEmpty) {
            addScreenTimeApps(screenTimeCache);
          }

          final history = await StorageService.getScreenTimeHistory();
          if (shouldContinue?.call() == false) return dbItems;
          for (final dayEntry in history.entries) {
            final dayStats = dayEntry.value;
            if (dayStats.isEmpty) continue;
            addScreenTimeApps(dayStats);
          }
        } catch (e) {
          // debugPrint('Screen time search error: $e');
        }
      }
    }

    if (scope.includes(SearchResultType.log)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('pomodoro');
      // ── 番茄钟 ──────────────────────────────────────────────────────────
      {
        try {
          final matchingRange = isDateQuery
              ? await PomodoroService.getRecordsInRange(startOfDay!, endOfDay!)
              : await PomodoroService.getRecords();
          if (shouldContinue?.call() == false) return dbItems;
          final tagNames = isDateQuery
              ? const <String, String>{}
              : {
                  for (final tag in await PomodoroService.getTags())
                    tag.uuid: tag.name,
                };
          if (shouldContinue?.call() == false) return dbItems;
          final matchedPoms = isDateQuery
              ? matchingRange
              : matchingRange.where((p) {
                  final searchable = StringBuffer()
                    ..write(p.todoTitle ?? '')
                    ..write(' ')
                    ..write(p.note ?? '');
                  for (final tagUuid in p.tagUuids) {
                    final tagName = tagNames[tagUuid];
                    if (tagName == null) continue;
                    searchable
                      ..write(' ')
                      ..write(tagName);
                  }
                  return _matchesAllTerms(searchable.toString(), searchTerms);
                }).toList();
          final pomodoroTimeFormat = _searchDateFormat('HH:mm');
          for (var p in matchedPoms) {
            final start = DateTime.fromMillisecondsSinceEpoch(p.startTime);
            final end = p.endTime != null
                ? DateTime.fromMillisecondsSinceEpoch(p.endTime!)
                : start.add(Duration(minutes: p.effectiveDuration ~/ 60));
            final mins = p.effectiveDuration ~/ 60;
            dbItems.add(
              SearchResult(
                id: 'db_pom_${p.uuid}',
                title: p.todoTitle?.isNotEmpty == true ? p.todoTitle! : '专注记录',
                subtitle:
                    '$mins 分钟 · ${pomodoroTimeFormat.format(start)}'
                    ' - ${pomodoroTimeFormat.format(end)} · ${p.isCompleted ? "完成" : "中断"}',
                icon: Icons.timer_outlined,
                type: SearchResultType.log, // 与时间日志归在一组
                extraData: {
                  'uuid': p.uuid,
                  'table': 'pomodoro_records',
                  'date_query_hint': ?dateQueryHint,
                },
              ),
            );
          }
        } catch (e) {
          // debugPrint('Pomodoro search error: $e');
        }
      }
    }

    if (scope.includes(SearchResultType.todoGroup)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('todoGroups');
      // ── 待办文件夹 ────────────────────────────────────────────────────────
      try {
        final groupMap = <String, Map<String, dynamic>>{};
        final rows = await db.searchTodoGroupsByTerms(searchTerms);
        if (shouldContinue?.call() == false) return dbItems;
        for (final row in rows) {
          groupMap[row['uuid'].toString()] = row;
        }
        final groups = groupMap.values.where((g) {
          final name = g['name']?.toString() ?? '';
          final teamName = g['team_name']?.toString() ?? '';
          final haystack = '$name $teamName';
          return _matchesAllTerms(haystack, searchTerms);
        }).toList();
        for (var g in groups) {
          dbItems.add(
            SearchResult(
              id: 'db_group_${g['uuid']}',
              title: g['name'] ?? '未命名文件夹',
              subtitle: g['team_name'] != null
                  ? '团队文件夹 · ${g['team_name']}'
                  : '个人文件夹',
              icon: Icons.folder_rounded,
              type: SearchResultType.todoGroup,
              extraData: {'uuid': g['uuid'], 'table': 'todo_groups'},
            ),
          );
        }
      } catch (e) {
        // debugPrint('Todo group search error: $e');
      }
    }

    return dbItems;
  }

  /// 🚀 猜你想搜：非常轻量的启发式“小模型”
  /// 基于时间、任务紧急度、搜索历史、近期活动进行智能推荐
  Future<List<SearchResult>> guessSearch({
    bool Function()? shouldContinue,
  }) async {
    final suggestions = <SearchResult>[];
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final username = await StorageService.getLoginSession() ?? 'default';
    if (shouldContinue?.call() == false) return suggestions;
    // Start independent recommendation inputs together. Processing remains
    // ordered so the visible ranking is stable.
    final coursesFuture = CourseService.getAllCourses(username)
        .catchError((_) => <CourseItem>[]);
    // Keep the recommendation count aligned with the todo list and filter
    // used by the result detail and the home screen.
    final overdueTodosFuture =
        Future.wait<dynamic>([
              StorageService.getTodos(username),
              HabitRepository.getHabitOnlyRecurringTodoSeriesIds(),
            ])
            .then(
              (results) => shouldContinue?.call() == false
                  ? <TodoItem>[]
                  : SearchService._filterOverdueTodos(
                      todos: results[0] as List<TodoItem>,
                      excludedRecurrenceSeriesIds: results[1] as Set<String>,
                      before: now,
                    ),
            )
            .catchError((_) => <TodoItem>[]);
    final overdueCountFuture = overdueTodosFuture.then(
      (overdueTodos) => overdueTodos.length,
    );
    final topHistoryFuture = db
        .getRecentSearches(limit: 1)
        .catchError((_) => <Map<String, dynamic>>[]);
    final recentHistoryFuture = db
        .getRecentSearches(limit: 5, currentHour: now.hour)
        .catchError((_) => <Map<String, dynamic>>[]);
    final pomodoroFuture = PomodoroService.getLatestRecord().catchError(
      (_) => null,
    );

    // 1. 时间维度：根据时刻推荐
    final hour = now.hour;

    // 🚀 新增：基于“最近”课程的推荐 (全量时间轴最近)
    try {
      final allCourses = await coursesFuture;
      if (shouldContinue?.call() == false) return suggestions;
      if (allCourses.isNotEmpty) {
        CourseItem? nearestCourse;
        int minDiffSeconds = 0x7FFFFFFF; // 很大一个数
        String reason = "";

        for (var c in allCourses) {
          try {
            final dateParts = c.date.split('-');
            if (dateParts.length != 3) continue;

            final startDt = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              c.startTime ~/ 100,
              c.startTime % 100,
            );
            final endDt = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              c.endTime ~/ 100,
              c.endTime % 100,
            );

            // 1. 如果正在进行，优先级最高
            if (now.isAfter(startDt) && now.isBefore(endDt)) {
              nearestCourse = c;
              minDiffSeconds = 0;
              reason = "正在进行的课程";
              break;
            }

            // 2. 计算绝对距离
            final diffToStart = now.difference(startDt).inSeconds.abs();
            final diffToEnd = now.difference(endDt).inSeconds.abs();
            final localMin = diffToStart < diffToEnd ? diffToStart : diffToEnd;

            if (localMin < minDiffSeconds) {
              minDiffSeconds = localMin;
              nearestCourse = c;
              reason = now.isBefore(startDt) ? "即将开始的课程" : "最近结束的课程";
            }
          } catch (_) {}
        }

        if (nearestCourse != null) {
          suggestions.add(
            SearchResult(
              id: 'guess_recent_course',
              title: nearestCourse.courseName,
              subtitle: '🎓 $reason · ${nearestCourse.roomName}',
              icon: Icons.school_rounded,
              type: SearchResultType.recommend,
              extraData: {
                'action': 'apply_query',
                'query': nearestCourse.courseName,
              },
            ),
          );
        }
      }
    } catch (_) {}

    if (hour >= 6 && hour <= 10) {
      suggestions.add(
        SearchResult(
          id: 'guess_today_plan',
          title: '查看今日课表与待办',
          subtitle: '✨ 早安！开启高效的一天',
          icon: Icons.wb_sunny_outlined,
          type: SearchResultType.recommend,
          extraData: {'action': 'navigate', 'route': '/course/weekly'},
        ),
      );
    } else if (hour >= 21 || hour <= 2) {
      suggestions.add(
        SearchResult(
          id: 'guess_today_stats',
          title: '查看今日完成情况',
          subtitle: '🌙 晚安！回顾今日成就，展望下周规划',
          icon: Icons.insert_chart_outlined,
          type: SearchResultType.recommend,
          extraData: {
            'action': 'navigate',
            'route': '/personal_timeline',
            'initialDimension': 0, // 🚀 1 代表周视图
          },
        ),
      );
    }

    // 2. 紧急维度：逾期任务探测 (权重最高)
    try {
      final overdueCount = await overdueCountFuture;
      if (shouldContinue?.call() == false) return suggestions;
      if (overdueCount > 0) {
        suggestions.add(
          SearchResult(
            id: 'guess_overdue',
            title: '处理逾期任务 ($overdueCount)',
            subtitle: '⚠️ 发现已截止但未完成的任务，建议优先处理',
            icon: Icons.priority_high_rounded,
            type: SearchResultType.recommend,
            extraData: {'action': 'filter_overdue'},
          ),
        );
      }
    } catch (_) {}

    // 3. 历史频率维度：最常搜索 (Top 1)
    try {
      final topHistory = await topHistoryFuture; // 不按时段，按绝对频率
      if (shouldContinue?.call() == false) return suggestions;
      if (topHistory.isNotEmpty) {
        final h = topHistory.first;
        suggestions.add(
          SearchResult(
            id: 'guess_most_frequent',
            title: h['query'],
            subtitle: '💡 您最常搜索的内容',
            icon: Icons.lightbulb_outline_rounded,
            type: SearchResultType.recommend,
            extraData: {'action': 'apply_query', 'query': h['query']},
          ),
        );
      }
    } catch (_) {}

    // 4. 历史时间维度：最近搜索 (时段敏感型，展示前 5 条)
    try {
      final history = await recentHistoryFuture;
      if (shouldContinue?.call() == false) return suggestions;
      for (var h in history) {
        // 如果已经作为“最常搜索”推荐过了，就不再在历史里重复显示（可选）
        suggestions.add(
          SearchResult(
            id: 'history_${h['query']}',
            title: h['query'],
            subtitle: '最近搜过',
            icon: Icons.history_rounded,
            type: SearchResultType.history,
            extraData: {'action': 'apply_query', 'query': h['query']},
          ),
        );
      }
    } catch (_) {}

    // 4. 活动维度：近期专注活动
    try {
      final lastPom = await pomodoroFuture;
      if (shouldContinue?.call() == false) return suggestions;
      if (lastPom != null) {
        if (lastPom.todoTitle != null && lastPom.todoTitle!.isNotEmpty) {
          suggestions.add(
            SearchResult(
              id: 'guess_recent_focus',
              title: '继续搜索: ${lastPom.todoTitle}',
              subtitle: '🔥 您最近正在专注这项任务',
              icon: Icons.local_fire_department_rounded,
              type: SearchResultType.recommend,
              extraData: {'action': 'ai_query', 'query': lastPom.todoTitle},
            ),
          );
        }
      }
    } catch (_) {}

    // 5. 统计维度：今日屏幕时间
    suggestions.add(
      SearchResult(
        id: 'guess_screen_time',
        title: '今日屏幕使用时长',
        subtitle: '📊 看看今天在手机上花了多少时间',
        icon: Icons.pie_chart_rounded,
        type: SearchResultType.recommend,
        extraData: {'action': 'navigate', 'route': '/screen_time'},
      ),
    );

    // 6. 探索维度：功能探索百宝箱
    suggestions.add(
      SearchResult(
        id: 'guess_feature_explorer',
        title: '功能探索百宝箱 · 隐藏技巧与新功能',
        subtitle: '🧭 不知道某个功能在哪里？点击查看全景功能地图与操作指南',
        icon: Icons.explore_rounded,
        type: SearchResultType.recommend,
        extraData: {'action': 'navigate', 'route': '/feature_explorer'},
      ),
    );

    return suggestions;
  }
}
