import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

enum IslandState { idle, hoverWide, splitAlert, stackedCard, finishConfirm, abandonConfirm }

class IslandUI extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final void Function(String action, [int? modifiedSecs])? onAction;
  // A notifier the island entrypoint can update to push payloads into this UI.
  final ValueNotifier<Map<String, dynamic>?>? payloadNotifier;
  const IslandUI({super.key, this.initialPayload, this.onAction, this.payloadNotifier});

  @override
  State<IslandUI> createState() => _IslandUIState();
}

class _IslandUIState extends State<IslandUI> {
  IslandState _state = IslandState.idle;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _applyPayload(widget.initialPayload);
    if (widget.payloadNotifier != null) {
      widget.payloadNotifier!.addListener(_onNotifierPayload);
    }
  }

  void _onNotifierPayload() {
    _applyPayload(widget.payloadNotifier!.value);
  }

  void _applyPayload(Map<String, dynamic>? payload) {
    if (payload == null) return;
    setState(() {
      final endMs = payload['endMs'] ?? 0;
      _title = payload['title'] ?? '';
      _state = (endMs != 0) ? IslandState.hoverWide : IslandState.idle;
    });
  }

  @override
  void dispose() {
    if (widget.payloadNotifier != null) {
      try { widget.payloadNotifier!.removeListener(_onNotifierPayload); } catch (_) {}
    }
    super.dispose();
  }

  Widget _buildBody() {
    switch (_state) {
      case IslandState.idle:
        return _buildPill('Idle', Colors.grey[200]!);
      case IslandState.hoverWide:
        return _buildPill('Focus: $_title', Colors.blue[300]!);
      case IslandState.splitAlert:
        return _buildPill('Split Alert', Colors.orange[300]!);
      case IslandState.stackedCard:
        return _buildCard('Detail Card');
      case IslandState.finishConfirm:
        return _buildConfirm('Finish?', Colors.green, 'finish');
      case IslandState.abandonConfirm:
        return _buildConfirm('Abandon?', Colors.red, 'abandon');
    }
  }

  Widget _buildPill(String text, Color color) {
    return GestureDetector(
      onPanStart: (_) async {
        // Use WindowController to request a drag from the native window for
        // this island window. Different implementations of the host native
        // code may expose different method names; try a few common ones and
        // ignore errors so this remains a best-effort action in child engines.
        try {
          final controller = await WindowController.fromCurrentEngine();
          await controller.invokeMethod('window_start_drag').catchError((_) async {
            await controller.invokeMethod('startDragging').catchError((_) async {
              await controller.invokeMethod('window_startDragging').catchError((_) {});
            });
          });
        } catch (_) {
          // If controller isn't available (fallback/debug), do nothing.
        }
      },
      onTap: () {
        setState(() {
          _state = IslandState.splitAlert;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)],
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildCard(String text) {
    return Container(
      width: 320,
      height: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Detail line 1'),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => setState(() => _state = IslandState.idle), child: const Text('Close')),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildConfirm(String text, Color color, String action) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: Colors.white)),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              widget.onAction?.call(action);
            },
            child: const Text('OK'),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(() => _state = IslandState.idle),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildBody(),
        ),
      ),
    );
  }
}

