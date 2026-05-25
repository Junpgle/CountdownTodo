import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';
import 'island_config.dart';

// ── Win32 Window Utilities ────────────────────────────────────────────────

/// Cached HWND for the island window
int? _islandHwndCache;

/// Clear the cached HWND (call on new window creation)
void clearIslandHwndCache() {
  _islandHwndCache = null;
}

/// Get the smallest Flutter window HWND owned by current process.
/// Returns null if not on Windows or no window found.
int? getSmallestFlutterWindow() {
  if (!Platform.isWindows) return null;
  final cached = _islandHwndCache;
  if (cached != null) {
    if (isWindowValid(cached)) return cached;
    _islandHwndCache = null;
  }

  try {
    final currentPid = GetCurrentProcessId();
    final foundHwnds = <int>[];
    final emptyTitleHwnds = <int>[];

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
            try {
              final titleLen = GetWindowTextLength(hwnd);
              if (titleLen == 0) {
                emptyTitleHwnds.add(hwnd);
              }
            } catch (_) {}
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

    final candidates =
        emptyTitleHwnds.isNotEmpty ? emptyTitleHwnds : foundHwnds;

    if (candidates.isNotEmpty) {
      int? bestHwnd;
      int minArea = 999999999;
      for (final h in candidates) {
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
    debugPrint('[IslandWin32] getSmallestFlutterWindow error: $e');
  }
  return null;
}

/// Get the DPI scale factor for a window
double getIslandScaleFactor(int hwnd) {
  try {
    final hdc = GetDC(hwnd);
    final dpi = GetDeviceCaps(hdc, 88); // LOGPIXELSX
    ReleaseDC(hwnd, hdc);
    if (dpi > 0) return dpi / 96.0;
  } catch (_) {}
  return 1.0;
}

/// Apply the island window chrome.
///
/// The island is repeatedly moved/resized after creation, so the topmost bit
/// must be restored together with the frameless/transparent styles.
void applyFramelessTransparent(int hwnd) {
  try {
    const wsCaption = 0x00C00000;
    const wsThickframe = 0x00040000;
    const wsSysmenu = 0x00080000;
    const wsMinimizebox = 0x00020000;
    const wsMaximizebox = 0x00010000;

    var style = GetWindowLongPtr(hwnd, GWL_STYLE);
    style &= ~wsCaption;
    style &= ~wsThickframe;
    style &= ~wsSysmenu;
    style &= ~wsMinimizebox;
    style &= ~wsMaximizebox;
    SetWindowLongPtr(hwnd, GWL_STYLE, style);

    var exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    exStyle |= WS_EX_LAYERED | WS_EX_TOPMOST;
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle);

    SetLayeredWindowAttributes(hwnd, 0, 0, LWA_COLORKEY);
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  } catch (e) {
    debugPrint('[IslandWin32] applyFramelessTransparent failed: $e');
  }
}

void ensureIslandFrameless() {
  final hwnd = getSmallestFlutterWindow();
  if (hwnd == null) return;
  _islandHwndCache = hwnd;
  applyFramelessTransparent(hwnd);
}

/// Initialize FFI: wait for HWND to appear and shrink, then apply transparency
Future<void> initFfiTransparent() async {
  for (int i = 0; i < IslandConfig.ffiMaxAttempts; i++) {
    final hwnd = getSmallestFlutterWindow();
    var matched = false;
    if (hwnd != null) {
      using((arena) {
        final rectPtr = arena<RECT>();
        if (GetWindowRect(hwnd, rectPtr) != 0) {
          final w = rectPtr.ref.right - rectPtr.ref.left;
          final hSize = rectPtr.ref.bottom - rectPtr.ref.top;

          if (w <= IslandConfig.detectionMaxWidth &&
              hSize <= IslandConfig.detectionMaxHeight) {
            debugPrint(
                '[IslandWin32] HWND found and shrunk on attempt $i: $hwnd (${w}x$hSize)');
            _islandHwndCache = hwnd;
            applyFramelessTransparent(hwnd);
            matched = true;
          }
        }
      });
      if (matched) {
        return;
      }
    }
    await Future.delayed(IslandConfig.ffiRetryInterval);
  }
  debugPrint(
      '[IslandWin32] WARNING: Valid shrunk HWND not found after ${IslandConfig.ffiMaxAttempts} attempts');
}

/// Resize the current island window
void resizeCurrentWindow(int targetW, int targetH) {
  final hwnd = getSmallestFlutterWindow();
  if (hwnd == null) return;

  try {
    final scale = getIslandScaleFactor(hwnd);
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
        applyFramelessTransparent(hwnd);
        SetWindowPos(hwnd, HWND_TOPMOST, newX, newY, physicalW, physicalH,
            SWP_NOACTIVATE | SWP_FRAMECHANGED);
      }
    });
  } catch (e) {
    debugPrint('[IslandWin32] resize failed: $e');
  }
}

