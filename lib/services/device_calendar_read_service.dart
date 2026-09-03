import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_platform.dart';

/// A system-calendar event used only for presentation.
///
/// These records are deliberately never written to the app database. They do
/// not have a sync version, an oplog entry, or a server representation.
class DeviceCalendarEvent {
  const DeviceCalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.colorValue,
  });

  final String id;
  final String calendarId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final int? colorValue;

  bool overlaps(DateTime rangeStart, DateTime rangeEnd) {
    // Some calendar providers represent an instant reminder with identical
    // start/end timestamps. The platform bridge keeps that record and the
    // presentation layer gives it a one-minute hit area, so it remains
    // discoverable in every calendar view.
    final effectiveEnd = end.isAfter(start)
        ? end
        : start.add(const Duration(minutes: 1));
    return effectiveEnd.isAfter(rangeStart) && start.isBefore(rangeEnd);
  }

  factory DeviceCalendarEvent.fromPlatformMap(Map<dynamic, dynamic> raw) {
    final startMs = (raw['startMs'] as num?)?.toInt() ?? 0;
    final endMs = (raw['endMs'] as num?)?.toInt() ?? startMs;
    final start = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
    final rawEnd = DateTime.fromMillisecondsSinceEpoch(endMs).toLocal();
    return DeviceCalendarEvent(
      id: raw['id']?.toString() ?? '',
      calendarId: raw['calendarId']?.toString() ?? '',
      title: raw['title']?.toString().trim().isNotEmpty == true
          ? raw['title'].toString().trim()
          : '未命名日程',
      start: start,
      end: rawEnd.isAfter(start)
          ? rawEnd
          : start.add(const Duration(minutes: 1)),
      allDay: raw['allDay'] == true,
      location: raw['location']?.toString().trim().isNotEmpty == true
          ? raw['location'].toString().trim()
          : null,
      colorValue: _usableColorValue(raw['color']),
    );
  }
}

class DeviceCalendarSource {
  const DeviceCalendarSource({
    required this.id,
    required this.name,
    this.account,
    this.colorValue,
  });

  final String id;
  final String name;
  final String? account;
  final int? colorValue;

  factory DeviceCalendarSource.fromPlatformMap(Map<dynamic, dynamic> raw) =>
      DeviceCalendarSource(
        id: raw['id']?.toString() ?? '',
        name: raw['name']?.toString().trim().isNotEmpty == true
            ? raw['name'].toString().trim()
            : '日历',
        account: raw['account']?.toString().trim().isNotEmpty == true
            ? raw['account'].toString().trim()
            : null,
        colorValue: _usableColorValue(raw['color']),
      );
}

int? _usableColorValue(Object? raw) {
  final value = (raw as num?)?.toInt();
  return value == null || value == 0 ? null : value;
}

/// Read-only device-calendar bridge.
///
/// The native side exposes only permission checks, calendar discovery and
/// event queries. There are intentionally no create/update/delete methods.
class DeviceCalendarReadService {
  DeviceCalendarReadService._();

  static const MethodChannel _channel =
      MethodChannel('countdown_todo/device_calendar_read');
  static const String _enabledKey = 'device_calendar_read_enabled';
  static const String _guideOfferedKey = 'device_calendar_read_guide_offered';

  // Calendar provider queries are relatively expensive on some Android
  // devices. Keep each foreground range in process memory only: returning to
  // the homepage or rebuilding a card must not query the provider again.
  static final List<_DeviceCalendarReadRange> _sessionReadRanges = [];
  static final Map<String, Future<List<DeviceCalendarEvent>>> _inFlightReads =
      {};

  @visibleForTesting
  static bool? debugIsSupportedOverride;

  /// Lets foreground presentation widgets reload after the local toggle is
  /// changed. It is not a data-sync signal and has no persistence payload.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool get isSupported =>
      debugIsSupportedOverride ?? (AppPlatform.isAndroid || AppPlatform.isIOS);

