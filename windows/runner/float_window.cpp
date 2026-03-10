#include "float_window.h"
#include <algorithm>
#include <chrono>
#include <gdiplus.h>
#pragma comment(lib, "gdiplus.lib")
using namespace Gdiplus;

std::wstring FloatWindow::FmtSecs(int secs) {
    if (secs < 0) secs = 0;
    wchar_t buf[16];
    swprintf_s(buf, L"%02d:%02d", secs / 60, secs % 60);
    return buf;
}

std::wstring FloatWindow::JoinTags() {
    std::wstring out;
    for (size_t i = 0; i < tags_.size(); ++i) {
        if (i) out += L" ";
        out += L"#" + tags_[i];
    }
    return out;
}

void FloatWindow::SavePosition(int x, int y) {
    HKEY key;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegKey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
        RegSetValueExW(key, L"X", 0, REG_DWORD, (BYTE*)&x, sizeof(int));
        RegSetValueExW(key, L"Y", 0, REG_DWORD, (BYTE*)&y, sizeof(int));
        RegCloseKey(key);
    }
}

void FloatWindow::LoadPosition(int& x, int& y) {
    x = GetSystemMetrics(SM_CXSCREEN) - OV_W - 20;
    y = 20;
    HKEY key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegKey, 0, KEY_READ, &key) == ERROR_SUCCESS) {
        DWORD size = sizeof(int);
        RegQueryValueExW(key, L"X", nullptr, nullptr, (BYTE*)&x, &size);
        RegQueryValueExW(key, L"Y", nullptr, nullptr, (BYTE*)&y, &size);
        RegCloseKey(key);
    }
}

