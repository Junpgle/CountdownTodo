#pragma warning(disable: 4819)
#include "float_window.h"
#include <gdiplus.h>
#include <chrono>
#include <algorithm>
#include <cwchar>
#include <cstdio>
#include <ctime>
#include <windows.h> // Added missing header
#include <string>    // Added missing header
#include <vector>    // Added missing header
#include <mutex>     // Added missing header
#include <functional> // Added missing header
#include <thread>    // Added missing header
#include <atomic>    // Added missing header
#pragma comment(lib, "gdiplus.lib")
using namespace Gdiplus;
 
 static int RegGetInt(HKEY hKey, const wchar_t* name, int def) {
     DWORD val = 0, size = sizeof(val);
     if (RegQueryValueExW(hKey, name, nullptr, nullptr, (BYTE*)&val, &size) == ERROR_SUCCESS) {
         return (int)val;
     }
     return def;
 }

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

float FloatWindow::GetScale() {
    float dpi = 96.0f;
    HDC hdc = GetDC(NULL);
    if (hdc) {
        dpi = (float)GetDeviceCaps(hdc, LOGPIXELSX);
        ReleaseDC(NULL, hdc);
    }
    return dpi / 96.0f;
}

void FloatWindow::SaveState() {
    HKEY key;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegKey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
        DWORD dx = (DWORD)winX_;
        DWORD dy = (DWORD)winY_;
        DWORD dw = (DWORD)winW_;
        DWORD dh = (DWORD)winH_;
        DWORD dalpha = (DWORD)alpha_;
        // Store current user-adjusted base sizes so island uses them next time
        shrunkW_ = winW_;
        islandH_ = winH_;
        if (expandW_ < shrunkW_) expandW_ = shrunkW_;
        // Mark that user explicitly sized the window
        userSized_ = true;
        RegSetValueExW(key, L"X",     0, REG_DWORD, (BYTE*)&dx, sizeof(dx));
        RegSetValueExW(key, L"Y",     0, REG_DWORD, (BYTE*)&dy, sizeof(dy));
        RegSetValueExW(key, L"W",     0, REG_DWORD, (BYTE*)&dw, sizeof(dw));
        RegSetValueExW(key, L"H",     0, REG_DWORD, (BYTE*)&dh, sizeof(dh));
        RegSetValueExW(key, L"Alpha", 0, REG_DWORD, (BYTE*)&dalpha, sizeof(dalpha));
        RegCloseKey(key);
    }
}

void FloatWindow::LoadState() {
    winX_ = GetSystemMetrics(SM_CXSCREEN) - winW_ - 20;
    winY_ = 20;
    HKEY key;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegKey, 0, KEY_READ, &key) == ERROR_SUCCESS) {
        winX_ = RegGetInt(key, L"X", -1);
        winY_ = RegGetInt(key, L"Y", -1);
            winW_ = RegGetInt(key, L"W", 300);
            winH_ = RegGetInt(key, L"H", 110);
            // Use loaded W/H as base island sizes so user adjustments persist
            shrunkW_ = winW_;
            islandH_ = winH_;
            if (expandW_ < shrunkW_) expandW_ = shrunkW_;
            // Treat loaded values as user-sized
            userSized_ = true;
        DWORD size = sizeof(DWORD);
        DWORD dalpha = 200;
        RegQueryValueExW(key, L"Alpha", nullptr, nullptr, (BYTE*)&dalpha, &size);
        if (dalpha > 255) dalpha = 255;
        alpha_ = (BYTE)dalpha;
        RegCloseKey(key);
    }
    
    // Ensure min sizes or defaults
    if (winW_ < MIN_W) winW_ = 300;
    if (winH_ < MIN_H) winH_ = 110;

    float s = GetScale();
    centerX_ = (double)winX_ + (double)(winW_ * s) / 2.0;
    centerY_ = (double)winY_ + (double)(winH_ * s) / 2.0;

    // Ensure the restored window is visible on the (virtual) screen.
    // This prevents the window from staying off-screen if the display configuration
    // changed while the saved coordinates put it outside the visible area.
    int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);

    // Clamp window size to virtual screen (with small margins) to avoid oversized windows
    const int kMargin = 40;
    if (winW_ > vw - kMargin) winW_ = std::max(MIN_W, vw - kMargin);
    if (winH_ > vh - kMargin) winH_ = std::max(MIN_H, vh - kMargin);

    int minX = vx + 20;
    int minY = vy + 20;
    int maxX = vx + vw - winW_ - 20;
    int maxY = vy + vh - winH_ - 20;

    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;

    if (winX_ < minX || winX_ > maxX) {
        // move to the right edge of the primary/virtual screen with margin
        winX_ = maxX;
    }
    if (winY_ < minY || winY_ > maxY) {
        // move to top margin
        winY_ = minY;
    }
}

