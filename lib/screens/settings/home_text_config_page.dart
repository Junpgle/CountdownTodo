import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../storage_service.dart';

class HomeTextConfigPage extends StatefulWidget {
  const HomeTextConfigPage({super.key});

  @override
  State<HomeTextConfigPage> createState() => _HomeTextConfigPageState();
}

class _HomeTextConfigPageState extends State<HomeTextConfigPage> {
  final _timeSalutationController = TextEditingController();
  final _usernameFormatController = TextEditingController();
  bool _isLoading = true;

  // 日期格式下拉选项
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
  final Map<String, List<String>> _customGreetings = {
    'morning': [],    // 5:00-11:00
    'noon': [],       // 11:00-14:00
    'afternoon': [],  // 14:00-18:00
    'evening': [],    // 18:00-23:00
    'night': [],      // 23:00-3:00
    'latenight': [],  // 3:00-5:00
  };

  final Map<String, String> _timePeriodLabels = {
    'morning': '早晨 (5:00-11:00)',
    'noon': '中午 (11:00-14:00)',
    'afternoon': '下午 (14:00-18:00)',
    'evening': '傍晚 (18:00-23:00)',
    'night': '夜晚 (23:00-3:00)',
    'latenight': '凌晨 (3:00-5:00)',
  };

  final Map<String, List<String>> _defaultGreetings = {
    'morning': [
      "今天也要元气超标！",
      "新的一天，把快乐置顶。",
      "迎着光，做自己的小太阳。",
      "起床充电，活力满格。",
      "今日宜：开心、努力、好运。"
    ],
    'noon': [
      "吃饱喝足，继续奔赴。",
      "中场能量补给，快乐不打烊。",
      "稳住状态，万事可期。",
      "生活不慌不忙，慢慢发光。",
      "好好吃饭，就是好好爱自己。"
    ],
    'afternoon': [
      "保持热爱，保持冲劲。",
      "状态在线，干劲拉满。",
      "不急不躁，温柔又有力量。",
      "把普通日子，过得热气腾腾。",
      "继续向前，好运正在路上。"
    ],
    'evening': [
      "晚风轻踩云朵，今天辛苦啦。",
      "卸下疲惫，拥抱温柔。",
      "今日圆满，万事顺心。",
      "把烦恼清空，把快乐装满。",
      "好好休息，明天依旧闪亮。"
    ],
    'night': [
      "愿你心安，好梦常伴。",
      "安静沉淀，积蓄力量。",
      "不慌不忙，自在生长。",
      "温柔治愈，接纳所有情绪。",
      "今夜安睡，明日更好。"
    ],
    'latenight': [
      "凌晨的星光，为你照亮前路。",
      "此刻努力，未来可期。",
      "安静时光，悄悄变优秀。",
      "不负自己，不负岁月。",
      "愿你眼里有光，心中有梦。"
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _timeSalutationController.dispose();
    _usernameFormatController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await StorageService.getHomeTextConfig();
    setState(() {
      _timeSalutationController.text = config['customTimeSalutation'] as String? ?? '';
      _usernameFormatController.text = config['usernameFormat'] as String? ?? '{name}';
      _selectedDateFormat = config['dateFormat'] as String? ?? 'MM月dd日 EEEE';

      // 加载分时段问候语
      final savedGreetings = config['customGreetings'] as Map<String, dynamic>?;
      if (savedGreetings != null) {
        for (var entry in _customGreetings.keys) {
          final list = savedGreetings[entry] as List<dynamic>?;
          if (list != null) {
            _customGreetings[entry] = list.cast<String>();
          }
        }
      }

      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    final config = {
      'customTimeSalutation': _timeSalutationController.text.isEmpty
          ? null
          : _timeSalutationController.text,
      'dateFormat': _selectedDateFormat,
      'usernameFormat': _usernameFormatController.text.isEmpty
          ? '{name}'
          : _usernameFormatController.text,
      'customGreetings': _customGreetings,
    };
    await StorageService.saveHomeTextConfig(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存成功，重启应用后生效')),
      );
      Navigator.pop(context, true);
    }
  }

  void _editGreetings(String period) {
    final controller = TextEditingController(
      text: _customGreetings[period]!.join('\n'),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑${_timePeriodLabels[period]}问候语'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '每行一条，将随机显示其中一条',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '输入问候语，每行一条',
                  ),
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
          TextButton(
            onPressed: () {
              setState(() {
                final lines = controller.text
                    .split('\n')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                _customGreetings[period] = lines;
              });
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('首页文字自定义')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 时间问候语
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '时间问候语',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '自定义时间段问候语，留空则使用默认值（上午好、下午好等）',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _timeSalutationController,
                    decoration: const InputDecoration(
                      hintText: '例如：早上好、Hi、Hello',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 日期格式（下拉选择 + 实时预览）
          Card(
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
                    value: _selectedDateFormat,
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
          ),
          const SizedBox(height: 16),

          // 用户名格式
          Card(
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
          ),
          const SizedBox(height: 16),

          // 分时段随机问候语
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '分时段随机问候语',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '点击编辑各时段的问候语，每行一条将随机显示',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ..._customGreetings.keys.map((period) {
                    final greetings = _customGreetings[period]!;
                    final isCustom = greetings.isNotEmpty;
                    return Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            _getPeriodIcon(period),
                            color: isCustom
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                          title: Text(_timePeriodLabels[period]!),
                          subtitle: Text(
                            isCustom
                                ? '${greetings.length} 条自定义'
                                : '使用默认 (${_defaultGreetings[period]!.length} 条)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isCustom
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _editGreetings(period),
                        ),
                        if (period != 'latenight')
                          const Divider(height: 1, indent: 56),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 恢复默认按钮
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _timeSalutationController.clear();
                _selectedDateFormat = 'MM月dd日 EEEE';
                _usernameFormatController.text = '{name}';
                for (var key in _customGreetings.keys) {
                  _customGreetings[key] = [];
                }
              });
            },
            icon: const Icon(Icons.restore),
            label: const Text('恢复全部默认'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  IconData _getPeriodIcon(String period) {
    switch (period) {
      case 'morning':
        return Icons.wb_sunny;
      case 'noon':
        return Icons.wb_cloudy;
      case 'afternoon':
        return Icons.wb_twilight;
      case 'evening':
        return Icons.nights_stay;
      case 'night':
        return Icons.dark_mode;
      case 'latenight':
        return Icons.bedtime;
      default:
        return Icons.access_time;
    }
  }
}
