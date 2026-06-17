import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../storage_service.dart';

class GreetingTimeSlot {
  String id;
  int startHour;
  int startMinute;
  int endHour;
  int endMinute;
  List<String> greetings;

  GreetingTimeSlot({
    required this.id,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.greetings,
  });

  String get timeRange {
    return '${_formatTime(startHour, startMinute)} - ${_formatTime(endHour, endMinute)}';
  }

  String _formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  bool get isCrossDay {
    final start = startHour * 60 + startMinute;
    final end = endHour * 60 + endMinute;
    return end <= start;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'greetings': greetings,
      };

  factory GreetingTimeSlot.fromJson(Map<String, dynamic> json) {
    return GreetingTimeSlot(
      id: json['id'] as String,
      startHour: json['startHour'] as int,
      startMinute: json['startMinute'] as int,
      endHour: json['endHour'] as int,
      endMinute: json['endMinute'] as int,
      greetings: (json['greetings'] as List<dynamic>).cast<String>(),
    );
  }
}

class SalutationTimeSlot {
  String id;
  int startHour;
  int startMinute;
  int endHour;
  int endMinute;
  String text;

  SalutationTimeSlot({
    required this.id,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.text,
  });

  String get timeRange {
    return '${_formatTime(startHour, startMinute)} - ${_formatTime(endHour, endMinute)}';
  }

  String _formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  bool get isCrossDay {
    final start = startHour * 60 + startMinute;
    final end = endHour * 60 + endMinute;
    return end <= start;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'text': text,
      };

  factory SalutationTimeSlot.fromJson(Map<String, dynamic> json) {
    return SalutationTimeSlot(
      id: json['id'] as String,
      startHour: json['startHour'] as int,
      startMinute: json['startMinute'] as int,
      endHour: json['endHour'] as int,
      endMinute: json['endMinute'] as int,
      text: json['text'] as String,
    );
  }
}

class HomeTextConfigPage extends StatefulWidget {
  const HomeTextConfigPage({super.key});

  @override
  State<HomeTextConfigPage> createState() => _HomeTextConfigPageState();
}

class _HomeTextConfigPageState extends State<HomeTextConfigPage> {
  final _usernameFormatController = TextEditingController();
  final _fixedGreetingController = TextEditingController();
  final _fixedSalutationController = TextEditingController();
  bool _isLoading = true;

  // 时间问候语模式
  String _salutationMode = 'timed';
  List<SalutationTimeSlot> _salutationSlots = [];

  // 问候语模式
  String _greetingMode = 'timed';

  // 日期格式
  final List<Map<String, String>> _dateFormatOptions = [
    {'value': 'MM月dd日 EEEE', 'label': '06月17日 星期三'},
    {'value': 'yyyy-MM-dd EEEE', 'label': '2026-06-17 星期三'},
    {'value': 'MM/dd EEEE', 'label': '06/17 星期三'},
    {'value': 'EEEE MM月dd日', 'label': '星期三 06月17日'},
    {'value': 'MM月dd日', 'label': '06月17日'},
    {'value': 'yyyy-MM-dd', 'label': '2026-06-17'},
    {'value': 'MM/dd', 'label': '06/17'},
    {'value': 'EEEE', 'label': '星期三'},
  ];
  String _selectedDateFormat = 'MM月dd日 EEEE';

  // 分时段问候语配置
  List<GreetingTimeSlot> _timeSlots = [];

  // 默认时间问候语时段
  static final List<SalutationTimeSlot> _defaultSalutationSlots = [
    SalutationTimeSlot(
      id: 'morning',
      startHour: 5,
      startMinute: 0,
      endHour: 12,
      endMinute: 0,
      text: '上午好',
    ),
    SalutationTimeSlot(
      id: 'noon',
      startHour: 12,
      startMinute: 0,
      endHour: 14,
      endMinute: 0,
      text: '中午好',
    ),
    SalutationTimeSlot(
      id: 'afternoon',
      startHour: 14,
      startMinute: 0,
      endHour: 18,
      endMinute: 0,
      text: '下午好',
    ),
    SalutationTimeSlot(
      id: 'evening',
      startHour: 18,
      startMinute: 0,
      endHour: 5,
      endMinute: 0,
      text: '晚上好',
    ),
  ];

