import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/finance_storage.dart';

/// Shared `FinanceStorage.revision` listener with optional debouncing and
/// automatic cleanup on `dispose`.
mixin FinanceRevisionRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _financeRevisionRefreshTimer;
  bool _financeRevisionListening = false;

  /// Override to `Duration.zero` for immediate reload without debouncing.
  Duration get financeRevisionDebounce => const Duration(milliseconds: 100);

  void onFinanceRevisionRefresh();

  void startListeningToFinanceRevision() {
    if (_financeRevisionListening) return;
    FinanceStorage.revision.addListener(_handleFinanceRevisionChange);
    _financeRevisionListening = true;
  }

  void stopListeningToFinanceRevision() {
    _financeRevisionRefreshTimer?.cancel();
    _financeRevisionRefreshTimer = null;
    if (_financeRevisionListening) {
      FinanceStorage.revision.removeListener(_handleFinanceRevisionChange);
      _financeRevisionListening = false;
    }
  }

  void _handleFinanceRevisionChange() {
    final delay = financeRevisionDebounce;
    if (delay <= Duration.zero) {
      if (mounted) onFinanceRevisionRefresh();
      return;
    }
    _financeRevisionRefreshTimer?.cancel();
    _financeRevisionRefreshTimer = Timer(delay, () {
      _financeRevisionRefreshTimer = null;
      if (mounted) onFinanceRevisionRefresh();
    });
  }

  @override
  void dispose() {
    stopListeningToFinanceRevision();
    super.dispose();
  }
}
