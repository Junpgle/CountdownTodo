part of '../course_settings_page.dart';

extension _CourseSettingsSemesters on _CourseSettingsPageState {
  Widget _buildSemesterTile(SemesterInfo semester) {
    final isActive = semester.id == _activeSemesterId;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.5)
              : theme.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: isActive
            ? colorScheme.primary.withValues(alpha: 0.1)
            : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () {
            if (!isActive) _activateSemester(semester);
          },
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive
                  ? colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.check_circle : Icons.school_outlined,
              color: isActive ? colorScheme.primary : Colors.grey.shade600,
              size: 22,
            ),
          ),
          title: Text(
            semester.name,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
              fontSize: 16,
              color: isActive ? colorScheme.primary : null,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '开学: ${AppTimeFormats.dateFormatter('yyyy/MM/dd').format(semester.startDate)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (semester.endDate != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.flight_takeoff_outlined,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '放假: ${AppTimeFormats.dateFormatter('yyyy/MM/dd').format(semester.endDate!)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final now = DateTime.now();
                      final start = CalendarDateMath.dateOnly(
                        semester.startDate,
                      );
                      final end = DateTime(
                        semester.endDate!.year,
                        semester.endDate!.month,
                        semester.endDate!.day,
                        23,
                        59,
                        59,
                      );

                      double progress = 0.0;
                      if (now.isAfter(end)) {
                        progress = 1.0;
                      } else if (now.isAfter(start)) {
                        final total = end.difference(start).inMilliseconds;
                        final elapsed = now.difference(start).inMilliseconds;
                        progress = (elapsed / total).clamp(0.0, 1.0);
                      }

                      final percent = (progress * 100).toInt();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '学期进度',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '$percent%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: progress == 1.0
                                      ? Colors.green
                                      : (isActive
                                            ? colorScheme.primary
                                            : Colors.grey.shade600),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: Colors.grey.withValues(
                                alpha: 0.2,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress == 1.0
                                    ? Colors.green
                                    : (isActive
                                          ? colorScheme.primary
                                          : Colors.blue.shade400),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑',
                onPressed: () => _editSemester(semester),
              ),
              if (!isActive)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '删除',
                  onPressed: () => _deleteSemester(semester),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _activateSemester(SemesterInfo semester) async {
    // 更新所有学期的 isCurrent 状态
    final updatedSemesters = _semesters.map((s) {
      if (s.id == semester.id) {
        return SemesterInfo(
          id: s.id,
          name: s.name,
          startDate: s.startDate,
          endDate: s.endDate,
          isCurrent: true,
        );
      } else if (s.isCurrent) {
        return SemesterInfo(
          id: s.id,
          name: s.name,
          startDate: s.startDate,
          endDate: s.endDate,
          isCurrent: false,
        );
      }
      return s;
    }).toList();

    await StorageService.saveSemesters(updatedSemesters);
    await StorageService.setActiveSemesterId(semester.id);

    if (mounted) {
      _mutateState(() {
        _semesters = updatedSemesters;
        _activeSemesterId = semester.id;
        _semesterStart = semester.startDate;
        _semesterEnd = semester.endDate;
      });
    }

    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('已切换到: ${semester.name}')),
      );
    }
  }

  Future<void> _editSemester(
    SemesterInfo semester, {
    String? focusLabel,
  }) async {
    final nameController = TextEditingController(text: semester.name);
    DateTime? startDate = semester.startDate;
    DateTime? endDate = semester.endDate;

    final result = await showAppDialog<SemesterInfo>(
      context: context,
      builder: (ctx) {
        return SettingsFocusPage(
          labels: focusLabel == null
              ? const []
              : [
                  focusLabel,
                  if (focusLabel == '开学日期:') '选择开学日期',
                  if (focusLabel == '放假日期:') '选择放假日期 (可选)',
                ],
          child: StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text('编辑学期'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: '学期名称',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            '开学日期: ${AppTimeFormats.dateFormatter('yyyy/MM/dd').format(startDate!)}',
                          ),
                          onPressed: () async {
                            final picked = await showAppDatePicker(
                              context: context,
                              initialDate: startDate!,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null && context.mounted) {
                              _mutateState(
                                () => startDate =
                                    CourseScheduleSemantics.mondayOf(picked),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            endDate != null
                                ? '放假日期: ${AppTimeFormats.dateFormatter('yyyy/MM/dd').format(endDate!)}'
                                : '选择放假日期 (可选)',
                          ),
                          onPressed: () async {
                            final picked = await showAppDatePicker(
                              context: context,
                              initialDate:
                                  endDate ??
                                  startDate!.add(const Duration(days: 120)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null && context.mounted) {
                              _mutateState(() => endDate = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (nameController.text.isEmpty || startDate == null) {
                        AppSnackBars.showSnackBar(
                          context,
                          const SnackBar(content: Text('请填写学期名称和开学日期')),
                        );
                        return;
                      }
                      final normalizedStart = CourseScheduleSemantics.mondayOf(
                        startDate!,
                      );
                      Navigator.pop(
                        ctx,
                        SemesterInfo(
                          id: semester.id,
                          name: nameController.text,
                          startDate: normalizedStart,
                          endDate: endDate,
                          isCurrent: semester.isCurrent,
                        ),
                      );
                    },
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (result != null) {
      final updatedSemesters = _semesters.map((s) {
        if (s.id == result.id) return result;
        return s;
      }).toList();

      await StorageService.saveSemesters(updatedSemesters);

      if (mounted) {
        _mutateState(() {
          _semesters = updatedSemesters;
          if (result.isCurrent) {
            _semesterStart = result.startDate;
            _semesterEnd = result.endDate;
          }
        });
      }

      // 自动同步到服务器
      await _syncSemestersToServer();

      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('学期已更新')),
        );
      }
    }
  }

  Future<void> _deleteSemester(SemesterInfo semester) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: '删除学期',
      message: '确定要删除 "${semester.name}" 吗？\n\n该学期下的课程数据不会被删除。',
      confirmLabel: '删除',
      destructive: true,
    );

    if (confirmed) {
      final updatedSemesters = _semesters
          .where((s) => s.id != semester.id)
          .toList();
      await StorageService.saveSemesters(updatedSemesters);

      if (mounted) {
        _mutateState(() {
          _semesters = updatedSemesters;
        });
      }

      // 自动同步到服务器
      await _syncSemestersToServer();

      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('已删除: ${semester.name}')),
        );
      }
    }
  }

  /// 同步学期数据到服务器
  Future<void> _syncSemestersToServer() async {
    if (_userId == null) return;

    try {
      final semestersData = _semesters.map((s) => s.toCloudJson()).toList();
      await ApiService.uploadUserSettings(
        semesterStartMs: _semesterStart?.millisecondsSinceEpoch,
        semesterEndMs: _semesterEnd?.millisecondsSinceEpoch,
        semesters: semestersData,
      );
    } catch (e) {
      debugPrint('[CourseSettings] 同步学期设置失败: $e');
    }
  }

  /// 根据开学日期自动生成学期名称
  String _generateSemesterName(DateTime startDate) {
    final year = startDate.year;
    final month = startDate.month;

    // 3月-5月：春季
    // 6月-8月：夏季
    // 9月-11月：秋季
    // 12月-次年2月：冬季
    if (month >= 3 && month <= 5) {
      return '$year年春季';
    } else if (month >= 6 && month <= 8) {
      return '$year年夏季';
    } else if (month >= 9 && month <= 11) {
      return '$year年秋季';
    } else {
      // 12月、1月、2月
      if (month == 12) {
        return '$year年冬季';
      } else {
        return '$year年冬季';
      }
    }
  }

  Future<void> _showAddSemesterDialog({String? focusLabel}) async {
    final nameController = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;

    final result = await showAppDialog<SemesterInfo>(
      context: context,
      builder: (ctx) {
        return SettingsFocusPage(
          labels: focusLabel == null
              ? const []
              : [
                  focusLabel,
                  if (focusLabel == '开学日期:') '选择开学日期',
                  if (focusLabel == '放假日期:') '选择放假日期 (可选)',
                ],
          child: StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text('添加新学期'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            startDate != null
                                ? '开学日期: ${AppTimeFormats.dateFormatter('yyyy/MM/dd').format(startDate!)}'
                                : '选择开学日期',
                          ),
                          onPressed: () async {
                            final picked = await showAppDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              helpText: '选择开学日期',
                            );
                            if (picked != null && context.mounted) {
                              final normalizedStart =
                                  CourseScheduleSemantics.mondayOf(picked);
                              _mutateState(() {
                                startDate = normalizedStart;
                                // 自动生成学期名称
                                nameController.text = _generateSemesterName(
                                  normalizedStart,
                                );
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            endDate != null
                                ? '放假日期: ${AppTimeFormats.dateFormatter('yyyy/MM/dd').format(endDate!)}'
                                : '选择放假日期 (可选)',
                          ),
                          onPressed: () async {
                            final picked = await showAppDatePicker(
                              context: context,
                              initialDate:
                                  startDate?.add(const Duration(days: 120)) ??
                                  DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              helpText: '选择放假日期',
                            );
                            if (picked != null && context.mounted) {
                              _mutateState(() => endDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: '学期名称',
                          hintText: '自动生成，可手动修改',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (nameController.text.isEmpty || startDate == null) {
                        AppSnackBars.showSnackBar(
                          context,
                          const SnackBar(content: Text('请选择开学日期')),
                        );
                        return;
                      }
                      final normalizedStart = CourseScheduleSemantics.mondayOf(
                        startDate!,
                      );
                      final id =
                          'semester_${normalizedStart.millisecondsSinceEpoch}';
                      Navigator.pop(
                        ctx,
                        SemesterInfo(
                          id: id,
                          name: nameController.text,
                          startDate: normalizedStart,
                          endDate: endDate,
                        ),
                      );
                    },
                    child: const Text('添加'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (result != null) {
      final updatedSemesters = [..._semesters, result];
      await StorageService.saveSemesters(updatedSemesters);

      if (mounted) {
        _mutateState(() {
          _semesters = updatedSemesters;
        });
      }

      // 自动同步到服务器
      await _syncSemestersToServer();

      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('已添加: ${result.name}')),
        );
      }
    }
  }

  Future<void> _showClearSemesterCoursesDialog() async {
    if (_semesters.isEmpty) return;

    // 显示学期选择对话框
    final selectedSemester = await showAppDialog<SemesterInfo>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.delete_sweep_outlined, color: Colors.red),
              const SizedBox(width: 10),
              const Text('清除学期课程数据'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '选择要清除课程数据的学期：',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ..._semesters.map(
                  (semester) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, semester),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.school_outlined,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  semester.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '开学: ${AppTimeFormats.dateFormatter('yyyy/MM/dd').format(semester.startDate)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

    if (selectedSemester == null || !mounted) return;

    // 确认删除
    final confirmed = await AppDialogs.confirm(
      context,
      title: '确认清除',
      message: '确定要清除 "${selectedSemester.name}" 的所有课程数据吗？\n\n此操作不可撤销。',
      confirmLabel: '清除',
      destructive: true,
    );

    if (!confirmed) return;

    // 执行清除
    try {
      await CourseService.clearCoursesForSemester(
        _username,
        selectedSemester.id,
      );
      await _rescheduleReminders();

      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('已清除 "${selectedSemester.name}" 的课程数据')),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(context, SnackBar(content: Text('清除失败: $e')));
      }
    }
  }
}
