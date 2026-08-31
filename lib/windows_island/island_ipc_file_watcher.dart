import 'dart:async';
import 'dart:io';

typedef IslandDirectoryWatch = Stream<FileSystemEvent> Function(
  Directory directory,
);

/// Watches one IPC file without continuously polling the filesystem.
///
/// Directory notifications provide the normal low-power path. A slow periodic
/// check protects against dropped notifications, while the original faster
/// polling cadence is used only when directory watching is unavailable.
class IslandIpcFileWatcher {
  IslandIpcFileWatcher({
    required this.resolveFile,
    required this.onFileChanged,
    required this.fallbackInterval,
    required this.degradedPollInterval,
    this.eventDebounce = const Duration(milliseconds: 40),
    IslandDirectoryWatch? watchDirectory,
  }) : _watchDirectory = watchDirectory;

  final Future<File> Function() resolveFile;
  final Future<void> Function() onFileChanged;
  final Duration fallbackInterval;
  final Duration degradedPollInterval;
  final Duration eventDebounce;
  final IslandDirectoryWatch? _watchDirectory;

  StreamSubscription<FileSystemEvent>? _directorySubscription;
  Timer? _eventDebounceTimer;
  Timer? _fallbackTimer;
  String? _targetPath;
  bool _running = false;
  bool _callbackInFlight = false;
  bool _callbackPending = false;
  bool _usingDegradedPolling = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    final target = await resolveFile();
    if (!_running) return;
    await target.parent.create(recursive: true);
    if (!_running) return;

    _targetPath = _normalizePath(target.absolute.path);
    _startFallbackTimer(fallbackInterval);

    try {
      final events = _watchDirectory?.call(target.parent) ??
          target.parent.watch(
            events: FileSystemEvent.create |
                FileSystemEvent.modify |
                FileSystemEvent.move,
          );
      _directorySubscription = events.listen(
        _onDirectoryEvent,
        onError: (Object _, StackTrace __) => _enterDegradedPolling(),
        onDone: _enterDegradedPolling,
        cancelOnError: true,
      );
    } catch (_) {
      _enterDegradedPolling();
    }

    await _runCallback();
  }

  void dispose() {
    if (!_running) return;
    _running = false;
    _eventDebounceTimer?.cancel();
    _eventDebounceTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    final subscription = _directorySubscription;
    _directorySubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  void _onDirectoryEvent(FileSystemEvent event) {
    if (!_running || !_matchesTarget(event)) return;
    _eventDebounceTimer?.cancel();
    _eventDebounceTimer = Timer(
      eventDebounce,
      () => unawaited(_runCallback()),
    );
  }

  bool _matchesTarget(FileSystemEvent event) {
    final targetPath = _targetPath;
    if (targetPath == null) return false;
    if (_normalizePath(File(event.path).absolute.path) == targetPath) {
      return true;
    }
    if (event is FileSystemMoveEvent && event.destination != null) {
      return _normalizePath(File(event.destination!).absolute.path) ==
          targetPath;
    }
    return false;
  }

  String _normalizePath(String path) {
    return Platform.isWindows ? path.toLowerCase() : path;
  }

  void _enterDegradedPolling() {
    if (!_running || _usingDegradedPolling) return;
    _usingDegradedPolling = true;
    _startFallbackTimer(degradedPollInterval);
  }

  void _startFallbackTimer(Duration interval) {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(
      interval,
      (_) => unawaited(_runCallback()),
    );
  }

  Future<void> _runCallback() async {
    if (!_running) return;
    if (_callbackInFlight) {
      _callbackPending = true;
      return;
    }

    _callbackInFlight = true;
    try {
      do {
        _callbackPending = false;
        await onFileChanged();
      } while (_running && _callbackPending);
    } finally {
      _callbackInFlight = false;
    }
  }
}
