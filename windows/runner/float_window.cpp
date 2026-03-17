#include "float_window.h"
#include <gdiplus.h>
#include <chrono>
#include <algorithm>
#pragma comment(lib, "gdiplus.lib")
using namespace Gdiplus;

std::wstring FloatWindow::FmtSecs(int secs) {
    if (secs < 0) secs = 0;
    wchar_t buf[16];
    swprintf_s(buf, L"%02d:%02d", secs / 60, secs % 60);
    return buf;
}

std::wstring FloatWindow::BuildBottomLine() {
    std::wstring tags;
    for (size_t i = 0; i < tags_.size(); ++i) {
        if (i) tags += L" ";
        tags += L"#" + tags_[i];
    }
    if (title_.empty() && tags.empty()) return L"\u81ea\u7531\u4e13\u6ce8";
    if (title_.empty()) return tags;
    if (tags.empty())   return L"\u25b8 " + title_;
    return L"\u25b8 " + title_ + L"  " + tags;
}

void FloatWindow::SaveState() {
    HKEY key;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegKey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
        RegSetValueExW(key, L"X",     0, REG_DWORD, (BYTE*)&winX_,  sizeof(int));
        RegSetValueExW(key, L"Y",     0, REG_DWORD, (BYTE*)&winY_,  sizeof(int));
        RegSetValueExW(key, L"W",     0, REG_DWORD, (BYTE*)&winW_,  sizeof(int));
        RegSetValueExW(key, L"H",     0, REG_DWORD, (BYTE*)&winH_,  sizeof(int));
        RegSetValueExW(key, L"Alpha", 0, REG_DWORD, (BYTE*)&alpha_, sizeof(BYTE));
        RegCloseKey(key);
    }
}

void FloatWindow::LoadState() {
    winX_ = GetSystemMetrics(SM_CXSCREEN) - winW_ - 20;
    winY_ = 20;
    HKEY key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegKey, 0, KEY_READ, &key) == ERROR_SUCCESS) {
        DWORD size = sizeof(int);
        RegQueryValueExW(key, L"X",     nullptr, nullptr, (BYTE*)&winX_,  &size);
        RegQueryValueExW(key, L"Y",     nullptr, nullptr, (BYTE*)&winY_,  &size);
        RegQueryValueExW(key, L"W",     nullptr, nullptr, (BYTE*)&winW_,  &size);
        RegQueryValueExW(key, L"H",     nullptr, nullptr, (BYTE*)&winH_,  &size);
        size = sizeof(BYTE);
        RegQueryValueExW(key, L"Alpha", nullptr, nullptr, (BYTE*)&alpha_, &size);
        RegCloseKey(key);
    }
    winW_ = std::max(MIN_W, winW_);
    winH_ = std::max(MIN_H, winH_);
}

