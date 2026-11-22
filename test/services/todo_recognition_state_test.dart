import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/services/todo_recognition_state.dart';

void main() {
  const currentSession = 'current-session';

  test('recognizes a processing record from a previous app session', () {
    final interrupted = TodoRecognitionState.isInterrupted(
      status: 'processing',
      processingSessionId: 'previous-session',
      currentSessionId: currentSession,
      timestampMs: 10,
      nowMs: 20,
    );

    expect(interrupted, isTrue);
  });

  test('recovers a legacy processing record without a session id', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final interrupted = TodoRecognitionState.isInterrupted(
      status: 'processing',
      processingSessionId: null,
      currentSessionId: currentSession,
      timestampMs: now,
      nowMs: now,
    );

    expect(interrupted, isTrue);
  });

  test('keeps a fresh current-session processing record', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final interrupted = TodoRecognitionState.isInterrupted(
      status: 'processing',
      processingSessionId: currentSession,
      currentSessionId: currentSession,
      timestampMs: now,
      nowMs: now,
    );

    expect(interrupted, isFalse);
  });

  test(
    'allows retrying a failed image instead of blocking it as a duplicate',
    () {
      expect(
        TodoRecognitionState.blocksDuplicate(
          status: 'failed',
          processingSessionId: 'previous-session',
          currentSessionId: currentSession,
        ),
        isFalse,
      );
    },
  );
}
