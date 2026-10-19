import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/plan_manual_completion_service.dart';
import '../storage_service.dart';

/// Keeps the short-lived receipt on its source page, never in global storage.
class PlanManualCompletionHost extends StatefulWidget {
  const PlanManualCompletionHost({
    super.key,
    required this.child,
    required this.onRefresh,
    this.enabled = true,
    this.removeReminders,
  });
  final Widget child;
  final VoidCallback onRefresh;
  final bool enabled;
  final Future<void> Function(PlanManualCompletionReceipt)? removeReminders;
  @override
  State<PlanManualCompletionHost> createState() =>
      PlanManualCompletionHostState();
}

class PlanManualCompletionHostState extends State<PlanManualCompletionHost>
    with WidgetsBindingObserver {
  _Notice? _model;
  PlanManualCompletionReceipt? _pendingReceipt;
  int _presentSequence = 0;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _bar;
  Timer? _expiry;
  ScaffoldMessengerState? _messenger;
  bool get _available =>
      mounted &&
      widget.enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onSignal);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_available) _clear(defer: true);
  }

  @override
  void didUpdateWidget(covariant PlanManualCompletionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _clear(defer: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  void _clear({bool defer = false}) {
    ++_presentSequence;
    _pendingReceipt?.invalidate();
    _pendingReceipt = null;
    _expiry?.cancel();
    _model?.receipt.invalidate();
    _model = null;
    final bar = _bar;
    final messenger = _messenger;
    _bar = null;
    _messenger = null;
    if (bar != null) {
      if (defer) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (messenger?.mounted == true) bar.close();
        });
      } else {
        bar.close();
      }
    }
  }

  void _onSignal() {
    final signal = StorageService.scopedDataRefreshNotifier.value;
    if (signal.domains.contains(DataRefreshDomain.all)) {
      _clear();
    } else if ([
      DataRefreshDomain.planBlocks,
      DataRefreshDomain.todos,
      DataRefreshDomain.pomodoro,
    ].any(signal.affects)) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    final model = _model;
    if (model == null || model.busy) return;
    try {
      await model.receipt.service.verifyUnchanged(model.receipt);
    } catch (_) {
      if (mounted && _model == model) {
        model.receipt.invalidate();
        model.update(() => model.error ??= '规划或投入已变化，请重新查看');
      }
    }
  }

  void present(PlanManualCompletionReceipt receipt) {
    if (_pendingReceipt == receipt || _model?.receipt == receipt) return;
    _clear();
    _pendingReceipt = receipt;
    final sequence = _presentSequence;
    // The editor pops first. Wait for the source route to become current.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (sequence != _presentSequence || !_available || !receipt.canUndo) {
        receipt.invalidate();
        return;
      }
      try {
        await receipt.identity.check();
      } catch (_) {
        receipt.invalidate();
        return;
      }
      if (sequence != _presentSequence || !_available || !receipt.canUndo) {
        receipt.invalidate();
        return;
      }
      _pendingReceipt = null;
      final model = _Notice(receipt);
      _model = model;
      _show(model);
      _expiry = Timer(receipt.expiresAt.difference(receipt.service.now), () {
        receipt.invalidate();
        if (mounted && _model == model) model.update(() {});
      });
      unawaited(_reminders(model));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _current(_Notice model) => mounted && _model == model && _available;

  void _show(_Notice model, {bool reminderError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    _messenger = messenger;
    _bar?.close();
    messenger.hideCurrentSnackBar();
    model.bars++;
    final bar = messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: reminderError ? 20 : 10),
        behavior: SnackBarBehavior.floating,
        persist: false,
        margin: EdgeInsets.fromLTRB(
          12,
          0,
          max(12, MediaQuery.sizeOf(context).width - 452),
          MediaQuery.sizeOf(context).height < 500 ? 12 : 88,
        ),
        content: ListenableBuilder(
          listenable: model,
          builder: (context, _) {
            final buttonStyle = TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.inversePrimary,
            );
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  model.error ??
                      (model.reminderError ? '规划已完成，提醒更新未成功' : '已确认规划完成'),
                ),
                if (model.receipt.canUndo)
                  TextButton(
                    key: const ValueKey('plan-manual-undo'),
                    style: buttonStyle,
                    onPressed: model.busy ? null : () => _undo(model),
                    child: const Text('撤销'),
                  ),
                if (model.reminderError)
                  TextButton(
                    key: const ValueKey('plan-manual-retry-reminders'),
                    style: buttonStyle,
                    onPressed: model.busy || model.updatingReminders
                        ? null
                        : () => _reminders(model),
                    child: const Text('重试提醒'),
                  ),
              ],
            );
          },
        ),
      ),
    );
    _bar = bar;
    bar.closed.then((_) {
      if (_bar == bar) {
        _bar = null;
        _clear();
      }
      model.bars--;
      if (_model != model && model.bars == 0) model.dispose();
    });
  }

  Future<void> _reminders(_Notice model) async {
    if (!_current(model) || model.busy || model.updatingReminders) return;
    model.update(() => model.updatingReminders = true);
    try {
      await model.receipt.service.ensureCompleted(model.receipt);
      await (widget.removeReminders?.call(model.receipt) ??
          NotificationService.removePlanReminders(
            {model.receipt.id},
            ensureCurrent: () =>
                model.receipt.service.ensureCompleted(model.receipt),
          ));
      if (_current(model)) model.update(() => model.reminderError = false);
    } catch (_) {
      if (_current(model)) {
        model.update(() => model.reminderError = true);
        _show(model, reminderError: true);
      }
    } finally {
      if (_current(model)) {
        model.update(() => model.updatingReminders = false);
        unawaited(_check());
      }
    }
  }

  Future<void> _undo(_Notice model) async {
    if (!_current(model) || model.busy) return;
    model.update(() => model.busy = true);
    try {
      await model.receipt.service.undo(model.receipt);
      if (!mounted || !_current(model)) return;
      _clear();
      widget.onRefresh();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已撤回手动完成')));
    } catch (error) {
      if (_current(model)) {
        model.update(() => model.error = '撤销未成功：${error.toString()}');
      }
    } finally {
      if (_current(model)) {
        model.update(() => model.busy = false);
        unawaited(_check());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(_onSignal);
    _clear(defer: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Notice extends ChangeNotifier {
  _Notice(this.receipt);
  final PlanManualCompletionReceipt receipt;
  bool busy = false, reminderError = false, updatingReminders = false;
  int bars = 0;
  String? error;
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }
}