void FloatWindow::Render() {
    if (!hwnd_) return;
    int W = winW_;
    int H = winH_;

    HDC hdcScreen = GetDC(NULL);
    HDC memDC     = CreateCompatibleDC(hdcScreen);

    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize        = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth       = W;
    bmi.bmiHeader.biHeight      = -H;
    bmi.bmiHeader.biPlanes      = 1;
    bmi.bmiHeader.biBitCount    = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void* pBits = nullptr;
    HBITMAP memBmp = CreateDIBSection(hdcScreen, &bmi, DIB_RGB_COLORS, &pBits, NULL, 0);
    if (!memBmp) { DeleteDC(memDC); ReleaseDC(NULL, hdcScreen); return; }
    HBITMAP oldBmp = (HBITMAP)SelectObject(memDC, memBmp);
    memset(pBits, 0, W * H * 4);

    {
        Graphics g(memDC);
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        g.SetTextRenderingHint(TextRenderingHintAntiAlias);

        int r = 12;

        // background
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

        // divider
        int divY = H * 2 / 3;
        Pen divPen(Color(80, 200, 200, 200), 1.0f);
        g.DrawLine(&divPen, 8, divY, W - 8, divY);

        FontFamily ff(L"Microsoft YaHei UI");
        StringFormat sfCenter;
        sfCenter.SetAlignment(StringAlignmentCenter);
        sfCenter.SetLineAlignment(StringAlignmentCenter);
        StringFormat sfLeft;
        sfLeft.SetAlignment(StringAlignmentNear);
        sfLeft.SetLineAlignment(StringAlignmentCenter);
        sfLeft.SetTrimming(StringTrimmingEllipsisCharacter);
        sfLeft.SetFormatFlags(StringFormatFlagsNoWrap);

        SolidBrush whiteBr(Color(255, 255, 255, 255));

        auto nowMs = (long long)std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
        int displaySecs = 0;
        if (mode_ == 1) {
            displaySecs = (int)((nowMs - endMs_) / 1000);
        } else {
            displaySecs = (int)((endMs_ - nowMs) / 1000);
        }
        std::wstring countdown = FmtSecs(displaySecs);
        float cdFontSz = divY * 0.52f;
        Font fBig(&ff, cdFontSz, FontStyleBold, UnitPixel);
        RectF rcCD(8.0f, 4.0f, (float)(W - 24), (float)(divY * 0.65f));
        g.DrawString(countdown.c_str(), -1, &fBig, rcCD, &sfCenter, &whiteBr);

        std::wstring phase = isLocal_ ? L"\u4e13\u6ce8\u4e2d" : L"\u4e13\u6ce8\u4e2d (\u8de8\u7aef)";
        if (mode_ == 1) phase = isLocal_ ? L"\u6b63\u5728\u8ba1\u65f6" : L"\u6b63\u5728\u8ba1\u65f6 (\u8de8\u7aef)";
        float subFontSz = (float)divY * 0.18f;
        if (subFontSz < 11.0f) subFontSz = 11.0f;
        Font fSub(&ff, subFontSz, FontStyleRegular, UnitPixel);
        SolidBrush subBr(Color(200, 255, 150, 130));
        RectF rcPhase(8.0f, (float)(divY * 0.66f), (float)(W - 16), (float)(divY * 0.34f));
        g.DrawString(phase.c_str(), -1, &fSub, rcPhase, &sfCenter, &subBr);

        float botH      = (float)(H - divY);
        float botFontSz = botH * 0.38f;
        if (botFontSz < 10.0f) botFontSz = 10.0f;
        Font fBot(&ff, botFontSz, FontStyleRegular, UnitPixel);
        float lineH  = botFontSz * 1.4f;
        float midY   = divY + botH * 0.5f;

        std::wstring bottomLine = BuildBottomLine();

        // task part: white
        std::wstring taskPart;
        std::wstring tagPart;
        if (!title_.empty()) {
            taskPart = L"\u25b8 " + title_;
            if (!tags_.empty()) {
                tagPart = L"  ";
                for (size_t i = 0; i < tags_.size(); ++i) {
                    if (i) tagPart += L" ";
                    tagPart += L"#" + tags_[i];
                }
            }
        } else if (!tags_.empty()) {
            for (size_t i = 0; i < tags_.size(); ++i) {
                if (i) tagPart += L" ";
                tagPart += L"#" + tags_[i];
            }
        } else {
            taskPart = L"\u81ea\u7531\u4e13\u6ce8";
        }

        float padX   = 10.0f;
        float startY = midY - lineH * 0.5f;
        float availW = (float)(W - 20);

        // measure task part width to position tag part correctly
        if (!taskPart.empty()) {
            SolidBrush taskBr(Color(230, 230, 240, 255));
            RectF rcTask(padX, startY, availW, lineH);
            if (tagPart.empty()) {
                g.DrawString(taskPart.c_str(), -1, &fBot, rcTask, &sfLeft, &taskBr);
            } else {
                // measure task text width
                RectF measured;
                g.MeasureString(taskPart.c_str(), -1, &fBot,
                                RectF(0, 0, (float)W, lineH), &sfLeft, &measured);
                float taskW = measured.Width;

                // draw task in white
                RectF rcT(padX, startY, taskW, lineH);
                g.DrawString(taskPart.c_str(), -1, &fBot, rcT, &sfLeft, &taskBr);

                // draw tags in purple right after
                SolidBrush tagBr(Color(220, 160, 160, 255));
                float tagX = padX + taskW;
                float tagW = availW - taskW;
                if (tagW > 0) {
                    RectF rcTag(tagX, startY, tagW, lineH);
                    g.DrawString(tagPart.c_str(), -1, &fBot, rcTag, &sfLeft, &tagBr);
                }
            }
        } else if (!tagPart.empty()) {
            SolidBrush tagBr(Color(220, 160, 160, 255));
            RectF rcTag(padX, startY, availW, lineH);
            g.DrawString(tagPart.c_str(), -1, &fBot, rcTag, &sfLeft, &tagBr);
        }

        // close button top-right
        Font fX(&ff, 12.0f, FontStyleBold, UnitPixel);
        SolidBrush xBr(Color(150, 200, 200, 200));
        RectF rcX((float)(W - 22), 3.0f, 18.0f, 18.0f);
        StringFormat sfX;
        sfX.SetAlignment(StringAlignmentCenter);
        sfX.SetLineAlignment(StringAlignmentCenter);
        g.DrawString(L"\u00d7", -1, &fX, rcX, &sfX, &xBr);

        // resize handle bottom-right corner (small triangle indicator)
        SolidBrush resizeBr(Color(60, 200, 200, 200));
        PointF tri[3] = {
                PointF((float)(W - 2),  (float)(H - 12)),
                PointF((float)(W - 12), (float)(H - 2)),
                PointF((float)(W - 2),  (float)(H - 2)),
        };
        g.FillPolygon(&resizeBr, tri, 3);
    }

    BLENDFUNCTION bf = {};
    bf.BlendOp             = AC_SRC_OVER;
    bf.SourceConstantAlpha = alpha_;
    bf.AlphaFormat         = AC_SRC_ALPHA;
    RECT wr;
    GetWindowRect(hwnd_, &wr);
    POINT ptDest = { wr.left, wr.top };
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
if (self->mode_ == 0 && nowMs >= self->endMs_) { self->Hide(); return 0; }
self->Render();
}
break;

