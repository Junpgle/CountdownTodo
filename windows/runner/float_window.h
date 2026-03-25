#pragma once
#include <windows.h>
#include <gdiplus.h>
#include <string>
#include <vector>
#include <mutex>
#include <functional>
#include <thread>
#include <atomic>
#include <chrono>



class FloatWindow {
public:
    static FloatWindow& instance() {
        static FloatWindow inst;
        return inst;
    }
    enum class Style { Classic = 0, Island = 1 };
    enum class IslandState { Default, Hovered, FinishConfirm, AbandonConfirm, DetailCard, TopBar, FocusBar };

    // Structured detail info for expanded cards
    struct DetailCardInfo {
        std::wstring type;     // "course", "todo", "countdown", "birthday"
        std::wstring title;
        std::wstring subtitle; // teacher / note
        std::wstring location;
        std::wstring time;
        std::wstring note;
    };
    
    struct ReminderItem {
        std::wstring text;
        std::wstring type;       // "course", "todo", "countdown", "birthday"
        std::wstring timeLabel;  // "20分钟后" or "!就是今天"
    };

    void Show(long long endMs, const std::wstring& title,
              const std::vector<std::wstring>& tags, bool isLocal, int mode = 0,
              int style = 0, const std::wstring& left = L"", const std::wstring& right = L"",
              bool forceReset = false, const std::wstring& reminder = L"",
              const std::wstring& reminderType = L"",
              const DetailCardInfo& detail = {},
              const std::wstring& topBarLeft = L"",
              const std::wstring& topBarRight = L"",
              const std::vector<ReminderItem>& reminderQueue = {});
    void Hide();
    
    // Callback for confirmed actions (Finish, Abandon)
    using ActionCallback = std::function<void(const std::string& action, int modifiedSecs)>;
    void SetActionCallback(ActionCallback cb) { 
        std::lock_guard<std::recursive_mutex> lock(mtx_);
        actionCallback_ = cb; 
    }


private:
    FloatWindow() = default;
    ~FloatWindow();

    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    void RunLoop();
    void Render();
    void SaveState();
    void LoadState();
    std::wstring FmtSecs(int secs);
    std::wstring BuildBottomLine();
    float GetScale();

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

    int   mode_  = 0;
    Style style_ = Style::Classic;
    bool isLocal_ = false;

    // island state
    bool  isExpanded_ = false;
    float anim_       = 0.0f; // 0: shrunk, 1: expanded
    std::wstring leftText_;
    std::wstring rightText_;
    bool isReminderActive_ = false;
    std::wstring reminderText_;
    std::wstring reminderType_; // "course", "todo", "countdown"
    
    // Interactive Island states
    IslandState islandState_ = IslandState::Default;
    int modifiedSecs_ = 0; // for count-up time modification
    bool isModified_ = false;
    ActionCallback actionCallback_ = nullptr;
    
    // Top bar content
    std::wstring topBarLeft_;
    std::wstring topBarRight_;

    // Reminder queue
    std::vector<ReminderItem> reminderQueue_;
    int reminderQueueIndex_ = 0;

    // Detail card
    DetailCardInfo detailCard_;
    float heightAnim_ = 0.0f;    // 0: pill height, 1: full card height
    int   detailCardH_ = 140;    // target height for detail card in logical px
    bool  isHeightExpanding_ = false;


    BYTE  alpha_ = 200;
    int   winX_  = -1;
    int   winY_  = -1;
    double centerX_ = 0;
    double centerY_ = 0;
    int   winW_  = 300;
    int   winH_  = 110;
    // If user manually resized and it was saved, avoid overwriting these
    // dimensions during subsequent Show()/Render calls unless forceReset.
    bool  userSized_ = false;

    int   shrunkW_ = 150;
    int   expandW_ = 220;
    int   islandH_ = 48;

    static constexpr int   MIN_W    = 150;
    static constexpr int   MIN_H    = 48;
    static constexpr int   RBORDER  = 8;
    static constexpr wchar_t kClass[]  = L"MathQuizFloatV3";
    static constexpr wchar_t kRegKey[] = L"Software\\MathQuiz\\FloatV3";

    ULONG_PTR gdiplusToken_ = 0;
    float dpiScale_ = 1.0f;
    mutable std::recursive_mutex mtx_;
    std::chrono::steady_clock::time_point lastAnimTime_;
};
