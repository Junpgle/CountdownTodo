import 'package:flutter/material.dart';

import '../../../widgets/floating_glass_control.dart';
import '../services/ai_usage_cost_service.dart';

class AiUsageCostScreen extends StatefulWidget {
  const AiUsageCostScreen({super.key});

  @override
  State<AiUsageCostScreen> createState() => _AiUsageCostScreenState();
}

class _AiUsageCostScreenState extends State<AiUsageCostScreen> {
  bool _loading = true;
  bool _autoLedger = true;
  AiUsageSummary _summary = const AiUsageSummary();
  List<AiUsageRecord> _records = const [];
  List<AiUsagePricing> _pricing = const [];

  DateTime get _monthStart =>
      DateTime(DateTime.now().year, DateTime.now().month);
  DateTime get _monthEnd =>
      DateTime(DateTime.now().year, DateTime.now().month + 1);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<dynamic>([
      AiUsageCostService.isAutoLedgerEnabled(),
      AiUsageCostService.getSummary(from: _monthStart, to: _monthEnd),
      AiUsageCostService.getRecords(
          from: _monthStart, to: _monthEnd, limit: 20),
      AiUsageCostService.getPricing(),
    ]);
    if (!mounted) return;
    setState(() {
      _autoLedger = values[0] as bool;
      _summary = values[1] as AiUsageSummary;
      _records = values[2] as List<AiUsageRecord>;
      _pricing = values[3] as List<AiUsagePricing>;
      _loading = false;
    });
  }

  Future<void> _toggleAutoLedger(bool value) async {
    setState(() => _autoLedger = value);
    await AiUsageCostService.setAutoLedgerEnabled(value);
  }

  Future<void> _editPricing([AiUsagePricing? current]) async {
    final provider = TextEditingController(text: current?.provider ?? 'zhipu');
    final model = TextEditingController(text: current?.model ?? '');
    final input = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(current.inputMicrosPerMillion),
    );
    final output = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(current.outputMicrosPerMillion),
    );
    final image = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(current.imageMicrosPerImage),
    );
    final result = await showDialog<AiUsagePricing>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(current == null ? '添加模型单价' : '编辑模型单价'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: provider,
                decoration: const InputDecoration(labelText: '服务商标识，例如 zhipu'),
              ),
              TextField(
                controller: model,
                decoration: const InputDecoration(labelText: '模型 ID'),
              ),
              TextField(
                controller: input,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '输入 ¥ / 百万 Token'),
              ),
              TextField(
                controller: output,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '输出 ¥ / 百万 Token'),
              ),
              TextField(
                controller: image,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '图片 ¥ / 张（可选）'),
              ),
              const SizedBox(height: 12),
              const Text(
                '单价由你按服务商当前账单填写。未配置或 API 未返回 usage 的调用会保留明细，但不会自动入账。',
                style: TextStyle(fontSize: 12),
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
              if (provider.text.trim().isEmpty || model.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                AiUsagePricing(
                  provider: provider.text.trim(),
                  model: model.text.trim(),
                  inputMicrosPerMillion:
                      AiUsageCostService.yuanToMicros(input.text),
                  outputMicrosPerMillion:
                      AiUsageCostService.yuanToMicros(output.text),
                  imageMicrosPerImage:
                      AiUsageCostService.yuanToMicros(image.text),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    provider.dispose();
    model.dispose();
    input.dispose();
    output.dispose();
    image.dispose();
    if (result == null) return;
    await AiUsageCostService.savePricing(result);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('AI 调用费用'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editPricing(),
        icon: const Icon(Icons.add),
        label: const Text('添加单价'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Card(
                    color: colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('本月 API 费用',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            AiUsageCostService.formatMicros(
                                _summary.costMicros),
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                              '$_summary.calls 次调用 · ${_summary.totalTokens} Token'
                              '${_summary.unpricedCalls == 0 ? '' : ' · ${_summary.unpricedCalls} 次待定价'}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('自动写入记账'),
                    subtitle: const Text('同一天、同一服务商与模型的费用会汇总成一笔“AI 服务”支出'),
                    value: _autoLedger,
                    onChanged: _toggleAutoLedger,
                  ),
                  const SizedBox(height: 20),
                  Text('按服务商与模型',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_summary.breakdowns.isEmpty)
                    const Card(
                        child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('本月尚未收到带用量信息的 AI 调用。'),
                    ))
                  else
                    ..._summary.breakdowns.map(
                      (item) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: Text('${item.provider} · ${item.model}'),
                          subtitle: Text(
                              '${item.calls} 次 · ${item.totalTokens} Token'
                              '${item.unpricedCalls == 0 ? '' : ' · ${item.unpricedCalls} 次待定价'}'),
                          trailing: Text(
                              AiUsageCostService.formatMicros(item.costMicros)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                          child: Text('模型单价',
                              style: Theme.of(context).textTheme.titleMedium)),
                      TextButton.icon(
                        onPressed: () => _editPricing(),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('管理'),
                      ),
                    ],
                  ),
                  if (_pricing.isEmpty)
                    const Text('尚未配置单价；费用统计会显示为待定价。')
                  else
                    ..._pricing.map(
                      (item) => Card(
                        child: ListTile(
                          title: Text('${item.provider} · ${item.model}'),
                          subtitle: Text(
                            '输入 ${AiUsageCostService.microsToYuan(item.inputMicrosPerMillion)} / 百万 · '
                            '输出 ${AiUsageCostService.microsToYuan(item.outputMicrosPerMillion)} / 百万'
                            '${item.imageMicrosPerImage == 0 ? '' : ' · 图片 ${AiUsageCostService.microsToYuan(item.imageMicrosPerImage)} / 张'}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editPricing(item),
                          ),
                          onLongPress: () async {
                            await AiUsageCostService.deletePricing(item.id);
                            await _load();
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text('最近调用', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._records.map(
                    (item) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text('${item.provider} · ${item.model}'),
                      subtitle:
                          Text('${item.operation} · ${item.totalTokens} Token'),
                      trailing: Text(item.isPriced
                          ? AiUsageCostService.formatMicros(
                              item.costMicros ?? 0)
                          : '待定价'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
