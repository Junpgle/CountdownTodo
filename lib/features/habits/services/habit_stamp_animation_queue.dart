/// Coordinates one-shot stamp animations across duplicated habit cards.
///
/// The mobile dashboard keeps its home and focus lists mounted at once. A
/// habit can therefore receive the same completion in two separate widgets;
/// whichever copy becomes visible first claims and plays the animation.
abstract final class HabitStampAnimationQueue {
  static const Duration _retention = Duration(days: 7);
  static const int _maxRequests = 128;

  static final Map<String, _StampRequest> _requests = {};
  static int _nextToken = 0;

  static void request({
    required String habitUuid,
    required DateTime logicalDate,
  }) {
    _prune();
    final key = _key(habitUuid, logicalDate);
    // Pending, claimed, and completed requests all represent the same logical
    // completion. Repeated refreshes must not schedule duplicate stamps.
    _requests.putIfAbsent(
      key,
      () => _StampRequest(token: ++_nextToken, updatedAt: DateTime.now()),
    );
    _enforceCapacity();
  }

  static bool hasPending({
    required String habitUuid,
    required DateTime logicalDate,
  }) {
    _prune();
    return _requests[_key(habitUuid, logicalDate)]?.state ==
        _StampRequestState.pending;
  }

  static int? claim({
    required String habitUuid,
    required DateTime logicalDate,
  }) {
    _prune();
    final request = _requests[_key(habitUuid, logicalDate)];
    if (request == null || request.state != _StampRequestState.pending) {
      return null;
    }
    request
      ..state = _StampRequestState.claimed
      ..updatedAt = DateTime.now();
    return request.token;
  }

  static bool complete({
    required String habitUuid,
    required DateTime logicalDate,
    required int token,
  }) {
    _prune();
    final request = _requests[_key(habitUuid, logicalDate)];
    if (request == null ||
        request.token != token ||
        request.state != _StampRequestState.claimed) {
      return false;
    }
    request
      ..state = _StampRequestState.completed
      ..updatedAt = DateTime.now();
    return true;
  }

  static void release({
    required String habitUuid,
    required DateTime logicalDate,
    required int token,
  }) {
    _prune();
    final request = _requests[_key(habitUuid, logicalDate)];
    if (request == null ||
        request.token != token ||
        request.state != _StampRequestState.claimed) {
      return;
    }
    request
      ..state = _StampRequestState.pending
      ..updatedAt = DateTime.now();
  }

  static void cancel({
    required String habitUuid,
    required DateTime logicalDate,
  }) {
    _requests.remove(_key(habitUuid, logicalDate));
  }

  static void clearForTesting() {
    _requests.clear();
  }

  static String _key(String habitUuid, DateTime logicalDate) =>
      '$habitUuid|${logicalDate.year.toString().padLeft(4, '0')}-'
      '${logicalDate.month.toString().padLeft(2, '0')}-'
      '${logicalDate.day.toString().padLeft(2, '0')}';

  static void _prune() {
    final cutoff = DateTime.now().subtract(_retention);
    _requests.removeWhere((_, request) => request.updatedAt.isBefore(cutoff));
  }

  static void _enforceCapacity() {
    while (_requests.length > _maxRequests) {
      _requests.remove(_requests.keys.first);
    }
  }
}

enum _StampRequestState { pending, claimed, completed }

class _StampRequest {
  final int token;
  _StampRequestState state = _StampRequestState.pending;
  DateTime updatedAt;

  _StampRequest({required this.token, required this.updatedAt});
}
