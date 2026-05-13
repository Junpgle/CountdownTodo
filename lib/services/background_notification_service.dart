import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundNotificationService {
  static const MethodChannel _channel = MethodChannel(
    'com.math_quiz_app/background_notifications',
  );

  static Future<void> configureNotificationPoll({
    required int userId,
    required String token,
    required String apiBaseUrl,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod('configureNotificationPoll', {
      'userId': userId,
      'token': token,
      'apiBaseUrl': apiBaseUrl,
    });
  }

  static Future<void> stopNotificationPoll() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod('stopNotificationPoll');
  }

  static Future<void> runImmediateNotificationPoll() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod('runImmediateNotificationPoll');
  }

  static Future<List<Map<String, dynamic>>>
      getUnreadBackgroundNotifications() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    final raw = await _channel.invokeMethod<String>(
          'getUnreadBackgroundNotifications',
        ) ??
        '[]';
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<void> clearUnreadBackgroundNotifications() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod('clearUnreadBackgroundNotifications');
  }

  static Future<void> markNotificationEventShown(int eventId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (eventId <= 0) return;
    await _channel.invokeMethod('markNotificationEventShown', {
      'eventId': eventId,
    });
  }
}
