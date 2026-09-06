import 'package:flutter/material.dart';

import '../models.dart';
import '../storage_service.dart';
import 'course_schedule_semantics.dart';

/// Performs the checks that must succeed before a course import starts.
///
/// Importers need a concrete semester start date to turn relative week/day
/// values into dates. Keeping this check in one place prevents each entry
/// point from discovering the same missing configuration at a different stage.
class CourseImportPreflight {
  const CourseImportPreflight._();

  /// Returns whether a semester can safely be used as an import target.
  static bool hasUsableSemester(SemesterInfo semester) {
    if (semester.id.trim().isEmpty || semester.name.trim().isEmpty) {
      return false;
    }

    // SemesterInfo.fromJson uses the Unix epoch when an invalid start date was
    // stored. Treat that sentinel as missing configuration.
    if (semester.startDate.millisecondsSinceEpoch == 0) return false;

    final endDate = semester.endDate;
    if (endDate != null &&
        _dateOnly(endDate).isBefore(_dateOnly(semester.startDate))) {
      return false;
    }
    return true;
  }

  /// Selects a valid import target before any source/file/webview work starts.
  ///
  /// With one valid semester there is no reason to add another confirmation
  /// step. With multiple semesters the user must explicitly choose one. When
  /// none exists, the same flow offers creating the missing semester.
  static Future<SemesterInfo?> selectTargetSemester(
      BuildContext context) async {
    final semesters =
        (await StorageService.getSemesters()).where(hasUsableSemester).toList();
    final activeSemesterId = await StorageService.getActiveSemesterId();
    if (!context.mounted) return null;

    if (semesters.length == 1) return semesters.single;

    final selected = await showDialog<SemesterInfo>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final hasConfiguredSemester = semesters.isNotEmpty;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.school_outlined, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                hasConfiguredSemester ? '选择导入到哪个学期' : '导入前需要设置学期',
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hasConfiguredSemester)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '课表导入需要学期的开学日期来计算每节课的具体日期。请先创建一个学期。',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ...semesters.map((semester) {
                  final isActive = semester.id == activeSemesterId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, semester),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isActive
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isActive
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isActive
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  semester.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isActive ? colorScheme.primary : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '开学日期: ${semester.startDate.year}/${semester.startDate.month}/${semester.startDate.day}',
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
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final newSemester = await _showCreateSemesterDialog(context);
                if (newSemester != null && ctx.mounted) {
                  Navigator.pop(ctx, newSemester);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('新建学期'),
            ),
          ],
        );
      },
    );

    return selected;
  }

  static Future<SemesterInfo?> _showCreateSemesterDialog(
      BuildContext context) async {
    final nameController = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;

    final result = await showDialog<SemesterInfo>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('创建新学期'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '学期名称',
                        hintText: '例如: 2026春季学期',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          startDate != null
                              ? '开学日期: ${startDate!.year}/${startDate!.month}/${startDate!.day}'
                              : '选择开学日期',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            helpText: '选择开学日期',
                          );
                          if (picked != null) {
                            setState(() {
                              startDate =
                                  CourseScheduleSemantics.mondayOf(picked);
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
                              ? '放假日期: ${endDate!.year}/${endDate!.month}/${endDate!.day}'
                              : '选择放假日期 (可选)',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: startDate?.add(
                                  const Duration(days: 120),
                                ) ??
                                DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            helpText: '选择放假日期',
                          );
                          if (picked != null) {
                            setState(() => endDate = picked);
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
                    final name = nameController.text.trim();
                    if (name.isEmpty || startDate == null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('请填写学期名称和开学日期')),
                      );
                      return;
                    }
                    if (endDate != null &&
                        _dateOnly(endDate!).isBefore(_dateOnly(startDate!))) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('放假日期不能早于开学日期')),
                      );
                      return;
                    }

                    final normalizedStart =
                        CourseScheduleSemantics.mondayOf(startDate!);
                    final id =
                        'semester_${normalizedStart.millisecondsSinceEpoch}';
                    Navigator.pop(
                      ctx,
                      SemesterInfo(
                        id: id,
                        name: name,
                        startDate: normalizedStart,
                        endDate: endDate,
                      ),
                    );
                  },
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return null;

    final semesters = await StorageService.getSemesters();
    final duplicate = semesters.where((semester) => semester.id == result.id);
    if (duplicate.isNotEmpty) return duplicate.first;

    await StorageService.saveSemesters([...semesters, result]);
    return result;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
