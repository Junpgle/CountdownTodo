// Island window entrypoint for desktop_multi_window
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' hide window; // For Rect
import 'dart:ffi' hide Size;
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' hide Size;
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'island_ui.dart';
import 'island_payload.dart';
import '../storage_service.dart';
import '../services/course_service.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

// ── DWM API Bindings ──────────────────────────────────────────────────────
final _dwmapi = DynamicLibrary.open('dwmapi.dll');

final class MARGINS extends Struct {
  @Int32()
  external int cxLeftWidth;
  @Int32()
  external int cxRightWidth;
  @Int32()
  external int cyTopHeight;
  @Int32()
  external int cyBottomHeight;
}

final class DWM_BLURBEHIND extends Struct {
  @Uint32()
  external int dwFlags;
  @Int32()
  external int fEnable;
  external Pointer<IntPtr> hRgnBlur;
  @Int32()
  external int fTransitionOnMaximized;
}

const int DWM_BB_ENABLE = 0x00000001;
const int TRUE = 1;

/// Entry point for the lightweight Windows Island process.
Future<File> _getActionFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/island_action.json');
}

/// 后台轮询等待 HWND 出现并缩小后，应用透明设置
Future<void> _initFfi() async {
  for (int i = 0; i < 100; i++) {
    final hwnd = _getSmallestFlutterWindow();
    if (hwnd != null) {
      using((arena) {
        final rectPtr = arena<RECT>();
        if (GetWindowRect(hwnd, rectPtr) != 0) {
          final w = rectPtr.ref.right - rectPtr.ref.left;
          final hSize = rectPtr.ref.bottom - rectPtr.ref.top;

          // 只有当窗口切实被 Flutter 缩小后，才将其锁定为灵动岛并透明化。
          // 这完美避开了把主程序变透明的风险。
          if (w <= 800 && hSize <= 600) {
            debugPrint(
                '[Island] HWND found and shrunk on attempt $i: $hwnd (${w}x${hSize})');
            _islandHwndCache = hwnd;
            _applyWin32FramelessTransparentImpl(hwnd);
            return;
          }
        }
      });
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
  debugPrint(
      '[Island] WARNING: Valid shrunk HWND not found after 100 attempts');
}

/// 检查未来20分钟内的提醒事项
Future<Map<String, dynamic>?> _checkUpcomingReminder() async {
  final username = await StorageService.getLoginSession() ?? 'default';
  final now = DateTime.now();
  final allReminders = <Map<String, dynamic>>[];

  debugPrint('[Island] 检查提醒: username=$username, now=$now');

  // 检查待办
  try {
    final todos = await StorageService.getTodos(username);
    debugPrint('[Island] 获取到 ${todos.length} 个待办');
    for (final t
        in todos.where((t) => !t.isDone && !t.isDeleted && t.dueDate != null)) {
      // 计算开始时间
      DateTime? startTime;
      if (t.createdDate != null) {
        startTime =
            DateTime.fromMillisecondsSinceEpoch(t.createdDate!, isUtc: true)
                .toLocal();
      } else {
        startTime =
            DateTime.fromMillisecondsSinceEpoch(t.createdAt, isUtc: true)
                .toLocal();
      }

      // 创建今日的开始时间
      final todayStartTime = DateTime(
          now.year, now.month, now.day, startTime.hour, startTime.minute);

      // 检查开始时间是否在20分钟内
      final startDiff = todayStartTime.difference(now).inMinutes;
      if (startDiff >= 0 && startDiff <= 20) {
        allReminders.add({
          'type': 'todo',
          'title': t.title,
          'subtitle': t.remark ?? '',
          'startTime':
              '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
          'endTime':
              '${t.dueDate!.hour.toString().padLeft(2, '0')}:${t.dueDate!.minute.toString().padLeft(2, '0')}',
          'minutesUntil': startDiff,
          'isEnding': false,
          'itemId': t.id,
        });
        debugPrint('[Island] 找到待办提醒(开始): ${t.title}, 还有 $startDiff 分钟开始');
        continue;
      }

      // 检查结束时间是否在20分钟内
      final endDiff = t.dueDate!.difference(now).inMinutes;
      if (endDiff >= 0 && endDiff <= 20) {
        allReminders.add({
          'type': 'todo',
          'title': t.title,
          'subtitle': t.remark ?? '',
          'startTime':
              '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
          'endTime':
              '${t.dueDate!.hour.toString().padLeft(2, '0')}:${t.dueDate!.minute.toString().padLeft(2, '0')}',
          'minutesUntil': endDiff,
          'isEnding': true,
          'itemId': t.id,
        });
        debugPrint('[Island] 找到待办提醒(结束): ${t.title}, 还有 $endDiff 分钟结束');
      }
    }
  } catch (e) {
    debugPrint('[Island] 检查待办失败: $e');
  }

  // 检查课程
  try {
    final courses = await CourseService.getAllCourses();
    debugPrint('[Island] 获取到 ${courses.length} 个课程');
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    debugPrint('[Island] 今日日期: $todayStr');
    for (final c in courses.where((c) => c.date == todayStr)) {
      debugPrint('[Island] 检查课程: ${c.courseName}, startTime=${c.startTime}');
      final startHour = c.startTime ~/ 100;
      final startMin = c.startTime % 100;
      final courseStart =
          DateTime(now.year, now.month, now.day, startHour, startMin);
      final diff = courseStart.difference(now).inMinutes;
      debugPrint('[Island] 课程开始时间: $courseStart, 还有 $diff 分钟');
      if (diff >= 0 && diff <= 20) {
        allReminders.add({
          'type': 'course',
          'title': c.courseName,
          'subtitle': c.roomName,
          'startTime': c.formattedStartTime,
          'endTime': c.formattedEndTime,
          'minutesUntil': diff,
          'isEnding': false,
          'itemId': '${c.date}_${c.startTime}',
        });
      }
    }
  } catch (e) {
    debugPrint('[Island] 检查课程失败: $e');
  }

  debugPrint('[Island] 找到 ${allReminders.length} 个提醒');
  if (allReminders.isEmpty) return null;

  // 按时间排序，最近的先弹
  allReminders.sort(
      (a, b) => (a['minutesUntil'] as int).compareTo(b['minutesUntil'] as int));
  debugPrint('[Island] 返回最近的提醒: ${allReminders.first}');
  return allReminders.first;
}

@pragma('vm:entry-point')
Future<void> islandMain(List<String> args) async {
  // 🚀 重置 HWND 缓存，确保每次新窗口启动时都能正确获取窗口句柄
  _islandHwndCache = null;

  // 🚀 终极修复 1：必须在最外层直接调用 ensureInitialized
  WidgetsFlutterBinding.ensureInitialized();

  // 🚀 终极修复 2：彻底废除 runZonedGuarded，改用 PlatformDispatcher。
  // 这完美解决了 Zone mismatch 崩溃，让 runApp 能顺利渲染出纯黑背景供 FFI 抠图！
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[Island] Unhandled error in island isolate: $error\n$stack');
    return true;
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[Island] FlutterError: ${details.exceptionAsString()}');
  };

  final ValueNotifier<Map<String, dynamic>?> payloadNotifier =
      ValueNotifier(IslandPayload.fromMap(null).toMap());

  Map<String, dynamic>? lastReportedBounds;
  bool _boundsSaveEnabled = false;
  bool _boundsSaveReady = false;
  bool _isDragging = false;
  bool _needsSaveAfterDrag = false;

  Future<void> _restoreWindowPosition() async {
    try {
      final bounds = await StorageService.getIslandBounds('island-1');
      if (bounds != null && bounds.isNotEmpty) {
        final left = (bounds['left'] as num?)?.toDouble();
        final top = (bounds['top'] as num?)?.toDouble();
        final width = (bounds['width'] as num?)?.toDouble() ?? 160.0;
        final height = (bounds['height'] as num?)?.toDouble() ?? 56.0;

        if (left != null && top != null) {
          final hwnd = _getSmallestFlutterWindow();
          if (hwnd != null) {
            using((arena) {
              final rectPtr = arena<RECT>();
              rectPtr.ref.left = left.toInt();
              rectPtr.ref.top = top.toInt();
              rectPtr.ref.right = (left + width).toInt();
              rectPtr.ref.bottom = (top + height).toInt();
              SetWindowPos(
                  hwnd,
                  0,
                  rectPtr.ref.left,
                  rectPtr.ref.top,
                  rectPtr.ref.right - rectPtr.ref.left,
                  rectPtr.ref.bottom - rectPtr.ref.top,
                  0x0041);
            });
            debugPrint('[Island] Win32 API 恢复窗口位置: left=$left, top=$top');
          }
        }
      }
    } catch (e) {
      debugPrint('[Island] 恢复窗口位置失败: $e');
    }
  }

  try {
    final controller = await WindowController.fromCurrentEngine();
    try {
      // 只设置大小，不设置位置，避免覆盖保存的位置
      await controller
          .invokeMethod('setFrame', {'width': 160.0, 'height': 56.0});
      await controller.invokeMethod('setAlwaysOnTop', true);
    } catch (_) {}

    // 延迟恢复窗口位置，确保窗口已完全初始化
    Future.delayed(const Duration(milliseconds: 500), () {
      _restoreWindowPosition();
    });

    // 后台轮询，绝不阻塞 runApp 渲染
    _initFfi();

    debugPrint(
        '[Island] islandMain started for windowId=${controller.windowId} args=$args');

    const globalChannel = MethodChannel('mixin.one/desktop_multi_window');
    globalChannel.setMethodCallHandler((call) async {
      final fromWindowId =
          (call.arguments is Map) ? call.arguments['windowId'] : 0;
      debugPrint(
          '[Island] >>> GLOBAL CALL: "${call.method}" from=$fromWindowId args=${call.arguments}');

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
              final rawMap = Map<String, dynamic>.from(m);
              final dynamic mmRaw =
                  rawMap.containsKey('payload') ? rawMap['payload'] : rawMap;
              if (mmRaw is! Map) return;

              final mm = Map<String, dynamic>.from(mmRaw);
              if (mm['handshake'] == 'ping') {
                controller.invokeMethod('onAction', {
                  'action': 'handshake_pong',
                  'windowId': controller.windowId
                }).catchError((_) {});
                debugPrint('[Island] responded handshake_pong to host');
              }
              if (mm.containsKey('legacy') && mm['legacy'] is Map) {
                payloadNotifier.value = Map<String, dynamic>.from(mm['legacy']);
              } else if (mm.containsKey('focusData') ||
                  mm.containsKey('state')) {
                try {
                  final structured = Map<String, dynamic>.from(mm);
                  payloadNotifier.value = structured;
                } catch (e) {
                  debugPrint(
                      '[Island] failed to apply structured payload directly: $e');
                }
              } else {
                try {
                  final dto = IslandPayload.fromMap(mm);
                  payloadNotifier.value = dto.toMap();
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
            final hwnd = _getSmallestFlutterWindow();
            if (hwnd != null) {
              const int WM_NCLBUTTONDOWN = 0x00A1;
              const int HTCAPTION = 2;
              ReleaseCapture();
              PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
              _isDragging = true;
              _needsSaveAfterDrag = true;
              Timer(const Duration(milliseconds: 500), () {
                _isDragging = false;
              });
            }
          } catch (e) {}
        }

        if (call.method == 'setWindowSize') {
          final a = call.arguments as Map?;
          if (a != null) {
            final w = (a['width'] as num?)?.toInt() ?? 160;
            final h = (a['height'] as num?)?.toInt() ?? 56;
            Future.microtask(() => _resizeCurrentWindow(w, h));
          }
        }
      } catch (e) {}
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
            debugPrint(
                '[Island] 读取到 initialBounds: left=$left, top=$top, width=$width, height=$height');
            if (width is num && height is num && left is num && top is num) {
              Future.microtask(() async {
                for (int i = 0; i < 20; i++) {
                  final hw = _getSmallestFlutterWindow();
                  if (hw != null) {
                    final scale = _getIslandScaleFactor(hw);
                    final phyW = (width * scale).ceil();
                    final phyH = (height * scale).ceil();
                    final phyLeft = (left * scale).toInt();
                    final phyTop = (top * scale).toInt();
                    debugPrint(
                        '[Island] 设置窗口位置: phyLeft=$phyLeft, phyTop=$phyTop, phyW=$phyW, phyH=$phyH, scale=$scale');
                    const int HWND_TOPMOST = -1;
                    const int SWP_NOACTIVATE = 0x0010;
                    final result = SetWindowPos(hw, HWND_TOPMOST, phyLeft,
                        phyTop, phyW, phyH, SWP_NOACTIVATE);
                    debugPrint('[Island] SetWindowPos result: $result');
                    break;
                  }
                  await Future.delayed(const Duration(milliseconds: 100));
                }
              });
            }
          }
        } catch (e) {
          debugPrint('[Island] 位置恢复失败: $e');
        }
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

    // 提醒弹出相关变量
    Timer? _reminderCheckTimer;
    final Set<String> _acknowledgedReminders = {};
    String? _lastShownReminderId;
    String? _stateBeforeReminder;

    // 延迟 3 秒后再启用位置保存，确保窗口已完全初始化
    Timer(const Duration(seconds: 3), () {
      _boundsSaveEnabled = true;
      debugPrint('[Island] 位置保存已启用');
      // 再延迟 2 秒后允许保存，确保窗口位置稳定
      Timer(const Duration(seconds: 2), () {
        _boundsSaveReady = true;
        debugPrint('[Island] 位置保存已就绪');
      });
    });

    boundsPollingTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final hwnd = _getSmallestFlutterWindow();
        if (hwnd == null) return;

        // Isolate 生命周期检查（可选）：如果窗口已失效，直接自毁计时器
        if (IsWindow(hwnd) == 0) {
          timer.cancel();
          return;
        }

        using((arena) {
          final rectPtr = arena<RECT>();
          if (GetWindowRect(hwnd, rectPtr) != 0) {
            final curX = rectPtr.ref.left;
            final curY = rectPtr.ref.top;
            final curW = rectPtr.ref.right - rectPtr.ref.left;
            final curH = rectPtr.ref.bottom - rectPtr.ref.top;

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

            final lastLeft = lastReportedBounds?['left'] as double?;
            final lastTop = lastReportedBounds?['top'] as double?;
            if (_boundsSaveEnabled &&
                _boundsSaveReady &&
                !_isDragging &&
                (lastReportedBounds == null ||
                    lastLeft == null ||
                    lastTop == null ||
                    (lastLeft - logicalX).abs() > 1.0 ||
                    (lastTop - logicalY).abs() > 1.0)) {
              lastReportedBounds = currentBounds;
              if (_needsSaveAfterDrag) {
                _needsSaveAfterDrag = false;
                debugPrint('[Island] 拖拽后保存窗口位置: $currentBounds');
                StorageService.saveIslandBounds('island-1', currentBounds)
                    .catchError((_) {});
              }
            }
          }
        });
      } catch (_) {}
    });

    // 提醒检查定时器：每分钟检查一次未来20分钟内的提醒
    debugPrint('[Island] 启动提醒检查定时器');
    _reminderCheckTimer =
        Timer.periodic(const Duration(minutes: 1), (timer) async {
      debugPrint('[Island] 提醒检查定时器触发');
      try {
        final reminder = await _checkUpcomingReminder();
        debugPrint('[Island] 检查提醒结果: $reminder');
        if (reminder != null) {
          final itemId = reminder['itemId']?.toString();
          if (itemId != null &&
              _lastShownReminderId != itemId &&
              !_acknowledgedReminders.contains(itemId)) {
            _lastShownReminderId = itemId;
            // 保存当前状态以便恢复
            final currentState =
                payloadNotifier.value?['state']?.toString() ?? 'idle';
            _stateBeforeReminder =
                currentState == 'focusing' ? 'focusing' : 'idle';
            // 发送 reminder_popup 状态
            final currentPayload = payloadNotifier.value ?? {};
            payloadNotifier.value = {
              ...currentPayload,
              'state': 'reminder_popup',
              'reminderPopupData': reminder,
            };
            debugPrint('[Island] 触发提醒弹出: $itemId');
          } else {
            debugPrint(
                '[Island] 提醒已显示或已确认: itemId=$itemId, lastShown=$_lastShownReminderId, acknowledged=$_acknowledgedReminders');
          }
        } else {
          debugPrint('[Island] 未找到未来20分钟内的提醒');
        }
      } catch (e) {
        debugPrint('[Island] 检查提醒失败: $e');
      }
    });

    // 立即检查一次提醒
    Timer(const Duration(seconds: 5), () async {
      debugPrint('[Island] 立即检查提醒');
      try {
        final reminder = await _checkUpcomingReminder();
        debugPrint('[Island] 立即检查结果: $reminder');
        if (reminder != null) {
          final itemId = reminder['itemId']?.toString();
          if (itemId != null &&
              _lastShownReminderId != itemId &&
              !_acknowledgedReminders.contains(itemId)) {
            _lastShownReminderId = itemId;
            final currentState =
                payloadNotifier.value?['state']?.toString() ?? 'idle';
            _stateBeforeReminder =
                currentState == 'focusing' ? 'focusing' : 'idle';
            final currentPayload = payloadNotifier.value ?? {};
            payloadNotifier.value = {
              ...currentPayload,
              'state': 'reminder_popup',
              'reminderPopupData': reminder,
            };
            debugPrint('[Island] 立即触发提醒弹出: $itemId');
          }
        }
      } catch (e) {
        debugPrint('[Island] 立即检查提醒失败: $e');
      }
    });

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF000000),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Stack(
          alignment: Alignment.topCenter,
          children: [
            IslandUI(
              payloadNotifier: payloadNotifier,
              initialPayload: payloadNotifier.value,
              onAction: (action, [modifiedSecs]) async {
                try {
                  // 处理提醒相关 action
                  if (action == 'reminder_ok') {
                    // 记录已确认的提醒 ID
                    final itemId = payloadNotifier.value?['reminderPopupData']
                            ?['itemId']
                        ?.toString();
                    if (itemId != null) {
                      _acknowledgedReminders.add(itemId);
                    }
                    // 恢复之前的状态
                    final prevState = _stateBeforeReminder ?? 'idle';
                    _stateBeforeReminder = null;
                    payloadNotifier.value = {
                      ...payloadNotifier.value ?? {},
                      'state': prevState,
                    };
                    // 写入 action 文件通知主应用
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
                    // 恢复之前的状态
                    final prevState = _stateBeforeReminder ?? 'idle';
                    _stateBeforeReminder = null;
                    payloadNotifier.value = {
                      ...payloadNotifier.value ?? {},
                      'state': prevState,
                    };
                    // 写入 action 文件通知主应用打开稍后提醒选择框
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
                      final fd = current['focusData'] as Map<String, dynamic>?;
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        scaffoldBackgroundColor: const Color(0xFF000000),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Center(child: IslandUI(initialPayload: payloadNotifier.value)),
      ),
    ));
  }
}

// Caches the correct island window handle to avoid expensive re-evaluations
int? _islandHwndCache;

/// 获取最小的 Flutter 窗口，但不做大于 800 的强制过滤。
/// 这样一来即使最初是 1200x900，也可以被捕获并正常执行 resize 缩小。
int? _getSmallestFlutterWindow() {
  if (_islandHwndCache != null) return _islandHwndCache;
  if (!Platform.isWindows) return null;
  try {
    final currentPid = GetCurrentProcessId();
    final foundHwnds = <int>[];

    final lpEnumFunc =
        NativeCallable<WNDENUMPROC>.isolateLocal((int hwnd, int lParam) {
      using((arena) {
        final pidPtr = arena<Uint32>();
        GetWindowThreadProcessId(hwnd, pidPtr);
        final pid = pidPtr.value;

        if (pid == currentPid && IsWindowVisible(hwnd) != 0) {
          bool isIgnored = false;
          try {
            final classNamePtr = arena<Uint16>(256).cast<Utf16>();
            GetClassName(hwnd, classNamePtr, 256);
            final className = classNamePtr.toDartString();

            final lowerClass = className.toLowerCase();

            if (!lowerClass.contains('flutter') &&
                className != 'Window Class') {
              isIgnored = true;
            }
            if (lowerClass.contains('ime') || lowerClass.contains('sogou')) {
              isIgnored = true;
            }
          } catch (_) {
            isIgnored = true;
          }

          if (!isIgnored) {
            foundHwnds.add(hwnd);
          }
        }
      });
      return 1;
    }, exceptionalReturn: 0);

    try {
      EnumWindows(lpEnumFunc.nativeFunction, 0);
    } finally {
      lpEnumFunc.close();
    }

    if (foundHwnds.isNotEmpty) {
      int? bestHwnd;
      int minArea = 999999999;
      for (final h in foundHwnds) {
        using((arena) {
          final rectPtr = arena<RECT>();
          if (GetWindowRect(h, rectPtr) != 0) {
            final w = rectPtr.ref.right - rectPtr.ref.left;
            final hSize = rectPtr.ref.bottom - rectPtr.ref.top;
            final area = w * hSize;

            if (area > 0 && area < minArea) {
              minArea = area;
              bestHwnd = h;
            }
          }
        });
      }
      return bestHwnd;
    }
  } catch (e) {
    debugPrint('[Island] _getSmallestFlutterWindow error: $e');
  }
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
  } catch (e) {
    debugPrint('[Island] FFI failed: $e');
  }
}

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
  final hwnd = _getSmallestFlutterWindow();
  if (hwnd == null) return;
  try {
    final scale = _getIslandScaleFactor(hwnd);
    final int physicalW = (targetW * scale).ceil();
    final int physicalH = (targetH * scale).ceil();

    using((arena) {
      final rectPtr = arena<RECT>();
      if (GetWindowRect(hwnd, rectPtr) != 0) {
        final curX = rectPtr.ref.left;
        final curY = rectPtr.ref.top;
        final curW = rectPtr.ref.right - rectPtr.ref.left;

        int newX = curX;
        int newY = curY;
        if (curW > 0 && curW != physicalW) {
          newX = curX - ((physicalW - curW) ~/ 2);
        }
        const int HWND_TOPMOST = -1;
        const int SWP_NOACTIVATE = 0x0010;

        SetWindowPos(hwnd, HWND_TOPMOST, newX, newY, physicalW, physicalH,
            SWP_NOACTIVATE);
      }
    });
  } catch (e) {
    debugPrint('[Island] resize failed: $e');
  }
}
