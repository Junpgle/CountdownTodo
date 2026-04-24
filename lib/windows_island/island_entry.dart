// Island window entrypoint for desktop_multi_window
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' hide window;
import 'dart:ffi' hide Size;
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' hide Size;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'island_ui.dart';
import 'island_payload.dart';
import 'island_config.dart';
import 'island_win32.dart';
import 'island_reminder.dart';
import '../storage_service.dart';

/// Get the action file for IPC
Future<File> _getActionFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/${IslandConfig.actionFileName}');
}

/// Launch a URL with fallback to Process
Future<void> _launchUrl(String url) async {
  try {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    debugPrint('[Island] url_launcher failed: $e, trying Process');
    try {
      final result = await Process.run('cmd', ['/c', 'start', '', url]);
      debugPrint('[Island] Process.run result: ${result.exitCode}');
    } catch (e2) {
      debugPrint('[Island] Process.run failed: $e2');
    }
  }
}

/// Restore window position from storage
Future<void> _restoreWindowPosition() async {
  try {
    final bounds =
        await StorageService.getIslandBounds(IslandConfig.defaultIslandId);
    if (bounds != null && bounds.isNotEmpty) {
      final left = (bounds['left'] as num?)?.toInt();
      final top = (bounds['top'] as num?)?.toInt();
      final width = (bounds['width'] as num?)?.toInt() ??
          IslandConfig.defaultWidth.toInt();
      final height = (bounds['height'] as num?)?.toInt() ??
          IslandConfig.defaultHeight.toInt();

      if (left != null && top != null) {
        setWindowPosition(left, top, width, height);
        debugPrint('[Island] Restored window position: left=$left, top=$top');
      }
    }
  } catch (e) {
    debugPrint('[Island] Failed to restore window position: $e');
  }
}

/// Set up reminder expire timer
void _setupReminderExpireTimer(
  Map<String, dynamic> reminder,
  ValueNotifier<Map<String, dynamic>?> payloadNotifier,
) {
  IslandReminderService.setupExpireTimer(
    reminder,
    (currentState) {
      final stateStr = currentState['state']?.toString();
      if (stateStr == 'reminder_split' ||
          stateStr == 'reminder_capsule' ||
          stateStr == 'reminder_popup') {
        final prevState = stateStr == 'reminder_split' ? 'focusing' : 'idle';
        payloadNotifier.value = {
          ...currentState,
          'state': prevState,
        };
        debugPrint('[Island] Reminder expired, restored state: $prevState');
      }
    },
    () => payloadNotifier.value ?? {},
  );
}