void FloatWindow::Render() {
    if (!hwnd_) return;

    int W = OV_W;
    int H = OV_H;

    HDC hdcScreen = GetDC(NULL);
    HDC memDC = CreateCompatibleDC(hdcScreen);

    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize        = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth       = W;
    bmi.bmiHeader.biHeight      = -H;
    bmi.bmiHeader.biPlanes      = 1;
    bmi.bmiHeader.biBitCount    = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void* pBits = nullptr;
    HBITMAP memBmp = CreateDIBSection(hdcScreen, &bmi, DIB_RGB_COLORS, &pBits, NULL, 0);
    if (!memBmp) {
        DeleteDC(memDC);
        ReleaseDC(NULL, hdcScreen);
        return;
    }
    HBITMAP oldBmp = (HBITMAP)SelectObject(memDC, memBmp);
    memset(pBits, 0, W * H * 4);

    {
        Graphics g(memDC);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        g.SetTextRenderingHint(TextRenderingHintAntiAlias);

        int r = 12;

        // Background + border
        Color bgColor(210, 15, 20, 30);
        SolidBrush bgBrush(bgColor);
        GraphicsPath path;
        path.AddArc(0,     0,     2*r, 2*r, 180.0f, 90.0f);
        path.AddArc(W-2*r, 0,     2*r, 2*r, 270.0f, 90.0f);
        path.AddArc(W-2*r, H-2*r, 2*r, 2*r,   0.0f, 90.0f);
        path.AddArc(0,     H-2*r, 2*r, 2*r,  90.0f, 90.0f);
        path.CloseFigure();
        g.FillPath(&bgBrush, &path);

        Pen borderPen(Color(180, 239, 83, 80), 1.5f);
        g.DrawPath(&borderPen, &path);

        // Divider at 2/3 height
        int divY = (int)(H * 2.0f / 3.0f);
        Pen divPen(Color(80, 200, 200, 200), 1.0f);
        g.DrawLine(&divPen, 8, divY, W - 8, divY);

        StringFormat sfCenter;
        sfCenter.SetAlignment(StringAlignmentCenter);
        sfCenter.SetLineAlignment(StringAlignmentCenter);

        StringFormat sfLeft;
        sfLeft.SetAlignment(StringAlignmentNear);
        sfLeft.SetLineAlignment(StringAlignmentCenter);
        sfLeft.SetTrimming(StringTrimmingEllipsisCharacter);
        sfLeft.SetFormatFlags(StringFormatFlagsNoWrap);

        SolidBrush whiteBr(Color(255, 255, 255, 255));

        // Countdown (upper 2/3)
        auto nowMs = (long long)std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
        int remaining = (int)((endMs_ - nowMs) / 1000);
        std::wstring countdown = FmtSecs(remaining);

        float cdFontSize = divY * 0.52f;
        FontFamily ff(L"\u5fae\u8f6f\u96c5\u9ed1");  // 微软雅黑
        SetWindowTextW(hwnd_, title_.empty() ? L"(empty)" : title_.c_str());
        Font fBig(&ff, cdFontSize, FontStyleBold, UnitPixel);
        RectF rcCD(8.0f, 4.0f, (float)(W - 16), (float)(divY * 0.68f));
        g.DrawString(countdown.c_str(), -1, &fBig, rcCD, &sfCenter, &whiteBr);

        // Phase label
        std::wstring phase = L"\u4e13\u6ce8\u4e2d (\u8de8\u7aef)";
        float subFontSize = (float)divY * 0.16f;
        if (subFontSize < 11.0f) subFontSize = 11.0f;
        Font fSub(&ff, subFontSize, FontStyleRegular, UnitPixel);
        Color subCol(200, 255, 150, 130);
        SolidBrush subBr(subCol);
        RectF rcPhase(8.0f, (float)(divY * 0.68f), (float)(W - 16), subFontSize * 1.6f);
        g.DrawString(phase.c_str(), -1, &fSub, rcPhase, &sfCenter, &subBr);

        // Bottom 1/3: task + tags
        float botH       = (float)(H - divY);
        float botMidY    = divY + botH * 0.5f;
        float botFontSz  = botH * 0.32f;
        if (botFontSz < 10.0f) botFontSz = 10.0f;
        Font fBot(&ff, botFontSz, FontStyleRegular, UnitPixel);
        float botLineH = botFontSz * 1.5f;

        std::wstring todoText;
        if (title_.empty() && tags_.empty()) {
            todoText = L"\u65e0\u4efb\u52a1";
        } else if (title_.empty()) {
            todoText = JoinTags();
        } else {
            todoText = L"\u25b8 " + title_;
            if (!tags_.empty()) todoText += L"  " + JoinTags();
        }

        Color todoCol = (title_.empty() && tags_.empty())
                        ? Color(120, 180, 180, 180)
                        : Color(230, 230, 240, 255);
        SolidBrush todoBr(todoCol);
        RectF rcTodo(8.0f, botMidY - botLineH * 0.5f, (float)(W - 16), botLineH);
        g.DrawString(todoText.c_str(), -1, &fBot, rcTodo, &sfLeft, &todoBr);

        // Close button top-right
        Font fX(&ff, 12.0f, FontStyleBold, UnitPixel);
        SolidBrush xBr(Color(150, 200, 200, 200));
        RectF rcX((float)(W - 22), 2.0f, 18.0f, 18.0f);
        StringFormat sfX;
        sfX.SetAlignment(StringAlignmentCenter);
        sfX.SetLineAlignment(StringAlignmentCenter);
        g.DrawString(L"\u00d7", -1, &fX, rcX, &sfX, &xBr);
    }

    BLENDFUNCTION bf = {};
    bf.BlendOp             = AC_SRC_OVER;
    bf.SourceConstantAlpha = alpha_;
    bf.AlphaFormat         = AC_SRC_ALPHA;

    RECT wrect;
    GetWindowRect(hwnd_, &wrect);
    POINT ptDest = { wrect.left, wrect.top };
    POINT ptSrc  = { 0, 0 };
    SIZE  szWnd  = { W, H };
    UpdateLayeredWindow(hwnd_, hdcScreen, &ptDest, &szWnd, memDC, &ptSrc, 0, &bf, ULW_ALPHA);

    SelectObject(memDC, oldBmp);
    DeleteObject(memBmp);
    DeleteDC(memDC);
    ReleaseDC(NULL, hdcScreen);
}

