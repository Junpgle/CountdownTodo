import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/pomodoro_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../storage_service.dart';

// ============================================================
// 首页今日专注记录卡片
// ============================================================
class PomodoroTodaySection extends StatefulWidget {
  final String username;
  final bool isLight;

  const PomodoroTodaySection({
    super.key,
    required this.username,
    this.isLight = false,
  });

  @override
  State<PomodoroTodaySection> createState() => _PomodoroTodaySectionState();
}

class _PomodoroTodaySectionState extends State<PomodoroTodaySection> {
  List<PomodoroRecord> _records = [];
  List<PomodoroTag> _tags = [];
  bool _loading = true;
  bool _collapsed = false;

  // 跨端感知
  Map<String, dynamic>? _remoteActive;   // 其他端正在进行的专注信息
  Timer? _pollTimer;
  int _remoteCountdown = 0;              // 剩余秒数
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    // 先从云端增量同步，再读本地（标签+记录）
    await PomodoroService.syncTagsFromCloud();
    final records = await PomodoroService.getTodayRecords();
    final tags = await PomodoroService.getTags();
    // 后台再拉一次记录（不阻塞）
    PomodoroService.syncRecordsFromCloud().then((changed) {
      if (changed && mounted) _loadLocal();
    });
    if (mounted) {
      setState(() {
        _records = records;
        _tags = tags;
        _loading = false;
      });
    }
  }

  // 每 30 秒轮询一次其他端专注状态
  void _startPolling() {
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
  }

  Future<void> _poll() async {
    final deviceId = await StorageService.getDeviceId();
    final remote = await ApiService.fetchActivePomodoroFromOtherDevice(deviceId);
    if (!mounted) return;
    if (remote != null) {
      // 计算剩余时间
      final startMs = remote['start_time'] as int? ?? 0;
      final planned = remote['planned_duration'] as int? ?? 1500;
      final elapsed = ((DateTime.now().millisecondsSinceEpoch - startMs) / 1000).round();
      final remaining = (planned - elapsed).clamp(0, planned);
      setState(() {
        _remoteActive = remote;
        _remoteCountdown = remaining;
      });
      _startCountdownTimer();
    } else {
      if (_remoteActive != null) {
        _countdownTimer?.cancel();
        setState(() {
          _remoteActive = null;
          _remoteCountdown = 0;
        });
        // 其他端专注结束，刷新本地记录
        await PomodoroService.syncRecordsFromCloud();
        if (mounted) _loadLocal();
      }
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    if (_remoteCountdown <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remoteCountdown = (_remoteCountdown - 1).clamp(0, 999999);
      });
      if (_remoteCountdown <= 0) {
        _countdownTimer?.cancel();
        _poll(); // 倒计时归零后立即重新查询
      }
    });
  }

  String _formatCountdown(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String? _tagNamesFor(PomodoroRecord r) {
    if (r.tagUuids.isEmpty) return null;
    final names = r.tagUuids
        .map((uuid) => _tags.cast<PomodoroTag?>()
            .firstWhere((t) => t?.uuid == uuid, orElse: () => null)
            ?.name)
        .whereType<String>()
        .join(' · ');
    return names.isEmpty ? null : names;
  }

  int get _totalSeconds =>
      _records.fold(0, (s, r) => s + r.effectiveDuration);

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isLight ? Colors.white : null;
    final subColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.7)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 标题行 ──
        Row(
          children: [
            Icon(Icons.timer_rounded,
                size: 20,
                color: widget.isLight
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '今日专注',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor),
            ),
            const SizedBox(width: 8),
            if (!_loading && _records.isNotEmpty)
              Text(
                PomodoroService.formatDuration(_totalSeconds),
                style: TextStyle(
                    fontSize: 14,
                    color: widget.isLight
                        ? Colors.white.withValues(alpha: 0.85)
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600),
              ),
            const Spacer(),
            // 折叠按钮
            if (_records.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _collapsed = !_collapsed),
                child: Icon(
                  _collapsed
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  color: subColor,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // ── 其他端专注提示条 ──
        if (_remoteActive != null) _buildRemoteBanner(subColor),

        // ── 记录列表 ──
        if (_loading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()))
        else if (_records.isEmpty && _remoteActive == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('今天还没有专注记录',
                style: TextStyle(color: subColor, fontSize: 14)),
          )
        else if (!_collapsed)
          ..._records.map((r) => _buildRecordTile(r, subColor)),
      ],
    );
  }

  Widget _buildRemoteBanner(Color? subColor) {
    final deviceId = (_remoteActive!['device_id'] as String?) ?? '其他设备';
    final mins = _remoteCountdown ~/ 60;
    final secs = _remoteCountdown % 60;
    final timeStr =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B6B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('🍅', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '其他设备正在专注中',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.isLight ? Colors.white : null),
                ),
                Text(
                  '设备 ${deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId}… · 剩余 $timeStr',
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
              ],
            ),
          ),
          // 加标签按钮
          TextButton.icon(
            onPressed: () => _showRemoteTagDialog(),
            icon: const Icon(Icons.label_outline, size: 16),
            label: const Text('加标签', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              foregroundColor: const Color(0xFFFF6B6B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(PomodoroRecord r, Color? subColor) {
    final startLocal =
        DateTime.fromMillisecondsSinceEpoch(r.startTime, isUtc: true).toLocal();
    final tagNames = _tagNamesFor(r);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isLight
            ? Colors.white.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isLight
              ? Colors.white.withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: r.isCompleted
                  ? const Color(0xFF4ECDC4).withValues(alpha: 0.15)
                  : const Color(0xFFFF6B6B).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              r.isCompleted
                  ? Icons.check_circle_rounded
                  : Icons.timer_off_rounded,
              size: 18,
              color: r.isCompleted
                  ? const Color(0xFF4ECDC4)
                  : const Color(0xFFFF6B6B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.todoTitle ?? '自由专注',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          widget.isLight ? Colors.white : null),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      DateFormat('HH:mm').format(startLocal),
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                    if (tagNames != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '🏷 $tagNames',
                          style:
                              TextStyle(fontSize: 11, color: subColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            PomodoroService.formatDuration(r.effectiveDuration),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: widget.isLight ? Colors.white : null),
          ),
        ],
      ),
    );
  }

  // 为其他端正在进行的专注添加标签
  void _showRemoteTagDialog() {
    if (_remoteActive == null) return;
    final todoUuid = _remoteActive!['todo_uuid'] as String?;
    List<String> selectedTags = [];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sd) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('为其他设备的专注添加标签',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (_tags.isEmpty)
                const Text('暂无标签，请先在番茄钟界面创建标签',
                    style: TextStyle(color: Colors.grey))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags.map((tag) {
                    final sel = selectedTags.contains(tag.uuid);
                    final color = _hexToColor(tag.color);
                    return FilterChip(
                      label: Text(tag.name),
                      selected: sel,
                      showCheckmark: false,
                      selectedColor: color.withValues(alpha: 0.2),
                      side: BorderSide(
                          color: sel ? color : Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      onSelected: (v) => sd(() {
                        if (v) {
                          selectedTags.add(tag.uuid);
                        } else {
                          selectedTags.remove(tag.uuid);
                        }
                      }),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selectedTags.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          // 上传标签关联（通过 todo_tags）
                          if (todoUuid != null) {
                            final fakeRecord = PomodoroRecord(
                              uuid: _remoteActive!['uuid']?.toString() ?? '',
                              todoUuid: todoUuid,
                              tagUuids: selectedTags,
                              startTime: _remoteActive!['start_time'] as int? ?? 0,
                              plannedDuration: _remoteActive!['planned_duration'] as int? ?? 1500,
                            );
                            await ApiService.uploadPomodoroRecord(fakeRecord.toJson());
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('标签已添加'), duration: Duration(seconds: 2)),
                            );
                          }
                        },
                  child: const Text('确认添加'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

Color _hexToColor(String hex) {
  try {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return Colors.blueGrey;
  }
}

