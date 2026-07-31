import 'package:countdown_todo/services/sync_capability_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncCapabilityService', () {
    test('accepts the fixed schedule v1 capability', () {
      expect(
        SyncCapabilityService.supportsFixedSchedules(
          {'fixed_schedules': 1},
        ),
        isTrue,
      );
    });

    test('rejects old or missing server capabilities', () {
      expect(SyncCapabilityService.supportsFixedSchedules(null), isFalse);
      expect(
        SyncCapabilityService.supportsFixedSchedules(const {}),
        isFalse,
      );
      expect(
        SyncCapabilityService.supportsFixedSchedules(
          {'fixed_schedules': 0},
        ),
        isFalse,
      );
    });

    test('keeps compatibility with a capability name list', () {
      expect(
        SyncCapabilityService.supportsFixedSchedules(
          const ['fixed_schedules'],
        ),
        isTrue,
      );
    });

    test('acknowledges fixed-schedule oplogs only after an explicit handshake',
        () {
      expect(
        SyncCapabilityService.shouldAcknowledgeFixedScheduleOps(
          syncEnabled: true,
          rawCapabilities: null,
        ),
        isFalse,
      );
      expect(
        SyncCapabilityService.shouldAcknowledgeFixedScheduleOps(
          syncEnabled: false,
          rawCapabilities: const {'fixed_schedules': 1},
        ),
        isFalse,
      );
      expect(
        SyncCapabilityService.shouldAcknowledgeFixedScheduleOps(
          syncEnabled: true,
          rawCapabilities: const {'fixed_schedules': 1},
        ),
        isTrue,
      );
    });
  });
}
