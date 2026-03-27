// Island window entrypoint for desktop_multi_window
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' hide window; // For Rect
import 'dart:ffi' hide Size;
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' hide Size;
import 'package:flutter/foundation.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'island_ui.dart';
import 'island_payload.dart';
import '../storage_service.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

// Deleted _globalDmwChannel because File IPC is used for sub->host communication.
// _dmw channel is still used for host->sub via setWindowMethodHandler.

/// Entry point for the lightweight Windows Island process.
Future<File> _getActionFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/island_action.json');
}

@pragma('vm:entry-point')
Future<void> islandMain(List<String> args) async {
  // CRITICAL: Initialize bindings at the very start of the isolate entrypoint
  // BEFORE any zones are created to avoid "Zone mismatch" errors.
  WidgetsFlutterBinding.ensureInitialized();

  // Start with a default idle payload so the island UI renders immediately
  final ValueNotifier<Map<String, dynamic>?> payloadNotifier =
      ValueNotifier(IslandPayload.fromMap(null).toMap());

  // Guard the entire island isolate so uncaught exceptions don't crash
  await runZonedGuarded(() async {
    Map<String, dynamic>? lastReportedBounds;

    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('[Island] FlutterError: ${details.exceptionAsString()}');
    };

    try {
      final controller = await WindowController.fromCurrentEngine();
      // FFI: Force Windows frameless & transparency by searching for sub-window HWND in current PID
      try {
        await controller.invokeMethod(
            'setFrame', {'x': 0.0, 'y': 0.0, 'width': 160.0, 'height': 56.0});
        await controller.invokeMethod('setAlwaysOnTop', true);
        await controller.invokeMethod(
            'setWindowTransparent', {'transparent': true}).catchError((_) {});
      } catch (_) {}

      // Apply FFI immediately and poll until window appears to prevent flicker
      Future<void> initFfi() async {
        for (int i = 0; i < 40; i++) {
          if (_getIslandHwnd() != null) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
      initFfi();

      debugPrint(
          '[Island] islandMain started for windowId=${controller.windowId} args=$args');

      // ✅ 这个才能收到 postMessage 发来的数据
      const globalChannel = MethodChannel('mixin.one/desktop_multi_window');
      globalChannel.setMethodCallHandler((call) async {
        final fromWindowId =
            (call.arguments is Map) ? call.arguments['windowId'] : 0;
        debugPrint(
            '[Island] >>> GLOBAL CALL: "${call.method}" from=$fromWindowId args=${call.arguments}');

        if (call.method == 'postWindowMessage' ||
            call.method == 'updateState') {
          final m = call.arguments as Map?;
          if (m != null) {
            try {
              final rawMap = Map<String, dynamic>.from(m);
              final dynamic mmRaw =
                  rawMap.containsKey('payload') ? rawMap['payload'] : rawMap;
              if (mmRaw is! Map) return null;

              final mm = Map<String, dynamic>.from(mmRaw);

              if (mm['handshake'] == 'ping') {
                controller.invokeMethod('onAction', {
                  'action': 'handshake_pong',
                  'windowId': controller.windowId
                }).catchError((_) {});
                return null;
              }

              if (mm.containsKey('focusData') || mm.containsKey('state')) {
                payloadNotifier.value = mm;
                debugPrint('[Island] ✅ payload applied: state=${mm['state']}');
              } else if (mm.containsKey('legacy') && mm['legacy'] is Map) {
                payloadNotifier.value =
                    Map<String, dynamic>.from(mm['legacy'] as Map);
              } else {
                final dto = IslandPayload.fromMap(mm);
                payloadNotifier.value = dto.toMap();
              }
            } catch (e) {
              debugPrint('[Island] global handler parse error: $e');
            }
          }
        }
        return null;
      });

      // Register handler to receive messages from host for this window
      await controller.setWindowMethodHandler((call) async {
        debugPrint('[Island] >>> CALL: "${call.method}" | ${call.arguments}');
        try {
          debugPrint(
              '[Island] received window method: ${call.method} args=${call.arguments}');
          if (call.method == 'postWindowMessage' ||
              call.method == 'updateState') {
            final m = call.arguments as Map?;
            if (m != null) {
              try {
                // Extract 'payload' key if the host wrapped it (standard for postWindowMessage)
                final rawMap = Map<String, dynamic>.from(m);
                final dynamic mmRaw =
                    rawMap.containsKey('payload') ? rawMap['payload'] : rawMap;
                if (mmRaw is! Map) return;

                final mm = Map<String, dynamic>.from(mmRaw);
                // Handshake ping
                if (mm['handshake'] == 'ping') {
                  // reply with handshake_pong to host
                  controller.invokeMethod('onAction', {
                    'action': 'handshake_pong',
                    'windowId': controller.windowId
                  }).catchError((_) {});
                  debugPrint('[Island] responded handshake_pong to host');
                }
                // Support both legacy DTO and the new structured payload.
                if (mm.containsKey('legacy') && mm['legacy'] is Map) {
                  payloadNotifier.value =
                      Map<String, dynamic>.from(mm['legacy']);
                  debugPrint(
                      '[Island] applied legacy payload from structured wrapper: ${payloadNotifier.value}');
                } else if (mm.containsKey('focusData') ||
                    mm.containsKey('state')) {
                  // If host sent a structured payload that already includes 'state' or 'focusData',
                  // prefer delivering the structured map to the Island UI so it can map states directly.
                  try {
                    final structured = Map<String, dynamic>.from(mm);
                    payloadNotifier.value = structured;
                    debugPrint(
                        '[Island] applied structured payload directly: ${payloadNotifier.value}');
                  } catch (e) {
                    debugPrint(
                        '[Island] failed to apply structured payload directly: $e');
                  }
                } else {
                  try {
                    final dto = IslandPayload.fromMap(mm);
                    payloadNotifier.value = dto.toMap();
                    debugPrint(
                        '[Island] payloadNotifier updated from method handler: ${payloadNotifier.value}');
                  } catch (e) {
                    debugPrint(
                        '[Island] failed to parse payload in handler as DTO: $e');
                  }
                }
              } catch (e) {
                debugPrint('[Island] failed to parse payload in handler: $e');
              }
            }
          }
          if (call.method == 'startDragging') {
            try {
              final hwnd = _getIslandHwnd();
              if (hwnd != null) {
                const int WM_NCLBUTTONDOWN = 0x00A1;
                const int HTCAPTION = 2;
                ReleaseCapture();
                PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
                debugPrint('[Island] Native dragging posted for HWND $hwnd');
              }
            } catch (e) {
              debugPrint('[Island] Native drag failed: $e');
            }
          }

          if (call.method == 'setWindowSize') {
            final a = call.arguments as Map?;
            if (a != null) {
              final w = (a['width'] as num?)?.toInt() ?? 160;
              final h = (a['height'] as num?)?.toInt() ?? 56;
              Future.microtask(() => _resizeCurrentWindow(w, h));
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
        final def = await controller
            .invokeMethod('getWindowDefinition', null)
            .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
        if (def is Map) {
          // The plugin may return 'payload' (map) or 'windowArgument' (string).
          dynamic payloadCandidate =
              def['payload'] ?? def['windowArgument'] ?? def['window_argument'];
          // If host provided initialBounds, apply them
          try {
            final ib = def['initialBounds'] ?? def['initial_bounds'];
            if (ib is Map) {
              final width = ib['width'];
              final height = ib['height'];
              final left = ib['left'];
              final top = ib['top'];
              if (width is num && height is num && left is num && top is num) {
                // Apply physical exact bounds at startup with retry loop
                Future.microtask(() async {
                  for (int i = 0; i < 20; i++) {
                    final hw = _getIslandHwnd();
                    if (hw != null) {
                      final scale = _getIslandScaleFactor(hw);
                      final phyW = (width * scale).ceil();
                      final phyH = (height * scale).ceil();
                      final phyLeft = (left * scale).toInt();
                      final phyTop = (top * scale).toInt();
                      const int HWND_TOPMOST = -1;
                      const int SWP_NOACTIVATE = 0x0010;
                      SetWindowPos(hw, HWND_TOPMOST, phyLeft, phyTop, phyW,
                          phyH, SWP_NOACTIVATE);
                      debugPrint(
                          '[Island] applied initial physical bounds from host: $phyLeft,$phyTop ${phyW}x${phyH}');
                      break;
                    }
                    await Future.delayed(const Duration(milliseconds: 100));
                  }
                });
              }
            }
          } catch (_) {}
          if (payloadCandidate != null) {
            Map<String, dynamic>? payloadMap;
            if (payloadCandidate is Map) {
              payloadMap = Map<String, dynamic>.from(payloadCandidate);
            } else if (payloadCandidate is String &&
                payloadCandidate.isNotEmpty) {
              try {
                final decoded = jsonDecode(payloadCandidate);
                if (decoded is Map)
                  payloadMap = Map<String, dynamic>.from(decoded);
              } catch (e) {
                debugPrint('[Island] initial payload JSON parse error: $e');
              }
            }

            if (payloadMap != null) {
              try {
                final dto = IslandPayload.fromMap(payloadMap);
                payloadNotifier.value = dto.toMap();
                debugPrint(
                    '[Island] initial payload applied: ${payloadNotifier.value}');
              } catch (e) {
                debugPrint('[Island] failed to apply initial payload: $e');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Island] getWindowDefinition error: $e');
      }
      // Register periodic bounds monitor to support window position memory
      Timer.periodic(const Duration(seconds: 2), (timer) async {
        try {
          final hwnd = _getIslandHwnd();
          if (hwnd == null) return;

          final rectPtr = calloc<RECT>();
          GetWindowRect(hwnd, rectPtr);
          final curX = rectPtr.ref.left;
          final curY = rectPtr.ref.top;
          final curW = rectPtr.ref.right - rectPtr.ref.left;
          final curH = rectPtr.ref.bottom - rectPtr.ref.top;
          calloc.free(rectPtr);

          final scale = _getIslandScaleFactor(hwnd);
          final double logicalX = curX / scale;
          final double logicalY = curY / scale;
          final double logicalW = curW / scale;
          final double logicalH = curH / scale;

          final currentBounds = {
            'left': logicalX,
            'top': logicalY,
            'width': logicalW.ceilToDouble(),
            'height': logicalH.ceilToDouble(),
          };

          // Compare with last reported to avoid redundant IPC
          if (lastReportedBounds == null ||
              lastReportedBounds!['left'] != currentBounds['left'] ||
              lastReportedBounds!['top'] != currentBounds['top']) {
            lastReportedBounds = currentBounds;
            
            // Only report if window is likely in a stable state (not moving right now)
            // Native drag (postMessage) might keep it in a modal loop, but this timer 
            // will fire once the loop ends or periodically.
            WindowController.fromWindowId('0').invokeMethod('onAction', {
              'action': 'bounds_changed',
              'bounds': currentBounds,
              'windowId': controller.windowId
            }).catchError((_) {});
          }
        } catch (_) {}
      });

      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF000000),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF000000), // ← ColorKey 透明化的关键
          body: Stack(
            alignment: Alignment.topCenter,
            children: [
              IslandUI(
                payloadNotifier: payloadNotifier,
                initialPayload: payloadNotifier.value,
                onAction: (action, [modifiedSecs]) async {
                  // Check local/remote permission before forwarding
                  try {
                    final current = payloadNotifier.value;
                    String syncMode = 'local';
                    if (current != null) {
                      if (current.containsKey('legacy')) {
                        final legacy = current['legacy'] as Map?;
                        if (legacy != null && legacy['isLocal'] is bool) {
                          syncMode =
                              (legacy['isLocal'] as bool) ? 'local' : 'remote';
                        }
                      } else if (current.containsKey('focusData')) {
                        final fd =
                            current['focusData'] as Map<String, dynamic>?;
                        if (fd != null && fd['syncMode'] != null) {
                          syncMode = fd['syncMode']?.toString() ?? 'local';
                        }
                      }
                    }

                    if ((action == 'finish' || action == 'abandon') &&
                        syncMode != 'local') {
                      debugPrint(
                          '[Island] action $action blocked because syncMode=$syncMode');
                      return;
                    }

                    try {
                      final file = await _getActionFile();
                      await file.writeAsString(jsonEncode({
                        'action': action,
                        'modifiedSecs': modifiedSecs ?? 0,
                        'windowId': controller.windowId,
                        'timestamp': DateTime.now().millisecondsSinceEpoch,
                      }));
                      debugPrint('[Island] onAction "$action" written to File IPC');
                    } catch (e) {
                      debugPrint('[Island] onAction "$action" FAILED: $e');
                    }
                  } catch (e) {
                    debugPrint('[Island] onAction flow error: $e');
                  }
                },
              ),
              ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: payloadNotifier,
                builder: (context, val, child) {
                  if (val == null || (val.isEmpty)) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('灵动岛已就绪 — 等待主程序数据',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ));

      // 3) Signal to host that we are ready to receive state/theme
      // Using File IPC for ready signal as well.
      Future.microtask(() async {
        try {
          final file = await _getActionFile();
          await file.writeAsString(jsonEncode({
            'action': 'ready',
            'windowId': controller.windowId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
          debugPrint(
              '[Island] ready signal written to File IPC for windowId=${controller.windowId}');
        } catch (e) {
          debugPrint('[Island] failed to write ready signal: $e');
        }
      });

      // NOTE: removed diagnostic debug payload injection to ensure island only
      // renders real data provided by the host. This matches the requirement
      // to not display debug data and to rely on actual IPC payloads.
    } catch (e) {
      debugPrint('[Island] initialization failed: $e');
      // Fallback: run in-layout island for debugging if controller not available
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF000000),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF000000),
          body: Center(child: IslandUI(initialPayload: payloadNotifier.value)),
        ),
      ));
    }
  }, (error, stack) {
    debugPrint('[Island] Unhandled error in island isolate: $error\n$stack');
    try {
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF000000),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF000000),
          body: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('灵动岛发生错误',
                      style: TextStyle(fontSize: 16, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(error.toString(),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ));
    } catch (_) {}
  });
}

// Caches the correct island window handle to avoid expensive re-evaluations
int? _islandHwndCache;

int? _getIslandHwnd() {
  if (_islandHwndCache != null) return _islandHwndCache;
  if (!Platform.isWindows) return null;
  try {
    final currentPid = GetCurrentProcessId();
    final foundHwnds = <int>[];

    final lpEnumFunc =
        NativeCallable<WNDENUMPROC>.isolateLocal((int hwnd, int lParam) {
      final pidPtr = calloc<Uint32>();
      GetWindowThreadProcessId(hwnd, pidPtr);
      final pid = pidPtr.value;
      calloc.free(pidPtr);

      if (pid == currentPid && IsWindowVisible(hwnd) != 0) {
        foundHwnds.add(hwnd);
      }
      return 1;
    }, exceptionalReturn: 0);

    EnumWindows(lpEnumFunc.nativeFunction, 0);
    lpEnumFunc.close();

    if (foundHwnds.isNotEmpty) {
      int? bestHwnd;
      int minArea = 999999999;
      for (final h in foundHwnds) {
        final rectPtr = calloc<RECT>();
        GetWindowRect(h, rectPtr);
        final w = rectPtr.ref.right - rectPtr.ref.left;
        final hSize = rectPtr.ref.bottom - rectPtr.ref.top;
        calloc.free(rectPtr);
        final area = w * hSize;
        if (area > 0 && area < minArea) {
          minArea = area;
          bestHwnd = h;
        }
      }

      if (bestHwnd != null) {
        _islandHwndCache = bestHwnd;
        _applyWin32FramelessTransparentImpl(_islandHwndCache!);
        // Ensure style persists by forcing the window to redraw after Flutter is fully attached.
        Future.delayed(const Duration(milliseconds: 200), () {
          if (_islandHwndCache != null) {
            _applyWin32FramelessTransparentImpl(_islandHwndCache!);
          }
        });
        return _islandHwndCache;
      }
    }
  } catch (_) {}
  return null;
}

void _applyWin32FramelessTransparentImpl(int hwnd) {
  try {
    const WS_CAPTION = 0x00C00000;
    const WS_THICKFRAME = 0x00040000;
    const WS_SYSMENU = 0x00080000;

    var style = GetWindowLongPtr(hwnd, GWL_STYLE);
    style &= ~WS_CAPTION;
    style &= ~WS_THICKFRAME;
    style &= ~WS_SYSMENU;
    SetWindowLongPtr(hwnd, GWL_STYLE, style);

    var exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    exStyle |= WS_EX_LAYERED;
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle);
    SetLayeredWindowAttributes(hwnd, 0, 0, LWA_COLORKEY);

    const int HWND_TOPMOST = -1;
    const int SWP_NOMOVE = 0x0002;
    const int SWP_NOSIZE = 0x0001;
    const int SWP_NOACTIVATE = 0x0010;
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  } catch (e) {
    debugPrint('[Island] PID-based FFI failed: $e');
  }
}

// Deprecated
void _applyWin32FramelessTransparent() {}

double _getIslandScaleFactor(int hwnd) {
  try {
    final hdc = GetDC(hwnd);
    final dpi = GetDeviceCaps(hdc, 88); // LOGPIXELSX
    ReleaseDC(hwnd, hdc);
    if (dpi > 0) return dpi / 96.0;
  } catch (_) {}
  return 1.0;
}

void _resizeCurrentWindow(int targetW, int targetH) {
  final hwnd = _getIslandHwnd();
  if (hwnd == null) return;
  try {
    final scale = _getIslandScaleFactor(hwnd);
    final int physicalW = (targetW * scale).ceil();
    final int physicalH = (targetH * scale).ceil();

    final rectPtr = calloc<RECT>();
    GetWindowRect(hwnd, rectPtr);
    final curX = rectPtr.ref.left;
    final curY = rectPtr.ref.top;
    final curW = rectPtr.ref.right - rectPtr.ref.left;
    calloc.free(rectPtr);

    int newX = curX;
    int newY = curY;
    if (curW > 0 && curW != physicalW) {
      newX = curX - ((physicalW - curW) ~/ 2);
    }
    const int HWND_TOPMOST = -1;
    const int SWP_NOACTIVATE = 0x0010;

    SetWindowPos(hwnd, HWND_TOPMOST, newX, newY, physicalW, physicalH, SWP_NOACTIVATE);
    
    StorageService.saveIslandBounds('island-1', {
      'left': newX.toDouble(),
      'top': newY.toDouble(),
      'width': targetW.toDouble(),
      'height': targetH.toDouble(),
    }).catchError((_) {});

    debugPrint('[Island] SetWindowPos centered phy:${physicalW}x${physicalH} -> HWND=$hwnd');
  } catch (e) {
    debugPrint('[Island] resize failed: $e');
  }
}