  /// Returns the first visible day of the month grid containing [value].
  /// Keeping this range shared by the homepage and course views means the
  /// provider is queried once for the foreground calendar window.
  static DateTime monthGridStart(DateTime value) {
    final firstDay = DateTime(value.year, value.month, 1);
    return firstDay.subtract(Duration(days: firstDay.weekday - 1));
  }

  /// Returns the exclusive end of the complete month grid containing [value].
  static DateTime monthGridEnd(DateTime value) {
    final nextMonth = DateTime(value.year, value.month + 1, 1);
    final trailingDays = (8 - nextMonth.weekday) % 7;
    return nextMonth.add(Duration(days: trailingDays));
  }

  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    _clearSessionReadCache();
    revision.value++;
  }

  @visibleForTesting
  static void clearSessionReadCacheForTesting() => _clearSessionReadCache();

  static void _clearSessionReadCache() {
    _sessionReadRanges.clear();
    _inFlightReads.clear();
  }

  /// The optional calendar toggle is offered once in the version guide.
  ///
  /// This is deliberately independent of [isEnabled]: declining the feature
  /// should not make the guide appear again on subsequent launches.
  static Future<bool> isGuideOfferDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_guideOfferedKey) ?? false;
  }

  static Future<void> markGuideOffered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guideOfferedKey, true);
  }

  static Future<bool> checkPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('checkPermission') ?? false;
  }

  /// Requests the platform's calendar read access. On Android this maps to
  /// READ_CALENDAR only; no WRITE_CALENDAR request is made by this feature.
  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  static Future<List<DeviceCalendarSource>> getSources() async {
    if (!isSupported || !await checkPermission()) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>('getSources') ??
        const <dynamic>[];
    return raw
        .whereType<Map>()
        .map(DeviceCalendarSource.fromPlatformMap)
        .where((source) => source.id.isNotEmpty)
        .toList();
  }

  /// Reads the requested range directly from the platform provider. The
  /// returned values remain in memory only and are never cached in SQLite.
  static Future<List<DeviceCalendarEvent>> readEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start) || !await isEnabled() || !await checkPermission()) {
      return const [];
    }
    final cached =
        _sessionReadRanges.where((range) => range.covers(start, end));
    if (cached.isNotEmpty) return cached.first.eventsFor(start, end);

    final rangeKey =
        '${start.millisecondsSinceEpoch}:${end.millisecondsSinceEpoch}';
    final pending = _inFlightReads.putIfAbsent(
      rangeKey,
      () => _readAndCacheRange(start: start, end: end),
    );
    try {
      final events = await pending;
      return events.where((event) => event.overlaps(start, end)).toList();
    } finally {
      _inFlightReads.remove(rangeKey);
    }
  }

  static Future<List<DeviceCalendarEvent>> _readAndCacheRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
          'readEvents',
          {
            'startMs': start.millisecondsSinceEpoch,
            'endMs': end.millisecondsSinceEpoch,
          },
        ) ??
        const <dynamic>[];
    final events = raw
        .whereType<Map>()
        .map(DeviceCalendarEvent.fromPlatformMap)
        .where((event) => event.id.isNotEmpty && event.overlaps(start, end))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    _sessionReadRanges.add(
      _DeviceCalendarReadRange(start: start, end: end, events: events),
    );
    return events;
  }
}

class _DeviceCalendarReadRange {
  const _DeviceCalendarReadRange({
    required this.start,
    required this.end,
    required this.events,
  });

  final DateTime start;
  final DateTime end;
  final List<DeviceCalendarEvent> events;

  bool covers(DateTime requestedStart, DateTime requestedEnd) =>
      !requestedStart.isBefore(start) && !requestedEnd.isAfter(end);

  List<DeviceCalendarEvent> eventsFor(
          DateTime requestedStart, DateTime requestedEnd) =>
      events
          .where((event) => event.overlaps(requestedStart, requestedEnd))
          .toList();
}
