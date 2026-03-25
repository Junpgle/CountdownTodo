// Island window entrypoint for desktop_multi_window
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'island_ui.dart';
import 'island_payload.dart';
import 'dart:convert';

@pragma('vm:entry-point')
Future<void> islandMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final ValueNotifier<Map<String, dynamic>?> payloadNotifier = ValueNotifier(null);

  try {
    final controller = await WindowController.fromCurrentEngine();
    debugPrint('[Island] islandMain started for windowId=${controller.windowId} args=$args');

    // Try to fetch any initial payload that the host passed during createWindow.
    // Some hosts deliver an initial payload as part of the window definition
    // (getWindowDefinition) or as a serialized argument. We try both forms so
    // the island isn't blank if a postWindowMessage arrived before the Dart
    // handler was registered.
    try {
      final def = await controller.invokeMethod('getWindowDefinition', null).timeout(const Duration(milliseconds: 800), onTimeout: () => null);
      if (def is Map) {
        // The plugin may return 'payload' (map) or 'windowArgument' (string).
        dynamic payloadCandidate = def['payload'] ?? def['windowArgument'] ?? def['window_argument'];
        if (payloadCandidate != null) {
          Map<String, dynamic>? payloadMap;
          if (payloadCandidate is Map) {
            payloadMap = Map<String, dynamic>.from(payloadCandidate);
          } else if (payloadCandidate is String && payloadCandidate.isNotEmpty) {
            try {
              final decoded = jsonDecode(payloadCandidate);
              if (decoded is Map) payloadMap = Map<String, dynamic>.from(decoded);
            } catch (_) {
              // ignore JSON parse errors
            }
          }

          if (payloadMap != null) {
            try {
              final dto = IslandPayload.fromMap(payloadMap);
              payloadNotifier.value = dto.toMap();
              debugPrint('[Island] initial payload applied: ${payloadNotifier.value}');
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // ignore errors here — handler below will receive any postWindowMessage
    }
    // Register handler to receive messages from host for this window
    await controller.setWindowMethodHandler((call) async {
      try {
        debugPrint('[Island] received window method: ${call.method} args=${call.arguments}');
        if (call.method == 'postWindowMessage' || call.method == 'updateState') {
          final m = call.arguments as Map?;
          if (m != null) {
            final dto = IslandPayload.fromMap(Map<String, dynamic>.from(m));
            payloadNotifier.value = dto.toMap();
            debugPrint('[Island] payloadNotifier updated from method handler: ${payloadNotifier.value}');
          }
        }
      } catch (e) {
        debugPrint('[Island] error in window method handler: $e');
      }
      return null;
    });

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: IslandUI(
            payloadNotifier: payloadNotifier,
            initialPayload: payloadNotifier.value,
            onAction: (action, [modifiedSecs]) {
              // Forward actions back to the host window via controller
              controller.invokeMethod('onAction', {'action': action, 'modifiedSecs': modifiedSecs ?? 0}).catchError((_) {});
            },
          ),
        ),
      ),
    ));
  } catch (e) {
    // Fallback: run in-layout island for debugging if controller not available
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: IslandUI(initialPayload: payloadNotifier.value))),
    ));
  }
}