@pragma('vm:entry-point')
Future<void> islandMain(List<String> args) async {
  clearIslandHwndCache();

  WidgetsFlutterBinding.ensureInitialized();

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[Island] Unhandled error: $error\n$stack');
    return true;
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[Island] FlutterError: ${details.exceptionAsString()}');
  };

  final ValueNotifier<Map<String, dynamic>?> payloadNotifier =
      ValueNotifier(IslandPayload.fromMap(null).toMap());

  Map<String, dynamic>? lastReportedBounds;
  bool boundsSaveEnabled = false;
  bool boundsSaveReady = false;
  bool isDragging = false;
  bool needsSaveAfterDrag = false;

  try {
    final controller = await WindowController.fromCurrentEngine();
    try {
      await controller.invokeMethod('setFrame', {
        'width': IslandConfig.defaultWidth,
        'height': IslandConfig.defaultHeight,
      });
      await controller.invokeMethod('setAlwaysOnTop', true);
    } catch (_) {}

    Future.delayed(IslandConfig.windowRestoreDelay, () {
      _restoreWindowPosition();
    });

    initFfiTransparent();

    debugPrint(
        '[Island] islandMain started for windowId=${controller.windowId}');

    const globalChannel = MethodChannel('mixin.one/desktop_multi_window');
    globalChannel.setMethodCallHandler((call) async {
      final fromWindowId =
          (call.arguments is Map) ? call.arguments['windowId'] : 0;
      debugPrint('[Island] GLOBAL CALL: "${call.method}" from=$fromWindowId');

      if (call.method == 'postWindowMessage' || call.method == 'updateState') {
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
            } else if (mm.containsKey('legacy') && mm['legacy'] is Map) {
              payloadNotifier.value =
                  Map<String, dynamic>.from(mm['legacy'] as Map);
            } else {
              final dto = IslandPayload.fromMap(mm);
              payloadNotifier.value = dto.toMap();
            }
          } catch (e) {
            debugPrint('[Island] Global handler parse error: $e');
          }
        }
      }
      return null;
    });

    await controller.setWindowMethodHandler((call) async {
      debugPrint('[Island] CALL: "${call.method}" | ${call.arguments}');
      try {
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
              }
              if (mm.containsKey('legacy') && mm['legacy'] is Map) {
                payloadNotifier.value = Map<String, dynamic>.from(mm['legacy']);
              } else if (mm.containsKey('focusData') ||
                  mm.containsKey('state')) {
                payloadNotifier.value = Map<String, dynamic>.from(mm);
              } else {
                final dto = IslandPayload.fromMap(mm);
                payloadNotifier.value = dto.toMap();
              }
            } catch (e) {
              debugPrint('[Island] Failed to parse payload: $e');
            }
          }
        }

        if (call.method == 'startDragging') {
          startWindowDragging();
          isDragging = true;
          needsSaveAfterDrag = true;
          Timer(const Duration(milliseconds: 500), () {
            isDragging = false;
          });
        }

        if (call.method == 'setWindowSize') {
          final a = call.arguments as Map?;
          if (a != null) {
            final w = (a['width'] as num?)?.toInt() ??
                IslandConfig.defaultWidth.toInt();
            final h = (a['height'] as num?)?.toInt() ??
                IslandConfig.defaultHeight.toInt();
            Future.microtask(() => resizeCurrentWindow(w, h));
          }
        }

        if (call.method == 'setWindowPosition') {
          final a = call.arguments as Map?;
          if (a != null) {
            final left = (a['left'] as num?)?.toInt() ?? 0;
            final top = (a['top'] as num?)?.toInt() ?? 0;
            Future.microtask(() => moveCurrentWindow(left, top));
          }
        }

        if (call.method == 'getWindowRect') {
          return getWindowRect();
        }
      } catch (e) {
        debugPrint('[Island] Handler error: $e');
      }
      return null;
    });

    try {
      final def = await controller
          .invokeMethod('getWindowDefinition', null)
          .timeout(const Duration(milliseconds: 800), onTimeout: () => null);
      if (def is Map) {
        dynamic payloadCandidate =
            def['payload'] ?? def['windowArgument'] ?? def['window_argument'];
        try {
          final ib = def['initialBounds'] ?? def['initial_bounds'];
          if (ib is Map) {
            final width = ib['width'];
            final height = ib['height'];
            final left = ib['left'];
            final top = ib['top'];
            if (width is num && height is num && left is num && top is num) {
              Future.microtask(() async {
                for (int i = 0; i < 20; i++) {
                  final hw = getSmallestFlutterWindow();
                  if (hw != null) {
                    final scale = getIslandScaleFactor(hw);
                    final phyW = (width * scale).ceil();
                    final phyH = (height * scale).ceil();
                    final phyLeft = (left * scale).toInt();
                    final phyTop = (top * scale).toInt();
                    const int hwndTopmost = -1;
                    const int swpNoactivate = 0x0010;
                    using((arena) {
                      final rectPtr = arena<RECT>();
                      rectPtr.ref.left = phyLeft;
                      rectPtr.ref.top = phyTop;
                      rectPtr.ref.right = phyLeft + phyW;
                      rectPtr.ref.bottom = phyTop + phyH;
                      SetWindowPos(hw, hwndTopmost, rectPtr.ref.left,
                          rectPtr.ref.top, phyW, phyH, swpNoactivate);
                    });
                    break;
                  }
                  await Future.delayed(IslandConfig.ffiRetryInterval);
                }
              });
            }
          }
        } catch (e) {
          debugPrint('[Island] Position restore failed: $e');
        }
        if (payloadCandidate != null) {
          Map<String, dynamic>? payloadMap;
          if (payloadCandidate is Map) {
            payloadMap = Map<String, dynamic>.from(payloadCandidate);
          } else if (payloadCandidate is String &&
              payloadCandidate.isNotEmpty) {
            try {
              final decoded = jsonDecode(payloadCandidate);
              if (decoded is Map) {
                payloadMap = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
          }
          if (payloadMap != null) {
            try {
              final dto = IslandPayload.fromMap(payloadMap);
              payloadNotifier.value = dto.toMap();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    Timer? boundsPollingTimer;
    Timer? reminderCheckTimer;
    final Set<String> acknowledgedReminders = {};
    String? lastShownReminderId;
    Map<String, dynamic>? currentReminder;

    Timer(IslandConfig.boundsSaveEnableDelay, () {
      boundsSaveEnabled = true;
      Timer(IslandConfig.boundsSaveReadyDelay, () {
        boundsSaveReady = true;
      });
    });

    boundsPollingTimer =
        Timer.periodic(IslandConfig.boundsPollInterval, (timer) async {
      try {
        final hwnd = getSmallestFlutterWindow();
        if (hwnd == null) return;

        if (!isWindowValid(hwnd)) {
          timer.cancel();
          return;
        }

        final rect = getWindowRect();
        if (rect != null &&
            boundsSaveEnabled &&
            boundsSaveReady &&
            !isDragging) {
          final logicalX = rect['left']!;
          final lastLeft = lastReportedBounds?['left'] as double?;

          if (lastReportedBounds == null ||
              lastLeft == null ||
              (lastLeft - logicalX).abs() > 1.0) {
            lastReportedBounds = rect;
            if (needsSaveAfterDrag) {
              needsSaveAfterDrag = false;
              StorageService.saveIslandBounds(
                      IslandConfig.defaultIslandId, rect)
                  .catchError((_) {});
            }
          }
        }
      } catch (_) {}
    });

    Future<void> checkAndShowReminder() async {
      try {
        final reminder = await IslandReminderService.checkUpcomingReminder();
        final currentState =
            payloadNotifier.value?['state']?.toString() ?? 'idle';
        final currentReminderData = payloadNotifier.value?['reminderPopupData']
            as Map<String, dynamic>?;
        final currentMinutesUntil =
            currentReminderData?['minutesUntil'] as int?;
        final isCurrentlyAcknowledged =
            currentReminderData?['acknowledged'] as bool? ?? false;

        if (reminder != null) {
          final itemId = reminder['itemId']?.toString();
          final newMinutesUntil = reminder['minutesUntil'] as int?;

          bool needUpdate = false;
          bool needStrongExpand = false;

          if (itemId != null) {
            final isNewReminder = lastShownReminderId != itemId;
            final isSameButChanged = currentMinutesUntil != null &&
                newMinutesUntil != null &&
                currentMinutesUntil != newMinutesUntil;
            final isAcknowledged = isCurrentlyAcknowledged ||
                acknowledgedReminders.contains(itemId);

            if (!isAcknowledged &&
                (isNewReminder ||
                    isSameButChanged ||
                    currentReminderData == null)) {
              needStrongExpand = true;
            }

            if (isNewReminder ||
                isSameButChanged ||
                currentReminderData == null) {
              needUpdate = true;
            } else if (isAcknowledged && currentMinutesUntil != null) {
              needUpdate = true;
            }
          }

          if (needUpdate) {
            lastShownReminderId = itemId!;
            currentReminder = reminder;

            final bool isAlreadyReminderState =
                currentState == 'reminder_split' ||
                    currentState == 'reminder_capsule' ||
                    currentState == 'reminder_popup';

            String targetState;
            if (!isAlreadyReminderState) {
              targetState = currentState == 'focusing'
                  ? 'reminder_split'
                  : 'reminder_capsule';
            } else {
              targetState = currentState;
            }

            final updatedReminder = {
              ...reminder,
              'acknowledged': isCurrentlyAcknowledged,
              'needsExpand': needStrongExpand,
            };

            final currentPayload = payloadNotifier.value ?? {};
            payloadNotifier.value = {
              ...currentPayload,
              'state': targetState,
              'reminderPopupData': updatedReminder,
            };
          }
        }
      } catch (e) {
        debugPrint('[Island] Check reminder failed: $e');
      }
    }

    reminderCheckTimer =
        Timer.periodic(IslandConfig.reminderCheckInterval, (timer) async {
      await checkAndShowReminder();
    });

    Timer(IslandConfig.initialReminderCheckDelay, () async {
      await checkAndShowReminder();
    });

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: IslandConfig.scaffoldBg,
      ),
      home: Scaffold(
        backgroundColor: IslandConfig.scaffoldBg,
        body: Focus(
          onKeyEvent: (node, event) {
            // 拦截 SendKeys 等外部注入的重复按键，防止 HardwareKeyboard 断言崩
            return KeyEventResult.handled;
          },
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              IslandUI(
                payloadNotifier: payloadNotifier,
                initialPayload: payloadNotifier.value,
                onAction: (action, [modifiedSecs, data]) async {
                  try {
                    if (action == 'reminder_ok') {
                      final itemId = payloadNotifier.value?['reminderPopupData']
                              ?['itemId']
                          ?.toString();
                      if (itemId != null) {
                        acknowledgedReminders.add(itemId);
                      }
                      final currentPayload = payloadNotifier.value ?? {};
                      final currentReminder =
                          currentPayload['reminderPopupData']
                              as Map<String, dynamic>?;
                      final updatedReminder = {
                        ...?currentReminder,
                        'acknowledged': true,
                      };
                      payloadNotifier.value = {
                        ...currentPayload,
                        'reminderPopupData': updatedReminder,
                      };
                      try {
                        final file = await _getActionFile();
                        await file.writeAsString(jsonEncode({
                          'action': action,
                          'itemId': itemId,
                          'windowId': controller.windowId,
                          'timestamp': DateTime.now().millisecondsSinceEpoch,
                        }));
                      } catch (_) {}
                      return;
                    }

                    if (action == 'remind_later') {
                      try {
                        final file = await _getActionFile();
                        await file.writeAsString(jsonEncode({
                          'action': action,
                          'windowId': controller.windowId,
                          'timestamp': DateTime.now().millisecondsSinceEpoch,
                        }));
                      } catch (_) {}
                      return;
                    }

                    if (action == 'snooze_reminder') {
                      final currentPayload = payloadNotifier.value ?? {};
                      final reminderData = currentPayload['reminderPopupData']
                          as Map<String, dynamic>?;
                      final newMinutes =
                          (data is String ? int.tryParse(data) : null) ??
                              currentPayload['snoozeMinutes'] as int? ??
                              5;
                      if (reminderData != null) {
                        lastShownReminderId = null;
                        acknowledgedReminders
                            .remove(reminderData['itemId']?.toString());
                        final updatedReminder = {
                          ...reminderData,
                          'minutesUntil': newMinutes,
                          'acknowledged': false,
                          'needsExpand': true,
                        };
                        final currentState =
                            payloadNotifier.value?['state']?.toString() ??
                                'idle';
                        final targetState = currentState == 'focusing'
                            ? 'reminder_split'
                            : 'reminder_capsule';
                        payloadNotifier.value = {
                          ...payloadNotifier.value ?? {},
                          'state': targetState,
                          'reminderPopupData': updatedReminder,
                        };
                        _setupReminderExpireTimer(
                            updatedReminder, payloadNotifier);
                      }
                      return;
                    }

                    if (action == 'check_reminder') {
                      lastShownReminderId = null;
                      await checkAndShowReminder();
                      return;
                    }

                    if (action == 'open_link') {
                      String? url = data;
                      if (url == null) {
                        final currentPayload = payloadNotifier.value ?? {};
                        final copiedLinkData = currentPayload['copiedLinkData']
                            as Map<String, dynamic>?;
                        url = copiedLinkData?['url']?.toString();
                      }
                      if (url != null) {
                        await _launchUrl(url);
                      }
                      // 通知主应用刷新岛的状态（恢复到打开链接前的状态）
                      try {
                        final file = await _getActionFile();
                        await file.writeAsString(jsonEncode({
                          'action': 'link_opened',
                          'windowId': controller.windowId,
                          'timestamp': DateTime.now().millisecondsSinceEpoch,
                        }));
                      } catch (_) {}
                      return;
                    }

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
                    } catch (_) {}
                  } catch (_) {}
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
        ), // Focus
      ),
    ));

    Future.microtask(() async {
      try {
        final file = await _getActionFile();
        await file.writeAsString(jsonEncode({
          'action': 'ready',
          'windowId': controller.windowId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (_) {}
    });
  } catch (e) {
    debugPrint('[Island] initialization failed: $e');
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: IslandConfig.scaffoldBg,
      ),
      home: Scaffold(
        backgroundColor: IslandConfig.scaffoldBg,
        body: Focus(
          onKeyEvent: (node, event) => KeyEventResult.handled,
          child: Center(child: IslandUI(initialPayload: payloadNotifier.value)),
        ),
      ),
    ));
  }
}
