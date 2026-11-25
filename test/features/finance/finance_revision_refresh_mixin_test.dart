import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/widgets/finance_revision_refresh_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RevisionHost extends StatefulWidget {
  const _RevisionHost({
    required this.onRefresh,
    this.debounce = const Duration(milliseconds: 100),
  });

  final VoidCallback onRefresh;
  final Duration debounce;

  @override
  State<_RevisionHost> createState() => _RevisionHostState();
}

class _RevisionHostState extends State<_RevisionHost>
    with FinanceRevisionRefreshMixin<_RevisionHost> {
  @override
  Duration get financeRevisionDebounce => widget.debounce;

  @override
  void initState() {
    super.initState();
    startListeningToFinanceRevision();
    // Idempotent duplicate registration must not attach twice.
    startListeningToFinanceRevision();
  }

  @override
  void onFinanceRevisionRefresh() => widget.onRefresh();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets(
    'FinanceRevisionRefreshMixin coalesces bursts and cancels timer on dispose',
    (tester) async {
      var refreshCount = 0;
      await tester.pumpWidget(
        MaterialApp(home: _RevisionHost(onRefresh: () => refreshCount++)),
      );

      FinanceStorage.revision.value++;
      FinanceStorage.revision.value++;
      FinanceStorage.revision.value++;
      await tester.pump(const Duration(milliseconds: 50));
      expect(refreshCount, 0);

      await tester.pump(const Duration(milliseconds: 60));
      expect(refreshCount, 1);

      // Burst right before unmount must cancel pending timer and remove listener.
      FinanceStorage.revision.value++;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      expect(refreshCount, 1);

      FinanceStorage.revision.value++;
      await tester.pump(const Duration(milliseconds: 200));
      expect(refreshCount, 1);
    },
  );

  testWidgets(
    'FinanceRevisionRefreshMixin supports immediate Duration.zero mode',
    (tester) async {
      var refreshCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: _RevisionHost(
            debounce: Duration.zero,
            onRefresh: () => refreshCount++,
          ),
        ),
      );

      FinanceStorage.revision.value++;
      FinanceStorage.revision.value++;
      expect(refreshCount, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      FinanceStorage.revision.value++;
      expect(refreshCount, 2);
    },
  );
}
