import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Small in-memory LRU for data snapshots used by disposable homepage sections.
///
/// The cache holds only loaded models/futures, never widgets or render objects,
/// so evicting an off-screen section can release its image and GPU resources.
/// Only the newest snapshot per section family is retained; refresh revisions
/// must not keep older copies alive for the rest of the session.
abstract final class HomeDashboardSectionDataCache {
  static const int _capacity = 8;
  static final LinkedHashMap<String, Object> _values = LinkedHashMap();
  static final Map<String, Future<Object>> _pending = {};

  static String _familyOf(String key) => key.split('/').first;

  static void _evictOtherVersions(String key) {
    final family = _familyOf(key);
    for (final staleKey
        in _values.keys
            .where(
              (candidate) => candidate != key && _familyOf(candidate) == family,
            )
            .toList(growable: false)) {
      _values.remove(staleKey);
    }
    for (final staleKey
        in _pending.keys
            .where(
              (candidate) => candidate != key && _familyOf(candidate) == family,
            )
            .toList(growable: false)) {
      _pending.remove(staleKey);
    }
  }

  static T? get<T extends Object>(String key) {
    final value = _values.remove(key);
    if (value == null) return null;
    _values[key] = value;
    return value is T ? value : null;
  }

  static void put<T extends Object>(String key, T value) {
    _evictOtherVersions(key);
    _pending.remove(key);
    _values.remove(key);
    _values[key] = value;
    while (_values.length > _capacity) {
      _values.remove(_values.keys.first);
    }
  }

  static Future<T> load<T extends Object>(
    String key,
    Future<T> Function() loader,
  ) {
    final cached = get<T>(key);
    if (cached != null) return Future<T>.value(cached);

    final pending = _pending[key];
    if (pending != null) return pending.then((value) => value as T);

    _evictOtherVersions(key);
    final future = Future<T>.sync(loader);
    _pending[key] = future;
    future.then<void>(
      (value) {
        if (!identical(_pending[key], future)) return;
        _pending.remove(key);
        put(key, value);
      },
      onError: (Object _, StackTrace _) {
        if (identical(_pending[key], future)) _pending.remove(key);
      },
    );
    return future;
  }

  @visibleForTesting
  static void clearForTesting() {
    _values.clear();
    _pending.clear();
  }
}
