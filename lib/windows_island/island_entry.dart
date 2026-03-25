// Island window entrypoint for desktop_multi_window
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'island_ui.dart';
import 'island_payload.dart';
import 'dart:convert';

@pragma('vm:entry-point')
Future<void> islandMain(List<String> args) async {
  final ValueNotifier<Map<String, dynamic>?> payloadNotifier = ValueNotifier(null);

  // Guard the entire island isolate so uncaught exceptions don't crash the
  // engine without a readable error message. Present an error UI instead.
  await runZonedGuarded(() async {
    // Ensure bindings are initialized in the same zone that will later run
    // the Flutter UI. Calling this outside the zone causes the zone mismatch
    // error seen previously.
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('[Island] FlutterError: ${details.exceptionAsString()}');
    };

    try {
      final controller = await WindowController.fromCurrentEngine();
    debugPrint('[Island] islandMain started for windowId=${controller.windowId} args=$args');

    // Register handler to receive messages from host for this window
    await controller.setWindowMethodHandler((call) async {
      try {
        debugPrint('[Island] received window method: ${call.method} args=${call.arguments}');
        if (call.method == 'postWindowMessage' || call.method == 'updateState') {
          final m = call.arguments as Map?;
          if (m != null) {
            try {
              final dto = IslandPayload.fromMap(Map<String, dynamic>.from(m));
              payloadNotifier.value = dto.toMap();
              debugPrint('[Island] payloadNotifier updated from method handler: ${payloadNotifier.value}');
            } catch (e) {
              debugPrint('[Island] failed to parse payload in handler: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('[Island] error in window method handler: $e');
      }
      return null;
    });

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
            } catch (e) {
              debugPrint('[Island] initial payload JSON parse error: $e');
            }
          }

          if (payloadMap != null) {
            try {
              final dto = IslandPayload.fromMap(payloadMap);
              payloadNotifier.value = dto.toMap();
              debugPrint('[Island] initial payload applied: ${payloadNotifier.value}');
            } catch (e) {
              debugPrint('[Island] failed to apply initial payload: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Island] getWindowDefinition error: $e');
    }

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              IslandUI(
                payloadNotifier: payloadNotifier,
                initialPayload: payloadNotifier.value,
                onAction: (action, [modifiedSecs]) {
                  // Forward actions back to the host window via controller
                  controller.invokeMethod('onAction', {'action': action, 'modifiedSecs': modifiedSecs ?? 0}).catchError((_) {});
                },
              ),
              // Debug / placeholder overlay to avoid white blank while waiting
              ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: payloadNotifier,
                builder: (context, val, child) {
                  if (val == null) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(8)),
                      child: const Text('Island ready — waiting for payload', style: TextStyle(color: Colors.white, fontSize: 12)),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    ));

    // Notify host that this island window has initialized and is ready to receive messages.
    // This is best-effort: ignore errors if host doesn't implement onAction.
    Future.microtask(() async {
      try {
        await controller.invokeMethod('onAction', {'action': 'ready'}).timeout(const Duration(milliseconds: 800), onTimeout: () => null);
        debugPrint('[Island] ready signal sent to host for windowId=${controller.windowId}');
      } catch (e) {
        debugPrint('[Island] failed to send ready signal: $e');
      }
    });

    // Diagnostic: if after a short timeout we still have no payload, inject
    // a debug payload so the UI can render and we can tell whether the
    // island is able to draw independently of IPC delivery.
    Future.delayed(const Duration(seconds: 3), () {
      try {
        if (payloadNotifier.value == null) {
          final debugMap = IslandPayload.fromMap({
            'endMs': DateTime.now().millisecondsSinceEpoch + 25 * 60 * 1000,
            'title': 'Debug Focus',
            'tags': <String>[],
            'isLocal': true,
            'mode': 1,
            'style': 1,
            'left': '',
            'right': '',
            'forceReset': false,
            'topBarLeft': '',
            'topBarRight': '',
            'reminderQueue': <Map<String, String>>[],
            'detail_type': '',
            'detail_title': '',
            'detail_subtitle': '',
            'detail_location': '',
            'detail_time': '',
            'detail_note': '',
          }).toMap();
          payloadNotifier.value = debugMap;
          debugPrint('[Island] injected debug payload to force render: $debugMap');
        }
      } catch (e) {
        debugPrint('[Island] failed to inject debug payload: $e');
      }
    });
    } catch (e) {
      debugPrint('[Island] top-level island error: $e');
      // Fallback: run in-layout island for debugging if controller not available
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: IslandUI(initialPayload: payloadNotifier.value))),
      ));
    }
  }, (error, stack) {
    debugPrint('[Island] Unhandled error in island isolate: $error\n$stack');
    try {
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('Island encountered an error', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(error.toString(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ),
        ),
      ));
    } catch (_) {}
  });
}

