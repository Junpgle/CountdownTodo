import '../models/plan_availability.dart';
import 'plan_availability_service.dart';

typedef PlanContinuousRangeLoader = Future<PlanContinuousRangeResult> Function(
  PlanAvailabilityQuery query, {
  bool forceRefresh,
});

abstract final class PlanContinuousRangeService {
  static PlanContinuousRangeResult find(
    List<PlanAvailabilityQuery> queries,
    List<PlanAvailabilitySnapshot> snapshots, {
    required DateTime now,
    required DateTime start,
    required DateTime end,
    required String coverage,
    PlanAvailabilitySnapshot? currentSnapshot,
  }) {
    if (queries.length != snapshots.length || queries.length > 7) {
      throw const PlanAvailabilityException('范围数据不完整，请重新查找');
    }
    final days = <List<PlanAvailabilitySelection>>[];
    for (var i = 0; i < queries.length; i++) {
      final q = queries[i], snapshot = snapshots[i];
      final invalid = PlanAvailabilityService.invalidReason(
        q,
        snapshot.todo,
        now,
      );
      if (invalid != null) throw PlanAvailabilityException(invalid);
      final result = PlanAvailabilityService.find(q, snapshot, now: now);
      days.add([
        for (final slot in result.slots)
          PlanAvailabilitySelection(q, slot, snapshot),
      ]);
    }
    final choices = [
      for (final day in days)
        if (day.isNotEmpty) day.first,
    ].take(5).toList();
    if (choices.length < 5) {
      final more = [for (final day in days) ...day.skip(1)]
        ..sort((a, b) => a.slot.start.compareTo(b.slot.start));
      choices.addAll(more.take(5 - choices.length));
    }
    choices.sort((a, b) => a.slot.start.compareTo(b.slot.start));
    return PlanContinuousRangeResult(start, end, coverage, choices, [
      for (final snapshot in snapshots) ...snapshot.unknownTimes,
    ], currentSnapshot: currentSnapshot);
  }
}
