import 'minor_mode_state.dart';

enum MinorAgeSignalStatus {
  notRequested,
  shared,
  notShared,
  verificationRequired,
  unavailable,
  error,
}

extension MinorAgeSignalStatusLabel on MinorAgeSignalStatus {
  String get label => switch (this) {
        MinorAgeSignalStatus.notRequested => '尚未请求',
        MinorAgeSignalStatus.shared => '已获得用户或家长授权',
        MinorAgeSignalStatus.notShared => '用户或家长未分享',
        MinorAgeSignalStatus.verificationRequired => '需要在 Google Play 完成年龄验证',
        MinorAgeSignalStatus.unavailable => '当前设备或安装来源不可用',
        MinorAgeSignalStatus.error => '暂时无法获取',
      };
}

class MinorAgeSignalState {
  final bool available;
  final MinorAgeSignalStatus status;
  final int? ageLower;
  final int? ageUpper;
  final MinorAgeBand ageBand;
  final String? ageRangeSource;
  final String? significantChangeStatus;
  final int? significantChangeApprovalDateMillis;
  final String? lastError;

  const MinorAgeSignalState({
    required this.available,
    required this.status,
    this.ageLower,
    this.ageUpper,
    this.ageBand = MinorAgeBand.unknown,
    this.ageRangeSource,
    this.significantChangeStatus,
    this.significantChangeApprovalDateMillis,
    this.lastError,
  });

  const MinorAgeSignalState.unavailable()
      : available = false,
        status = MinorAgeSignalStatus.unavailable,
        ageLower = null,
        ageUpper = null,
        ageBand = MinorAgeBand.unknown,
        ageRangeSource = null,
        significantChangeStatus = null,
        significantChangeApprovalDateMillis = null,
        lastError = null;

  factory MinorAgeSignalState.fromPlatformMap(Map<Object?, Object?> map) {
    return MinorAgeSignalState(
      available: _asBool(map['available']),
      status: _parseStatus(map['status']),
      ageLower: _asInt(map['ageLower']),
      ageUpper: _asInt(map['ageUpper']),
      ageBand: _parseAgeBand(map['ageBand']),
      ageRangeSource: map['ageRangeSource']?.toString(),
      significantChangeStatus: map['significantChangeStatus']?.toString(),
      significantChangeApprovalDateMillis:
          _asInt(map['significantChangeApprovalDateMillis']),
      lastError: map['lastError']?.toString(),
    );
  }

  bool get isMinor {
    if (status != MinorAgeSignalStatus.shared) return false;
    return switch (ageBand) {
      MinorAgeBand.under13 ||
      MinorAgeBand.under3 ||
      MinorAgeBand.age3to7 ||
      MinorAgeBand.age8to11 ||
      MinorAgeBand.age13to15 ||
      MinorAgeBand.age12to15 ||
      MinorAgeBand.age16to17 =>
        true,
      MinorAgeBand.unknown || MinorAgeBand.adult => false,
    };
  }

  String get ageRangeLabel {
    if (ageLower == null) return ageBand.label;
    if (ageUpper == null) return '$ageLower 岁以上';
    return '$ageLower～$ageUpper 岁';
  }

  static MinorAgeSignalStatus _parseStatus(Object? value) {
    return switch (value) {
      'shared' => MinorAgeSignalStatus.shared,
      'notShared' => MinorAgeSignalStatus.notShared,
      'verificationRequired' => MinorAgeSignalStatus.verificationRequired,
      'error' => MinorAgeSignalStatus.error,
      'unavailable' => MinorAgeSignalStatus.unavailable,
      _ => MinorAgeSignalStatus.notRequested,
    };
  }

  static MinorAgeBand _parseAgeBand(Object? value) {
    if (value is String) {
      for (final band in MinorAgeBand.values) {
        if (band.name == value) return band;
      }
    }
    return MinorAgeBand.unknown;
  }

  static bool _asBool(Object? value) => value is bool && value;

  static int? _asInt(Object? value) {
    return switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };
  }
}
