part of 'todo_section_widget.dart';

// ignore_for_file: annotate_overrides

mixin _TodoSectionCaptureMixin on _TodoSectionStateBase {
  void _showAddTodoDialogWithData(
    List<Map<String, dynamic>>? llmResults,
    String? imagePath,
    String? originalText,
  ) {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController remarkCtrl = TextEditingController();
    DateTime createdAt = DateTime.now();
    DateTime? dueDate;
    RecurrenceType recurrence = RecurrenceType.none;
    TextEditingController customDaysCtrl = TextEditingController();
    int? customDays;
    DateTime? recurrenceEndDate;
    bool isAllDay = false;
    int reminderMinutes = 5; // 🚀 新增提醒设置

    TextEditingController aiInputCtrl = TextEditingController();
    List<ParsedTodoResult> parsedResults = [];
    int currentParseIndex = 0;
    bool isParsing = false;
    String? llmRawResponse;
    String? sharedImagePath = imagePath; // 保存分享的图片路径

    int selectedTabIndex = 0;
    String? currentOriginalText = originalText; // 📄 保存原始文本内容

    // 如果有预填充的大模型数据，解析并设置
    if (llmResults != null && llmResults.isNotEmpty) {
      parsedResults = llmResults.map((result) {
        final startTime = result['startTime'] != null
            ? DateTime.tryParse(result['startTime'])
            : null;
        final endTime = result['endTime'] != null
            ? DateTime.tryParse(result['endTime'])
            : null;
        final isAllDay = result['isAllDay'] ?? false;
        return ParsedTodoResult(
          title: result['title'] ?? '',
          remark: result['remark'],
          location: result['location']?.toString(),
          isAllDay: isAllDay,
          startTime: startTime,
          endTime: endTime,
          timeSemantics: _parseTimeSemantics(
            result['timeMode'],
            isAllDay: isAllDay,
            startTime: startTime,
            endTime: endTime,
          ),
          recurrence: _parseRecurrenceType(result['recurrence']),
          customIntervalDays: result['customIntervalDays'],
          recurrenceEndDate: DateTime.tryParse(
            (result['recurrenceEndDate'] ?? result['recurrence_end_date'] ?? '')
                .toString(),
          ),
          reminderMinutes: result['reminderMinutes'],
          itemKind: result['itemKind']?.toString(),
          originalText: originalText,
        );
      }).toList();

      llmRawResponse = const JsonEncoder.withIndent('  ').convert(llmResults);

      // 设置第一个待办的数据
      if (parsedResults.isNotEmpty) {
        final first = parsedResults[0];
        titleCtrl.text = first.title;
        remarkCtrl.text = first.remark ?? "";
        dueDate = null;
        if (first.startTime != null) {
          createdAt = first.startTime!;
          if (first.isAllDay) {
            createdAt = DateTime(
              createdAt.year,
              createdAt.month,
              createdAt.day,
              0,
              0,
            );
          }
        }
        if (first.endTime != null) {
          dueDate = first.endTime;
        } else if (first.startTime != null && first.isAllDay) {
          dueDate = DateTime(
            createdAt.year,
            createdAt.month,
            createdAt.day,
            23,
            59,
          );
        }
        isAllDay = first.isAllDay;
        recurrence = first.recurrence;
        customDays = first.customIntervalDays;
        recurrenceEndDate = first.recurrenceEndDate;
        if (customDays != null) {
          customDaysCtrl.text = customDays.toString();
        } else {
          customDaysCtrl.clear();
        }
        reminderMinutes = first.reminderMinutes ??
            (first.itemKind == 'fixedSchedule' ? 15 : 5);
        currentOriginalText = first.originalText;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget manualInputTab() {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: "事项内容",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarkCtrl,
                    decoration: InputDecoration(
                      labelText: "备注 (可选)",
                      hintText: "添加备注...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                  const SizedBox(height: 12),
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "某天内完成",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: isAllDay,
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    onChanged: (val) {
                      setDialogState(() {
                        final wasDateOnlyRange = dueDate != null &&
                            TodoItem.looksLikeLegacyDateOnlyRange(
                              createdAt,
                              dueDate!,
                            );
                        isAllDay = val;
                        if (isAllDay) {
                          createdAt = DateTime(
                            createdAt.year,
                            createdAt.month,
                            createdAt.day,
                            0,
                            0,
                          );
                          if (dueDate != null) {
                            dueDate = DateTime(
                              dueDate!.year,
                              dueDate!.month,
                              dueDate!.day,
                              23,
                              59,
                            );
                          } else {
                            dueDate = DateTime(
                              createdAt.year,
                              createdAt.month,
                              createdAt.day,
                              23,
                              59,
                            );
                          }
                        } else if (wasDateOnlyRange) {
                          final now = DateTime.now();
                          createdAt = DateTime(
                            createdAt.year,
                            createdAt.month,
                            createdAt.day,
                            now.hour,
                            now.minute,
                          );
                          dueDate = null;
                        }
                      });
                    },
                  ),
                  if (isAllDay)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        "完成日期: ${DateFormat('yyyy-MM-dd').format(createdAt)}",
                      ),
                      trailing: Icon(
                        Icons.edit_calendar,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: createdAt,
                        );
                        if (pickedDate != null) {
                          if (isAllDay) {
                            setDialogState(
                              () {
                                createdAt = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  0,
                                  0,
                                );
                                dueDate = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  23,
                                  59,
                                );
                              },
                            );
                          } else {
                            if (!context.mounted) return;
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(createdAt),
                            );
                            if (pickedTime != null) {
                              setDialogState(
                                () => createdAt = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  if (!isAllDay)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        dueDate == null
                            ? "设置截止时间（当前未安排）"
                            : "${DateFormat('yyyy-MM-dd HH:mm').format(dueDate!)} 前完成",
                      ),
                      trailing: Icon(
                        Icons.event,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: dueDate ?? createdAt,
                        );
                        if (pickedDate != null) {
                          if (isAllDay) {
                            setDialogState(
                              () => dueDate = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                23,
                                59,
                              ),
                            );
                          } else {
                            if (!context.mounted) return;
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(
                                dueDate ?? DateTime.now(),
                              ),
                            );
                            if (pickedTime != null) {
                              setDialogState(
                                () => dueDate = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  const Divider(),
                  DropdownButtonFormField<RecurrenceType>(
                    initialValue: recurrence,
                    decoration: InputDecoration(
                      labelText: "重复 (可选)",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: RecurrenceType.none,
                        child: Text("不重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.daily,
                        child: Text("每天重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.weekly,
                        child: Text("每周重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.monthly,
                        child: Text("每月重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.yearly,
                        child: Text("每年重复"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.weekdays,
                        child: Text("工作日"),
                      ),
                      DropdownMenuItem(
                        value: RecurrenceType.customDays,
                        child: Text("间隔几天"),
                      ),
                    ],
                    onChanged: (val) => setDialogState(() => recurrence = val!),
                  ),
                  if (recurrence == RecurrenceType.customDays)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: TextField(
                        controller: customDaysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "间隔天数",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (val) => customDays = int.tryParse(val),
                      ),
                    ),
                  if (recurrence != RecurrenceType.none)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        recurrenceEndDate == null
                            ? "重复结束日期 (可选)"
                            : "重复结束: ${DateFormat('yyyy-MM-dd').format(recurrenceEndDate!)}",
                      ),
                      trailing: Icon(
                        Icons.event_busy,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                          initialDate: DateTime.now().add(
                            const Duration(days: 30),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => recurrenceEndDate = picked);
                        }
                      },
                    ),
                  const Divider(),
                  DropdownButtonFormField<int>(
                    initialValue: reminderMinutes,
                    decoration: InputDecoration(
                      labelText: "温馨提醒 (提前量)",
                      prefixIcon:
                          const Icon(Icons.notifications_active_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("准时提醒")),
                      DropdownMenuItem(value: 5, child: Text("提前 5 分钟")),
                      DropdownMenuItem(value: 10, child: Text("提前 10 分钟")),
                      DropdownMenuItem(value: 15, child: Text("提前 15 分钟")),
                      DropdownMenuItem(value: 30, child: Text("提前 30 分钟")),
                      DropdownMenuItem(value: 45, child: Text("提前 45 分钟")),
                      DropdownMenuItem(value: 60, child: Text("提前 1 小时")),
                      DropdownMenuItem(value: 120, child: Text("提前 2 小时")),
                      DropdownMenuItem(value: 1440, child: Text("提前 1 天")),
                    ],
                    onChanged: (val) => setDialogState(() {
                      if (val != null) reminderMinutes = val;
                    }),
                  ),
                ],
              ),
            );
          }

          Widget aiRecognitionTab() {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 显示分享的图片缩略图（如果有）
                  if (sharedImagePath != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.image,
                                size: 16,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "识别的图片",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () =>
                                    _showFullImage(context, sharedImagePath),
                                child: const Text("查看大图"),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () =>
                                _showFullImage(context, sharedImagePath),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: localImageWidget(
                                sharedImagePath,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "支持的格式示例",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildExampleText("买牛奶明天5点"),
                        _buildExampleText("下周一在图书馆学习"),
                        _buildExampleText("三天后提醒我交水电费"),
                        _buildExampleText("每天跑步30分钟"),
                        _buildExampleText("上午9点到11点开会@会议室"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: aiInputCtrl,
                    decoration: InputDecoration(
                      labelText: "输入事项内容",
                      hintText: "在此粘贴或输入文字...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 4,
                    minLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: isParsing
                              ? null
                              : () async {
                                  if (aiInputCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("请输入事项内容")),
                                    );
                                    return;
                                  }

                                  final config = await LLMService.getConfig();
                                  if (config == null || !config.isConfigured) {
                                    if (!context.mounted) return;
                                    final goToSettings = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text("未配置大模型"),
                                        content: const Text(
                                          "使用大模型识别需要先配置API地址和密钥，是否前往设置？",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text("取消"),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text("去配置"),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (goToSettings == true &&
                                        context.mounted) {
                                      Navigator.of(context).push(
                                        PageTransitions.material(
                                          builder: (_) => const SettingsPage(),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  setDialogState(() {
                                    isParsing = true;
                                  });

                                  // 给一个短暂延迟让UI刷新出 Loading 状态，避免同步卡顿
                                  await Future.delayed(
                                    const Duration(milliseconds: 150),
                                  );

                                  try {
                                    final results =
                                        await LLMService.parseTodoWithLLM(
                                      aiInputCtrl.text,
                                    );
                                    if (!context.mounted || !ctx.mounted) {
                                      return;
                                    }

                                    final parsedResultsList = results.map((
                                      result,
                                    ) {
                                      return ParsedTodoResult(
                                        title:
                                            result['title'] ?? aiInputCtrl.text,
                                        remark: result['remark'],
                                        location:
                                            result['location']?.toString(),
                                        isAllDay: result['isAllDay'] ?? false,
                                        startTime: result['startTime'] != null
                                            ? DateTime.tryParse(
                                                result['startTime'],
                                              )
                                            : null,
                                        endTime: result['endTime'] != null
                                            ? DateTime.tryParse(
                                                result['endTime'],
                                              )
                                            : null,
                                        timeSemantics: _parseTimeSemantics(
                                          result['timeMode'],
                                          isAllDay: result['isAllDay'] ?? false,
                                          startTime: result['startTime'] != null
                                              ? DateTime.tryParse(
                                                  result['startTime'],
                                                )
                                              : null,
                                          endTime: result['endTime'] != null
                                              ? DateTime.tryParse(
                                                  result['endTime'],
                                                )
                                              : null,
                                        ),
                                        recurrence: _parseRecurrenceType(
                                          result['recurrence'],
                                        ),
                                        customIntervalDays:
                                            result['customIntervalDays'],
                                        recurrenceEndDate: DateTime.tryParse(
                                          (result['recurrenceEndDate'] ?? '')
                                              .toString(),
                                        ),
                                        reminderMinutes:
                                            result['reminderMinutes'],
                                        itemKind:
                                            result['itemKind']?.toString(),
                                        originalText: aiInputCtrl.text,
                                      );
                                    }).toList();

                                    setDialogState(() {
                                      parsedResults = parsedResultsList;
                                      currentParseIndex = 0;
                                      isParsing = false;
                                      currentOriginalText = aiInputCtrl.text;
                                    });

                                    if (parsedResults.isNotEmpty) {
                                      final first = parsedResults[0];
                                      setDialogState(() {
                                        titleCtrl.text = first.title;
                                        remarkCtrl.text = first.remark ?? "";
                                        dueDate = null;
                                        if (first.startTime != null) {
                                          createdAt = first.startTime!;
                                          if (first.isAllDay) {
                                            createdAt = DateTime(
                                              createdAt.year,
                                              createdAt.month,
                                              createdAt.day,
                                              0,
                                              0,
                                            );
                                          }
                                        }
                                        if (first.endTime != null) {
                                          dueDate = first.endTime;
                                        } else if (first.startTime != null &&
                                            first.isAllDay) {
                                          dueDate = DateTime(
                                            createdAt.year,
                                            createdAt.month,
                                            createdAt.day,
                                            23,
                                            59,
                                          );
                                        }
                                        isAllDay = first.isAllDay;
                                        recurrence = first.recurrence;
                                        customDays = first.customIntervalDays;
                                        recurrenceEndDate =
                                            first.recurrenceEndDate;
                                        if (customDays != null) {
                                          customDaysCtrl.text =
                                              customDays.toString();
                                        } else {
                                          customDaysCtrl.clear();
                                        }
                                        reminderMinutes = first
                                                .reminderMinutes ??
                                            (first.itemKind == 'fixedSchedule'
                                                ? 15
                                                : 5);

                                        // ★ 解析完成后自动切回"手动输入"标签页供用户检查或修改 ★
                                        selectedTabIndex = 0;
                                      });

                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "大模型解析成功，共${parsedResults.length}个事项",
                                            ),
                                            duration:
                                                const Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    setDialogState(() {
                                      isParsing = false;
                                    });
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text("大模型解析失败: $e")),
                                      );
                                    }
                                  }
                                },
                          child: isParsing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("智能解析"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isParsing
                              ? null
                              : () async {
                                  if (aiInputCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("请输入事项内容")),
                                    );
                                    return;
                                  }

                                  final config = await LLMService.getConfig();
                                  if (config == null || !config.isConfigured) {
                                    if (!context.mounted) return;
                                    final goToSettings = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text("未配置大模型"),
                                        content: const Text(
                                          "使用大模型识别需要先配置API地址和密钥，是否前往设置？",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text("取消"),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text("去配置"),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (goToSettings == true &&
                                        context.mounted) {
                                      Navigator.of(context).push(
                                        PageTransitions.material(
                                          builder: (_) => const SettingsPage(),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  setDialogState(() {
                                    isParsing = true;
                                  });

                                  try {
                                    final results =
                                        await LLMService.parseTodoWithLLM(
                                      aiInputCtrl.text,
                                    );
                                    if (!context.mounted || !ctx.mounted) {
                                      return;
                                    }

                                    final parsedResultsList = results.map((
                                      result,
                                    ) {
                                      return ParsedTodoResult(
                                        title:
                                            result['title'] ?? aiInputCtrl.text,
                                        remark: result['remark'],
                                        location:
                                            result['location']?.toString(),
                                        isAllDay: result['isAllDay'] ?? false,
                                        startTime: result['startTime'] != null
                                            ? DateTime.tryParse(
                                                result['startTime'],
                                              )
                                            : null,
                                        endTime: result['endTime'] != null
                                            ? DateTime.tryParse(
                                                result['endTime'],
                                              )
                                            : null,
                                        timeSemantics: _parseTimeSemantics(
                                          result['timeMode'],
                                          isAllDay: result['isAllDay'] ?? false,
                                          startTime: result['startTime'] != null
                                              ? DateTime.tryParse(
                                                  result['startTime'],
                                                )
                                              : null,
                                          endTime: result['endTime'] != null
                                              ? DateTime.tryParse(
                                                  result['endTime'],
                                                )
                                              : null,
                                        ),
                                        recurrence: _parseRecurrenceType(
                                          result['recurrence'],
                                        ),
                                        customIntervalDays:
                                            result['customIntervalDays'],
                                        recurrenceEndDate: DateTime.tryParse(
                                          (result['recurrenceEndDate'] ?? '')
                                              .toString(),
                                        ),
                                        reminderMinutes:
                                            result['reminderMinutes'],
                                        itemKind:
                                            result['itemKind']?.toString(),
                                        originalText:
                                            aiInputCtrl.text, // 📄 保存原始输入文字
                                      );
                                    }).toList();

                                    setDialogState(() {
                                      parsedResults = parsedResultsList;
                                      currentParseIndex = 0;
                                      isParsing = false;
                                      llmRawResponse =
                                          const JsonEncoder.withIndent(
                                        '  ',
                                      ).convert(results);
                                    });

                                    if (parsedResults.isNotEmpty) {
                                      // 如果有回调，关闭对话框并导航到确认页面
                                      if (widget.onLLMResultsParsed != null) {
                                        Navigator.pop(ctx);
                                        final existingTeams =
                                            <String, String>{};
                                        for (var t in widget.todos) {
                                          if (t.teamUuid != null &&
                                              t.teamName != null) {
                                            existingTeams[t.teamUuid!] =
                                                t.teamName!;
                                          }
                                        }
                                        final currentTeamName =
                                            _selectedSubTeamUuid != null
                                                ? existingTeams[
                                                    _selectedSubTeamUuid]
                                                : null;

                                        widget.onLLMResultsParsed!(
                                            results,
                                            imagePath,
                                            aiInputCtrl.text,
                                            _selectedSubTeamUuid,
                                            currentTeamName);
                                        return;
                                      }

                                      final first = parsedResults[0];
                                      setDialogState(() {
                                        titleCtrl.text = first.title;
                                        remarkCtrl.text = first.remark ?? "";
                                        dueDate = null;
                                        if (first.startTime != null) {
                                          createdAt = first.startTime!;
                                          if (first.isAllDay) {
                                            createdAt = DateTime(
                                              createdAt.year,
                                              createdAt.month,
                                              createdAt.day,
                                              0,
                                              0,
                                            );
                                          }
                                        }
                                        if (first.endTime != null) {
                                          dueDate = first.endTime;
                                        } else if (first.startTime != null &&
                                            first.isAllDay) {
                                          dueDate = DateTime(
                                            createdAt.year,
                                            createdAt.month,
                                            createdAt.day,
                                            23,
                                            59,
                                          );
                                        }
                                        isAllDay = first.isAllDay;
                                        recurrence = first.recurrence;
                                        customDays = first.customIntervalDays;
                                        recurrenceEndDate =
                                            first.recurrenceEndDate;
                                        if (customDays != null) {
                                          customDaysCtrl.text =
                                              customDays.toString();
                                        } else {
                                          customDaysCtrl.clear();
                                        }
                                        reminderMinutes = first
                                                .reminderMinutes ??
                                            (first.itemKind == 'fixedSchedule'
                                                ? 15
                                                : 5);
                                        currentOriginalText = aiInputCtrl.text;
                                        selectedTabIndex = 0;
                                      });

                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "大模型解析成功，共${parsedResults.length}个事项，请确认或修改后保存",
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    setDialogState(() {
                                      isParsing = false;
                                    });
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text("大模型解析失败: $e")),
                                      );
                                    }
                                  }
                                },
                          child: isParsing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("大模型识别"),
                        ),
                      ),
                    ],
                  ),
                  if (parsedResults.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      "解析结果 (${currentParseIndex + 1}/${parsedResults.length})",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildParseResultItem(
                      '类型',
                      _quickCaptureKindLabel(
                        parsedResults[currentParseIndex],
                      ),
                    ),
                    _buildParseResultItem(
                      '事项内容',
                      parsedResults[currentParseIndex].title,
                    ),
                    _buildParseResultItem(
                      '时间',
                      _quickCaptureTimeLabel(
                        parsedResults[currentParseIndex],
                      ),
                    ),
                    _buildParseResultItem(
                      "重复",
                      _getRecurrenceText(
                        parsedResults[currentParseIndex].recurrence,
                      ),
                    ),
                    _buildParseResultItem(
                      "备注/地点",
                      _quickCaptureDetailLabel(
                        parsedResults[currentParseIndex],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (currentParseIndex > 0)
                          TextButton(
                            onPressed: () {
                              setDialogState(() => currentParseIndex--);
                              _applyParsedResult(
                                parsedResults[currentParseIndex],
                                setDialogState,
                                titleCtrl,
                                remarkCtrl,
                                (d) => createdAt = d,
                                (d) => dueDate = d,
                                (b) => isAllDay = b,
                                (r) => recurrence = r,
                                (i) => customDays = i,
                                (d) => recurrenceEndDate = d,
                                (minutes) => reminderMinutes = minutes,
                                customDaysCtrl,
                              );
                            },
                            child: const Text("上一个"),
                          ),
                        if (currentParseIndex < parsedResults.length - 1)
                          TextButton(
                            onPressed: () {
                              setDialogState(() => currentParseIndex++);
                              _applyParsedResult(
                                parsedResults[currentParseIndex],
                                setDialogState,
                                titleCtrl,
                                remarkCtrl,
                                (d) => createdAt = d,
                                (d) => dueDate = d,
                                (b) => isAllDay = b,
                                (r) => recurrence = r,
                                (i) => customDays = i,
                                (d) => recurrenceEndDate = d,
                                (minutes) => reminderMinutes = minutes,
                                customDaysCtrl,
                              );
                            },
                            child: const Text("下一个"),
                          ),
                      ],
                    ),
                    if (llmRawResponse != null) ...[
                      const SizedBox(height: 12),
                      ExpansionTile(
                        title: const Text(
                          "大模型原始返回",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              llmRawResponse!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            );
          }

          return AlertDialog(
            title: const Text("添加事项"),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text("手动输入")),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.auto_awesome),
                        label: Text("AI识别"),
                      ),
                    ],
                    selected: {selectedTabIndex},
                    onSelectionChanged: (Set<int> selection) {
                      setDialogState(() {
                        selectedTabIndex = selection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 400,
                    child: selectedTabIndex == 0
                        ? manualInputTab()
                        : aiRecognitionTab(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("取消"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  if (titleCtrl.text.isNotEmpty) {
                    final currentParsed = parsedResults.isEmpty
                        ? null
                        : parsedResults[currentParseIndex];
                    final saveTarget = await _confirmQuickCaptureIntent(
                      currentOriginalText ?? titleCtrl.text,
                      declaredKind: currentParsed?.itemKind,
                      semanticText: currentParsed == null
                          ? null
                          : '${currentParsed.title} ${currentParsed.remark ?? ''}',
                    );
                    if (saveTarget == _QuickCaptureTarget.cancel ||
                        !context.mounted) {
                      return;
                    }
                    if (saveTarget == _QuickCaptureTarget.fixedSchedule) {
                      final sourceText = currentOriginalText ?? titleCtrl.text;
                      final hasParsedDate = currentParsed?.startTime != null ||
                          currentParsed?.endTime != null ||
                          isAllDay ||
                          dueDate != null;
                      final parsedForSchedule = currentParsed == null
                          ? TodoParserService.parse(sourceText)
                          : ParsedTodoResult(
                              title: titleCtrl.text.trim(),
                              remark: remarkCtrl.text.trim().isEmpty
                                  ? null
                                  : remarkCtrl.text.trim(),
                              location: currentParsed.location,
                              isAllDay: isAllDay,
                              startTime: hasParsedDate ? createdAt : null,
                              endTime: dueDate,
                              timeSemantics: currentParsed.timeSemantics,
                              recurrence: recurrence,
                              customIntervalDays: customDays,
                              recurrenceEndDate: recurrenceEndDate,
                              reminderMinutes: reminderMinutes,
                              itemKind: currentParsed.itemKind,
                              originalText: sourceText,
                            );
                      if (!await _saveQuickFixedSchedule(parsedForSchedule)) {
                        return;
                      }
                      widget.onRefreshRequested();
                      if (ctx.mounted) Navigator.pop(ctx);
                      return;
                    }
                    final normalizedTime = TodoItem.normalizeTimeForWrite(
                      selectedDate: createdAt,
                      dueDate: dueDate,
                      isDateOnly: isAllDay,
                    );
                    if (recurrence != RecurrenceType.none &&
                        normalizedTime.start == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('重复待办需要先设置首次完成日期'),
                        ),
                      );
                      return;
                    }
                    final newTodo = TodoItem(
                      title: titleCtrl.text,
                      recurrence: recurrence,
                      customIntervalDays: customDays,
                      recurrenceEndDate: recurrenceEndDate,
                      dueDate: normalizedTime.due,
                      createdDate: normalizedTime.start?.millisecondsSinceEpoch,
                      remark: remarkCtrl.text.trim().isEmpty
                          ? null
                          : remarkCtrl.text.trim(),
                      imagePath: sharedImagePath,
                      originalText: currentOriginalText,
                      reminderMinutes: reminderMinutes,
                      isAllDay: isAllDay,
                    );
                    List<TodoItem> updatedList = List.from(widget.todos)
                      ..add(newTodo);
                    widget.onTodosChanged(updatedList);
                    if (mounted) Navigator.pop(ctx);
                  }
                },
                child: const Text("添加"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<_QuickCaptureTarget> _confirmQuickCaptureIntent(
    String sourceText, {
    String? declaredKind,
    String? semanticText,
  }) async {
    final intent = ItemSemanticsService.classifyCaptureIntent(
      declaredKind == null ? sourceText : semanticText ?? sourceText,
      declaredKind: declaredKind,
    );
    if (intent == CaptureIntentKind.todo || !mounted) {
      return _QuickCaptureTarget.todo;
    }
    final (title, message) = switch (intent) {
      CaptureIntentKind.fixedSchedule => (
          '识别为固定日程',
          '考试、会议或预约属于不可自由移动的固定日程，可以直接按日程保存。',
        ),
      CaptureIntentKind.planBlock => (
          '识别为规划时段',
          '这个时间段更适合关联到待办的规划块。继续只保存待办，不占用规划日历。',
        ),
      CaptureIntentKind.needsConfirmation => (
          '需要确认时间性质',
          '无法确定这是固定日程还是可调整的规划时段。继续会暂存为待办。',
        ),
      CaptureIntentKind.todo => ('', ''),
    };
    return await showDialog<_QuickCaptureTarget>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _QuickCaptureTarget.cancel,
                ),
                child: const Text('返回调整'),
              ),
              if (intent == CaptureIntentKind.fixedSchedule)
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _QuickCaptureTarget.fixedSchedule,
                  ),
                  child: const Text('保存为固定日程'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _QuickCaptureTarget.todo,
                ),
                child: const Text('暂存为待办'),
              ),
            ],
          ),
        ) ??
        _QuickCaptureTarget.cancel;
  }

  Future<bool> _saveQuickFixedSchedule(ParsedTodoResult parsed) async {
    final dateSource = parsed.startTime ?? parsed.endTime;
    if (dateSource == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('固定日程需要先确认日期')),
        );
      }
      return false;
    }
    DateTime? start = parsed.startTime;
    DateTime? end = parsed.endTime;
    if (parsed.isAllDay) {
      start = null;
      end = null;
    } else if (parsed.timeSemantics == ParsedTimeSemantics.deadline &&
        end != null) {
      start = end;
      end = null;
    }
    final item = FixedScheduleItem(
      title: parsed.title,
      date: DateFormat('yyyy-MM-dd').format(dateSource),
      startTime: start?.millisecondsSinceEpoch,
      endTime: end?.millisecondsSinceEpoch,
      source: FixedScheduleSource.ai,
      location: parsed.location,
      remark: parsed.remark,
      reminderMinutes: [parsed.reminderMinutes ?? 15],
      timezone: DateTime.now().timeZoneName,
      recurrence: parsed.recurrence,
    );
    if (item.recurrence != RecurrenceType.none) {
      item.recurrenceSeriesId = item.id;
      final recurrenceEnd = parsed.recurrenceEndDate ??
          FixedScheduleRecurrenceService.defaultEndDate(
            startDate: dateSource,
            recurrence: item.recurrence,
            customIntervalDays: parsed.customIntervalDays ?? 1,
          );
      try {
        final series = FixedScheduleRecurrenceService.rebuildSeries(
          template: item,
          existingSeries: const [],
          recurrence: item.recurrence,
          recurrenceEndDate: recurrenceEnd,
          customIntervalDays: parsed.customIntervalDays ?? 1,
        );
        await StorageService.saveFixedSchedules(
          widget.username,
          series.changes,
        );
      } on FixedScheduleRecurrenceLimitException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        }
        return false;
      }
    } else {
      await StorageService.saveFixedSchedules(widget.username, [item]);
    }
    await ReminderScheduleService.scheduleFromStorage(
      widget.username,
      force: true,
    );
    return true;
  }

  /// 显示全屏图片预览
  void _showFullImage(BuildContext context, String imagePath) {
    Navigator.of(context).push(
      PageTransitions.material(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: FloatingGlassAppBar(
            flexibleSpace: const FloatingGlassTopBarBackground(),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text("图片预览"),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: localImageWidget(
                imagePath,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExampleText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Text(
        "• $text",
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
    );
  }

  Widget _buildParseResultItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              "$label:",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _getRecurrenceText(RecurrenceType type) {
    switch (type) {
      case RecurrenceType.none:
        return "不重复";
      case RecurrenceType.daily:
        return "每天重复";
      case RecurrenceType.weekly:
        return "每周重复";
      case RecurrenceType.monthly:
        return "每月重复";
      case RecurrenceType.yearly:
        return "每年重复";
      case RecurrenceType.weekdays:
        return "工作日重复";
      case RecurrenceType.customDays:
        return "自定义间隔";
    }
  }

  RecurrenceType _parseRecurrenceType(String? value) {
    switch (value) {
      case 'daily':
        return RecurrenceType.daily;
      case 'weekly':
        return RecurrenceType.weekly;
      case 'monthly':
        return RecurrenceType.monthly;
      case 'yearly':
        return RecurrenceType.yearly;
      case 'weekdays':
        return RecurrenceType.weekdays;
      case 'customDays':
        return RecurrenceType.customDays;
      default:
        return RecurrenceType.none;
    }
  }

  ParsedTimeSemantics _parseTimeSemantics(
    dynamic raw, {
    required bool isAllDay,
    required DateTime? startTime,
    required DateTime? endTime,
  }) {
    if (isAllDay) return ParsedTimeSemantics.dateOnly;
    return ParsedTimeSemantics.values.firstWhere(
      (value) => value.name == raw?.toString(),
      orElse: () => startTime != null && endTime != null
          ? ParsedTimeSemantics.range
          : ParsedTimeSemantics.unscheduled,
    );
  }

  CaptureIntentKind _quickCaptureIntentFor(ParsedTodoResult result) {
    return ItemSemanticsService.classifyCaptureIntent(
      result.itemKind == null
          ? result.originalText ?? result.title
          : '${result.title} ${result.remark ?? ''}',
      declaredKind: result.itemKind,
    );
  }

  String _quickCaptureKindLabel(ParsedTodoResult result) {
    return switch (_quickCaptureIntentFor(result)) {
      CaptureIntentKind.todo => '待办',
      CaptureIntentKind.fixedSchedule => '固定日程',
      CaptureIntentKind.planBlock => '规划块',
      CaptureIntentKind.needsConfirmation => '待确认',
    };
  }

  String _quickCaptureTimeLabel(ParsedTodoResult result) {
    final intent = _quickCaptureIntentFor(result);
    if (intent == CaptureIntentKind.fixedSchedule) {
      if (result.isAllDay) {
        return result.startTime == null
            ? '日期待确认 · 时间待定'
            : '${DateFormat('yyyy-MM-dd').format(result.startTime!)} · 时间待定';
      }
      if (result.startTime != null && result.endTime != null) {
        return '${DateFormat('yyyy-MM-dd HH:mm').format(result.startTime!)}–${DateFormat('HH:mm').format(result.endTime!)}';
      }
      if (result.startTime != null) {
        return '${DateFormat('yyyy-MM-dd HH:mm').format(result.startTime!)}开始 · 结束待定';
      }
      return '日期和时间待确认';
    }
    if (intent == CaptureIntentKind.planBlock) {
      return result.startTime != null && result.endTime != null
          ? '${DateFormat('yyyy-MM-dd HH:mm').format(result.startTime!)}–${DateFormat('HH:mm').format(result.endTime!)}'
          : '规划时段待确认';
    }
    if (result.isAllDay && result.startTime != null) {
      return '${DateFormat('yyyy-MM-dd').format(result.startTime!)} 内完成';
    }
    if (result.endTime != null) {
      return '${DateFormat('yyyy-MM-dd HH:mm').format(result.endTime!)} 前完成';
    }
    return '未安排';
  }

  String _quickCaptureDetailLabel(ParsedTodoResult result) {
    final detail = [result.location, result.remark]
        .whereType<String>()
        .where((text) => text.trim().isNotEmpty)
        .join(' · ');
    return detail.isEmpty ? '-' : detail;
  }

  void _applyParsedResult(
    ParsedTodoResult result,
    void Function(void Function()) setDialogState,
    TextEditingController titleCtrl,
    TextEditingController remarkCtrl,
    Function(DateTime) setCreatedAt,
    Function(DateTime?) setDueDate,
    Function(bool) setIsAllDay,
    Function(RecurrenceType) setRecurrence,
    Function(int?) setCustomDays,
    Function(DateTime?) setRecurrenceEndDate,
    Function(int) setReminderMinutes,
    TextEditingController customDaysCtrl,
  ) {
    setDialogState(() {
      titleCtrl.text = result.title;
      remarkCtrl.text = result.remark ?? "";
      setDueDate(null);
      if (result.startTime != null) {
        setCreatedAt(result.startTime!);
        if (result.isAllDay) {
          final d = result.startTime!;
          setCreatedAt(DateTime(d.year, d.month, d.day, 0, 0));
        }
      }
      if (result.endTime != null) {
        setDueDate(result.endTime);
      } else if (result.startTime != null && result.isAllDay) {
        final d = result.startTime!;
        setDueDate(DateTime(d.year, d.month, d.day, 23, 59));
      }
      setIsAllDay(result.isAllDay);
      setRecurrence(result.recurrence);
      setCustomDays(result.customIntervalDays);
      setRecurrenceEndDate(result.recurrenceEndDate);
      if (result.customIntervalDays != null) {
        customDaysCtrl.text = result.customIntervalDays.toString();
      } else {
        customDaysCtrl.clear();
      }
      setReminderMinutes(result.reminderMinutes ??
          (result.itemKind == 'fixedSchedule' ? 15 : 5));
    });
  }
}