/// Move the current island window
void moveCurrentWindow(int targetX, int targetY) {
  final hwnd = getSmallestFlutterWindow();
  if (hwnd == null) return;

  try {
    final scale = getIslandScaleFactor(hwnd);
    final int physicalX = (targetX * scale).ceil();
    final int physicalY = (targetY * scale).ceil();

    using((arena) {
      final rectPtr = arena<RECT>();
      if (GetWindowRect(hwnd, rectPtr) != 0) {
        final curW = rectPtr.ref.right - rectPtr.ref.left;
        final curH = rectPtr.ref.bottom - rectPtr.ref.top;

        applyFramelessTransparent(hwnd);
        SetWindowPos(hwnd, HWND_TOPMOST, physicalX, physicalY, curW, curH,
            SWP_NOACTIVATE | SWP_NOSIZE | SWP_FRAMECHANGED);
      }
    });
  } catch (e) {
    debugPrint('[IslandWin32] move failed: $e');
  }
}

/// Get current window rect as a map
Map<String, double>? getWindowRect() {
  try {
    final hwnd = getSmallestFlutterWindow();
    if (hwnd != null) {
      RECT? result;
      using((arena) {
        final rectPtr = arena<RECT>();
        if (GetWindowRect(hwnd, rectPtr) != 0) {
          result = rectPtr.ref;
        }
      });
      if (result != null) {
        return {
          'left': result!.left.toDouble(),
          'top': result!.top.toDouble(),
          'right': result!.right.toDouble(),
          'bottom': result!.bottom.toDouble(),
          'width': (result!.right - result!.left).toDouble(),
          'height': (result!.bottom - result!.top).toDouble(),
        };
      }
    }
  } catch (e) {
    debugPrint('[IslandWin32] getWindowRect error: $e');
  }
  return null;
}

/// Start window dragging using Win32 API
void startWindowDragging() {
  try {
    final hwnd = getSmallestFlutterWindow();
    if (hwnd != null) {
      const int wmNclbuttondown = 0x00A1;
      const int htCaption = 2;
      ReleaseCapture();
      PostMessage(hwnd, wmNclbuttondown, htCaption, 0);
    }
  } catch (e) {
    debugPrint('[IslandWin32] startWindowDragging error: $e');
  }
}

/// Set window position and size
void setWindowPosition(int left, int top, int width, int height) {
  try {
    final hwnd = getSmallestFlutterWindow();
    if (hwnd != null) {
      using((arena) {
        final rectPtr = arena<RECT>();
        rectPtr.ref.left = left;
        rectPtr.ref.top = top;
        rectPtr.ref.right = left + width;
        rectPtr.ref.bottom = top + height;
        applyFramelessTransparent(hwnd);
        SetWindowPos(
            hwnd,
            HWND_TOPMOST,
            rectPtr.ref.left,
            rectPtr.ref.top,
            rectPtr.ref.right - rectPtr.ref.left,
            rectPtr.ref.bottom - rectPtr.ref.top,
            SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
      });
    }
  } catch (e) {
    debugPrint('[IslandWin32] setWindowPosition error: $e');
  }
}

/// Check if window is still valid
bool isWindowValid(int hwnd) {
  return IsWindow(hwnd) != 0;
}
