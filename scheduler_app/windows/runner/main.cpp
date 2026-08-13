#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "app_links/app_links_plugin_c_api.h"

// Google ile girişin Windows'taki geri dönüşü (G8b).
//
// Tarayıcı `dizge://login-callback...` adresine yönlendiğinde Windows,
// registry'deki kayda bakıp uygulamayı **yeni bir süreç** olarak başlatır
// (bkz. tools/dizge_scheme.ps1). Bu fonksiyon olmasaydı kullanıcının önünde
// iki kopya açık kalırdı: jetonu alan yeni pencere ve az önce düğmeye bastığı
// eski pencere. Onun yerine adres WM_COPYDATA ile çalışan örneğe geçiriliyor
// ve yeni süreç hiç pencere açmadan kapanıyor.
//
// Pencere başlığı aşağıdaki `window.Create` çağrısıyla **birebir aynı**
// olmalı; ayrışırlarsa dönüş sessizce ikinci bir kopya açar.
bool SendAppLinkToInstance(const std::wstring& title) {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title.c_str());
  if (!hwnd) {
    return false;
  }

  SendAppLink(hwnd);

  // Çalışan örneği öne al — kullanıcı tarayıcıdan dönüyor ve uygulamayı
  // görmeyi bekliyor. Simge durumundaysa eski boyutuna döner.
  WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
  GetWindowPlacement(hwnd, &place);
  switch (place.showCmd) {
    case SW_SHOWMAXIMIZED:
      ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ShowWindow(hwnd, SW_NORMAL);
      break;
  }
  SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
               SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
  SetForegroundWindow(hwnd);

  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Zaten açık bir pencere varsa bu süreç yalnızca adresi taşıyıcıdır.
  if (SendAppLinkToInstance(L"scheduler_app")) {
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

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"scheduler_app", origin, size)) {
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
