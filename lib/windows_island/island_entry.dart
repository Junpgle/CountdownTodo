// Island window entrypoint for desktop_multi_window
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' hide window;
import 'package:flutter/services.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'island_ui.dart';
import 'island_payload.dart';
import 'island_config.dart';
import 'island_ipc_paths.dart';
import 'island_win32.dart';
import 'island_reminder.dart';
import '../storage_service.dart';

/// Get the action file for IPC
Future<File> _getActionFile() async {
  return getIslandIpcFile(IslandConfig.actionFileName);
}

/// Get the latest payload file for file-based IPC fallback.
Future<File> _getPayloadFile() async {
  return getIslandIpcFile(IslandConfig.payloadFileName);
}

Map<String, dynamic>? _payloadFromRaw(dynamic raw) {
  if (raw is! Map) return null;
  final rawMap = Map<String, dynamic>.from(raw);
  final dynamic payloadRaw =
      rawMap.containsKey('payload') ? rawMap['payload'] : rawMap;
  if (payloadRaw is! Map) return null;
  return Map<String, dynamic>.from(payloadRaw);
}

void _applyIncomingPayload(
  Map<String, dynamic> payload,
  ValueNotifier<Map<String, dynamic>?> payloadNotifier,
  WindowController? controller,
  String windowId,
) {
  if (payload['handshake'] == 'ping') {
    controller?.invokeMethod('onAction', {
      'action': 'handshake_pong',
      'windowId': windowId,
    }).catchError((_) {});
    return;
  }

  if (payload.containsKey('focusData') || payload.containsKey('state')) {
    payloadNotifier.value = Map<String, dynamic>.from(payload);
  } else if (payload.containsKey('legacy') && payload['legacy'] is Map) {
    payloadNotifier.value = Map<String, dynamic>.from(payload['legacy'] as Map);
  } else {
    final dto = IslandPayload.fromMap(payload);
    payloadNotifier.value = dto.toMap();
  }
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
    final bounds = await loadIslandBounds(IslandConfig.defaultIslandId) ??
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
        await appendIslandIpcLog(
          'island restored bounds left=$left top=$top width=$width height=$height',
        );
        debugPrint('[Island] Restored window position: left=$left, top=$top');
      }
    }
  } catch (e) {
    debugPrint('[Island] Failed to restore window position: $e');
  }
}

