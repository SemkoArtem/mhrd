#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <shobjidl.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "shell_integration.h"
#include "utils.h"

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

  // Один екземпляр MHRD: друга копія (зокрема з «Недавніх» на значку) передає першій, який ПК
  // відкрити, і завершується.
  std::string connect_id;
  for (size_t i = 0; i + 1 < command_line_arguments.size(); i++) {
    if (command_line_arguments[i] == "--connect") connect_id = command_line_arguments[i + 1];
  }
  if (shell::ForwardToRunningInstance(connect_id)) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }
  ::SetCurrentProcessExplicitAppUserModelID(shell::kAppId);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Шаблонні 1280×720 при масштабі Windows 150 % — це 1920×1080, тобто весь екран разом із панеллю
  // завдань. Тож: не більше 90 % робочої області (без панелі завдань) основного монітора, по центру.
  // Win32Window::Create множить на масштаб сам — рахуємо в його одиницях.
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  {
    HMONITOR monitor = ::MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info{sizeof(info)};
    if (::GetMonitorInfoW(monitor, &info)) {
      const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
      const double workW = (info.rcWork.right - info.rcWork.left) / scale;
      const double workH = (info.rcWork.bottom - info.rcWork.top) / scale;
      size = Win32Window::Size(static_cast<unsigned int>(std::min(1280.0, workW * 0.9)),
                               static_cast<unsigned int>(std::min(800.0, workH * 0.9)));
      origin = Win32Window::Point(static_cast<unsigned int>(info.rcWork.left / scale + (workW - size.width) / 2),
                                  static_cast<unsigned int>(info.rcWork.top / scale + (workH - size.height) / 2));
    }
  }
  if (!window.Create(L"mhrd", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
