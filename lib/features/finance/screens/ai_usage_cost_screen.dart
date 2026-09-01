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
    try {
      await AiUsageCostService.reconcileCurrentMonth();
    } catch (_) {
      // 费用明细仍可查看，下一次进入页面时继续尝试补齐账本。
    }
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
    final cachedInput = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(
              current.cachedInputMicrosPerMillion,
            ),
    );
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
    final peakCachedInput = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(
              current.peakCachedInputMicrosPerMillion,
            ),
    );
    final peakInput = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(current.peakInputMicrosPerMillion),
    );
    final peakOutput = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(
              current.peakOutputMicrosPerMillion,
            ),
    );
    final image = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(current.imageMicrosPerImage),
    );
    final audio = TextEditingController(
      text: current == null
          ? ''
          : AiUsageCostService.microsToYuan(current.audioMicrosPerHour),
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
                controller: cachedInput,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: '缓存输入 ¥ / 百万 Token（可选）'),
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
                controller: peakCachedInput,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '高峰缓存输入 ¥ / 百万 Token（DeepSeek 可选）',
                ),
              ),
              TextField(
                controller: peakInput,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '高峰输入 ¥ / 百万 Token（DeepSeek 可选）',
                ),
              ),
              TextField(
                controller: peakOutput,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '高峰输出 ¥ / 百万 Token（DeepSeek 可选）',
                ),
              ),
              TextField(
                controller: image,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: '图片固定费 ¥ / 张（非 MiMo 可选）'),
              ),
              TextField(
                controller: audio,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '音频 ¥ / 小时（可选）'),
              ),
              const SizedBox(height: 12),
              const Text(
                '智谱内置分段单价会按输入/输出 Token 自动匹配；DeepSeek 内置北京时间工作日高峰价（09:00–12:00、14:00–18:00）。MiMo、智谱视觉和 DeepSeek 视觉的媒体 Token 已计入输入 Token，不另加图片费。NVIDIA NIM 与自定义模型没有统一公价，请手动配置；Token Plan 额度不按按量价格自动折算。',
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
              final providerValue = provider.text.trim();
              final modelValue = model.text.trim();
              final cachedInputValue =
                  AiUsageCostService.yuanToMicros(cachedInput.text);
              final inputValue = AiUsageCostService.yuanToMicros(input.text);
              final outputValue = AiUsageCostService.yuanToMicros(output.text);
              final peakCachedInputValue =
                  AiUsageCostService.yuanToMicros(peakCachedInput.text);
              final peakInputValue =
                  AiUsageCostService.yuanToMicros(peakInput.text);
              final peakOutputValue =
                  AiUsageCostService.yuanToMicros(peakOutput.text);
              final sameIdentity = current != null &&
                  current.provider == providerValue &&
                  current.model == modelValue;
              final preservesTiers = sameIdentity &&
                  current.tiers.isNotEmpty &&
                  current.cachedInputMicrosPerMillion == cachedInputValue &&
                  current.inputMicrosPerMillion == inputValue &&
                  current.outputMicrosPerMillion == outputValue;
              final preservesFree = sameIdentity &&
                  current.isFree &&
                  cachedInputValue == 0 &&
                  inputValue == 0 &&
                  outputValue == 0 &&
                  peakCachedInputValue == 0 &&
                  peakInputValue == 0 &&
                  peakOutputValue == 0 &&
                  AiUsageCostService.yuanToMicros(image.text) == 0 &&
                  AiUsageCostService.yuanToMicros(audio.text) == 0;
              Navigator.pop(
                context,
                AiUsagePricing(
                  provider: providerValue,
                  model: modelValue,
                  cachedInputMicrosPerMillion: cachedInputValue,
                  inputMicrosPerMillion: inputValue,
                  outputMicrosPerMillion: outputValue,
                  imageMicrosPerImage:
                      AiUsageCostService.yuanToMicros(image.text),
                  audioMicrosPerHour:
                      AiUsageCostService.yuanToMicros(audio.text),
                  peakCachedInputMicrosPerMillion: peakCachedInputValue,
                  peakInputMicrosPerMillion: peakInputValue,
                  peakOutputMicrosPerMillion: peakOutputValue,
                  imageTokensIncluded:
                      sameIdentity && current.imageTokensIncluded,
                  isFree: preservesFree,
                  tiers: preservesTiers ? current.tiers : const [],
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
    cachedInput.dispose();
    input.dispose();
    output.dispose();
    peakCachedInput.dispose();
    peakInput.dispose();
    peakOutput.dispose();
    image.dispose();
    audio.dispose();
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
                            '${item.cachedPromptTokens == 0 ? '' : ' · 缓存 ${item.cachedPromptTokens}'}'
                            '${item.imageTokens == 0 ? '' : ' · 图片 ${item.imageTokens}'}'
                            '${item.unpricedCalls == 0 ? '' : ' · ${item.unpricedCalls} 次待定价'}',
                          ),
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
                  const Text(
                    '内置精确价目：智谱支持上下文/输出分段，DeepSeek 支持北京时间高峰与闲时；NVIDIA NIM 和自定义模型需按实际账户价格配置。没有返回 usage 的调用会保留为待定价。',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (_pricing.isEmpty)
                    const Text('尚未配置单价；费用统计会显示为待定价。')
                  else
                    ..._pricing.map(
                      (item) => Card(
                        child: ListTile(
                          title: Text(
                            '${item.provider} · ${item.model}'
                            '${AiUsageCostService.isBuiltInPricing(item) ? ' · 内置' : ''}',
                          ),
                          subtitle: Text(
                            _pricingSubtitle(item),
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
                      subtitle: Text(
                        '${item.operation} · ${item.totalTokens} Token'
                        '${item.cachedPromptTokens == 0 ? '' : ' · 缓存 ${item.cachedPromptTokens}'}'
                        '${item.imageTokens == 0 ? '' : ' · 图片 ${item.imageTokens}'}'
                        '${item.audioSeconds == 0 ? '' : ' · 音频 ${item.audioSeconds}s'}',
                      ),
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

  String _pricingSubtitle(AiUsagePricing item) {
    final parts = <String>[];
    if (item.isFree) {
      parts.add('免费');
    } else {
      if (item.cachedInputMicrosPerMillion > 0) {
        parts.add(
          '缓存 ${AiUsageCostService.microsToYuan(item.cachedInputMicrosPerMillion)} / 百万',
        );
      }
      if (item.inputMicrosPerMillion > 0) {
        parts.add(
          '输入 ${AiUsageCostService.microsToYuan(item.inputMicrosPerMillion)} / 百万',
        );
      }
      if (item.outputMicrosPerMillion > 0) {
        parts.add(
          '输出 ${AiUsageCostService.microsToYuan(item.outputMicrosPerMillion)} / 百万',
        );
      }
    }
    if (item.tiers.isNotEmpty) parts.add('按输入/输出 Token 分段');
    if (item.peakInputMicrosPerMillion > 0 ||
        item.peakOutputMicrosPerMillion > 0 ||
        item.peakCachedInputMicrosPerMillion > 0) {
      parts.add('DeepSeek 北京时间高峰价已内置');
    }
    if (item.imageTokensIncluded) parts.add('视觉 Token 已含');
    if (item.imageMicrosPerImage > 0) {
      parts.add(
        '图片 ${AiUsageCostService.microsToYuan(item.imageMicrosPerImage)} / 张',
      );
    }
    if (item.audioMicrosPerHour > 0) {
      parts.add(
        '音频 ${AiUsageCostService.microsToYuan(item.audioMicrosPerHour)} / 小时',
      );
    }
    return parts.isEmpty ? '未配置可用单价' : parts.join(' · ');
  }
}
