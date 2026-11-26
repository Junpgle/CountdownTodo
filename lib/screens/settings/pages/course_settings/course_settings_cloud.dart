part of '../course_settings_page.dart';

extension _CourseSettingsCloud on _CourseSettingsPageState {
  Future<void> _uploadCoursesToCloud() async {
    if (_userId == null || _username.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请先登录账号')),
      );
      return;
    }

    final confirm = await AppDialogs.confirm(
      context,
      title: '上传课表到云端',
      message: '这将覆盖你云端的所有课表数据。\n\n用于与电脑或其他设备同步。\n\n是否继续？',
      confirmLabel: '上传',
    );

    if (!confirm || !mounted) return;

    _showLoadingDialog("正在同步到云端...");

    try {
      final result = await CourseService.syncCoursesToCloud(
        _username,
        _userId!,
      );
      if (!mounted) return;

      if (result['success'] == true) {
        final startMs = _semesterStart != null
            ? DateTime(
                _semesterStart!.year,
                _semesterStart!.month,
                _semesterStart!.day,
              ).millisecondsSinceEpoch
            : null;
        final endMs = _semesterEnd != null
            ? DateTime(
                _semesterEnd!.year,
                _semesterEnd!.month,
                _semesterEnd!.day,
              ).millisecondsSinceEpoch
            : null;

        final semestersData = _semesters.map((s) => s.toCloudJson()).toList();
        final settingsUploaded = await ApiService.uploadUserSettings(
          semesterStartMs: startMs,
          semesterEndMs: endMs,
          semesters: semestersData,
        );
        if (!settingsUploaded) {
          result['success'] = false;
          result['message'] = '课表已上传，但学期设置同步失败';
        }
      }

      if (!mounted) return;
      if (result['success'] == true) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('✅ 课表已成功同步到云端')),
        );
      } else if (result['isLimitExceeded'] == true) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text(result['message'] ?? '今日同步次数已达上限')),
        );
      } else {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text(result['message'] ?? '同步失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(context, SnackBar(content: Text('同步失败: $e')));
      }
    } finally {
      await _closeLoadingDialog();
    }
  }

  int? _readCloudInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  DateTime? _readCloudDate(dynamic value) {
    final milliseconds = _readCloudInt(value);
    if (milliseconds != null && milliseconds > 0) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _fetchCoursesFromCloud() async {
    if (_userId == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请先登录账号')),
      );
      return;
    }

    _showLoadingDialog("正在获取云端数据...");

    try {
      final userSettings = await ApiService.fetchUserSettings();
      final data = await ApiService.fetchCoursesForSemesters(
        _userId!,
        ApiService.semesterIdsFromSettings(userSettings),
      );

      if (!mounted) return;

      DateTime? importedStart = _semesterStart;
      DateTime? importedEnd = _semesterEnd;
      var importedSemesters = List<SemesterInfo>.from(_semesters);
      var hasCloudSemesterList = false;

      // 先在内存中校验和准备云端学期设置。用户确认导入方式并且课程写入
      // 成功之前，不改变本地设置，避免取消导入后留下半套同步结果。
      if (userSettings != null) {
        final cloudStart = _readCloudDate(userSettings['semester_start']);
        final cloudEnd = _readCloudDate(userSettings['semester_end']);
        if (cloudStart != null) importedStart = cloudStart;
        if (cloudEnd != null) importedEnd = cloudEnd;

        final rawSemesters = userSettings['semesters'];
        if (rawSemesters is List) {
          final cloudSemesters = <SemesterInfo>[];
          for (final rawSemester in rawSemesters) {
            if (rawSemester is! Map) {
              AppSnackBars.showSnackBar(
                context,
                const SnackBar(content: Text('❌ 云端学期设置格式错误，未导入课表')),
              );
              return;
            }
            final semester = SemesterInfo.fromCloudJson(
              Map<String, dynamic>.from(rawSemester),
            );
            cloudSemesters.add(semester);
          }
          importedSemesters = cloudSemesters;
          hasCloudSemesterList = true;
        }
      }

      // Validate both the cloud list and the local fallback list. A cloud
      // `semesters: []` is an explicit configuration, not a reason to reuse
      // stale local semesters; duplicate IDs would otherwise collapse in the
      // startsBySemester map and leave ambiguous course ownership.
      final importedSemesterIds = <String>{};
      for (final semester in importedSemesters) {
        final semesterId = CourseScheduleSemantics.canonicalSemesterId(
          semester.id,
        );
        if (!CourseImportPreflight.hasUsableSemester(semester) ||
            !importedSemesterIds.add(semesterId)) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(content: Text('❌ 存在无效或重复的学期设置，请修正后再导入')),
          );
          return;
        }
      }

      if (data.isEmpty) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('❌ 获取失败，云端暂无课表数据')),
        );
        return;
      }

      final startsBySemester = <String, DateTime>{};
      for (final semester in importedSemesters) {
        startsBySemester.putIfAbsent(
          CourseScheduleSemantics.canonicalSemesterId(semester.id),
          () => semester.startDate,
        );
      }
      if (importedStart != null) {
        startsBySemester.putIfAbsent('default', () => importedStart!);
      }

      int skippedCourses = 0;
      var courses = <CourseItem>[];
      for (final rawCourse in data) {
        if (rawCourse is! Map) {
          skippedCourses++;
          continue;
        }

        final course = Map<String, dynamic>.from(rawCourse);
        final courseName =
            (course['course_name'] ?? course['courseName'])
                ?.toString()
                .trim() ??
            '';
        if (courseName.isEmpty) {
          skippedCourses++;
          continue;
        }

        final semesterId = CourseScheduleSemantics.canonicalSemesterId(
          (course['semester'] ??
                  course['semester_id'] ??
                  course['semesterId'] ??
                  'default')
              .toString(),
        );
        final weekIndex =
            (_readCloudInt(course['week_index'] ?? course['weekIndex']) ?? 1)
                .clamp(1, 1000)
                .toInt();
        final weekday = (_readCloudInt(course['weekday']) ?? 1)
            .clamp(DateTime.monday, DateTime.sunday)
            .toInt();
        final semesterStartForCourse = startsBySemester[semesterId];
        final cloudDate = (course['date']?.toString() ?? '').trim();

        // A course must reference a configured semester. Accepting an unknown
        // semester merely because it has a concrete date creates an orphan
        // row which the semester-based UI cannot select later.
        if (semesterStartForCourse == null ||
            (cloudDate.isNotEmpty && DateTime.tryParse(cloudDate) == null)) {
          skippedCourses++;
          continue;
        }

        final date = CourseScheduleSemantics.dateFor(
          semesterStart: semesterStartForCourse,
          weekIndex: weekIndex,
          weekday: weekday,
        );
        courses.add(
          CourseItem(
            uuid: (course['uuid'] ?? course['id'])?.toString(),
            courseName: courseName,
            roomName:
                (course['room_name'] ?? course['roomName'])?.toString() ?? '',
            teacherName:
                (course['teacher_name'] ?? course['teacherName'])?.toString() ??
                '',
            startTime:
                _readCloudInt(course['start_time'] ?? course['startTime']) ?? 0,
            endTime:
                _readCloudInt(course['end_time'] ?? course['endTime']) ?? 0,
            weekday: weekday,
            weekIndex: weekIndex,
            lessonType: (course['lesson_type'] ?? course['lessonType'])
                ?.toString(),
            date: date,
            semesterId: semesterId,
          ),
        );
      }

      if (skippedCourses > 0) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text(
              '⚠️ 云端有 $skippedCourses 条课程无法确定所属学期开学日期或数据格式，已全部取消导入；请先配置学期',
            ),
          ),
        );
        return;
      }
      if (courses.isEmpty) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('❌ 云端课表没有可导入的课程')),
        );
        return;
      }

      if (courses.any(
        (course) => !CourseScheduleSemantics.hasUsableTime(course),
      )) {
        await _closeLoadingDialog();
        if (!mounted) return;
        final repaired = await CourseTimeRepairDialog.show(context, courses);
        if (repaired == null || !mounted) return;
        courses = repaired;
        if (courses.any(
          (course) => !CourseScheduleSemantics.hasUsableTime(course),
        )) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(content: Text('❌ 仍有课程缺少有效时间，已取消导入')),
          );
          return;
        }
      }

      await _closeLoadingDialog();

      // 检测冲突并让用户选择导入模式。确认前不执行任何本地写入。
      final conflicts = await CourseService.detectTimeConflicts(
        _username,
        courses,
      );
      if (!mounted) return;
      final ImportMode? mode = await _askCloudImportMode(courses, conflicts);
      if (mode == null || !mounted) return;

      if (mode == ImportMode.merge) {
        await CourseService.mergeCoursesToSql(_username, courses);
      } else {
        await CourseService.replaceCoursesForSemesters(_username, courses);
      }

      var settingsSyncFailed = false;
      try {
        if (userSettings != null) {
          if (userSettings.containsKey('semester_start') &&
              importedStart != null) {
            await StorageService.saveAppSetting(
              StorageService.keySemesterStart,
              importedStart.toIso8601String(),
            );
          }
          if (userSettings.containsKey('semester_end') && importedEnd != null) {
            await StorageService.saveAppSetting(
              StorageService.keySemesterEnd,
              importedEnd.toIso8601String(),
            );
          }
          if (hasCloudSemesterList) {
            await StorageService.saveSemesters(importedSemesters);
            final currentSemester = importedSemesters.where((s) => s.isCurrent);
            if (currentSemester.isNotEmpty) {
              await StorageService.setActiveSemesterId(
                currentSemester.first.id,
              );
            }
          }
        }
      } catch (error) {
        settingsSyncFailed = true;
        debugPrint('[CourseSettings] 保存云端学期设置失败: $error');
      }

      if (!mounted) return;
      _mutateState(() {
        _semesterStart = importedStart;
        _semesterEnd = importedEnd;
        if (hasCloudSemesterList) _semesters = importedSemesters;
        final currentSemester = importedSemesters.where((s) => s.isCurrent);
        if (currentSemester.isNotEmpty) {
          _activeSemesterId = currentSemester.first.id;
        }
      });
      await _rescheduleReminders();
      if (!mounted) return;

      final modeText = mode == ImportMode.merge ? '合并' : '同步';
      final suffix = settingsSyncFailed ? '，但学期设置保存失败' : '';
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text('✅ 成功从云端$modeText ${courses.length} 条课程$suffix'),
        ),
      );
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('❌ 发生错误: $e')),
        );
      }
    } finally {
      await _closeLoadingDialog();
    }
  }

  /// 云端获取时的导入模式选择
  Future<ImportMode?> _askCloudImportMode(
    List<CourseItem> newCourses,
    List<CourseItem> conflicts,
  ) async {
    if (conflicts.isNotEmpty) {
      // 有冲突：提示用户
      final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (ctx) {
          final conflictSummary = <String, int>{};
          for (final c in conflicts) {
            final key = '${c.courseName} (${c.teacherName})';
            conflictSummary[key] = (conflictSummary[key] ?? 0) + 1;
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Text('检测到时间冲突'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '以下 ${conflictSummary.length} 门课程与云端课表存在时间冲突，导入后将被覆盖：',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ...conflictSummary.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.circle, size: 8, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${e.key}${e.value > 1 ? " (${e.value}节)" : ""}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '不冲突的课程将保留。',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续导入'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return null;
      return ImportMode.merge;
    } else {
      // 无冲突：让用户选择
      final mode = await showAppDialog<ImportMode>(
        context: context,
        builder: (ctx) {
          final colorScheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.cloud_download_outlined),
                SizedBox(width: 10),
                Text('选择获取方式'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CourseImportOptionCard(
                  icon: Icons.swap_horiz_rounded,
                  title: '替换本地课表',
                  subtitle: '清除本地课表，仅保留云端数据',
                  accentColor: colorScheme.secondary,
                  onTap: () => Navigator.pop(ctx, ImportMode.replace),
                ),
                const SizedBox(height: 12),
                CourseImportOptionCard(
                  icon: Icons.merge_rounded,
                  title: '与本地课表共存',
                  subtitle: '合并云端和本地课表，适用于不同学期',
                  accentColor: colorScheme.primary,
                  highlighted: true,
                  onTap: () => Navigator.pop(ctx, ImportMode.merge),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          );
        },
      );

      return mode;
    }
  }
}
