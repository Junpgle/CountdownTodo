/// Pure state rules shared by the image-recognition lifecycle and its tests.
class TodoRecognitionState {
  static const Duration staleAge = Duration(minutes: 2);

  static bool isInterrupted({
    required String? status,
    required String? processingSessionId,
    required String currentSessionId,
    required int? timestampMs,
    required int nowMs,
  }) {
    final normalizedStatus = status?.trim().toLowerCase();
    if (normalizedStatus != 'processing' && normalizedStatus != 'retrying') {
      return false;
    }

    final ageMs = timestampMs == null ? null : nowMs - timestampMs;
    final hasSessionId = processingSessionId?.trim().isNotEmpty == true;
    return !hasSessionId ||
        (hasSessionId && processingSessionId != currentSessionId) ||
        timestampMs == null ||
        (ageMs != null && ageMs >= staleAge.inMilliseconds);
  }

  static bool blocksDuplicate({
    required String? status,
    required String? processingSessionId,
    required String currentSessionId,
  }) {
    final normalizedStatus = status?.trim().toLowerCase();
    if (normalizedStatus == 'failed') return false;
    if (normalizedStatus == 'processing' || normalizedStatus == 'retrying') {
      // 没有 session 的旧记录先继续挡住并发分享，直到启动时按时间判断为
      // 中断；这样不会因为旧版数据缺字段而重新触发重复识别。
      final hasSessionId = processingSessionId?.trim().isNotEmpty == true;
      if (hasSessionId && processingSessionId != currentSessionId) {
        return false;
      }
    }
    return true;
  }
}