void FloatWindow::Render() {
    std::lock_guard<std::recursive_mutex> lock(mtx_);
    if (!hwnd_) return;

    float newScale = GetScale();
    if (newScale != dpiScale_) dpiScale_ = newScale;
    float s = dpiScale_;

    int W = std::max(1, (int)(winW_ * s));
    int H = std::max(1, (int)(winH_ * s));

if (style_ == Style::Island) {
    if (winX_ == -1) {
        int screenW = GetSystemMetrics(SM_CXSCREEN);
        winX_ = (screenW - W) / 2;
        winY_ = (int)(10 * s);
        centerX_ = winX_ + (double)W / 2.0;
        centerY_ = winY_ + (double)H / 2.0;
    }
    SetWindowPos(hwnd_, HWND_TOP, 0, 0, W, H,
                 SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOMOVE);
}

    HDC hdcScreen = GetDC(NULL);
    if (!hdcScreen) return;
    HDC memDC     = CreateCompatibleDC(hdcScreen);
    if (!memDC) { ReleaseDC(NULL, hdcScreen); return; }

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

        // float s = GetScale(); // Removed redundant declaration shadowing line 116
        if (style_ == Style::Classic) {
            // Fix: ensure W/H are calculated from winW_ * s even in Render for consistency
            int r = (int)(12 * s);
            // background
            Color bgColor(210, 15, 20, 30);
            SolidBrush bgBrush(bgColor);
            GraphicsPath path;
            path.AddArc(0.0f,       0.0f,       (float)(2*r), (float)(2*r), 180.0f, 90.0f);
            path.AddArc((float)W-2*r, 0.0f,       (float)(2*r), (float)(2*r), 270.0f, 90.0f);
            path.AddArc((float)W-2*r, (float)H-2*r, (float)(2*r), (float)(2*r),   0.0f, 90.0f);
            path.AddArc(0.0f,       (float)H-2*r, (float)(2*r), (float)(2*r),  90.0f, 90.0f);
            path.CloseFigure();
            g.FillPath(&bgBrush, &path);
            Pen borderPen(Color(180, 239, 83, 80), 1.5f);
            g.DrawPath(&borderPen, &path);

            // divider
            int divY = H * 2 / 3;
            Pen divPen(Color(80, 200, 200, 200), 1.0f);
            g.DrawLine(&divPen, (float)(8 * s), (float)divY, (float)(W - 8 * s), (float)divY);

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
            RectF rcCD(8.0f * s, 4.0f * s, (float)(W - 16 * s), (float)(divY * 0.65f));
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
                                    RectF(0.0f, 0.0f, (float)W, (float)lineH), &sfLeft, &measured);
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
            g.FillPolygon(&resizeBr, tri, 3);
        } else {
            // island style rendering
            // Note: s, W, H are already defined in outer scope as dpiScale_, (int)(winW_*s), (int)(winH_*s)
            float s_f = dpiScale_;
            float W_f = (float)winW_ * s_f;
            float H_f = (float)winH_ * s_f;
            float r = (islandState_ == IslandState::DetailCard) ? 16.0f * s_f : H_f / 2.0f;
            Color bgColor(255, 10, 10, 10); // pure black
            SolidBrush bgBrush(bgColor);

            if (islandState_ == IslandState::DetailCard) {
                // Rounded Rectangle for DetailCard
                GraphicsPath bgPath;
                float d = 2.0f * r;
                bgPath.AddArc(0.0f, 0.0f, d, d, 180.0f, 90.0f);
                bgPath.AddArc(W_f - d, 0.0f, d, d, 270.0f, 90.0f);
                bgPath.AddArc(W_f - d, H_f - d, d, d, 0.0f, 90.0f);
                bgPath.AddArc(0.0f, H_f - d, d, d, 90.0f, 90.0f);
                bgPath.CloseFigure();
                g.FillPath(&bgBrush, &bgPath);
                Pen borderPen(Color(80, 255, 255, 255), 1.0f);
                g.DrawPath(&borderPen, &bgPath);
            } else {
                // Capsule for typical Island states
                g.FillEllipse(&bgBrush, 0.0f, 0.0f, 2.0f*r, 2.0f*r);
                g.FillEllipse(&bgBrush, W_f - 2.0f*r, 0.0f, 2.0f*r, 2.0f*r);
                g.FillRectangle(&bgBrush, r, 0.0f, W_f - 2.0f*r, H_f);
                
                // Subtitle border/glow
                Pen borderPen(Color(80, 255, 255, 255), 1.0f);
                g.DrawArc(&borderPen, 0.5f, 0.5f, (float)(2.0f * r - 1.0f), (float)(H_f - 1.0f), 90.0f, 180.0f);
                g.DrawArc(&borderPen, (float)(W_f - 2.0f * r + 0.5f), 0.5f, (float)(2.0f * r - 1.0f), (float)(H_f - 1.0f), 270.0f, 180.0f);
                g.DrawLine(&borderPen, (float)r, 0.5f, (float)(W_f - r), 0.5f);
                g.DrawLine(&borderPen, (float)r, (float)(H_f - 0.5f), (float)(W_f - r), (float)(H_f - 0.5f));
            }


            const wchar_t* fontName = L"Microsoft YaHei UI";
            FontFamily ff(fontName);
            if (ff.GetLastStatus() != Ok) fontName = L"Segoe UI";
            FontFamily ffFinal(fontName);
            StringFormat sfCenter;
            sfCenter.SetAlignment(StringAlignmentCenter);
            sfCenter.SetLineAlignment(StringAlignmentCenter);
            StringFormat sfLeft;
            sfLeft.SetAlignment(StringAlignmentNear);
            sfLeft.SetLineAlignment(StringAlignmentCenter);

            // Common rendering variables to avoid redefinition
            float btnSize = 28.0f * s_f;
            float btnY = (H_f - btnSize) / 2.0f;
            Pen whitePen(Color(255, 255, 255, 255), 2.0f);
            SolidBrush whiteBr(Color(255, 255, 255, 255));
            SolidBrush greenBr(Color(200, 46, 125, 50));
            SolidBrush redBr(Color(200, 211, 47, 47));
            SolidBrush glassBr(Color(180, 20, 20, 20)); // Glassy background for Interactive state

            auto nowMs = (long long)std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::system_clock::now().time_since_epoch()).count();
            
            // High Precision Position Update
            if (!dragging_ && !resizing_) {
                winX_ = (int)(centerX_ - (double)W_f / 2.0);
                winY_ = (int)(centerY_ - (double)H_f / 2.0);
            }

            if (islandState_ == IslandState::TopBar) {
                // TopBar: [Left: Days] [Center: Time] [Right: Course]
                float rx = 16.0f * s_f;
                // Full width rendering of the bar content
                Font fDays(&ffFinal, (REAL)(14.0f * s_f), FontStyleRegular, UnitPixel);
                Font fTime(&ffFinal, (REAL)(20.0f * s_f), FontStyleBold, UnitPixel);
                Font fCourse(&ffFinal, (REAL)(12.0f * s_f), FontStyleRegular, UnitPixel);
                SolidBrush subBr(Color(200, 200, 200, 200));

                // Left: topBarLeft_
                RectF rcLeft(rx, 0, W_f * 0.35f, H_f);
                g.DrawString(topBarLeft_.c_str(), -1, &fDays, rcLeft, &sfLeft, &whiteBr);

                // Center: Current Time
                time_t t = time(nullptr); tm local; localtime_s(&local, &t);
                wchar_t buf[16]; swprintf_s(buf, L"%02d:%02d", local.tm_hour, local.tm_min);
                g.DrawString(buf, -1, &fTime, RectF(0, 0, W_f, H_f), &sfCenter, &whiteBr);

                // Right: topBarRight_
                StringFormat sfRight;
                sfRight.SetAlignment(StringAlignmentFar);
                sfRight.SetLineAlignment(StringAlignmentCenter);
                sfRight.SetTrimming(StringTrimmingEllipsisCharacter);
                RectF rcRight(W_f * 0.65f, 0, W_f * 0.35f - rx, H_f);
                g.DrawString(topBarRight_.c_str(), -1, &fCourse, rcRight, &sfRight, &subBr);

            } else if (isReminderActive_ && (!reminderQueue_.empty() || !reminderText_.empty())) {
                // ReminderCapsule with Queue support
                std::wstring text = reminderText_;
                std::wstring icon = L"\u2630"; // default
                std::wstring timeLab = L"";
                
                if (!reminderQueue_.empty() && reminderQueueIndex_ < (int)reminderQueue_.size()) {
                    const auto& item = reminderQueue_[reminderQueueIndex_];
                    text = item.text;
                    timeLab = item.timeLabel;
                    if (item.type == L"course") icon = L"\u2666";
                    else if (item.type == L"birthday") icon = L"\u2605";
                    else if (item.type == L"countdown") icon = L"\u25C6";
                } else if (!reminderType_.empty()) {
                    if (reminderType_ == L"course") icon = L"\u2666";
                    else if (reminderType_ == L"birthday") icon = L"\u2605";
                    else if (reminderType_ == L"countdown") icon = L"\u25C6";
                }

                float pad = r * 1.2f;
                float iconSize = 24.0f * s_f;
                float checkBtnX = W_f - r - btnSize;
                
                // Draw Icon
                Font fIcon(&ffFinal, (REAL)(18.0f * s_f), FontStyleRegular, UnitPixel);
                g.DrawString(icon.c_str(), -1, &fIcon, RectF(pad - 10.0f*s_f, 0, iconSize, H_f), &sfCenter, &whiteBr);
                
                // Draw Text + TimeLabel
                std::wstring combined = text;
                if (!timeLab.empty()) combined += L"  " + timeLab;
                Font fRem(&ffFinal, (REAL)(14.0f * s_f), FontStyleRegular, UnitPixel);
                RectF rcText(pad + iconSize - 4.0f*s_f, 0, checkBtnX - (pad + iconSize), H_f);
                g.DrawString(combined.c_str(), -1, &fRem, rcText, &sfLeft, &whiteBr);

                // Check Button (Next or Done)
                g.FillEllipse(&greenBr, checkBtnX, btnY, btnSize, btnSize);
                g.DrawLine(&whitePen, checkBtnX + btnSize*0.3f, btnY + btnSize*0.5f, checkBtnX + btnSize*0.45f, btnY + btnSize*0.7f);
                g.DrawLine(&whitePen, checkBtnX + btnSize*0.45f, btnY + btnSize*0.7f, checkBtnX + btnSize*0.75f, btnY + btnSize*0.35f);

            } else if (islandState_ == IslandState::FocusBar) {
                // FocusBar: [Title] [Timer]
                std::wstring timeStr;
                int ds = (mode_ == 1) ? (int)((nowMs - endMs_) / 1000) : (int)((endMs_ - nowMs) / 1000);
                timeStr = FmtSecs(ds);

                std::wstring displayTitle = title_;
                if (displayTitle.empty() && !tags_.empty()) displayTitle = tags_[0];
                if (displayTitle.empty()) displayTitle = L"\u81ea\u7531\u4e13\u6ce8";

                Font fTitle(&ffFinal, (REAL)(14.0f * s_f), FontStyleRegular, UnitPixel);
                Font fTime(&ffFinal, (REAL)(16.0f * s_f), FontStyleBold, UnitPixel);
                
                float sepX = W_f * 0.6f;
                RectF rcTitle(r, 0, sepX - r, H_f);
                RectF rcTime(sepX, 0, W_f - sepX - r, H_f);
                
                g.DrawString(displayTitle.c_str(), -1, &fTitle, rcTitle, &sfLeft, &whiteBr);
                g.DrawString(timeStr.c_str(), -1, &fTime, rcTime, &sfCenter, &whiteBr);

            } else if (islandState_ == IslandState::FinishConfirm || islandState_ == IslandState::AbandonConfirm) {
                // Expansion triggered already in Show()
            } else if (islandState_ == IslandState::DetailCard) {
                // Expanded Detail Card rendering
                std::wstring icon = L"\u2630";
                if (detailCard_.type == L"course") icon = L"\u2666";
                else if (detailCard_.type == L"birthday") icon = L"\u2605";
                else if (detailCard_.type == L"countdown") icon = L"\u25C6";
                
                float pad = 12.0f * s_f;
                float iconSize = 28.0f * s_f;
                float textX = pad + iconSize + 8.0f * s_f;
                float textW = W_f - textX - pad;
                float lineH = 18.0f * s_f;
                float y = pad;
                
                Font fIcon(&ffFinal, (REAL)(20.0f * s_f), FontStyleRegular, UnitPixel);
                g.DrawString(icon.c_str(), -1, &fIcon, RectF(pad, pad, iconSize, iconSize), &sfCenter, &whiteBr);
                
                std::wstring displayTitle = detailCard_.title;
                if (displayTitle.empty()) displayTitle = L"\u6682\u65e0\u8be6\u60c5";
                Font fTitle(&ffFinal, (REAL)(15.0f * s_f), FontStyleBold, UnitPixel);
                StringFormat sfDetailLeft;
                sfDetailLeft.SetAlignment(StringAlignmentNear);
                sfDetailLeft.SetLineAlignment(StringAlignmentNear);
                sfDetailLeft.SetTrimming(StringTrimmingEllipsisCharacter);
                g.DrawString(displayTitle.c_str(), -1, &fTitle, RectF(textX, y, textW, lineH), &sfDetailLeft, &whiteBr);
                y += lineH;
                
                if (!detailCard_.subtitle.empty()) {
                    Font fSub(&ffFinal, (REAL)(12.0f * s_f), FontStyleRegular, UnitPixel);
                    SolidBrush subBr(Color(220, 200, 200, 200));
                    g.DrawString(detailCard_.subtitle.c_str(), -1, &fSub, RectF(textX, y, textW, lineH), &sfDetailLeft, &subBr);
                    y += lineH;
                }
                if (!detailCard_.location.empty()) {
                    Font fLoc(&ffFinal, (REAL)(12.0f * s_f), FontStyleRegular, UnitPixel);
                    SolidBrush locBr(Color(200, 180, 180, 220));
                    g.DrawString(detailCard_.location.c_str(), -1, &fLoc, RectF(textX, y, textW, lineH), &sfDetailLeft, &locBr);
                    y += lineH;
                }
                if (!detailCard_.time.empty()) {
                    Font fTime(&ffFinal, (REAL)(12.0f * s_f), FontStyleRegular, UnitPixel);
                    SolidBrush timeBr(Color(200, 180, 220, 180));
                    g.DrawString(detailCard_.time.c_str(), -1, &fTime, RectF(textX, y, textW, lineH), &sfDetailLeft, &timeBr);
                    y += lineH;
                }
                if (!detailCard_.note.empty()) {
                    Font fNote(&ffFinal, (REAL)(11.0f * s_f), FontStyleItalic, UnitPixel);
                    SolidBrush noteBr(Color(180, 160, 160, 160));
                    g.DrawString(detailCard_.note.c_str(), -1, &fNote, RectF(textX, y, textW, lineH), &sfDetailLeft, &noteBr);
                }

            } else {
                // Default Island State (Capsule Clock)
                std::wstring timeStr;
                if (endMs_ == 0) {
                    time_t t = time(nullptr); tm local; localtime_s(&local, &t);
                    wchar_t buf[16]; swprintf_s(buf, L"%02d:%02d", local.tm_hour, local.tm_min);
                    timeStr = buf;
                } else {
                    int ds = (mode_ == 1) ? (int)((nowMs - endMs_) / 1000) : (int)((endMs_ - nowMs) / 1000);
                    timeStr = FmtSecs(ds);
                }

                // Island Base Rendering (centered title/timer) - Only if not hovering or fully interactive
                if (islandState_ == IslandState::Default || anim_ < 1.0f) {
                    float defaultAlpha = (1.0f - anim_);
                    if (defaultAlpha < 0) defaultAlpha = 0;
                    if (defaultAlpha > 0) {
                        bool isFocusMode = (endMs_ > 0);
                        if (isFocusMode && anim_ < 0.5f) {
                            float alpha = (0.5f - anim_) * 2.0f * defaultAlpha;
                            if (alpha < 0) alpha = 0;
                            SolidBrush brush(Color((BYTE)(255 * alpha), 255, 255, 255));
                            SolidBrush titleBr(Color((BYTE)(200 * alpha), 200, 200, 200));

                            std::wstring displayTitle = title_;
                            if (displayTitle.empty() && !tags_.empty()) displayTitle = tags_[0];
                            if (displayTitle.empty()) displayTitle = L"\u81ea\u7531\u4e13\u6ce8";

                            // Title + Timer
                            Font fTitle(&ffFinal, (REAL)(11.0f * s_f), FontStyleRegular, UnitPixel);
                            Font fTime(&ffFinal, (REAL)(16.0f * s_f), FontStyleBold, UnitPixel);
                            RectF rcTitle(0.0f, 4.0f * s_f, W_f, H_f * 0.4f);
                            RectF rcTime(0.0f, 18.0f * s_f, W_f, H_f * 0.6f);
                            g.DrawString(displayTitle.c_str(), -1, &fTitle, rcTitle, &sfCenter, &titleBr);
                            g.DrawString(timeStr.c_str(), -1, &fTime, rcTime, &sfCenter, &brush);
                        } else {
                            Font fTime(&ffFinal, (REAL)(18.0f * s_f), FontStyleBold, UnitPixel);
                            SolidBrush brush(Color((BYTE)(255 * defaultAlpha), 255, 255, 255));
                            g.DrawString(timeStr.c_str(), -1, &fTime, RectF(0.0f, 0.0f, W_f, H_f), &sfCenter, &brush);
                        }
                    }
                }
            }

            // Overlay Interactive States (Hovered/Confirm)
            if (anim_ > 0.0f && (islandState_ == IslandState::Hovered || islandState_ == IslandState::FinishConfirm || islandState_ == IslandState::AbandonConfirm)) {
                float alpha = anim_;
                SolidBrush brushAnim(Color((BYTE)(255 * alpha), 255, 255, 255));
                Pen whitePenAnim(Color((BYTE)(255 * alpha), 255, 255, 255), 2.0f);
                SolidBrush greenBrAnim(Color((BYTE)(200 * alpha), 46, 125, 50));
                SolidBrush redBrAnim(Color((BYTE)(200 * alpha), 211, 47, 47));

                std::wstring timeStr;
                int ds = (mode_ == 1) ? (int)((nowMs - endMs_) / 1000) : (int)((endMs_ - nowMs) / 1000);
                timeStr = FmtSecs(ds);

                if (islandState_ == IslandState::Hovered && isLocal_) {
                    float btnSpace = 8.0f * s_f;
                    float x2 = W_f - r - btnSize;      // ✗ on right
                    float x1 = x2 - btnSize - btnSpace; // ✓ to its left
                    std::wstring displayTitle = title_;
                    if (displayTitle.empty() && !tags_.empty()) displayTitle = tags_[0];
                    if (displayTitle.empty()) displayTitle = L"\u81ea\u7531\u4e13\u6ce8";
                    std::wstring combined = displayTitle + L" " + timeStr;
                    Font fText(&ffFinal, (REAL)(13.0f * s_f), FontStyleRegular, UnitPixel);
                    RectF rcText(r, 0.0f, x1 - r - 4.0f * s_f, H_f);
                    g.DrawString(combined.c_str(), -1, &fText, rcText, &sfLeft, &brushAnim);
                    g.FillEllipse(&greenBrAnim, x1, btnY, btnSize, btnSize);
                    g.DrawLine(&whitePenAnim, x1 + btnSize*0.3f, btnY + btnSize*0.5f, x1 + btnSize*0.45f, btnY + btnSize*0.7f);
                    g.DrawLine(&whitePenAnim, x1 + btnSize*0.45f, btnY + btnSize*0.7f, x1 + btnSize*0.75f, btnY + btnSize*0.35f);
                    g.FillEllipse(&redBrAnim, x2, btnY, btnSize, btnSize);
                    g.DrawLine(&whitePenAnim, x2 + btnSize*0.35f, btnY + btnSize*0.35f, x2 + btnSize*0.65f, btnY + btnSize*0.65f);
                    g.DrawLine(&whitePenAnim, x2 + btnSize*0.65f, btnY + btnSize*0.35f, x2 + btnSize*0.35f, btnY + btnSize*0.65f);
                } else if (islandState_ == IslandState::FinishConfirm) {
                    std::wstring msg = L"\u672c\u6b21\u4e13\u6ce8\u65f6\u957f " + timeStr;
                    Font fMsg(&ffFinal, (REAL)(14.0f * s_f), FontStyleRegular, UnitPixel);
                    float finishBtnX = W_f - r - btnSize;
                    RectF rcMsg(0.0f, 0.0f, W_f, H_f);
                    g.DrawString(msg.c_str(), -1, &fMsg, rcMsg, &sfCenter, &brushAnim);
                    g.FillEllipse(&greenBrAnim, finishBtnX, btnY, btnSize, btnSize);
                    g.DrawLine(&whitePenAnim, finishBtnX + btnSize*0.3f, btnY + btnSize*0.5f, finishBtnX + btnSize*0.45f, btnY + btnSize*0.7f);
                    g.DrawLine(&whitePenAnim, finishBtnX + btnSize*0.45f, btnY + btnSize*0.7f, finishBtnX + btnSize*0.75f, btnY + btnSize*0.35f);
                } else if (islandState_ == IslandState::AbandonConfirm) {
                    std::wstring msg = L"\u786e\u8ba4\u653e\u5f03\u5417\uff1f";
                    Font fMsg(&ffFinal, (REAL)(15.0f * s_f), FontStyleRegular, UnitPixel);
                    float x1 = r; // ✓ on left
                    float x2 = W_f - r - btnSize; // ✗ on right
                    RectF rcMsg(0.0f, 0.0f, W_f, H_f);
                    g.DrawString(msg.c_str(), -1, &fMsg, rcMsg, &sfCenter, &brushAnim);
                    g.FillEllipse(&greenBrAnim, x1, btnY, btnSize, btnSize);
                    g.DrawLine(&whitePenAnim, x1 + btnSize*0.3f, btnY + btnSize*0.5f, x1 + btnSize*0.45f, btnY + btnSize*0.7f);
                    g.DrawLine(&whitePenAnim, x1 + btnSize*0.45f, btnY + btnSize*0.7f, x1 + btnSize*0.75f, btnY + btnSize*0.35f);
                    g.FillEllipse(&redBrAnim, x2, btnY, btnSize, btnSize);
                    g.DrawLine(&whitePenAnim, x2 + btnSize*0.35f, btnY + btnSize*0.35f, x2 + btnSize*0.65f, btnY + btnSize*0.65f);
                    g.DrawLine(&whitePenAnim, x2 + btnSize*0.65f, btnY + btnSize*0.35f, x2 + btnSize*0.35f, btnY + btnSize*0.65f);
                }
            }
        }
    }

    BLENDFUNCTION bf = {};
    bf.BlendOp             = AC_SRC_OVER;
    bf.SourceConstantAlpha = alpha_;
    bf.AlphaFormat         = AC_SRC_ALPHA;
    POINT ptDest = { winX_, winY_ };
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
    if (wParam == 1) { // 1s clock
        auto nowMs = (long long)std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
        if (self->mode_ == 0 && self->style_ == Style::Classic && nowMs >= self->endMs_) { 
            self->Hide(); return 0; 
        }
    } else if (wParam == 2) { // animation
        if (self->dragging_ || self->resizing_) return 0;

        auto now = std::chrono::steady_clock::now();
        float dt = std::chrono::duration<float>(now - self->lastAnimTime_).count();
        self->lastAnimTime_ = now;
        if (dt > 0.1f) dt = 0.016f; // cap for frame drops

        float step = dt * 6.0f; // Expand fully in ~160ms

        {
            std::lock_guard<std::recursive_mutex> lock(self->mtx_);
            bool animDone = false;
            if (self->isExpanded_) {
                self->anim_ += step;
                if (self->anim_ >= 1.0f) { self->anim_ = 1.0f; animDone = true; }
            } else {
                self->anim_ -= step;
                if (self->anim_ <= 0.0f) { self->anim_ = 0.0f; animDone = true; }
            }

            bool heightDone = true; // Default to true if not in Island
            if (self->style_ == Style::Island) {
                heightDone = false;
                float targetW = (float)self->expandW_;
                if (self->islandState_ == IslandState::DetailCard || 
                    self->islandState_ == IslandState::TopBar || 
                    self->islandState_ == IslandState::FocusBar) {
                    targetW = 300.0f; // Redesigned wide bars
                }
                
                float newW = (float)self->shrunkW_ + (targetW - (float)self->shrunkW_) * self->anim_;
                // Height animation for redesigned states + detail card
                float baseH = (float)self->islandH_;
                if (self->islandState_ == IslandState::TopBar || self->islandState_ == IslandState::FocusBar) {
                    baseH = (float)self->islandH_ * 1.5f; // 72px
                }
                
                float targetH = self->isHeightExpanding_ ? (float)self->detailCardH_ : baseH;
                float hAnim = self->heightAnim_;
                float newH = baseH; 
                
                if (self->isHeightExpanding_) {
                    newH = baseH + (targetH - baseH) * hAnim;
                    self->heightAnim_ += step * 0.8f; 
                    if (self->heightAnim_ >= 1.0f) { self->heightAnim_ = 1.0f; heightDone = true; }
                } else {
                    // If not expanding but current H matches targetH, we are at baseH/TopBar height
                    newH = baseH;
                    heightDone = true;
                }
                
                self->winW_ = (int)newW;
                self->winH_ = (int)newH;
                if (!self->dragging_ && !self->resizing_) {
                    self->winX_ = (int)(self->centerX_ - (double)newW * (double)self->dpiScale_ / 2.0);
                    self->winY_ = (int)(self->centerY_ - (double)newH * (double)self->dpiScale_ / 2.0);
                }

                // Animate height
                if (self->isHeightExpanding_) {
                    self->heightAnim_ += step;
                    if (self->heightAnim_ >= 1.0f) { self->heightAnim_ = 1.0f; heightDone = true; }
                } else if (self->heightAnim_ > 0.0f) {
                    self->heightAnim_ -= step;
                    if (self->heightAnim_ <= 0.0f) {
                        self->heightAnim_ = 0.0f;
                        heightDone = true;
                        // Fully collapsed, reset to pill height
                        self->winH_ = (int)baseH;
                    }
                } else {
                    heightDone = true;
                }
            }

            if (animDone && heightDone) {
                KillTimer(hwnd, 2);
            }
        }
    }
    {
        std::lock_guard<std::recursive_mutex> lock(self->mtx_);
        self->Render();
    }
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

