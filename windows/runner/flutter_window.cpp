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
                try {
                    if (call.method_name() == "showFloat") {
                        // Validate arguments
                        const flutter::EncodableValue* argsVal = call.arguments();
                        if (!argsVal || !std::holds_alternative<flutter::EncodableMap>(*argsVal)) {
                            OutputDebugStringA("[FloatWindow] showFloat called with invalid or missing arguments\n");
                            result->Error("invalid_args", "Expected map arguments for showFloat");
                            return;
                        }
                        auto args = std::get<flutter::EncodableMap>(*argsVal);

                        long long endMs = 0;
                        auto endIt = args.find(flutter::EncodableValue("endMs"));
                        if (endIt != args.end()) {
                            const auto& v = endIt->second;
                            if (std::holds_alternative<int64_t>(v)) endMs = std::get<int64_t>(v);
                            else if (std::holds_alternative<int32_t>(v)) endMs = std::get<int32_t>(v);
                            else if (std::holds_alternative<double>(v)) endMs = (long long)std::get<double>(v);
                            else {
                                OutputDebugStringA("[FloatWindow] endMs has unexpected type, using 0\n");
                            }
                        }

                        std::string titleUtf8;
                        auto titleIt = args.find(flutter::EncodableValue("title"));
                        if (titleIt != args.end() && std::holds_alternative<std::string>(titleIt->second)) {
                            titleUtf8 = std::get<std::string>(titleIt->second);
                        }

                        OutputDebugStringA((std::string("[FloatWindow] title utf8 = ") + titleUtf8 + "\n").c_str());

                        std::wstring title;
                        if (!titleUtf8.empty()) {
                            int wlen = MultiByteToWideChar(CP_UTF8, 0, titleUtf8.c_str(), (int)titleUtf8.length(), nullptr, 0);
                            title.assign(wlen, L'\0');
                            if (wlen > 0) {
                                MultiByteToWideChar(CP_UTF8, 0, titleUtf8.c_str(), (int)titleUtf8.length(), &title[0], wlen);
                            }
                        }

                        std::vector<std::wstring> tags;
                        auto tagsIt = args.find(flutter::EncodableValue("tags"));
                        if (tagsIt != args.end() && std::holds_alternative<flutter::EncodableList>(tagsIt->second)) {
                            auto tagList = std::get<flutter::EncodableList>(tagsIt->second);
                            OutputDebugStringA((std::string("[FloatWindow] tags count = ") + std::to_string(tagList.size()) + "\n").c_str());
                            for (auto& t : tagList) {
                                if (std::holds_alternative<std::string>(t)) {
                                    std::string tagUtf8 = std::get<std::string>(t);
                                    int wl = MultiByteToWideChar(CP_UTF8, 0, tagUtf8.c_str(), (int)tagUtf8.length(), nullptr, 0);
                                    std::wstring wt(wl, L'\0');
                                    if (wl > 0) {
                                        MultiByteToWideChar(CP_UTF8, 0, tagUtf8.c_str(), (int)tagUtf8.length(), &wt[0], wl);
                                    }
                                    tags.push_back(wt);
                                }
                            }
                        }

                        int mode = 0;
                        auto modeIt = args.find(flutter::EncodableValue("mode"));
                        if (modeIt != args.end()) {
                            const auto& mv = modeIt->second;
                            if (std::holds_alternative<int32_t>(mv)) mode = std::get<int32_t>(mv);
                            else if (std::holds_alternative<int64_t>(mv)) mode = (int)std::get<int64_t>(mv);
                            else if (std::holds_alternative<double>(mv)) mode = (int)std::get<double>(mv);
                        }

                        bool isLocal = false;
                        auto isLocalIt = args.find(flutter::EncodableValue("isLocal"));
                        if (isLocalIt != args.end() && std::holds_alternative<bool>(isLocalIt->second)) {
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
                } catch (const std::exception& ex) {
                    OutputDebugStringA((std::string("[FloatWindow] exception in MethodCall handler: ") + ex.what() + "\n").c_str());
                    try { result->Error("exception", ex.what()); } catch (...) {}
                } catch (...) {
                    OutputDebugStringA("[FloatWindow] unknown exception in MethodCall handler\n");
                    try { result->Error("exception", "unknown"); } catch (...) {}
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