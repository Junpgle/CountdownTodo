import 'package:flutter/foundation.dart';

enum MinorModeSource {
  chinaSystem,
  googleAgeSignals,
  appleDeclaredAgeRange,
  manual,
  unsupported,
}

enum MinorAgeBand {
  unknown,
  under13,
  under3,
  age3to7,
  age8to11,
  age13to15,
  age12to15,
  age16to17,
  adult,
}

extension MinorModeSourceLabel on MinorModeSource {
  String get label => switch (this) {
        MinorModeSource.chinaSystem => '手机系统',
        MinorModeSource.googleAgeSignals => 'Google 年龄信号',
        MinorModeSource.appleDeclaredAgeRange => 'Apple 年龄范围',
        MinorModeSource.manual => 'App 设置',
        MinorModeSource.unsupported => '暂不支持系统联动',
      };
}

extension MinorAgeBandLabel on MinorAgeBand {
  String get label => switch (this) {
        MinorAgeBand.unknown => '未知',
        MinorAgeBand.under13 => '13 岁以下',
        MinorAgeBand.under3 => '3 岁以下',
        MinorAgeBand.age3to7 => '3～7 岁',
        MinorAgeBand.age8to11 => '8～11 岁',
        MinorAgeBand.age13to15 => '13～15 岁',
        MinorAgeBand.age12to15 => '12～15 岁',
        MinorAgeBand.age16to17 => '16～17 岁',
        MinorAgeBand.adult => '成人',
      };
}

extension MinorAgeBandSystemMapping on MinorAgeBand {
  static MinorAgeBand fromSystemAgeRange(Object? value) {
    final range = switch (value) {
      int value => value,
      String value => int.tryParse(value),
      _ => null,
    };

    return switch (range) {
      1 => MinorAgeBand.under3,
      2 => MinorAgeBand.age3to7,
      3 => MinorAgeBand.age8to11,
      4 => MinorAgeBand.age12to15,
      5 => MinorAgeBand.age16to17,
      _ => MinorAgeBand.unknown,
    };
  }
}

@immutable
class MinorModeState {
  final bool systemSupported;
  final bool systemEnabled;
  final bool manualEnabled;
  final MinorModeSource source;
  final MinorAgeBand ageBand;
  final bool parentAuthenticationSupported;
  final bool systemStateReadFailed;
  final String? lastError;

  const MinorModeState({
    required this.systemSupported,
    required this.systemEnabled,
    required this.manualEnabled,
    required this.source,
    required this.ageBand,
    required this.parentAuthenticationSupported,
    this.systemStateReadFailed = false,
    this.lastError,
  });

  const MinorModeState.unsupported({
    this.manualEnabled = false,
    this.parentAuthenticationSupported = false,
    this.systemStateReadFailed = false,
    this.lastError,
  })  : systemSupported = false,
        systemEnabled = false,
        source = manualEnabled
            ? MinorModeSource.manual
            : MinorModeSource.unsupported,
        ageBand = MinorAgeBand.unknown;

  bool get effectiveMinorMode => systemEnabled || manualEnabled;

  factory MinorModeState.fromPlatformMap(
    Map<Object?, Object?> map, {
    required bool manualEnabled,
  }) {
    final systemSupported = _asBool(map['systemSupported']);
    final systemEnabled = _asBool(map['systemEnabled']);
    final ageBand = _parseAgeBand(map['ageBand'] ?? map['ageRange']);
    final nativeSource = _parseSource(map['source']);

    return MinorModeState(
      systemSupported: systemSupported,
      systemEnabled: systemEnabled,
      manualEnabled: manualEnabled,
      source: _resolveSource(
        systemSupported: systemSupported,
        systemEnabled: systemEnabled,
        manualEnabled: manualEnabled,
        nativeSource: nativeSource,
      ),
      ageBand: ageBand,
      parentAuthenticationSupported:
          _asBool(map['parentAuthenticationSupported']),
      systemStateReadFailed: _asBool(map['systemStateReadFailed']),
      lastError: map['lastError']?.toString(),
    );
  }

  MinorModeState copyWith({
    bool? systemSupported,
    bool? systemEnabled,
    bool? manualEnabled,
    MinorModeSource? source,
    MinorAgeBand? ageBand,
    bool? parentAuthenticationSupported,
    bool? systemStateReadFailed,
    String? lastError,
  }) {
    return MinorModeState(
      systemSupported: systemSupported ?? this.systemSupported,
      systemEnabled: systemEnabled ?? this.systemEnabled,
      manualEnabled: manualEnabled ?? this.manualEnabled,
      source: source ?? this.source,
      ageBand: ageBand ?? this.ageBand,
      parentAuthenticationSupported:
          parentAuthenticationSupported ?? this.parentAuthenticationSupported,
      systemStateReadFailed:
          systemStateReadFailed ?? this.systemStateReadFailed,
      lastError: lastError,
    );
  }

  Map<String, Object?> toMap() => {
        'systemSupported': systemSupported,
        'systemEnabled': systemEnabled,
        'manualEnabled': manualEnabled,
        'source': source.name,
        'ageBand': ageBand.name,
        'parentAuthenticationSupported': parentAuthenticationSupported,
        'systemStateReadFailed': systemStateReadFailed,
      };

  @override
  bool operator ==(Object other) {
    return other is MinorModeState &&
        other.systemSupported == systemSupported &&
        other.systemEnabled == systemEnabled &&
        other.manualEnabled == manualEnabled &&
        other.source == source &&
        other.ageBand == ageBand &&
        other.parentAuthenticationSupported == parentAuthenticationSupported &&
        other.systemStateReadFailed == systemStateReadFailed &&
        other.lastError == lastError;
  }

  @override
  int get hashCode => Object.hash(
        systemSupported,
        systemEnabled,
        manualEnabled,
        source,
        ageBand,
        parentAuthenticationSupported,
        systemStateReadFailed,
        lastError,
      );

  static MinorAgeBand _parseAgeBand(Object? value) {
    if (value is String) {
      for (final band in MinorAgeBand.values) {
        if (band.name == value) return band;
      }
    }
    return MinorAgeBandSystemMapping.fromSystemAgeRange(value);
  }

  static MinorModeSource _parseSource(Object? value) {
    if (value is String) {
      final normalizedValue = value.replaceAll('_', '').toLowerCase();
      for (final source in MinorModeSource.values) {
        if (source.name == value ||
            source.name.toLowerCase() == normalizedValue) {
          return source;
        }
      }
    }
    return MinorModeSource.unsupported;
  }

  static MinorModeSource _resolveSource({
    required bool systemSupported,
    required bool systemEnabled,
    required bool manualEnabled,
    required MinorModeSource nativeSource,
  }) {
    if (systemEnabled) {
      return nativeSource == MinorModeSource.unsupported
          ? MinorModeSource.chinaSystem
          : nativeSource;
    }
    if (manualEnabled) return MinorModeSource.manual;
    return systemSupported ? nativeSource : MinorModeSource.unsupported;
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return value == '1' || value.toLowerCase() == 'true';
    }
    return false;
  }
}
