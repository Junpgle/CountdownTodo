import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/mimo_asr_service.dart';
import '../models/chat_message.dart';
import '../services/quick_voice_recorder.dart';
import '../utils/page_transitions.dart';
import 'quick_voice_container_transition.dart';
import 'quick_voice_gesture.dart';

class HeldQuickVoiceResult {
  const HeldQuickVoiceResult(
    this.text,
    this.usageSummary,
    this.sendImmediately,
  );
  final String text;
  final ChatUsageSummary? usageSummary;
  final bool sendImmediately;
}

/// An overlay preserves the original pointer's gesture arena until release.
Future<HeldQuickVoiceResult?> showHeldQuickVoiceChat({
  required BuildContext context,
  required String apiKey,
  required QuickVoiceGestureController gesture,
  GlobalKey? sourceKey,
  QuickVoiceRecorder? recorder,
  MimoAsrService? asrService,
}) async {
  await PageTransitions.init();
  if (!context.mounted || gesture.isReleased) return null;
  final overlay = Overlay.of(context);
  if (!overlay.mounted) return null;
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final source = sourceKey?.currentContext?.findRenderObject() as RenderBox?;
  final sourceRect = source != null && source.hasSize
      ? overlayBox.globalToLocal(source.localToGlobal(Offset.zero)) &
            source.size
      : Rect.fromCenter(
          center: overlayBox.globalToLocal(gesture.origin),
          width: 48,
          height: 48,
        );
  final transitionKey = GlobalKey<QuickVoiceContainerTransitionState>();
  final completion = Completer<HeldQuickVoiceResult?>();
  final colors = Theme.of(context);
  final media = MediaQuery.of(context);
  final history = LocalHistoryEntry(
    onRemove: () => gesture.release(cancel: true),
  );
  ModalRoute.of(context)?.addLocalHistoryEntry(history);
  ChatUsageSummary? usage;
  final entry = OverlayEntry(
    builder: (context) => Positioned.fill(
      child: Theme(
        data: colors,
        child: MediaQuery(
          data: media,
          child: QuickVoiceContainerTransition(
            key: transitionKey,
            sourceRect: sourceRect,
            child: ListenableBuilder(
              listenable: gesture,
              builder: (context, child) =>
                  IgnorePointer(ignoring: !gesture.isReleased, child: child),
              child: QuickVoiceChatSheet(
                apiKey: apiKey,
                gesture: gesture,
                recorder: recorder,
                asrService: asrService,
                onUsageSummary: (value) => usage = value,
                onCompleted: (text) {
                  if (completion.isCompleted) return;
                  completion.complete(
                    text == null
                        ? null
                        : HeldQuickVoiceResult(
                            text,
                            usage,
                            gesture.target == QuickVoiceTarget.send,
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    final result = await completion.future;
    await transitionKey.currentState?.close();
    return result;
  } finally {
    history.remove();
    entry.remove();
    entry.dispose();
  }
}

enum _VoicePhase { starting, recording, transcribing, failed }

class QuickVoiceChatSheet extends StatefulWidget {
  const QuickVoiceChatSheet({
    super.key,
    required this.apiKey,
    this.recorder,
    this.asrService,
    this.onUsageSummary,
    this.gesture,
    this.onCompleted,
  });

  final String apiKey;
  final QuickVoiceRecorder? recorder;
  final MimoAsrService? asrService;
  final ValueChanged<ChatUsageSummary>? onUsageSummary;
  final QuickVoiceGestureController? gesture;
  final ValueChanged<String?>? onCompleted;

  @override
  State<QuickVoiceChatSheet> createState() => _QuickVoiceChatSheetState();
}

class _QuickVoiceChatSheetState extends State<QuickVoiceChatSheet>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final QuickVoiceRecorder _recorder;
  late final MimoAsrService _asr;
  late Future<void> _operation;
  Future<void>? _recorderCleanup;
  _VoicePhase _phase = _VoicePhase.starting;
  Timer? _timer;
  int _seconds = 0;
  String _error = '';
  bool _permissionDenied = false;
  bool _closing = false;
  Uint8List? _audio;
  late final AnimationController _pulse;
  bool _reduceMotion = false;
  QuickVoiceTarget _target = QuickVoiceTarget.send;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorder = widget.recorder ?? RecordQuickVoiceRecorder();
    _asr = widget.asrService ?? MimoAsrService();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _target = widget.gesture?.target ?? QuickVoiceTarget.send;
    widget.gesture?.addListener(_handleGesture);
    _operation = Future<void>.value();
    if (widget.gesture?.isReleased ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cancel());
    } else {
      _operation = _start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _pulse.stop();
    } else if (widget.gesture != null && _phase == _VoicePhase.recording) {
      _pulse.repeat();
    }
  }

  void _handleGesture() {
    if (!mounted || _closing) return;
    final gesture = widget.gesture!;
    if (_target != gesture.target) {
      setState(() => _target = gesture.target);
      unawaited(HapticFeedback.selectionClick());
    }
    if (!gesture.isReleased) return;
    if (_target == QuickVoiceTarget.cancel || _phase == _VoicePhase.starting) {
      _cancel();
    } else if (_phase != _VoicePhase.failed) {
      _finish();
    }
  }

  Future<void> _start() async {
    _timer?.cancel();
    _audio = null;
    _seconds = 0;
    _permissionDenied = false;
    try {
      await _recorder.start();
      if (!mounted || _closing) return;
      setState(() => _phase = _VoicePhase.recording);
      if (widget.gesture != null && !_reduceMotion) _pulse.repeat();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _closing) return;
        setState(() => _seconds++);
        if (_seconds >= 60) {
          if (_target == QuickVoiceTarget.cancel) {
            _cancel();
          } else {
            _finish();
          }
        }
      });
    } catch (error) {
      _permissionDenied = error is MicrophoneAccessDenied;
      _fail(error);
    }
  }

  void _finish() {
    if (_phase != _VoicePhase.recording) return;
    _timer?.cancel();
    _pulse.stop();
    setState(() => _phase = _VoicePhase.transcribing);
    _operation = _stopAndTranscribe();
  }

  Future<void> _stopAndTranscribe() async {
    try {
      _audio = await _recorder.stop();
      if (!mounted || _closing) return;
      await _transcribe();
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _transcribe() async {
    try {
      final result = await _asr.transcribeWithUsage(
        wavBytes: _audio!,
        apiKey: widget.apiKey,
      );
      if (!mounted || _closing) return;
      if (result.usageSummary != null) {
        widget.onUsageSummary?.call(result.usageSummary!);
      }
      _closing = true;
      _complete(result.text);
    } on TimeoutException {
      _fail('识别超时，请重试');
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    _timer?.cancel();
    _pulse.stop();
    if (!mounted || _closing) return;
    setState(() {
      _phase = _VoicePhase.failed;
      _error = error.toString().replaceFirst(
        RegExp(r'^(Exception|FormatException): '),
        '',
      );
    });
  }

  void _retry() {
    if (_closing) return;
    setState(
      () => _phase = _audio == null
          ? _VoicePhase.starting
          : _VoicePhase.transcribing,
    );
    _operation = _audio == null ? _start() : _transcribe();
  }

  void _cancel() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _asr.dispose();
    unawaited(_releaseRecorder());
    _complete(null);
  }

  void _complete(String? text) {
    if (widget.onCompleted != null) {
      widget.onCompleted!(text);
    } else {
      Navigator.pop(context, text);
    }
  }

  Future<void> _releaseRecorder() => _recorderCleanup ??= _operation
      .whenComplete(_recorder.dispose)
      .catchError((Object _) {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _cancel();
    }
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    widget.gesture?.removeListener(_handleGesture);
    _pulse.dispose();
    _asr.dispose();
    // Permission and recorder startup may still be pending when the sheet closes.
    // Wait for that operation before releasing the microphone.
    unawaited(_releaseRecorder());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gesture != null &&
        _phase != _VoicePhase.failed &&
        (_closing ||
            !widget.gesture!.isReleased ||
            _phase == _VoicePhase.transcribing)) {
      return _buildHeldRecording(context);
    }
    final colors = Theme.of(context).colorScheme;
    final recording = _phase == _VoicePhase.recording;
    final failed = _phase == _VoicePhase.failed;
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '快速语音对话',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _cancel,
                    tooltip: '取消录音',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (recording || failed)
                Icon(
                  recording ? Icons.mic_rounded : Icons.mic_off_rounded,
                  size: 56,
                  color: failed ? colors.error : colors.primary,
                )
              else
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(),
                ),
              const SizedBox(height: 16),
              Text(
                switch (_phase) {
                  _VoicePhase.starting => '正在准备麦克风…',
                  _VoicePhase.recording => '正在聆听 · ${_seconds}s / 60s',
                  _VoicePhase.transcribing => '正在识别语音…',
                  _VoicePhase.failed => _error,
                },
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: failed ? colors.error : colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '录音结束后交给 AI 理解需求，操作会先生成确认卡片。',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (recording)
                FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('结束录音并发送'),
                ),
              if (failed) ...[
                if (_permissionDenied)
                  TextButton(
                    onPressed: openAppSettings,
                    child: const Text('打开系统设置'),
                  ),
                FilledButton(
                  onPressed: _retry,
                  child: Text(_audio == null ? '重新录音' : '重试识别'),
                ),
                if (_audio != null)
                  TextButton(
                    onPressed: () {
                      _audio = null;
                      _retry();
                    },
                    child: const Text('重新录音'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeldRecording(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final recording = _phase == _VoicePhase.recording;
    final color = _target == QuickVoiceTarget.cancel
        ? colors.error
        : colors.primary;
    final title = _phase == _VoicePhase.starting
        ? '正在准备麦克风…'
        : _phase == _VoicePhase.transcribing
        ? (_target == QuickVoiceTarget.openAi ? '正在转成 AI 草稿…' : '正在识别并发送…')
        : switch (_target) {
            QuickVoiceTarget.send => '松手发送',
            QuickVoiceTarget.cancel => '松手取消',
            QuickVoiceTarget.openAi => '松手进入 AI · 保留草稿',
          };
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDragTarget(
                      '进入 AI',
                      Icons.auto_awesome_rounded,
                      QuickVoiceTarget.openAi,
                      colors.primary,
                    ),
                    _buildDragTarget(
                      '取消',
                      Icons.close_rounded,
                      QuickVoiceTarget.cancel,
                      colors.error,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: Duration(milliseconds: _reduceMotion ? 0 : 160),
                  child: Text(
                    title,
                    key: ValueKey(title),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  recording ? '${_seconds}s / 60s' : '请稍候',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                if (recording)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final source = _recorder;
                      if (source is QuickVoiceLevelSource) {
                        return ValueListenableBuilder<double>(
                          valueListenable:
                              (source as QuickVoiceLevelSource).level,
                          builder: (context, level, _) =>
                              _buildWave(color, level),
                        );
                      }
                      return _buildWave(color, 0);
                    },
                  )
                else
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                const SizedBox(height: 20),
                Text(
                  recording ? '按住说话 · 左上进入 AI · 右上取消' : '语音内容将交给 AI 理解需求',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                if (_phase == _VoicePhase.transcribing)
                  TextButton(onPressed: _cancel, child: const Text('取消等待')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragTarget(
    String label,
    IconData icon,
    QuickVoiceTarget target,
    Color color,
  ) {
    final colors = Theme.of(context).colorScheme;
    final selected = _target == target;
    return Flexible(
      child: AnimatedScale(
        scale: selected ? 1.1 : 1,
        duration: Duration(milliseconds: _reduceMotion ? 0 : 180),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          key: ValueKey('voice-target-${target.name}'),
          duration: Duration(milliseconds: _reduceMotion ? 0 : 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? color : colors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected
                    ? (target == QuickVoiceTarget.cancel
                          ? colors.onError
                          : colors.onPrimary)
                    : color,
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? (target == QuickVoiceTarget.cancel
                              ? colors.onError
                              : colors.onPrimary)
                        : colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWave(Color color, double level) {
    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(19, (index) {
          final motion = _reduceMotion
              ? 0.5
              : (math.sin(_pulse.value * math.pi * 2 + index * 0.7) + 1) / 2;
          final envelope = 1 - (index - 9).abs() / 12;
          return Container(
            width: 4,
            height: 6 + envelope * (8 * motion + level * 30),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
