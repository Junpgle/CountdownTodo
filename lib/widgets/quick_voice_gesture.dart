import 'package:flutter/material.dart';

enum QuickVoiceTarget { send, cancel, openAi }

/// Created at press-start so release cannot be lost during async key loading.
class QuickVoiceGestureController extends ChangeNotifier {
  QuickVoiceGestureController(this.origin);

  final Offset origin;
  QuickVoiceTarget target = QuickVoiceTarget.send;
  bool isReleased = false;

  void move(Offset position) {
    if (isReleased) return;
    final delta = position - origin;
    final next = delta.dy <= -72 && delta.dx.abs() >= 36
        ? (delta.dx < 0 ? QuickVoiceTarget.openAi : QuickVoiceTarget.cancel)
        : QuickVoiceTarget.send;
    if (next == target) return;
    target = next;
    notifyListeners();
  }

  void release({bool cancel = false}) {
    if (isReleased && !cancel) return;
    if (cancel) target = QuickVoiceTarget.cancel;
    isReleased = true;
    notifyListeners();
  }
}
