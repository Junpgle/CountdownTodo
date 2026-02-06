import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 状态变量
  List<String> selectedOps = [];
  final TextEditingController _minN1Ctrl = TextEditingController();
  final TextEditingController _maxN1Ctrl = TextEditingController();
  final TextEditingController _minN2Ctrl = TextEditingController();
  final TextEditingController _maxN2Ctrl = TextEditingController();
  final TextEditingController _maxResCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    var settings = await StorageService.getSettings();
    setState(() {
      selectedOps = List<String>.from(settings['operators']);
      _minN1Ctrl.text = settings['min_num1'].toString();
      _maxN1Ctrl.text = settings['max_num1'].toString();
      _minN2Ctrl.text = settings['min_num2'].toString();
      _maxN2Ctrl.text = settings['max_num2'].toString();
      _maxResCtrl.text = settings['max_result'].toString();
    });
  }

  void _saveSettings() async {
    if (selectedOps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少选择一种运算符号')));
      return;
    }

    // 解析数值
    int minN1 = int.tryParse(_minN1Ctrl.text) ?? 0;
    int maxN1 = int.tryParse(_maxN1Ctrl.text) ?? 50;
    int minN2 = int.tryParse(_minN2Ctrl.text) ?? 0;
    int maxN2 = int.tryParse(_maxN2Ctrl.text) ?? 50;
    int maxRes = int.tryParse(_maxResCtrl.text) ?? 100;

    // 简单校验
    if (minN1 > maxN1) { int t = minN1; minN1 = maxN1; maxN1 = t; }
    if (minN2 > maxN2) { int t = minN2; minN2 = maxN2; maxN2 = t; }

    Map<String, dynamic> settings = {
      'operators': selectedOps,
      'min_num1': minN1, 'max_num1': maxN1,
      'min_num2': minN2, 'max_num2': maxN2,
      'max_result': maxRes,
    };

    await StorageService.saveSettings(settings);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存')));
    Navigator.pop(context);
  }

  Widget _buildOpCheckbox(String op, String label) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 18)),
      selected: selectedOps.contains(op),
      onSelected: (bool selected) {
        setState(() {
          if (selected) {
            selectedOps.add(op);
          } else {
            selectedOps.remove(op);
          }
        });
      },
    );
  }

  Widget _buildRangeRow(String label, TextEditingController minCtrl, TextEditingController maxCtrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: "最小值", border: OutlineInputBorder()),
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("至")),
            Expanded(
              child: TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: "最大值", border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("题目设置")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("运算类型 (可多选)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                _buildOpCheckbox('+', '加法 (+)'),
                _buildOpCheckbox('-', '减法 (-)'),
                _buildOpCheckbox('*', '乘法 (×)'),
                _buildOpCheckbox('/', '除法 (÷)'),
              ],
            ),
            const Divider(height: 30),
            _buildRangeRow("第一个数范围", _minN1Ctrl, _maxN1Ctrl),
            _buildRangeRow("第二个数范围", _minN2Ctrl, _maxN2Ctrl),
            const Text("结果最大值", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            TextField(
              controller: _maxResCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  hintText: "例如: 100",
                  border: OutlineInputBorder(),
                  helperText: "加法和乘法结果不超过此值"
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("保存配置", style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _saveSettings,
              ),
            )
          ],
        ),
      ),
    );
  }
}