// checkmark button click for reminder — dismiss reminder → return to clock
if (self->isReminderActive_ && self->style_ == Style::Island) {
    float s = self->GetScale();
    float W = (float)self->winW_ * s;
    float H = (float)self->winH_ * s;
    float r = H / 2.0f;
    float btnSize = 28.0f * s;
    float btnX = W - r - btnSize;
    float btnY = (H - btnSize) / 2.0f;
    
    // Check button click (Next Reminder or Dismiss)
    if (pt.x >= btnX && pt.x <= btnX + btnSize && pt.y >= btnY && pt.y <= btnY + btnSize) {
        std::lock_guard<std::recursive_mutex> lock(self->mtx_);
        if (!self->reminderQueue_.empty()) {
            self->reminderQueueIndex_++;
            if (self->reminderQueueIndex_ >= (int)self->reminderQueue_.size()) {
                self->isReminderActive_ = false;
                self->reminderQueue_.clear();
                self->reminderQueueIndex_ = 0;
            }
        } else {
            self->isReminderActive_ = false;
            self->reminderText_.clear();
            self->reminderType_.clear();
        }
        
        if (!self->isReminderActive_) {
            // Restore to appropriate state
            if (self->endMs_ > 0) self->islandState_ = IslandState::FocusBar;
            else self->islandState_ = IslandState::TopBar;
        }
        
        self->Render();
        return 0;
    }
    
    // Click on pill body: expand to detail card
    if (self->islandState_ != IslandState::DetailCard) {
        std::lock_guard<std::recursive_mutex> lock(self->mtx_);
        self->islandState_ = IslandState::DetailCard;
        self->isHeightExpanding_ = true;
        self->isExpanded_ = true;
        self->lastAnimTime_ = std::chrono::steady_clock::now();
        SetTimer(hwnd, 2, 16, nullptr);
        self->Render();
        return 0;
    }
}