  // 默认问候语时段
  static final List<GreetingTimeSlot> _defaultTimeSlots = [
    GreetingTimeSlot(
      id: 'morning',
      startHour: 5,
      startMinute: 0,
      endHour: 11,
      endMinute: 0,
      greetings: [
        "今天也要元气超标！",
        "新的一天，把快乐置顶。",
        "迎着光，做自己的小太阳。",
        "起床充电，活力满格。",
        "今日宜：开心、努力、好运。"
      ],
    ),
    GreetingTimeSlot(
      id: 'noon',
      startHour: 11,
      startMinute: 0,
      endHour: 14,
      endMinute: 0,
      greetings: [
        "吃饱喝足，继续奔赴。",
        "中场能量补给，快乐不打烊。",
        "稳住状态，万事可期。",
        "生活不慌不忙，慢慢发光。",
        "好好吃饭，就是好好爱自己。"
      ],
    ),
    GreetingTimeSlot(
      id: 'afternoon',
      startHour: 14,
      startMinute: 0,
      endHour: 18,
      endMinute: 0,
      greetings: [
        "保持热爱，保持冲劲。",
        "状态在线，干劲拉满。",
        "不急不躁，温柔又有力量。",
        "把普通日子，过得热气腾腾。",
        "继续向前，好运正在路上。"
      ],
    ),
    GreetingTimeSlot(
      id: 'evening',
      startHour: 18,
      startMinute: 0,
      endHour: 23,
      endMinute: 0,
      greetings: [
        "晚风轻踩云朵，今天辛苦啦。",
        "卸下疲惫，拥抱温柔。",
        "今日圆满，万事顺心。",
        "把烦恼清空，把快乐装满。",
        "好好休息，明天依旧闪亮。"
      ],
    ),
    GreetingTimeSlot(
      id: 'night',
      startHour: 23,
      startMinute: 0,
      endHour: 3,
      endMinute: 0,
      greetings: [
        "愿你心安，好梦常伴。",
        "安静沉淀，积蓄力量。",
        "不慌不忙，自在生长。",
        "温柔治愈，接纳所有情绪。",
        "今夜安睡，明日更好。"
      ],
    ),
    GreetingTimeSlot(
      id: 'latenight',
      startHour: 3,
      startMinute: 0,
      endHour: 5,
      endMinute: 0,
      greetings: [
        "凌晨的星光，为你照亮前路。",
        "此刻努力，未来可期。",
        "安静时光，悄悄变优秀。",
        "不负自己，不负岁月。",
        "愿你眼里有光，心中有梦。"
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _usernameFormatController.dispose();
    _fixedGreetingController.dispose();
    _fixedSalutationController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await StorageService.getHomeTextConfig();
    setState(() {
      _usernameFormatController.text =
          config['usernameFormat'] as String? ?? '{name}';
      _selectedDateFormat =
          config['dateFormat'] as String? ?? 'MM月dd日 EEEE';

      // 加载时间问候语配置
      _salutationMode = config['salutationMode'] as String? ?? 'timed';
      final fixedSalutation = config['fixedSalutation'] as String?;
      if (fixedSalutation != null) {
        _fixedSalutationController.text = fixedSalutation;
      }
      final savedSalutationSlots =
          config['salutationSlots'] as List<dynamic>?;
      if (savedSalutationSlots != null && savedSalutationSlots.isNotEmpty) {
        _salutationSlots = savedSalutationSlots
            .map((e) =>
                SalutationTimeSlot.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _salutationSlots = _defaultSalutationSlots
            .map((e) => SalutationTimeSlot(
                  id: e.id,
                  startHour: e.startHour,
                  startMinute: e.startMinute,
                  endHour: e.endHour,
                  endMinute: e.endMinute,
                  text: e.text,
                ))
            .toList();
      }

      // 加载问候语配置
      _greetingMode = config['greetingMode'] as String? ?? 'timed';
      final fixedGreetings =
          config['fixedGreetings'] as List<dynamic>?;
      if (fixedGreetings != null && fixedGreetings.isNotEmpty) {
        _fixedGreetingController.text = fixedGreetings.join('\n');
      }
      final savedSlots =
          config['timeSlots'] as List<dynamic>?;
      if (savedSlots != null && savedSlots.isNotEmpty) {
        _timeSlots = savedSlots
            .map((e) =>
                GreetingTimeSlot.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _timeSlots = _defaultTimeSlots
            .map((e) => GreetingTimeSlot(
                  id: e.id,
                  startHour: e.startHour,
                  startMinute: e.startMinute,
                  endHour: e.endHour,
                  endMinute: e.endMinute,
                  greetings: List.from(e.greetings),
                ))
            .toList();
      }

      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    final fixedGreetings = _fixedGreetingController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final config = {
      'dateFormat': _selectedDateFormat,
      'usernameFormat': _usernameFormatController.text.isEmpty
          ? '{name}'
          : _usernameFormatController.text,
      'salutationMode': _salutationMode,
      'fixedSalutation': _fixedSalutationController.text.isEmpty
          ? null
          : _fixedSalutationController.text,
      'salutationSlots': _salutationSlots.map((e) => e.toJson()).toList(),
      'greetingMode': _greetingMode,
      'fixedGreetings': fixedGreetings,
      'timeSlots': _timeSlots.map((e) => e.toJson()).toList(),
    };
    await StorageService.saveHomeTextConfig(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存成功，重启应用后生效')),
      );
      Navigator.pop(context, true);
    }
  }

  // 时间问候语相关方法
  void _addSalutationSlot() {
    final id = 'salutation_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _salutationSlots.add(SalutationTimeSlot(
        id: id,
        startHour: 8,
        startMinute: 0,
        endHour: 20,
        endMinute: 0,
        text: '',
      ));
    });
    _editSalutationSlot(_salutationSlots.length - 1);
  }

  void _removeSalutationSlot(int index) {
    setState(() {
      _salutationSlots.removeAt(index);
    });
  }

  void _editSalutationSlot(int index) {
    final slot = _salutationSlots[index];
    final textController = TextEditingController(text: slot.text);

    showDialog(
      context: context,
      builder: (context) => _SalutationSlotEditDialog(
        slot: slot,
        textController: textController,
        onSave: (updatedSlot) {
          setState(() {
            _salutationSlots[index] = updatedSlot;
          });
        },
      ),
    );
  }

  // 问候语相关方法
  void _addTimeSlot() {
    final id = 'slot_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _timeSlots.add(GreetingTimeSlot(
        id: id,
        startHour: 8,
        startMinute: 0,
        endHour: 20,
        endMinute: 0,
        greetings: [],
      ));
    });
    _editTimeSlot(_timeSlots.length - 1);
  }

  void _removeTimeSlot(int index) {
    setState(() {
      _timeSlots.removeAt(index);
    });
  }

  void _editTimeSlot(int index) {
    final slot = _timeSlots[index];
    final greetingController =
        TextEditingController(text: slot.greetings.join('\n'));

    showDialog(
      context: context,
      builder: (context) => _TimeSlotEditDialog(
        slot: slot,
        greetingController: greetingController,
        onSave: (updatedSlot) {
          setState(() {
            _timeSlots[index] = updatedSlot;
          });
        },
      ),
    );
  }

  IconData _getSlotIcon(int hour) {
    if (hour >= 5 && hour < 11) return Icons.wb_sunny;
    if (hour >= 11 && hour < 14) return Icons.wb_cloudy;
    if (hour >= 14 && hour < 18) return Icons.wb_twilight;
    if (hour >= 18 && hour < 23) return Icons.nights_stay;
    return Icons.dark_mode;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('首页文字自定义')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isWideScreen = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      appBar: AppBar(
        title: const Text('首页文字自定义'),
        actions: [
          TextButton(
            onPressed: _saveConfig,
            child: const Text('保存'),
          ),
        ],
      ),
      body: isWideScreen ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：基础配置 + 时间问候语
        Expanded(
          flex: 1,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildDateFormatCard(),
              const SizedBox(height: 16),
              _buildUsernameFormatCard(),
              const SizedBox(height: 16),
              _buildSalutationModeCard(),
              const SizedBox(height: 16),
              if (_salutationMode == 'fixed')
                _buildFixedSalutationCard()
              else
                _buildSalutationSlotsCard(),
            ],
          ),
        ),
        // 右侧：问候语配置
        Expanded(
          flex: 1,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGreetingModeCard(),
              const SizedBox(height: 16),
              if (_greetingMode == 'fixed')
                _buildFixedGreetingCard()
              else
                _buildTimeSlotsCard(),
              const SizedBox(height: 16),
              _buildRestoreButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDateFormatCard(),
        const SizedBox(height: 16),
        _buildUsernameFormatCard(),
        const SizedBox(height: 16),
        _buildSalutationModeCard(),
        const SizedBox(height: 16),
        if (_salutationMode == 'fixed')
          _buildFixedSalutationCard()
        else
          _buildSalutationSlotsCard(),
        const SizedBox(height: 16),
        _buildGreetingModeCard(),
        const SizedBox(height: 16),
        if (_greetingMode == 'fixed')
          _buildFixedGreetingCard()
        else
          _buildTimeSlotsCard(),
        const SizedBox(height: 24),
        _buildRestoreButton(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildDateFormatCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '日期格式',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedDateFormat,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '选择日期格式',
              ),
              items: _dateFormatOptions.map((option) {
                return DropdownMenuItem<String>(
                  value: option['value'],
                  child: Text(option['label']!),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedDateFormat = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.preview, size: 16),
                  const SizedBox(width: 8),
                  const Text('预览: ',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    DateFormat(_selectedDateFormat, 'zh_CN')
                        .format(DateTime.now()),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsernameFormatCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '用户名格式',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '使用 {name} 作为用户名占位符',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameFormatController,
              decoration: const InputDecoration(
                hintText: '{name}',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.preview, size: 16),
                  const SizedBox(width: 8),
                  const Text('预览: ',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    _usernameFormatController.text
                        .replaceAll('{name}', '小明'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalutationModeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '时间问候语模式',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '显示在用户名前面的问候语，如"上午好"',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'timed',
                  label: Text('分时段'),
                  icon: Icon(Icons.schedule),
                ),
                ButtonSegment(
                  value: 'fixed',
                  label: Text('固定'),
                  icon: Icon(Icons.text_fields),
                ),
              ],
              selected: {_salutationMode},
              onSelectionChanged: (Set<String> selected) {
                setState(() {
                  _salutationMode = selected.first;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedSalutationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '固定时间问候语',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '所有时间段显示相同的问候语',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fixedSalutationController,
              decoration: const InputDecoration(
                hintText: '例如：你好、Hi、Hello',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalutationSlotsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '分时段时间问候语',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _addSalutationSlot,
                  tooltip: '添加时段',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '支持跨天时段（如 18:00 - 05:00）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_salutationSlots.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '暂无时段，点击右上角 + 添加',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _salutationSlots.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _salutationSlots.removeAt(oldIndex);
                    _salutationSlots.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final slot = _salutationSlots[index];
                  return ListTile(
                    key: ValueKey(slot.id),
                    leading: Icon(
                      _getSlotIcon(slot.startHour),
                      color: slot.text.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    title: Text(
                      slot.timeRange,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      slot.text.isNotEmpty ? slot.text : '未设置',
                      style: TextStyle(
                        fontSize: 12,
                        color: slot.text.isNotEmpty
                            ? Theme.of(context).colorScheme.primary
                            : Colors.orange,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _editSalutationSlot(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          onPressed: () => _removeSalutationSlot(index),
                        ),
                        const Icon(Icons.drag_handle),
                      ],
                    ),
                    onTap: () => _editSalutationSlot(index),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGreetingModeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '随机问候语模式',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '显示在时间问候语下方的随机文案',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'timed',
                  label: Text('分时段'),
                  icon: Icon(Icons.schedule),
                ),
                ButtonSegment(
                  value: 'fixed',
                  label: Text('固定'),
                  icon: Icon(Icons.text_fields),
                ),
              ],
              selected: {_greetingMode},
              onSelectionChanged: (Set<String> selected) {
                setState(() {
                  _greetingMode = selected.first;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedGreetingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '固定随机问候语',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '每行一条，将随机显示其中一条',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fixedGreetingController,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入问候语，每行一条',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSlotsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '分时段随机问候语',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _addTimeSlot,
                  tooltip: '添加时段',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '支持跨天时段（如 23:00 - 05:00），点击编辑问候语',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_timeSlots.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '暂无时段，点击右上角 + 添加',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _timeSlots.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _timeSlots.removeAt(oldIndex);
                    _timeSlots.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final slot = _timeSlots[index];
                  return ListTile(
                    key: ValueKey(slot.id),
                    leading: Icon(
                      _getSlotIcon(slot.startHour),
                      color: slot.greetings.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    title: Text(
                      slot.timeRange,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      slot.greetings.isNotEmpty
                          ? '${slot.greetings.length} 条问候语'
                          : '未设置问候语',
                      style: TextStyle(
                        fontSize: 12,
                        color: slot.greetings.isNotEmpty
                            ? Theme.of(context).colorScheme.primary
                            : Colors.orange,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _editTimeSlot(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          onPressed: () => _removeTimeSlot(index),
                        ),
                        const Icon(Icons.drag_handle),
                      ],
                    ),
                    onTap: () => _editTimeSlot(index),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreButton() {
    return OutlinedButton.icon(
      onPressed: () {
        setState(() {
          _selectedDateFormat = 'MM月dd日 EEEE';
          _usernameFormatController.text = '{name}';
          _salutationMode = 'timed';
          _fixedSalutationController.clear();
          _salutationSlots = _defaultSalutationSlots
              .map((e) => SalutationTimeSlot(
                    id: e.id,
                    startHour: e.startHour,
                    startMinute: e.startMinute,
                    endHour: e.endHour,
                    endMinute: e.endMinute,
                    text: e.text,
                  ))
              .toList();
          _greetingMode = 'timed';
          _fixedGreetingController.clear();
          _timeSlots = _defaultTimeSlots
              .map((e) => GreetingTimeSlot(
                    id: e.id,
                    startHour: e.startHour,
                    startMinute: e.startMinute,
                    endHour: e.endHour,
                    endMinute: e.endMinute,
                    greetings: List.from(e.greetings),
                  ))
              .toList();
        });
      },
      icon: const Icon(Icons.restore),
      label: const Text('恢复全部默认'),
    );
  }
}

// 时间问候语编辑对话框
class _SalutationSlotEditDialog extends StatefulWidget {
  final SalutationTimeSlot slot;
  final TextEditingController textController;
  final Function(SalutationTimeSlot) onSave;

  const _SalutationSlotEditDialog({
    required this.slot,
    required this.textController,
    required this.onSave,
  });

  @override
  State<_SalutationSlotEditDialog> createState() =>
      _SalutationSlotEditDialogState();
}

class _SalutationSlotEditDialogState
    extends State<_SalutationSlotEditDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    _startTime =
        TimeOfDay(hour: widget.slot.startHour, minute: widget.slot.startMinute);
    _endTime =
        TimeOfDay(hour: widget.slot.endHour, minute: widget.slot.endMinute);
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 500;

    return AlertDialog(
      title: const Text('编辑时间问候语'),
      content: SizedBox(
        width: isWideScreen ? 500 : double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间选择
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(true),
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text('开始: ${_formatTime(_startTime)}'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, color: Colors.grey),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(false),
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text('结束: ${_formatTime(_endTime)}'),
                  ),
                ),
              ],
            ),
            if (_endTime.hour * 60 + _endTime.minute <=
                _startTime.hour * 60 + _startTime.minute)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '跨天时段：${_formatTime(_startTime)} - 次日 ${_formatTime(_endTime)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // 问候语输入
            const Text(
              '问候语文本',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: widget.textController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如：上午好、中午好',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(SalutationTimeSlot(
              id: widget.slot.id,
              startHour: _startTime.hour,
              startMinute: _startTime.minute,
              endHour: _endTime.hour,
              endMinute: _endTime.minute,
              text: widget.textController.text.trim(),
            ));
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// 问候语编辑对话框
class _TimeSlotEditDialog extends StatefulWidget {
  final GreetingTimeSlot slot;
  final TextEditingController greetingController;
  final Function(GreetingTimeSlot) onSave;

  const _TimeSlotEditDialog({
    required this.slot,
    required this.greetingController,
    required this.onSave,
  });

  @override
  State<_TimeSlotEditDialog> createState() => _TimeSlotEditDialogState();
}

class _TimeSlotEditDialogState extends State<_TimeSlotEditDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    _startTime =
        TimeOfDay(hour: widget.slot.startHour, minute: widget.slot.startMinute);
    _endTime =
        TimeOfDay(hour: widget.slot.endHour, minute: widget.slot.endMinute);
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 500;

    return AlertDialog(
      title: const Text('编辑时段'),
      content: SizedBox(
        width: isWideScreen ? 500 : double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间选择
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(true),
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text('开始: ${_formatTime(_startTime)}'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, color: Colors.grey),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(false),
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text('结束: ${_formatTime(_endTime)}'),
                  ),
                ),
              ],
            ),
            if (_endTime.hour * 60 + _endTime.minute <=
                _startTime.hour * 60 + _startTime.minute)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '跨天时段：${_formatTime(_startTime)} - 次日 ${_formatTime(_endTime)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // 问候语输入
            const Text(
              '问候语（每行一条，随机显示）',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: widget.greetingController,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入问候语，每行一条',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final greetings = widget.greetingController.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();

            widget.onSave(GreetingTimeSlot(
              id: widget.slot.id,
              startHour: _startTime.hour,
              startMinute: _startTime.minute,
              endHour: _endTime.hour,
              endMinute: _endTime.minute,
              greetings: greetings,
            ));
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