LRESULT CALLBACK FloatWindow::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
FloatWindow* self = reinterpret_cast<FloatWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

switch (msg) {
case WM_CREATE:
SetTimer(hwnd, 1, 1000, nullptr);
break;

case WM_TIMER:
if (self) {
auto nowMs = (long long)std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
if (nowMs >= self->endMs_) {
self->Hide();
return 0;
}
self->Render();
}
break;

case WM_LBUTTONDOWN: {
if (!self) break;
RECT rc;
GetClientRect(hwnd, &rc);
POINT pt = { LOWORD(lParam), HIWORD(lParam) };

// Close button hit test
if (pt.x >= rc.right - 22 && pt.y <= 20) {
self->Hide();
return 0;
}

self->dragging_ = true;
self->dragStart_ = pt;
ClientToScreen(hwnd, &self->dragStart_);
RECT wr;
GetWindowRect(hwnd, &wr);
self->winStart_ = { wr.left, wr.top };
SetCapture(hwnd);
break;
}

case WM_MOUSEMOVE:
if (self && self->dragging_) {
POINT cur = { LOWORD(lParam), HIWORD(lParam) };
ClientToScreen(hwnd, &cur);
int nx = self->winStart_.x + (cur.x - self->dragStart_.x);
int ny = self->winStart_.y + (cur.y - self->dragStart_.y);
SetWindowPos(hwnd, nullptr, nx, ny, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
self->Render();
}
break;

case WM_LBUTTONUP:
if (self && self->dragging_) {
self->dragging_ = false;
ReleaseCapture();
RECT wr;
GetWindowRect(hwnd, &wr);
self->SavePosition(wr.left, wr.top);
}
break;

case WM_MOUSEWHEEL: {
if (!self) break;
int delta = GET_WHEEL_DELTA_WPARAM(wParam);
int newAlpha = (int)self->alpha_ + (delta > 0 ? 15 : -15);
newAlpha = std::max(30, std::min(255, newAlpha));
self->alpha_ = (BYTE)newAlpha;
self->Render();
break;
}

case WM_RBUTTONUP:
if (self) self->Hide();
break;

case WM_DESTROY:
KillTimer(hwnd, 1);
if (self) self->hwnd_ = nullptr;
break;

default:
return DefWindowProcW(hwnd, msg, wParam, lParam);
}
return 0;
}

void FloatWindow::RunLoop(long long endMs, std::wstring title, std::vector<std::wstring> tags) {
    // Init GDI+
    GdiplusStartupInput gdiplusInput;
    GdiplusStartup(&gdiplusToken_, &gdiplusInput, nullptr);

    endMs_ = endMs;
    title_ = std::move(title);
    tags_  = std::move(tags);

    HINSTANCE hInst = GetModuleHandleW(nullptr);

    WNDCLASSEXW wc = {};
    wc.cbSize        = sizeof(wc);
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInst;
    wc.lpszClassName = kClass;
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassExW(&wc);

    int x, y;
    LoadPosition(x, y);

    hwnd_ = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE,
            kClass, L"",
            WS_POPUP,
            x, y, OV_W, OV_H,
            nullptr, nullptr, hInst, nullptr
    );

    if (!hwnd_) {
        GdiplusShutdown(gdiplusToken_);
        return;
    }

    SetWindowLongPtrW(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
    Render();

    MSG msg;
    while (running_ && GetMessageW(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    GdiplusShutdown(gdiplusToken_);
}

void FloatWindow::Show(long long endMs, const std::wstring& title,
                       const std::vector<std::wstring>& tags) {
    Hide();
    running_ = true;
    thread_ = std::thread([this, endMs, title, tags]() {
        RunLoop(endMs, title, tags);
    });
}

void FloatWindow::Hide() {
    running_ = false;
    if (hwnd_ && IsWindow(hwnd_)) {
        PostMessageW(hwnd_, WM_DESTROY, 0, 0);
    }
    if (thread_.joinable()) {
        thread_.join();
    }
    hwnd_ = nullptr;
}