case WM_LBUTTONDOWN: {
if (!self) break;
POINT pt = { LOWORD(lParam), HIWORD(lParam) };

// close button
if (pt.x >= self->winW_ - 22 && pt.y <= 22) {
PostMessageW(hwnd, WM_CLOSE, 0, 0);
return 0;
}

// resize corner
bool onRight  = pt.x >= self->winW_ - RBORDER;
bool onBottom = pt.y >= self->winH_ - RBORDER;
if (onRight || onBottom) {
self->resizing_    = true;
self->resizeStart_ = pt;
ClientToScreen(hwnd, &self->resizeStart_);
self->resizeOrigW_ = self->winW_;
self->resizeOrigH_ = self->winH_;
SetCapture(hwnd);
return 0;
}

// drag move
self->dragging_  = true;
self->dragStart_ = pt;
ClientToScreen(hwnd, &self->dragStart_);
RECT wr; GetWindowRect(hwnd, &wr);
self->winStart_ = { wr.left, wr.top };
SetCapture(hwnd);
break;
}

case WM_MOUSEMOVE: {
if (!self) break;
POINT pt = { LOWORD(lParam), HIWORD(lParam) };

if (self->resizing_) {
POINT cur = pt;
ClientToScreen(hwnd, &cur);
int dx = cur.x - self->resizeStart_.x;
int dy = cur.y - self->resizeStart_.y;
int nw = std::max(MIN_W, self->resizeOrigW_ + dx);
int nh = std::max(MIN_H, self->resizeOrigH_ + dy);
self->winW_ = nw;
self->winH_ = nh;
SetWindowPos(hwnd, nullptr, 0, 0, nw, nh,
SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
self->Render();
return 0;
}

if (self->dragging_) {
POINT cur = pt;
ClientToScreen(hwnd, &cur);
int nx = self->winStart_.x + (cur.x - self->dragStart_.x);
int ny = self->winStart_.y + (cur.y - self->dragStart_.y);
self->winX_ = nx; self->winY_ = ny;
SetWindowPos(hwnd, nullptr, nx, ny, 0, 0,
SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
self->Render();
return 0;
}

// cursor hint
bool onRight  = pt.x >= self->winW_ - RBORDER;
bool onBottom = pt.y >= self->winH_ - RBORDER;
if (onRight && onBottom) SetCursor(LoadCursor(nullptr, IDC_SIZENWSE));
else if (onRight)        SetCursor(LoadCursor(nullptr, IDC_SIZEWE));
else if (onBottom)       SetCursor(LoadCursor(nullptr, IDC_SIZENS));
else                     SetCursor(LoadCursor(nullptr, IDC_ARROW));
break;
}

case WM_LBUTTONUP:
if (self) {
if (self->resizing_) {
self->resizing_ = false;
ReleaseCapture();
self->SaveState();
return 0;
}
if (self->dragging_) {
self->dragging_ = false;
ReleaseCapture();
self->SaveState();
}
}
break;

case WM_MOUSEWHEEL: {
if (!self) break;
int delta = GET_WHEEL_DELTA_WPARAM(wParam);
int a = (int)self->alpha_ + (delta > 0 ? 15 : -15);
self->alpha_ = (BYTE)std::max(30, std::min(255, a));
self->Render();
self->SaveState();
break;
}

case WM_RBUTTONUP:
PostMessageW(hwnd, WM_CLOSE, 0, 0);
break;

case WM_CLOSE:
DestroyWindow(hwnd);
break;

case WM_DESTROY:
KillTimer(hwnd, 1);
PostQuitMessage(0);
break;
}
return DefWindowProcW(hwnd, msg, wParam, lParam);
}

