#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>
#include <functional>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // A separate data directory is useful for portable copies and isolated tests.
  wchar_t data_dir[32768] = {};
  GetEnvironmentVariableW(L"CORIANDER_DATA_DIR", data_dir, 32768);
  const auto suffix = std::to_wstring(std::hash<std::wstring>{}(data_dir));
  const auto mutex_name = L"Local\\CorianderPlayer_" + suffix;
  const auto window_title = L"coriander_player_" + suffix;
  HANDLE single_instance = CreateMutexW(nullptr, FALSE, mutex_name.c_str());
  if (single_instance != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    // Flutter can update the window title after startup. Identify our window
    // with a private property instead of relying on that user-visible title.
    HWND existing = nullptr;
    while ((existing = FindWindowExW(nullptr, existing, nullptr, nullptr)) != nullptr) {
      if (GetPropW(existing, mutex_name.c_str()) != nullptr) break;
    }
    if (existing != nullptr) {
      ShowWindowAsync(existing, IsIconic(existing) ? SW_RESTORE : SW_SHOW);
      SetForegroundWindow(existing);
    }
    CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(window_title.c_str(), origin, size)) {
    if (single_instance != nullptr) CloseHandle(single_instance);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  SetPropW(window.GetHandle(), mutex_name.c_str(), reinterpret_cast<HANDLE>(1));

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Destroy while the derived window is still alive and COM is available.
  // Leaving this to C++ member destruction tears down Flutter before the base
  // window destructor has a chance to hide the still-visible native window.
  window.Destroy();
  ::CoUninitialize();
  if (single_instance != nullptr) CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
