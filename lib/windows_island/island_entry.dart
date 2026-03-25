// Island window entrypoint for desktop_multi_window
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'island_ui.dart';
import 'island_payload.dart';

@pragma('vm:entry-point')
Future<void> islandMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final ValueNotifier<Map<String, dynamic>?> payloadNotifier = ValueNotifier(null);

  try {
    final controller = await WindowController.fromCurrentEngine();
    debugPrint('[Island] islandMain started for windowId=${controller.windowId} args=$args');

    // Register handler to receive messages from host for this window
    await controller.setWindowMethodHandler((call) async {
      try {
        if (call.method == 'postWindowMessage' || call.method == 'updateState') {
          final m = call.arguments as Map?;
          if (m != null) {
            final dto = IslandPayload.fromMap(Map<String, dynamic>.from(m));
            payloadNotifier.value = dto.toMap();
          }
        }
      } catch (_) {
        // ignore parse errors
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

