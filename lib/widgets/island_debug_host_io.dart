import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/float_window_service.dart';
import '../utils/app_platform.dart';
import '../windows_island/island_debug.dart';
import '../windows_island/island_ui.dart';

class IslandDebugHost {
  IslandDebugHost._();

  static bool get shouldShowOverlay => AppPlatform.isWindows && kDebugMode;

  static Widget route() => const IslandDebugPage();

  static Widget overlay() {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: FloatWindowService.debugPayload,
      builder: (context, payload, _) {
        if (payload == null || payload.isEmpty) {
          return const SizedBox.shrink();
        }
        return Positioned(
          top: 16,
          right: 16,
          child: SizedBox(
            width: 380,
            height: 220,
            child: IslandUI(
              inLayoutDebugMode: true,
              payloadNotifier: FloatWindowService.debugPayload,
              initialPayload: payload,
            ),
          ),
        );
      },
    );
  }
}
