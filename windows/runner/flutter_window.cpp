#include "flutter_window.h"

#include <windows.h>
#include <optional>
#include <string>
#include <vector>

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include "flutter/generated_plugin_registrant.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
        : project_(project) {}

FlutterWindow::~FlutterWindow() {}

namespace {
constexpr ULONG_PTR kDeepLinkCopyData = 0x43445444;  // CDTD

void ConfigureFloatingIslandWindow(flutter::FlutterViewController *controller) {
    if (controller == nullptr || controller->view() == nullptr) {
        return;
    }

    HWND content = controller->view()->GetNativeWindow();
    HWND window = GetAncestor(content, GA_ROOT);
    if (window == nullptr) {
        return;
    }

    LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
    style &= ~WS_CAPTION;
    style &= ~WS_THICKFRAME;
    style &= ~WS_SYSMENU;
    style &= ~WS_MINIMIZEBOX;
    style &= ~WS_MAXIMIZEBOX;
    SetWindowLongPtr(window, GWL_STYLE, style);

    LONG_PTR ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
    ex_style |= WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED;
    ex_style &= ~WS_EX_APPWINDOW;
    SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);

    SetLayeredWindowAttributes(window, RGB(0, 0, 0), 0, LWA_COLORKEY);

    SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                 SWP_FRAMECHANGED);
}
}

bool FlutterWindow::OnCreate() {
    if (!Win32Window::OnCreate()) {
        return false;
    }

    RECT frame = GetClientArea();

    flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
            frame.right - frame.left, frame.bottom - frame.top, project_);

    if (!flutter_controller_->engine() || !flutter_controller_->view()) {
        return false;
    }

    RegisterPlugins(flutter_controller_->engine());
    deep_link_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            flutter_controller_->engine()->messenger(),
            "com.math_quiz_app/deep_links",
            &flutter::StandardMethodCodec::GetInstance());
    DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
        auto *flutter_view_controller =
                reinterpret_cast<flutter::FlutterViewController *>(controller);
        ConfigureFloatingIslandWindow(flutter_view_controller);
        auto *registry = flutter_view_controller->engine();
        RegisterPlugins(registry);
    });


    SetChildContent(flutter_controller_->view()->GetNativeWindow());

    flutter_controller_->engine()->SetNextFrameCallback([&]() {
        this->Show();
    });

    flutter_controller_->ForceRedraw();

    return true;
}

void FlutterWindow::OnDestroy() {

    deep_link_channel_.reset();

    if (flutter_controller_) {
        flutter_controller_ = nullptr;
    }

    Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
if (flutter_controller_) {
std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
if (result) {
return *result;
}
}

switch (message) {
case WM_COPYDATA: {
const auto* copy_data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
if (copy_data != nullptr && copy_data->dwData == kDeepLinkCopyData &&
copy_data->lpData != nullptr && copy_data->cbData > 0) {
std::string link(static_cast<const char*>(copy_data->lpData),
                 copy_data->cbData);
if (!link.empty() && link.back() == '\0') {
link.pop_back();
}
if (deep_link_channel_ && !link.empty()) {
deep_link_channel_->InvokeMethod(
    "openDeepLink", std::make_unique<flutter::EncodableValue>(link));
}
return TRUE;
}
break;
}
case WM_FONTCHANGE:
flutter_controller_->engine()->ReloadSystemFonts();
break;
}

return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