bool _boundsChanged(
  Map<String, dynamic> previous,
  Map<String, dynamic> current,
) {
  bool changed(String key) {
    final prev = previous[key] as num?;
    final next = current[key] as num?;
    if (prev == null || next == null) return true;
    return (prev.toDouble() - next.toDouble()).abs() > 1.0;
  }

  return changed('left') ||
      changed('top') ||
      changed('width') ||
      changed('height');
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
  const enableNativeChrome =
      bool.fromEnvironment('ENABLE_WINDOWS_ISLAND_NATIVE_CHROME');

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
  WindowController? controller;
  final argWindowId = args.length > 1 ? args[1] : '';
  String currentWindowId() => controller?.windowId ?? argWindowId;

  int lastPayloadFileSequence = 0;
  int lastPayloadFileTimestamp = 0;
  Future<void> loadLatestPayloadFromFile() async {
    try {
      final file = await _getPayloadFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final envelope = Map<String, dynamic>.from(decoded);
      final sequence = (envelope['sequence'] as num?)?.toInt() ?? 0;
      final timestamp = (envelope['timestamp'] as num?)?.toInt() ?? 0;
      if (sequence > 0) {
        final sameRunPayload = sequence <= lastPayloadFileSequence;
        final oldTimestamp =
            timestamp > 0 && timestamp <= lastPayloadFileTimestamp;
        if (sameRunPayload && oldTimestamp) return;
      } else if (timestamp > 0 && timestamp <= lastPayloadFileTimestamp) {
        return;
      }
      final payload = _payloadFromRaw(envelope);
      if (payload == null) return;
      _applyIncomingPayload(
        payload,
        payloadNotifier,
        controller,
        currentWindowId(),
      );
      if (sequence > 0) {
        lastPayloadFileSequence = sequence;
      }
      if (timestamp > 0) {
        lastPayloadFileTimestamp = timestamp;
      }
      await appendIslandIpcLog(
        'island applied file payload seq=$sequence state=${payload['state']}',
      );
      debugPrint(
          '[Island] Applied payload from file: state=${payload['state']}');
    } catch (e) {
      debugPrint('[Island] load latest payload failed: $e');
      await appendIslandIpcLog('island failed to load payload: $e');
    }
  }

  await appendIslandIpcLog('islandMain entered args=${args.join('|')}');
  await loadLatestPayloadFromFile();
  Timer.periodic(IslandConfig.ipcPollInterval, (_) async {
    await loadLatestPayloadFromFile();
  });

  Future.delayed(IslandConfig.windowRestoreDelay, () {
    _restoreWindowPosition();
  });
  Future.delayed(const Duration(milliseconds: 1500), () {
    _restoreWindowPosition();
  });

  Timer(IslandConfig.boundsSaveEnableDelay, () {
    boundsSaveEnabled = true;
    Timer(IslandConfig.boundsSaveReadyDelay, () {
      boundsSaveReady = true;
    });
  });

  Timer.periodic(IslandConfig.boundsPollInterval, (timer) async {
    try {
      final hwnd = getSmallestFlutterWindow();
      if (hwnd == null) return;

      if (!isWindowValid(hwnd)) {
        timer.cancel();
        return;
      }

      if (enableNativeChrome) {
        ensureIslandFrameless();
      }

      final rect = getWindowRect();
      if (rect != null && boundsSaveEnabled && boundsSaveReady && !isDragging) {
        if (lastReportedBounds == null ||
            _boundsChanged(lastReportedBounds!, rect)) {
          lastReportedBounds = rect;
          if (needsSaveAfterDrag) needsSaveAfterDrag = false;
          await saveIslandBounds(IslandConfig.defaultIslandId, rect);
          StorageService.saveIslandBounds(IslandConfig.defaultIslandId, rect)
              .catchError((_) {});
          await appendIslandIpcLog(
            'island saved bounds left=${rect['left']} top=${rect['top']} width=${rect['width']} height=${rect['height']}',
          );
        }
      }
    } catch (_) {}
  });

  try {
    controller = await WindowController.fromCurrentEngine()
        .timeout(const Duration(milliseconds: 350));
    final windowController = controller;
    try {
      await windowController.invokeMethod('setFrame', {
        'width': IslandConfig.defaultWidth,
        'height': IslandConfig.defaultHeight,
      });
      await windowController.invokeMethod('setAlwaysOnTop', true);
    } catch (_) {}

    if (enableNativeChrome) {
      Timer(const Duration(milliseconds: 120), ensureIslandFrameless);
      Timer(const Duration(milliseconds: 500), ensureIslandFrameless);
      Timer(const Duration(milliseconds: 1200), ensureIslandFrameless);
    }

    if (enableNativeChrome) {
      initFfiTransparent();
    }

    debugPrint(
        '[Island] islandMain started for windowId=${windowController.windowId}');

    const globalChannel = MethodChannel('mixin.one/desktop_multi_window');
    globalChannel.setMethodCallHandler((call) async {
      final fromWindowId =
          (call.arguments is Map) ? call.arguments['windowId'] : 0;
      debugPrint('[Island] GLOBAL CALL: "${call.method}" from=$fromWindowId');

      if (call.method == 'postWindowMessage' || call.method == 'updateState') {
        try {
          final payload = _payloadFromRaw(call.arguments);
          if (payload != null) {
            _applyIncomingPayload(
              payload,
              payloadNotifier,
              controller,
              currentWindowId(),
            );
            await appendIslandIpcLog(
              'island applied global channel payload state=${payload['state']}',
            );
          }
        } catch (e) {
          debugPrint('[Island] Global handler parse error: $e');
          await appendIslandIpcLog('island global channel parse failed: $e');
        }
      }
      return null;
    });

    await windowController.setWindowMethodHandler((call) async {
      debugPrint('[Island] CALL: "${call.method}" | ${call.arguments}');
      try {
        if (call.method == 'postWindowMessage' ||
            call.method == 'updateState') {
          try {
            final payload = _payloadFromRaw(call.arguments);
            if (payload != null) {
              _applyIncomingPayload(
                payload,
                payloadNotifier,
                controller,
                currentWindowId(),
              );
              await appendIslandIpcLog(
                'island applied window channel payload state=${payload['state']}',
              );
            }
          } catch (e) {
            debugPrint('[Island] Failed to parse payload: $e');
            await appendIslandIpcLog('island window channel parse failed: $e');
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
      final def = await windowController
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
              Future.microtask(
                () => setWindowPosition(
                  left.toInt(),
                  top.toInt(),
                  width.toInt(),
                  height.toInt(),
                ),
              );
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

    final Set<String> acknowledgedReminders = {};
    String? lastShownReminderId;

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

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: IslandConfig.scaffoldBg,
      ),
      home: ExcludeSemantics(
        child: Scaffold(
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
                        final itemId = payloadNotifier
                            .value?['reminderPopupData']?['itemId']
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
                            'windowId': currentWindowId(),
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
                            'windowId': currentWindowId(),
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
                          final copiedLinkData =
                              currentPayload['copiedLinkData']
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
                            'windowId': currentWindowId(),
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
                            syncMode = (legacy['isLocal'] as bool)
                                ? 'local'
                                : 'remote';
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
                          'windowId': currentWindowId(),
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
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text('灵动岛已就绪 — 等待主程序数据',
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ), // Focus
        ),
      ),
    ));

    Future.microtask(() async {
      try {
        final file = await _getActionFile();
        await file.writeAsString(jsonEncode({
          'action': 'ready',
          'windowId': currentWindowId(),
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
      home: ExcludeSemantics(
        child: Scaffold(
          backgroundColor: IslandConfig.scaffoldBg,
          body: Focus(
            onKeyEvent: (node, event) => KeyEventResult.handled,
            child: Center(
              child: IslandUI(
                payloadNotifier: payloadNotifier,
                initialPayload: payloadNotifier.value,
              ),
            ),
          ),
        ),
      ),
    ));
  }
}
