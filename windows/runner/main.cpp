#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr ULONG_PTR kDeepLinkCopyData = 0x43445444;  // CDTD
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\CountDownTodo.MainWindow.SingleInstance";

bool IsCountDownTodoDeepLink(const std::string& arg) {
  return arg.rfind("countdowntodo://", 0) == 0 ||
         arg.rfind("countdowntodo:/", 0) == 0;
}

bool SendDeepLinkToRunningWindow(const std::string& link) {
  HWND existing_window =
      ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"math_quiz_app");
  if (existing_window == nullptr) {
    return false;
  }

  COPYDATASTRUCT copy_data{};
  copy_data.dwData = kDeepLinkCopyData;
  copy_data.cbData = static_cast<DWORD>(link.size() + 1);
  copy_data.lpData = const_cast<char*>(link.c_str());

  DWORD_PTR result = 0;
  const LRESULT sent = ::SendMessageTimeoutW(
      existing_window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&copy_data),
      SMTO_ABORTIFHUNG, 2000, &result);
  if (sent == 0) {
    return false;
  }

  if (::IsIconic(existing_window)) {
    ::ShowWindow(existing_window, SW_RESTORE);
  } else {
    ::ShowWindow(existing_window, SW_SHOW);
  }
  ::SetForegroundWindow(existing_window);
  return true;
}

bool FocusRunningWindow() {
  HWND existing_window =
      ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"math_quiz_app");
  if (existing_window == nullptr) {
    return false;
  }

  if (::IsIconic(existing_window)) {
    ::ShowWindow(existing_window, SW_RESTORE);
  } else {
    ::ShowWindow(existing_window, SW_SHOW);
  }
  ::SetForegroundWindow(existing_window);
  return true;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    for (const auto& arg : command_line_arguments) {
      if (IsCountDownTodoDeepLink(arg)) {
        SendDeepLinkToRunningWindow(arg);
        ::CloseHandle(single_instance_mutex);
        ::CoUninitialize();
        return EXIT_SUCCESS;
      }
    }

    FocusRunningWindow();
    ::CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  for (const auto& arg : command_line_arguments) {
    if (IsCountDownTodoDeepLink(arg) && SendDeepLinkToRunningWindow(arg)) {
      if (single_instance_mutex != nullptr) {
        ::CloseHandle(single_instance_mutex);
      }
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"math_quiz_app", origin, size)) {
    if (single_instance_mutex != nullptr) {
      ::ReleaseMutex(single_instance_mutex);
      ::CloseHandle(single_instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex != nullptr) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
