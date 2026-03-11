#pragma once
#include <windows.h>
#include <gdiplus.h>
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <chrono>
#include <algorithm>

class FloatWindow {
public:
    static FloatWindow& instance() {
        static FloatWindow inst;
        return inst;
    }
    void Show(long long endMs, const std::wstring& title,
              const std::vector<std::wstring>& tags, bool isLocal);
    void Hide();

private:
    FloatWindow() = default;
    ~FloatWindow() { Hide(); }

    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    void RunLoop(long long endMs, std::wstring title, std::vector<std::wstring> tags);
    void Render();
    void SaveState();
    void LoadState();
    std::wstring FmtSecs(int secs);
    std::wstring BuildBottomLine();

    HWND hwnd_ = nullptr;
    std::thread thread_;
    std::atomic<bool> running_{ false };

    long long endMs_ = 0;
    std::wstring title_;
    std::vector<std::wstring> tags_;

    // drag move
    bool dragging_ = false;
    POINT dragStart_ = { 0, 0 };
    POINT winStart_  = { 0, 0 };

    // resize
    bool resizing_ = false;
    POINT resizeStart_ = { 0, 0 };
    int resizeOrigW_ = 0;
    int resizeOrigH_ = 0;

    bool isLocal_ = false;

    BYTE  alpha_ = 200;
    int   winX_  = -1;
    int   winY_  = -1;
    int   winW_  = 300;
    int   winH_  = 110;

    static constexpr int   MIN_W    = 200;
    static constexpr int   MIN_H    = 80;
    static constexpr int   RBORDER  = 8;
    static constexpr wchar_t kClass[]  = L"MathQuizFloatV3";
    static constexpr wchar_t kRegKey[] = L"Software\\MathQuiz\\FloatV3";

    ULONG_PTR gdiplusToken_ = 0;
};