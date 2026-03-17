#include "flutter_window.h"
#include "float_window.h"

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
        : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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

    float_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            flutter_controller_->engine()->messenger(),
                    "com.math_quiz_app/float_window",
                    &flutter::StandardMethodCodec::GetInstance()
    );

    float_channel_->SetMethodCallHandler(
            [](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

                if (call.method_name() == "showFloat") {
                    auto& args = std::get<flutter::EncodableMap>(*call.arguments());

                    long long endMs = std::get<int64_t>(args.at(flutter::EncodableValue("endMs")));

                    std::string titleUtf8 = std::get<std::string>(args.at(flutter::EncodableValue("title")));


                    OutputDebugStringA(("[FloatWindow] title utf8 = " + titleUtf8 + "\n").c_str());

                    int wlen = MultiByteToWideChar(CP_UTF8, 0, titleUtf8.c_str(), (int)titleUtf8.length(), nullptr, 0);
                    std::wstring title(wlen, 0);
                    if (wlen > 0) {
                        MultiByteToWideChar(CP_UTF8, 0, titleUtf8.c_str(), (int)titleUtf8.length(), &title[0], wlen);
                    }

                    std::vector<std::wstring> tags;
                    auto& tagList = std::get<flutter::EncodableList>(args.at(flutter::EncodableValue("tags")));


                    OutputDebugStringA(("[FloatWindow] tags count = " + std::to_string(tagList.size()) + "\n").c_str());

                    for (auto& t : tagList) {
                        std::string tagUtf8 = std::get<std::string>(t);
                        int wl = MultiByteToWideChar(CP_UTF8, 0, tagUtf8.c_str(), (int)tagUtf8.length(), nullptr, 0);
                        std::wstring wt(wl, 0);
                        if (wl > 0) {
                            MultiByteToWideChar(CP_UTF8, 0, tagUtf8.c_str(), (int)tagUtf8.length(), &wt[0], wl);
                        }
                        tags.push_back(wt);
                    }

                    int mode = 0;
                    auto modeIt = args.find(flutter::EncodableValue("mode"));
                    if (modeIt != args.end()) {
                        if (std::holds_alternative<int32_t>(modeIt->second)) {
                            mode = std::get<int32_t>(modeIt->second);
                        } else if (std::holds_alternative<int64_t>(modeIt->second)) {
                            mode = (int)std::get<int64_t>(modeIt->second);
                        }
                    }

                    bool isLocal = false;
                    auto isLocalIt = args.find(flutter::EncodableValue("isLocal"));
                    if (isLocalIt != args.end()) {
                        isLocal = std::get<bool>(isLocalIt->second);
                    }

                    FloatWindow::instance().Show(endMs, title, tags, isLocal, mode);
                    result->Success();
                } else if (call.method_name() == "hideFloat") {
                    FloatWindow::instance().Hide();
                    result->Success();

                } else {
                    result->NotImplemented();
                }
            }
    );

    SetChildContent(flutter_controller_->view()->GetNativeWindow());

    flutter_controller_->engine()->SetNextFrameCallback([&]() {
        this->Show();
    });

    flutter_controller_->ForceRedraw();

    return true;
}

void FlutterWindow::OnDestroy() {
    FloatWindow::instance().Hide();

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
case WM_FONTCHANGE:
flutter_controller_->engine()->ReloadSystemFonts();
break;
}

return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}