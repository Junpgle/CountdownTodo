#pragma once
#include <windows.h>
#include <gdiplus.h>
#include <string>
#include <vector>
#include <thread>
#include <atomic>

class FloatWindow {
public:
    static FloatWindow& instance() {
        static FloatWindow inst;
        return inst;
    }

    void Show(long long endMs, const std::wstring& title, const std::vector<std::wstring>& tags);
    void Hide();

private:
    FloatWindow() = default;
    ~FloatWindow() { Hide(); }

    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    void RunLoop(long long endMs, std::wstring title, std::vector<std::wstring> tags);
    void Render();
    void SavePosition(int x, int y);
    void LoadPosition(int& x, int& y);
    std::wstring FmtSecs(int secs);
    std::wstring JoinTags();

    HWND hwnd_ = nullptr;
    std::thread thread_;
    std::atomic<bool> running_{ false };

    long long endMs_ = 0;
    std::wstring title_;
    std::vector<std::wstring> tags_;

    bool dragging_ = false;
    POINT dragStart_ = { 0, 0 };
    POINT winStart_  = { 0, 0 };

    BYTE alpha_ = 200;

    static constexpr int OV_W = 300;
    static constexpr int OV_H = 120;
    static constexpr wchar_t kClass[] = L"MathQuizFloatV2";
    static constexpr wchar_t kRegKey[] = L"Software\\MathQuiz\\FloatWindow";

    ULONG_PTR gdiplusToken_ = 0;
};