void FloatWindow::RunLoop(long long endMs, std::wstring title, std::vector<std::wstring> tags, int mode) {
    GdiplusStartupInput gi;
    GdiplusStartup(&gdiplusToken_, &gi, nullptr);

    endMs_ = endMs;
    title_ = std::move(title);
    tags_  = std::move(tags);
    mode_  = mode;

    LoadState();

    HINSTANCE hInst = GetModuleHandleW(nullptr);
    WNDCLASSEXW wc = {};
    wc.cbSize        = sizeof(wc);
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInst;
    wc.lpszClassName = kClass;
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassExW(&wc);

    int x = (winX_ >= 0) ? winX_ : GetSystemMetrics(SM_CXSCREEN) - winW_ - 20;
    int y = (winY_ >= 0) ? winY_ : 20;

    hwnd_ = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE,
            kClass, L"", WS_POPUP,
            x, y, winW_, winH_,
            nullptr, nullptr, hInst, nullptr
    );
    if (!hwnd_) { GdiplusShutdown(gdiplusToken_); return; }

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
                       const std::vector<std::wstring>& tags, bool isLocal, int mode) {
    Hide();
    isLocal_ = isLocal;
    running_ = true;
    thread_ = std::thread([this, endMs, title, tags, mode]() {
        RunLoop(endMs, title, tags, mode);
    });
}

void FloatWindow::Hide() {
    running_ = false;
    if (hwnd_ && IsWindow(hwnd_)) {
        PostMessageW(hwnd_, WM_CLOSE, 0, 0);
        hwnd_ = nullptr;
    }
    if (thread_.joinable()) {
        thread_.join();
    }
}