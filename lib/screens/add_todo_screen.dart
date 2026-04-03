import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/todo_parser_service.dart';
import '../services/llm_service.dart';
import '../screens/home_settings_screen.dart';

class AddTodoScreen extends StatefulWidget {
  final Function(TodoItem) onTodoAdded;
  final Function(List<Map<String, dynamic>>, String?)? onLLMResultsParsed;

  const AddTodoScreen({
    super.key,
    required this.onTodoAdded,
    this.onLLMResultsParsed,
  });

  @override
  State<AddTodoScreen> createState() => _AddTodoScreenState();
}

class _AddTodoScreenState extends State<AddTodoScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();
  final TextEditingController _aiInputCtrl = TextEditingController();
  final TextEditingController _customDaysCtrl = TextEditingController();

  DateTime _createdAt = DateTime.now();
  DateTime? _dueDate;
  RecurrenceType _recurrence = RecurrenceType.none;
  int? _customDays;
  DateTime? _recurrenceEndDate;
  bool _isAllDay = false;

  int _selectedTabIndex = 0;
  bool _isParsing = false;
  List<ParsedTodoResult> _parsedResults = [];
  int _currentParseIndex = 0;
  String? _llmRawResponse;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _remarkCtrl.dispose();
    _aiInputCtrl.dispose();
    _customDaysCtrl.dispose();
    super.dispose();
  }

  RecurrenceType _parseRecurrenceType(String? type) {
    switch (type) {
      case 'daily':
        return RecurrenceType.daily;
      case 'weekly':
        return RecurrenceType.weekly;
      case 'monthly':
        return RecurrenceType.monthly;
      case 'yearly':
        return RecurrenceType.yearly;
      case 'customDays':
        return RecurrenceType.customDays;
      default:
        return RecurrenceType.none;
    }
  }

  String _getRecurrenceText(RecurrenceType r) {
    switch (r) {
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
      case RecurrenceType.customDays:
        return "每 ${_customDays ?? '?'} 天重复";
      default:
        return "不重复";
    }
  }

  void _applyParsedResult(ParsedTodoResult result) {
    setState(() {
      _titleCtrl.text = result.title;
      _remarkCtrl.text = result.remark ?? "";
      if (result.startTime != null) {
        _createdAt = result.startTime!;
        if (result.isAllDay) {
          _createdAt = DateTime(
            _createdAt.year,
            _createdAt.month,
            _createdAt.day,
            0,
            0,
          );
        }
      }
      if (result.endTime != null) {
        _dueDate = result.endTime;
      } else if (result.startTime != null && result.isAllDay) {
        _dueDate = DateTime(
          _createdAt.year,
          _createdAt.month,
          _createdAt.day,
          23,
          59,
        );
      }
      _isAllDay = result.isAllDay;
      _recurrence = result.recurrence;
      _customDays = result.customIntervalDays;
      if (_customDays != null) {
        _customDaysCtrl.text = _customDays.toString();
      }
    });
  }

  Future<void> _doSmartParse() async {
    if (_aiInputCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("请输入待办内容")),
      );
      return;
    }
    setState(() => _isParsing = true);
    await Future.delayed(const Duration(milliseconds: 150));

    final results = TodoParserService.parseMulti(_aiInputCtrl.text);
    setState(() {
      _parsedResults = results;
      _currentParseIndex = 0;
      _isParsing = false;
    });

    if (_parsedResults.isNotEmpty) {
      _applyParsedResult(_parsedResults[0]);
      setState(() => _selectedTabIndex = 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("解析成功，共${_parsedResults.length}个待办"),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _doLLMParse() async {
    if (_aiInputCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("请输入待办内容")),
      );
      return;
    }

    final config = await LLMService.getConfig();
    if (config == null || !config.isConfigured) {
      if (!mounted) return;
      final goToSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("未配置大模型"),
          content: const Text("使用大模型识别需要先配置API地址和密钥，是否前往设置？"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("取消"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("去配置"),
            ),
          ],
        ),
      );
      if (goToSettings == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
      }
      return;
    }

    setState(() => _isParsing = true);

    try {
      final results = await LLMService.parseTodoWithLLM(_aiInputCtrl.text);

      // 如果有回调且有多个待办结果，导航到确认页面
      if (widget.onLLMResultsParsed != null && results.length > 1) {
        setState(() => _isParsing = false);
        widget.onLLMResultsParsed!(results, null);
        return;
      }

      // 没有回调时，在当前页面显示结果
      final parsedResultsList = results.map((result) {
        return ParsedTodoResult(
          title: result['title'] ?? _aiInputCtrl.text,
          remark: result['remark'],
          isAllDay: result['isAllDay'] ?? false,
          startTime: result['startTime'] != null
              ? DateTime.tryParse(result['startTime'])
              : null,
          endTime: result['endTime'] != null
              ? DateTime.tryParse(result['endTime'])
              : null,
          recurrence: _parseRecurrenceType(result['recurrence']),
          customIntervalDays: result['customIntervalDays'],
        );
      }).toList();

      setState(() {
        _parsedResults = parsedResultsList;
        _currentParseIndex = 0;
        _isParsing = false;
        _llmRawResponse = const JsonEncoder.withIndent('  ').convert(results);
      });

      if (_parsedResults.isNotEmpty) {
        _applyParsedResult(_parsedResults[0]);
        setState(() => _selectedTabIndex = 0);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("大模型解析成功，共${_parsedResults.length}个待办"),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isParsing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("大模型解析失败: $e")),
        );
      }
    }
  }

  void _addTodo() {
    if (_titleCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("请输入待办内容")),
      );
      return;
    }

    final todo = TodoItem(
      title: _titleCtrl.text,
      recurrence: _recurrence,
      customIntervalDays: _customDays,
      recurrenceEndDate: _recurrenceEndDate,
      dueDate: _dueDate,
      createdDate: _createdAt.millisecondsSinceEpoch,
      remark: _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
    );

    widget.onTodoAdded(todo);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("添加待办"),
        actions: [
          FilledButton.icon(
            onPressed: _addTodo,
            icon: const Icon(Icons.check),
            label: const Text("添加"),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 标签切换
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text("手动输入")),
                ButtonSegment(value: 1, label: Text("AI识别")),
              ],
              selected: {_selectedTabIndex},
              onSelectionChanged: (Set<int> selection) {
                setState(() => _selectedTabIndex = selection.first);
              },
            ),
          ),
          // 内容区域
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildManualInputTab()
                : _buildAIRecognitionTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildManualInputTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: "待办内容",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarkCtrl,
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              "全天事件",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            value: _isAllDay,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) {
              setState(() {
                _isAllDay = val;
                if (_isAllDay) {
                  _createdAt = DateTime(
                    _createdAt.year,
                    _createdAt.month,
                    _createdAt.day,
                    0,
                    0,
                  );
                  if (_dueDate != null) {
                    _dueDate = DateTime(
                      _dueDate!.year,
                      _dueDate!.month,
                      _dueDate!.day,
                      23,
                      59,
                    );
                  } else {
                    _dueDate = DateTime(
                      _createdAt.year,
                      _createdAt.month,
                      _createdAt.day,
                      23,
                      59,
                    );
                  }
                }
              });
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              "开始时间: ${DateFormat(_isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(_createdAt)}",
            ),
            trailing: Icon(Icons.edit_calendar,
                size: 20, color: Theme.of(context).colorScheme.primary),
            onTap: () async {
              final pickedDate = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: _createdAt,
              );
              if (pickedDate != null) {
                if (_isAllDay) {
                  setState(() => _createdAt = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        0,
                        0,
                      ));
                } else {
                  if (!mounted) return;
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_createdAt),
                  );
                  if (pickedTime != null) {
                    setState(() => _createdAt = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        ));
                  }
                }
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _dueDate == null
                  ? "设置截止时间 (可选)"
                  : "截止时间: ${DateFormat(_isAllDay ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm').format(_dueDate!)}",
            ),
            trailing: Icon(Icons.event,
                size: 20, color: Theme.of(context).colorScheme.primary),
            onTap: () async {
              final pickedDate = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: _dueDate ?? _createdAt,
              );
              if (pickedDate != null) {
                if (_isAllDay) {
                  setState(() => _dueDate = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        23,
                        59,
                      ));
                } else {
                  if (!mounted) return;
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime:
                        TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()),
                  );
                  if (pickedTime != null) {
                    setState(() => _dueDate = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        ));
                  }
                }
              }
            },
          ),
          const Divider(),
          DropdownButtonFormField<RecurrenceType>(
            value: _recurrence,
            decoration: InputDecoration(
              labelText: "循环设置 (可选)",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: const [
              DropdownMenuItem(value: RecurrenceType.none, child: Text("不重复")),
              DropdownMenuItem(
                  value: RecurrenceType.daily, child: Text("每天重复")),
              DropdownMenuItem(
                  value: RecurrenceType.weekly, child: Text("每周重复")),
              DropdownMenuItem(
                  value: RecurrenceType.monthly, child: Text("每月重复")),
              DropdownMenuItem(
                  value: RecurrenceType.yearly, child: Text("每年重复")),
              DropdownMenuItem(
                  value: RecurrenceType.customDays, child: Text("自定义天数")),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _recurrence = val;
                  if (val != RecurrenceType.customDays) {
                    _customDays = null;
                    _customDaysCtrl.clear();
                  }
                });
              }
            },
          ),
          if (_recurrence == RecurrenceType.customDays) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customDaysCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "间隔天数",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (val) {
                _customDays = int.tryParse(val);
              },
            ),
          ],
          if (_recurrence != RecurrenceType.none) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _recurrenceEndDate == null
                    ? "设置结束时间 (可选)"
                    : "结束时间: ${DateFormat('yyyy-MM-dd').format(_recurrenceEndDate!)}",
              ),
              trailing: Icon(Icons.event_busy,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              onTap: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2100),
                  initialDate: _recurrenceEndDate ??
                      DateTime.now().add(const Duration(days: 30)),
                );
                if (pickedDate != null) {
                  setState(() => _recurrenceEndDate = pickedDate);
                }
              },
            ),
          ],
          const SizedBox(height: 20),
          // 解析结果展示
          if (_parsedResults.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 8),
            Text(
              "解析结果 (${_currentParseIndex + 1}/${_parsedResults.length})",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildParseResultItem(
                "待办内容", _parsedResults[_currentParseIndex].title),
            _buildParseResultItem(
              "开始时间",
              _parsedResults[_currentParseIndex].startTime != null
                  ? DateFormat('yyyy-MM-dd HH:mm')
                      .format(_parsedResults[_currentParseIndex].startTime!)
                  : "未识别",
            ),
            _buildParseResultItem(
              "结束时间",
              _parsedResults[_currentParseIndex].endTime != null
                  ? DateFormat('yyyy-MM-dd HH:mm')
                      .format(_parsedResults[_currentParseIndex].endTime!)
                  : "未识别",
            ),
            _buildParseResultItem("全天事件",
                _parsedResults[_currentParseIndex].isAllDay ? "是" : "否"),
            _buildParseResultItem(
                "重复",
                _getRecurrenceText(
                    _parsedResults[_currentParseIndex].recurrence)),
            _buildParseResultItem(
                "备注/地点", _parsedResults[_currentParseIndex].remark ?? "-"),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_currentParseIndex > 0)
                  TextButton(
                    onPressed: () {
                      setState(() => _currentParseIndex--);
                      _applyParsedResult(_parsedResults[_currentParseIndex]);
                    },
                    child: const Text("上一个"),
                  ),
                if (_currentParseIndex < _parsedResults.length - 1)
                  TextButton(
                    onPressed: () {
                      setState(() => _currentParseIndex++);
                      _applyParsedResult(_parsedResults[_currentParseIndex]);
                    },
                    child: const Text("下一个"),
                  ),
              ],
            ),
            if (_llmRawResponse != null) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text(
                  "大模型原始返回",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                      _llmRawResponse!,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
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

  Widget _buildAIRecognitionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _aiInputCtrl,
            decoration: InputDecoration(
              labelText: "输入待办内容",
              hintText: "例：明天下午3点开会，每周一早上9点做周报",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 8),
          _buildExampleText("明天下午3点开会"),
          _buildExampleText("每周一早上9点做周报"),
          _buildExampleText("每天早上8点喝水，下午2点开会"),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isParsing ? null : _doSmartParse,
                  child: _isParsing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("智能解析"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isParsing ? null : _doLLMParse,
                  child: _isParsing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("大模型识别"),
                ),
              ),
            ],
          ),
          if (_parsedResults.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              "解析结果 (${_currentParseIndex + 1}/${_parsedResults.length})",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildParseResultItem(
                "待办内容", _parsedResults[_currentParseIndex].title),
            _buildParseResultItem(
              "开始时间",
              _parsedResults[_currentParseIndex].startTime != null
                  ? DateFormat('yyyy-MM-dd HH:mm')
                      .format(_parsedResults[_currentParseIndex].startTime!)
                  : "未识别",
            ),
            _buildParseResultItem(
              "结束时间",
              _parsedResults[_currentParseIndex].endTime != null
                  ? DateFormat('yyyy-MM-dd HH:mm')
                      .format(_parsedResults[_currentParseIndex].endTime!)
                  : "未识别",
            ),
            _buildParseResultItem("全天事件",
                _parsedResults[_currentParseIndex].isAllDay ? "是" : "否"),
            _buildParseResultItem(
                "重复",
                _getRecurrenceText(
                    _parsedResults[_currentParseIndex].recurrence)),
            _buildParseResultItem(
                "备注/地点", _parsedResults[_currentParseIndex].remark ?? "-"),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_currentParseIndex > 0)
                  TextButton(
                    onPressed: () {
                      setState(() => _currentParseIndex--);
                      _applyParsedResult(_parsedResults[_currentParseIndex]);
                    },
                    child: const Text("上一个"),
                  ),
                if (_currentParseIndex < _parsedResults.length - 1)
                  TextButton(
                    onPressed: () {
                      setState(() => _currentParseIndex++);
                      _applyParsedResult(_parsedResults[_currentParseIndex]);
                    },
                    child: const Text("下一个"),
                  ),
              ],
            ),
          ],
        ],
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
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