// Logic for Island Interactive States
if (self->style_ == Style::Island && !self->isReminderActive_) {
    // DetailCard: click anywhere to collapse
    if (self->islandState_ == IslandState::DetailCard) {
        std::lock_guard<std::recursive_mutex> lock(self->mtx_);
        self->islandState_ = IslandState::Default;
        self->isHeightExpanding_ = false;
        self->isReminderActive_ = false;
        self->reminderText_.clear();
        self->reminderType_.clear();
        self->isExpanded_ = false;
        self->lastAnimTime_ = std::chrono::steady_clock::now();
        SetTimer(hwnd, 2, 16, nullptr);
        self->Render();
        return 0;
    }

    float s = self->GetScale();
    float W = (float)self->winW_ * s;
    float H = (float)self->winH_ * s;
    float r = H / 2.0f;
    
    if (self->islandState_ == IslandState::Hovered) {
        float btnSize = 28.0f * s;
        float btnY = (H - btnSize) / 2.0f;
        float btnSpace = 8.0f * s;
        float x2 = W - r - btnSize;      // ✗ on right
        float x1 = x2 - btnSize - btnSpace; // ✓ to its left

        // Check button (Finish Early)
        if (pt.x >= x1 && pt.x <= x1 + btnSize && pt.y >= btnY && pt.y <= btnY + btnSize) {
            std::lock_guard<std::recursive_mutex> lock(self->mtx_);
            self->islandState_ = IslandState::FinishConfirm;
            auto nowMs = (long long)std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
            if (self->mode_ == 1) {
                self->modifiedSecs_ = (int)((nowMs - self->endMs_) / 1000);
            } else {
                self->modifiedSecs_ = (int)((self->endMs_ - nowMs) / 1000);
            }
            self->isModified_ = false;
            self->Render();
            return 0;
        }
        // Abandon button
        if (pt.x >= x2 && pt.x <= x2 + btnSize && pt.y >= btnY && pt.y <= btnY + btnSize) {
            std::lock_guard<std::recursive_mutex> lock(self->mtx_);
            self->islandState_ = IslandState::AbandonConfirm;
            self->Render();
            return 0;
        }
    } else if (self->islandState_ == IslandState::FinishConfirm) {
        float btnSize = 28.0f * s;
        float btnX = W - r - btnSize;
        float btnY = (H - btnSize) / 2.0f;
        // Confirm finish
        if (pt.x >= btnX && pt.x <= btnX + btnSize && pt.y >= btnY && pt.y <= btnY + btnSize) {
            {
                std::lock_guard<std::recursive_mutex> lock(self->mtx_);
                if (self->actionCallback_) self->actionCallback_("finish", self->modifiedSecs_);
                self->endMs_ = 0; // Immediate clear
                self->islandState_ = IslandState::Default;
                self->isExpanded_ = false;
                self->lastAnimTime_ = std::chrono::steady_clock::now();
                SetTimer(hwnd, 2, 16, nullptr);
            }
            self->Render();
            return 0;
        }
    } else if (self->islandState_ == IslandState::AbandonConfirm) {
        float btnSize = 28.0f * s;
        float btnY = (H - btnSize) / 2.0f;
        float x1 = r; // ✓ on left
        float x2 = W - r - btnSize; // ✗ on right

        // Check (Confirm abandon)
        if (pt.x >= x1 && pt.x <= x1 + btnSize && pt.y >= btnY && pt.y <= btnY + btnSize) {
            {
                std::lock_guard<std::recursive_mutex> lock(self->mtx_);
                if (self->actionCallback_) self->actionCallback_("abandon", 0);
                self->endMs_ = 0; // Immediate clear
                self->islandState_ = IslandState::Default;
                self->isExpanded_ = false;
                self->lastAnimTime_ = std::chrono::steady_clock::now();
                SetTimer(hwnd, 2, 16, nullptr);
            }
            self->Render();
            return 0;
        }

        // X (Cancel abandon) - reset to Default/Hovered and KEEP session
        if (pt.x >= x2 && pt.x <= x2 + btnSize && pt.y >= btnY && pt.y <= btnY + btnSize) {
            {
                std::lock_guard<std::recursive_mutex> lock(self->mtx_);
                self->islandState_ = IslandState::Default; // or Hovered? Default is safer.
                self->isExpanded_ = (self->endMs_ > 0); 
                self->lastAnimTime_ = std::chrono::steady_clock::now();
                SetTimer(hwnd, 2, 16, nullptr);
            }
            self->Render();
            return 0;
        }
    }
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

if (self->style_ == Style::Island && !self->dragging_ && !self->resizing_) {
    // Only enter Hovered state (with buttons) if a LOCAL focus session is active
    if ((self->islandState_ == IslandState::Default || self->islandState_ == IslandState::FocusBar) 
        && self->endMs_ > 0 && self->isLocal_) {
        std::lock_guard<std::recursive_mutex> lock(self->mtx_);
        self->islandState_ = IslandState::Hovered;
        if (!self->isExpanded_) {
            self->isExpanded_ = true;
            self->lastAnimTime_ = std::chrono::steady_clock::now();
            SetTimer(hwnd, 2, 16, nullptr);
        }
        TRACKMOUSEEVENT tme = { sizeof(tme), TME_LEAVE, hwnd, 0 };
        TrackMouseEvent(&tme);
        self->Render();
    } else if (self->islandState_ == IslandState::Default && self->endMs_ == 0) {
        // Still expand for clock view, but don't enter Hovered (no buttons)
        if (!self->isExpanded_) {
            std::lock_guard<std::recursive_mutex> lock(self->mtx_);
            self->isExpanded_ = true;
            self->lastAnimTime_ = std::chrono::steady_clock::now();
            SetTimer(hwnd, 2, 16, nullptr);
            TRACKMOUSEEVENT tme = { sizeof(tme), TME_LEAVE, hwnd, 0 };
            TrackMouseEvent(&tme);
            self->Render();
        }
    }
}


if (self->resizing_) {
    POINT cur = pt;
    ClientToScreen(hwnd, &cur);
    int dx = cur.x - self->resizeStart_.x;
    int dy = cur.y - self->resizeStart_.y;
    {
        std::lock_guard<std::recursive_mutex> lock(self->mtx_);
        self->winW_ = std::max(MIN_W, self->resizeOrigW_ + dx);
        self->winH_ = std::max(MIN_H, self->resizeOrigH_ + dy);
    }
    self->Render();
    return 0;
}

    if (self->dragging_) {
        POINT cur = pt;
        ClientToScreen(hwnd, &cur);
        int nextX = self->winStart_.x + (cur.x - self->dragStart_.x);
        int nextY = self->winStart_.y + (cur.y - self->dragStart_.y);
        {
            std::lock_guard<std::recursive_mutex> lock(self->mtx_);
            // Clamp and update floating-point center
            self->winX_ = std::clamp(nextX, -10000, 10000);
            self->winY_ = std::clamp(nextY, -10000, 10000);
            self->centerX_ = (double)self->winX_ + (double)self->winW_ / 2.0;
            self->centerY_ = (double)self->winY_ + (double)self->winH_ / 2.0;
        }
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

case WM_MOUSELEAVE:
if (self && self->style_ == Style::Island) {
    std::lock_guard<std::recursive_mutex> lock(self->mtx_);
    if (self->islandState_ == IslandState::Hovered) {
        self->islandState_ = IslandState::Default;
    }
    // Only collapse if not in a confirm state
    // Only collapse the pill view when there's no active session (endMs_ == 0).
    // If a session is active, keep the island expanded so it continues to show
    // the focus/floating content instead of reverting to the small clock pill.
    if (self->islandState_ == IslandState::Default && self->endMs_ == 0) {
        self->isExpanded_ = false;
        self->lastAnimTime_ = std::chrono::steady_clock::now();
        SetTimer(hwnd, 2, 16, nullptr);
    }
    self->Render();
}

break;

case WM_LBUTTONUP:
if (self) {
    if (self->resizing_) {
        std::lock_guard<std::recursive_mutex> lock(self->mtx_);
        self->resizing_ = false;
        ReleaseCapture();
        RECT wr; GetWindowRect(hwnd, &wr);
        self->centerX_ = (double)wr.left + (double)(wr.right - wr.left) / 2.0;
        self->centerY_ = (double)wr.top + (double)(wr.bottom - wr.top) / 2.0;
        self->SaveState();
        return 0;
    }
    if (self->dragging_) {
        std::lock_guard<std::recursive_mutex> lock(self->mtx_);
        self->dragging_ = false;
        ReleaseCapture();
        RECT wr; GetWindowRect(hwnd, &wr);
        self->centerX_ = (double)wr.left + (double)(wr.right - wr.left) / 2.0;
        self->centerY_ = (double)wr.top + (double)(wr.bottom - wr.top) / 2.0;
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


case WM_CLOSE:
DestroyWindow(hwnd);
break;

case WM_DESTROY:
self->hwnd_ = nullptr;
self->running_ = false;
KillTimer(hwnd, 1);
PostQuitMessage(0);
break;
}
return DefWindowProcW(hwnd, msg, wParam, lParam);
}

void FloatWindow::RunLoop() {
    GdiplusStartupInput gi;
    GdiplusStartup(&gdiplusToken_, &gi, nullptr);
    LoadState();

    if (style_ == Style::Island) {
        // Use persisted window size as the island's shrunk/base size instead
        // of overwriting it with a compile-time constant. This preserves
        // user-adjusted sizes across UI transitions.
        shrunkW_ = winW_;
        islandH_ = winH_;
        // Ensure expandW_ is at least as large as shrunkW_
        if (expandW_ < shrunkW_) expandW_ = shrunkW_;
    }

    float s = GetScale();
    int W = (int)(winW_ * s);
    int H = (int)(winH_ * s);

    HINSTANCE hInst = GetModuleHandleW(nullptr);
    WNDCLASSEXW wc = {};
    wc.cbSize        = sizeof(wc);
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInst;
    wc.lpszClassName = kClass;
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassExW(&wc);

    int x = (winX_ >= 0) ? winX_ : GetSystemMetrics(SM_CXSCREEN) - W - 20;
    int y = (winY_ >= 0) ? winY_ : 20;

    hwnd_ = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE,
            kClass, L"", WS_POPUP,
            x, y, W, H, 
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
                       const std::vector<std::wstring>& tags, bool isLocal, int mode,
                       int style, const std::wstring& left, const std::wstring& right,
                       bool forceReset, const std::wstring& reminder,
                       const std::wstring& reminderType,
                       const DetailCardInfo& detail,
                       const std::wstring& topBarLeft,
                       const std::wstring& topBarRight,
                       const std::vector<ReminderItem>& reminderQueue) {
    {
        // Debug: log entry to Show with key params (use OutputDebugStringW for Windows Debug viewers)
        wchar_t dbg[256];
        _snwprintf_s(dbg, _countof(dbg), L"[FloatWindow] Show called endMs=%lld isLocal=%d mode=%d style=%d forceReset=%d", endMs, isLocal ? 1 : 0, mode, style, forceReset ? 1 : 0);
        OutputDebugStringW(dbg);

        std::lock_guard<std::recursive_mutex> lock(mtx_);
        isLocal_ = isLocal;
        endMs_ = endMs;
        title_ = title;
        tags_ = tags;
        mode_ = mode;
        style_ = (Style)style;
        leftText_ = left;
        rightText_ = right;
        detailCard_ = detail;
        topBarLeft_ = topBarLeft;
        topBarRight_ = topBarRight;
        
        // Update reminder queue
        if (!reminderQueue.empty()) {
            reminderQueue_ = reminderQueue;
            reminderQueueIndex_ = 0;
            isReminderActive_ = true;
        }

        // Auto-reset state when session ends or changes significantly
        if (style_ == Style::Island) {
            if (endMs_ == 0 && !isReminderActive_ && islandState_ != IslandState::DetailCard) {
                islandState_ = IslandState::TopBar;
                // For TopBar, we want it expanded by default or animated? 
                // Let's ensure isExpanded_ is true if we want it to show immediately.
                if (!isExpanded_) {
                    isExpanded_ = true;
                    lastAnimTime_ = std::chrono::steady_clock::now();
                }
            } else if (endMs_ > 0) {
                // Enter FocusBar whenever a session is active (endMs_ > 0),
                // unless we're currently showing a DetailCard or in a confirm flow.
                if (islandState_ != IslandState::DetailCard &&
                    islandState_ != IslandState::FinishConfirm &&
                    islandState_ != IslandState::AbandonConfirm &&
                    islandState_ != IslandState::FocusBar) {
                    islandState_ = IslandState::FocusBar;
                }
                // Ensure the pill is expanded to show focus content
                if (!isExpanded_) {
                    isExpanded_ = true;
                    lastAnimTime_ = std::chrono::steady_clock::now();
                }
            }
            // Immediately apply size for island to avoid transient collapse
            // when Show() is called repeatedly by Flutter UI transitions.
            // Compute desired dimensions based on current islandState_
            if (islandState_ == IslandState::TopBar || islandState_ == IslandState::FocusBar) {
                int desiredW = std::max(expandW_, shrunkW_);
                int desiredH = (int)(islandH_ * 1.5f);
                winW_ = desiredW;
                winH_ = desiredH;
            } else {
                // Default / DetailCard / Hovered -> use shrunk/base sizes or detail height
                winW_ = shrunkW_;
                winH_ = islandH_;
            }
            // Apply window size immediately if hwnd exists
            if (hwnd_) {
                int sW = (int)(winW_ * dpiScale_);
                int sH = (int)(winH_ * dpiScale_);
                SetWindowPos(hwnd_, HWND_TOP, winX_, winY_, sW, sH, SWP_NOACTIVATE | SWP_NOZORDER);
            }
        } else {
            if (endMs_ == 0 && !isReminderActive_) {
                if (islandState_ != IslandState::Default) {
                    islandState_ = IslandState::Default;
                    isExpanded_ = false;
                    anim_ = 0.0f;
                }
            }
        }

        if (!reminder.empty()) {
            reminderText_ = reminder;
            reminderType_ = reminderType;
            isReminderActive_ = true;
            // Reset detail card state when new reminder arrives
            if (islandState_ == IslandState::DetailCard) {
                islandState_ = IslandState::Default;
                heightAnim_ = 0.0f;
                isHeightExpanding_ = false;
            }
        }

        // Sizing Logic
        if (style_ == Style::Island) {
            // Target dimensions based on state
            int targetH = (int)islandH_;
            int targetW = expandW_;

            if (islandState_ == IslandState::TopBar || islandState_ == IslandState::FocusBar) {
                targetH = (int)(islandH_ * 1.5f);
                // Use persisted expandW_ if available, fallback to ensure >= shrunkW_
                targetW = std::max(expandW_, shrunkW_);
            }

            // Don't reset height if DetailCard is actively expanding
            if (islandState_ != IslandState::DetailCard || heightAnim_ <= 0.0f) {
                // Smoothly transition winH_ if not in animation loop
                // Or let the animation loop handle it? 
                // Let's set the base winH_ but allow animation to override.
                winH_ = targetH;
            }
            
            // Trigger animation if dimension targets changed
            if (!isExpanded_) {
                isExpanded_ = true;
                lastAnimTime_ = std::chrono::steady_clock::now();
                SetTimer(hwnd_, 2, 16, nullptr);
            }
            
            winW_ = (int)(shrunkW_ + (targetW - shrunkW_) * anim_);
        } else {
            winW_ = 300;
            winH_ = 110;
        }
        
        lastAnimTime_ = std::chrono::steady_clock::now();
        
        if (forceReset || !hwnd_ || !IsWindow(hwnd_)) {
            int sw = GetSystemMetrics(SM_CXSCREEN);
            int sh = GetSystemMetrics(SM_CYSCREEN);
            if (forceReset) {
                // Place slightly toward the top instead of exact center.
                winX_ = (sw - (int)(winW_ * dpiScale_)) / 2;
                // Prefer any configured default top value stored in registry.
                int configuredTop = -1;
                HKEY key;
                if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegKey, 0, KEY_READ, &key) == ERROR_SUCCESS) {
                    configuredTop = RegGetInt(key, L"DefaultTop", -1);
                    RegCloseKey(key);
                }
                if (configuredTop != -1) {
                    winY_ = configuredTop;
                } else {
                    winY_ = std::max(12, (int)(sh * 0.12f));
                }
            }
            centerX_ = (double)winX_ + (double)(winW_ * dpiScale_) / 2.0;
            centerY_ = (double)winY_ + (double)(winH_ * dpiScale_) / 2.0;
        }
    }

    if (!running_ || !hwnd_ || !IsWindow(hwnd_)) {
        if (thread_.joinable()) {
            running_ = false; 
            thread_.join();
        }
        anim_ = 0.0f;
        isExpanded_ = false;
        running_ = true;
        thread_ = std::thread([this]() { RunLoop(); });
    } else {
        // Window already exists — reapply size + position for style changes
        int sw = (int)(winW_ * dpiScale_);
        int sh = (int)(winH_ * dpiScale_);
        ShowWindow(hwnd_, SW_SHOW);
        SetWindowPos(hwnd_, HWND_TOPMOST, winX_, winY_, sw, sh, SWP_SHOWWINDOW);
        SetTimer(hwnd_, 1, 1000, nullptr);
        // Trigger immediate render on the window thread
        PostMessageW(hwnd_, WM_TIMER, 1, 0);
    }
}

void FloatWindow::Hide() {
    if (hwnd_ && IsWindow(hwnd_)) {
        ShowWindow(hwnd_, SW_HIDE);
        KillTimer(hwnd_, 1);
        KillTimer(hwnd_, 2);
    }
}

FloatWindow::~FloatWindow() {
    running_ = false;
    if (hwnd_ && IsWindow(hwnd_)) PostMessageW(hwnd_, WM_CLOSE, 0, 0);
    if (thread_.joinable()) thread_.join();
}
