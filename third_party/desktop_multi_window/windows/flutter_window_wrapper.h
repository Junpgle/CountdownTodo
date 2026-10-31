#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_

#include <Windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <memory>
#include <string>

constexpr UINT kStartWindowDraggingMessage = WM_APP + 0x351;

class FlutterWindowWrapper {
 public:
  FlutterWindowWrapper(const std::string& window_id,
                       HWND hwnd,
                       const std::string& window_argument = "")
      : window_id_(window_id), hwnd_(hwnd), window_argument_(window_argument) {}

  ~FlutterWindowWrapper() = default;

  std::string GetWindowId() const { return window_id_; }

  std::string GetWindowArgument() const { return window_argument_; }

  HWND GetWindowHandle() { return hwnd_; }

  void SetChannel(
      std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
          channel) {
    channel_ = channel;
  }

  void NotifyWindowEvent(const std::string& event,
                         const flutter::EncodableMap& data) {
    if (channel_) {
      channel_->InvokeMethod(event,
                             std::make_unique<flutter::EncodableValue>(data));
    }
  }

  void HandleWindowMethod(
      const std::string& method,
      const flutter::EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (method == "window_show") {
      if (hwnd_) {
        ::ShowWindow(hwnd_, SW_SHOW);
      }
      result->Success();
    } else if (method == "window_hide") {
      if (hwnd_) {
        ::ShowWindow(hwnd_, SW_HIDE);
      }
      result->Success();
    } else if (method == "window_startDragging") {
      if (!hwnd_ || !::IsWindow(hwnd_)) {
        result->Error("-1", "failed to find target window");
        return;
      }

      POINT cursor_position{};
      if (!::GetCursorPos(&cursor_position)) {
        result->Error("-1", "failed to read cursor position");
        return;
      }

      // Let the target HWND's own message thread release capture and begin
      // the caption drag. ReleaseCapture is thread scoped, so doing it in the
      // Dart UI isolate can leave Flutter's mouse capture in place.
      const LPARAM cursor_coordinates =
          MAKELPARAM(cursor_position.x, cursor_position.y);
      if (!::PostMessage(hwnd_, kStartWindowDraggingMessage, 0,
                         cursor_coordinates)) {
        result->Error("-1", "failed to post window drag request");
        return;
      }
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("-1", "unknown method: " + method);
    }
  }

 protected:
  void SetWindowHandle(HWND hwnd) { hwnd_ = hwnd; }

 private:
  std::string window_id_;
  HWND hwnd_;
  std::string window_argument_;
  std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_
