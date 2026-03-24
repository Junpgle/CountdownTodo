#pragma warning(disable: 4819)
#include "flutter_window.h"
#include "float_window.h"

#include <optional>
#include <string>
#include <vector>
#include <variant>
#include <cstdint>

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

                    long long endMs = 0;
                    auto endMsIt = args.find(flutter::EncodableValue("endMs"));
                    if (endMsIt != args.end()) {
                        if (std::holds_alternative<int32_t>(endMsIt->second)) endMs = std::get<int32_t>(endMsIt->second);
                        else if (std::holds_alternative<int64_t>(endMsIt->second)) endMs = std::get<int64_t>(endMsIt->second);
                    }

                    std::wstring title;
                    auto titleIt = args.find(flutter::EncodableValue("title"));
                    if (titleIt != args.end() && std::holds_alternative<std::string>(titleIt->second)) {
                        std::string s = std::get<std::string>(titleIt->second);
                        int wl = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), nullptr, 0);
                        title.resize(wl);
                        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), &title[0], wl);
                    }

                    std::vector<std::wstring> tags;
                    auto tagsIt = args.find(flutter::EncodableValue("tags"));
                    if (tagsIt != args.end() && std::holds_alternative<flutter::EncodableList>(tagsIt->second)) {
                        auto& tagList = std::get<flutter::EncodableList>(tagsIt->second);
                        for (auto& t : tagList) {
                            if (std::holds_alternative<std::string>(t)) {
                                std::string tagUtf8 = std::get<std::string>(t);
                                int wl = MultiByteToWideChar(CP_UTF8, 0, tagUtf8.c_str(), (int)tagUtf8.length(), nullptr, 0);
                                std::wstring wt(wl, 0);
                                if (wl > 0) MultiByteToWideChar(CP_UTF8, 0, tagUtf8.c_str(), (int)tagUtf8.length(), &wt[0], wl);
                                tags.push_back(wt);
                            }
                        }
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
                    if (isLocalIt != args.end() && std::holds_alternative<bool>(isLocalIt->second)) {
                        isLocal = std::get<bool>(isLocalIt->second);
                    }

                    int style = 0;
                    auto styleIt = args.find(flutter::EncodableValue("style"));
                    if (styleIt != args.end()) {
                        if (std::holds_alternative<int32_t>(styleIt->second)) style = std::get<int32_t>(styleIt->second);
                        else if (std::holds_alternative<int64_t>(styleIt->second)) style = (int)std::get<int64_t>(styleIt->second);
                    }

                    std::wstring left, right;
                    auto leftIt = args.find(flutter::EncodableValue("left"));
                    if (leftIt != args.end() && std::holds_alternative<std::string>(leftIt->second)) {
                        std::string s = std::get<std::string>(leftIt->second);
                        int wl = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), nullptr, 0);
                        left.resize(wl);
                        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), &left[0], wl);
                    }
                    auto rightIt = args.find(flutter::EncodableValue("right"));
                    if (rightIt != args.end() && std::holds_alternative<std::string>(rightIt->second)) {
                        std::string s = std::get<std::string>(rightIt->second);
                        int wl = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), nullptr, 0);
                        right.resize(wl);
                        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), &right[0], wl);
                    }
                    bool forceReset = false;
                    auto resetIt = args.find(flutter::EncodableValue("forceReset"));
                    if (resetIt != args.end() && std::holds_alternative<bool>(resetIt->second)) {
                        forceReset = std::get<bool>(resetIt->second);
                    }

                    std::wstring reminder;
                    auto reminderIt = args.find(flutter::EncodableValue("reminder"));
                    if (reminderIt != args.end() && std::holds_alternative<std::string>(reminderIt->second)) {
                        std::string s = std::get<std::string>(reminderIt->second);
                        int wl = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), nullptr, 0);
                        reminder.resize(wl);
                        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), &reminder[0], wl);
                    }

                    // Helper lambda for UTF8 → wstring
                    auto getWStr = [&](const char* key) -> std::wstring {
                        auto it = args.find(flutter::EncodableValue(key));
                        if (it != args.end() && std::holds_alternative<std::string>(it->second)) {
                            std::string s = std::get<std::string>(it->second);
                            int wl = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), nullptr, 0);
                            std::wstring ws(wl, 0);
                            MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), &ws[0], wl);
                            return ws;
                        }
                        return L"";
                    };

                    std::wstring reminderType = getWStr("reminderType");
                    std::wstring topBarLeft   = getWStr("topBarLeft");
                    std::wstring topBarRight  = getWStr("topBarRight");

                    std::vector<FloatWindow::ReminderItem> reminderQueue;
                    auto queueIt = args.find(flutter::EncodableValue("reminderQueue"));
                    if (queueIt != args.end() && std::holds_alternative<flutter::EncodableList>(queueIt->second)) {
                        auto& qList = std::get<flutter::EncodableList>(queueIt->second);
                        for (auto& itemVal : qList) {
                            if (std::holds_alternative<flutter::EncodableMap>(itemVal)) {
                                auto& itemMap = std::get<flutter::EncodableMap>(itemVal);
                                FloatWindow::ReminderItem item;
                                auto getMapStr = [&](const char* k) -> std::wstring {
                                    auto it = itemMap.find(flutter::EncodableValue(k));
                                    if (it != itemMap.end() && std::holds_alternative<std::string>(it->second)) {
                                        std::string s = std::get<std::string>(it->second);
                                        int wl = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), nullptr, 0);
                                        std::wstring ws(wl, 0);
                                        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.length(), &ws[0], wl);
                                        return ws;
                                    }
                                    return L"";
                                };
                                item.text = getMapStr("text");
                                item.type = getMapStr("type");
                                item.timeLabel = getMapStr("timeLabel");
                                reminderQueue.push_back(item);
                            }
                        }
                    }

                    FloatWindow::DetailCardInfo detail;
                    detail.type     = getWStr("detail_type");
                    detail.title    = getWStr("detail_title");
                    detail.subtitle = getWStr("detail_subtitle");
                    detail.location = getWStr("detail_location");
                    detail.time     = getWStr("detail_time");
                    detail.note     = getWStr("detail_note");

                    // Debug: emit a simple trace so we can observe native received payloads
                    {
                        char buf[256];
                        int n = _snprintf_s(buf, sizeof(buf), _TRUNCATE, "[Native] showFloat recv endMs=%lld mode=%d isLocal=%d style=%d forceReset=%d", endMs, mode, isLocal ? 1 : 0, style, forceReset ? 1 : 0);
                        if (n > 0) OutputDebugStringA(buf);
                    }

                    FloatWindow::instance().Show(endMs, title, tags, isLocal, mode, style, left, right, forceReset,
                                                 reminder, reminderType, detail, topBarLeft, topBarRight, reminderQueue);
                    result->Success();
                } else if (call.method_name() == "hideFloat") {
                    FloatWindow::instance().Hide();
                    result->Success();

                } else {
                    result->NotImplemented();
                }
            }
    );

    FloatWindow::instance().SetActionCallback([this](const std::string& action, int secs) {
        // action: "finish" or "abandon"
        // secs: modified duration for finish
        struct ActionData {
            std::string action;
            int secs;
        };
        ActionData* data = new ActionData{ action, secs };
        PostMessage(this->GetHandle(), FlutterWindow::WM_FLOAT_ACTION, reinterpret_cast<WPARAM>(data), 0);
    });




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
case FlutterWindow::WM_FLOAT_ACTION: {
    struct ActionData { std::string action; int secs; };
    ActionData* data = reinterpret_cast<ActionData*>(wparam);

    if (data && float_channel_) {
        float_channel_->InvokeMethod("onAction", std::make_unique<flutter::EncodableValue>(
            flutter::EncodableMap{
                {flutter::EncodableValue("action"), flutter::EncodableValue(data->action)},
                {flutter::EncodableValue("modifiedSecs"), flutter::EncodableValue(data->secs)}
            }
        ));
        delete data;
    }
    return 0;
}
}


return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}