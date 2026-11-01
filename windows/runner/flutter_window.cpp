#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "shell_integration.h"

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

static std::string StringField(const EncodableMap& m, const char* key) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return std::string();
  const auto* s = std::get_if<std::string>(&it->second);
  return s ? *s : std::string();
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Друга копія MHRD знаходить це вікно за властивістю (shell::ForwardToRunningInstance).
  ::SetPropW(GetHandle(), shell::kMainWindowProp, reinterpret_cast<HANDLE>(1));
  shell_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), "mhrd/shell",
      &flutter::StandardMethodCodec::GetInstance());
  shell_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "setRecent") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (!args) {
      result->Error("args", "map expected");
      return;
    }
    std::vector<shell::RecentItem> items;
    auto list = args->find(EncodableValue("items"));
    if (list != args->end()) {
      if (const auto* l = std::get_if<EncodableList>(&list->second)) {
        for (const auto& v : *l) {
          if (const auto* m = std::get_if<EncodableMap>(&v)) {
            items.push_back({StringField(*m, "id"), StringField(*m, "title")});
          }
        }
      }
    }
    shell::SetRecent(shell::Utf8ToWide(StringField(*args, "category")), items);
    result->Success();
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      // Інша копія MHRD: показати вікно і, якщо передано id, підключитись до цього ПК.
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (!data || data->dwData != shell::kCopyDataTag) break;
      if (::IsIconic(hwnd)) ::ShowWindow(hwnd, SW_RESTORE);
      ::SetForegroundWindow(hwnd);
      const std::string id(static_cast<const char*>(data->lpData), data->cbData);
      if (!id.empty() && shell_channel_) {
        shell_channel_->InvokeMethod("connect", std::make_unique<EncodableValue>(id));
      }
      return TRUE;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
