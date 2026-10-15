import 'dart:async';

import 'package:flutter/material.dart';

import '../services/time_estimation_service.dart';
import '../services/time_estimation_repository.dart';
import '../storage_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/time_utils.dart';
import 'optional_liquid_glass_surface.dart';

/// The primary form stays compact; historical details live in a read-only sheet.
class TimeEstimationHint extends StatelessWidget {
  const TimeEstimationHint({super.key, required this.result});
  final TimeEstimationResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(
                '预计专注用时 ${formatMinutesChinese(result.estimatedMinutes)}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.primary),
              ),
              Text(
                result.referenceLabel,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('time-estimation-evidence'),
          tooltip: '估时依据',
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          onPressed: () => showTimeEstimationEvidence(context, result),
        ),
      ],
    );
  }
}

Future<void> showTimeEstimationEvidence(
  BuildContext context,
  TimeEstimationResult result,
) async {
  try {
    if (result.username != null) {
      await TimeEstimationRepository.checkAccount(result.username!);
    }
  } on TimeEstimationAccountChanged {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('账号已切换，请重新打开当前页面')));
    }
    return;
  }
  if (!context.mounted) return;
  await showAppModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    useGlassSheet: false,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _EvidenceSheet(result: result),
  );
}

class _EvidenceSheet extends StatefulWidget {
  const _EvidenceSheet({required this.result});
  final TimeEstimationResult result;
  @override
  State<_EvidenceSheet> createState() => _EvidenceSheetState();
}

class _EvidenceSheetState extends State<_EvidenceSheet>
    with WidgetsBindingObserver {
  bool _accountValid = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_checkAccount);
    _checkAccount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(_checkAccount);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccount();
  }

  void _checkAccount() => unawaited(_validateAccount());
  Future<void> _validateAccount() async {
    final username = widget.result.username;
    if (username == null) return;
    try {
      await TimeEstimationRepository.checkAccount(username);
    } on TimeEstimationAccountChanged {
      if (mounted) setState(() => _accountValid = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final groups = <String, List<int>>{};
    if (_accountValid) {
      for (final sample in result.samples) {
        groups.putIfAbsent(sample.title, () => []).add(sample.minutes.round());
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              (media.size.height -
                      media.viewInsets.bottom -
                      media.padding.vertical)
                  .clamp(80.0, 560.0),
        ),
        child: OptionalLiquidGlassSheet(
          fallbackDecoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '估时依据',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('time-estimation-close'),
                      tooltip: '关闭估时依据',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (!_accountValid)
                  const Text('账号已切换，请关闭后重新打开当前页面')
                else ...[
                  const SizedBox(height: 8),
                  Text(
                    '预计专注用时 ${formatMinutesChinese(result.estimatedMinutes)}',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: colors.primary),
                  ),
                  const SizedBox(height: 6),
                  Text(result.referenceLabel),
                  const SizedBox(height: 16),
                  Text(result.reason),
                  if (result.samples.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('本次参考 ${result.samples.length} 个已完成待办'),
                    ...groups.entries
                        .take(3)
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '累计专注 ${entry.value.take(5).join('、')} 分钟'
                                  '${entry.value.length > 5 ? '等${entry.value.length}次任务' : ' · ${entry.value.length}个待办'}',
                                ),
                              ],
                            ),
                          ),
                        ),
                    if (groups.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('另有 ${groups.length - 3} 组，本页最多展示3组概况'),
                      ),
                  ],
                  if (result.incompleteCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '另有 ${result.incompleteCount} 个已完成待办记录不完整，未作为估时样本。',
                      ),
                    ),
                  if (result.noActualCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '另有 ${result.noActualCount} 个已完成待办没有明确的实际投入，未作为估时样本。',
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    '参考的是已记录的专注投入，不包含休息或未记录的工作；不代表当前待办剩余时间。',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
