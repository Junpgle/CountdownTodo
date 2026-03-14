import 'package:flutter/material.dart';

class ZfTimeConfigDialog extends StatefulWidget {
  const ZfTimeConfigDialog({Key? key}) : super(key: key);

  @override
  State<ZfTimeConfigDialog> createState() => _ZfTimeConfigDialogState();
}

class _ZfTimeConfigDialogState extends State<ZfTimeConfigDialog> {
  // 默认作息方案 (可以根据国内大多数高校预设)
  final List<Map<String, int>> tempTimes = [
    {'sH': 8, 'sM': 0, 'eH': 8, 'eM': 45},    // 第一节 8:00—8:45
    {'sH': 8, 'sM': 55, 'eH': 9, 'eM': 40},   // 第二节 8:55—9:40
    {'sH': 9, 'sM': 55, 'eH': 10, 'eM': 40},  // 第三节 9:55—10:40
    {'sH': 10, 'sM': 50, 'eH': 11, 'eM': 35}, // 第四节 10:50—11:35
    {'sH': 11, 'sM': 45, 'eH': 12, 'eM': 30}, // 第五节 11:45—12:30
    {'sH': 13, 'sM': 30, 'eH': 14, 'eM': 15}, // 第六节 13:30—14:15
    {'sH': 14, 'sM': 25, 'eH': 15, 'eM': 10}, // 第七节 14:25—15:10
    {'sH': 15, 'sM': 25, 'eH': 16, 'eM': 10}, // 第八节 15:25—16:10
    {'sH': 16, 'sM': 20, 'eH': 17, 'eM': 5},  // 第九节 16:20—17:05
    {'sH': 17, 'sM': 15, 'eH': 18, 'eM': 0},  // 第十节 17:15—18:00
    {'sH': 19, 'sM': 0, 'eH': 19, 'eM': 45},  // 第十一节 19:00—19:45
    {'sH': 19, 'sM': 50, 'eH': 20, 'eM': 35}, // 第十二节 19:50—20:35
    {'sH': 20, 'sM': 40, 'eH': 21, 'eM': 25}, // 第十三节 20:40—21:25
  ];

  Future<void> _pickSingleTime(int index, bool isStart) async {
    final t = tempTimes[index];
    final initialTime = isStart
        ? TimeOfDay(hour: t['sH']!, minute: t['sM']!)
        : TimeOfDay(hour: t['eH']!, minute: t['eM']!);

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: "设置第 ${index + 1} 节课${isStart ? '开始' : '结束'}时间",
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          t['sH'] = picked.hour;
          t['sM'] = picked.minute;
        } else {
          t['eH'] = picked.hour;
          t['eM'] = picked.minute;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("配置课表作息时间"),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            const Text("正方教务不含时间，请分别设置每节课的开始与结束时刻：",
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: tempTimes.length,
                itemBuilder: (context, index) {
                  final t = tempTimes[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                          radius: 12,
                          child: Text("${index + 1}", style: const TextStyle(fontSize: 10))
                      ),
                      title: Row(
                        children: [
                          // 开始时间按钮
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickSingleTime(index, true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "${t['sH']}:${t['sM']!.toString().padLeft(2, '0')}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text("至", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ),
                          // 结束时间按钮
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickSingleTime(index, false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "${t['eH']}:${t['eM']!.toString().padLeft(2, '0')}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
        FilledButton(
          onPressed: () {
            Map<int, Map<String, int>> resultMap = {};
            for (int i = 0; i < tempTimes.length; i++) {
              final t = tempTimes[i];
              resultMap[i + 1] = {
                'start': t['sH']! * 100 + t['sM']!,
                'end': t['eH']! * 100 + t['eM']!,
              };
            }
            Navigator.pop(context, resultMap);
          },
          child: const Text("确认并导入"),
        ),
      ],
    );
  }
}
