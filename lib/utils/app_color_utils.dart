import 'package:flutter/material.dart';

class AppColorUtils {
  const AppColorUtils._();

  static Color? tryParseHex(String? hex, {double opacity = 1}) {
    if (hex == null) return null;
    var value = hex.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 3) {
      value = value.split('').map((char) => '$char$char').join();
    }
    if (value.length == 6) {
      value = 'FF$value';
    }
    if (value.length != 8) return null;

    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;
    return Color(parsed).withValues(alpha: opacity.clamp(0.0, 1.0));
  }

  static Color hexToColor(
    String? hex, {
    required Color fallback,
    double opacity = 1,
  }) {
    return tryParseHex(hex, opacity: opacity) ??
        fallback.withValues(alpha: opacity.clamp(0.0, 1.0));
  }

  static Color parseHex(
    String? hex, {
    double opacity = 1,
  }) {
    return hexToColor(
      hex,
      fallback: const Color(0xFF607D8B),
      opacity: opacity,
    );
  }
}

extension AppColorSchemeParsing on ColorScheme {
  Color hexToPrimary(String? hex, {double opacity = 1}) {
    return AppColorUtils.hexToColor(hex, fallback: primary, opacity: opacity);
  }

  Color hexToSecondary(String? hex, {double opacity = 1}) {
    return AppColorUtils.hexToColor(hex, fallback: secondary, opacity: opacity);
  }
}
