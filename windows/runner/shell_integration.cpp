#include "shell_integration.h"

#include <objectarray.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <cwctype>

using Microsoft::WRL::ComPtr;

namespace shell {

static std::wstring ExePath() {
  wchar_t exe[MAX_PATH];
  const DWORD n = ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  return n && n < MAX_PATH ? std::wstring(exe, n) : std::wstring();
}

static std::wstring ExeDir() {
  std::wstring dir = ExePath();
  const size_t slash = dir.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring() : dir.substr(0, slash);
}

bool IsPortable() {
  static const bool portable = [] {
    const std::wstring dir = ExeDir();
    if (dir.empty()) return false;
    const DWORD attrs = ::GetFileAttributesW((dir + L"\\portable.txt").c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
  }();
  return portable;
}

const wchar_t* AppId() { return IsPortable() ? L"mhrd.portable" : L"mhrd.desktop"; }

ULONG_PTR InstanceKey() {
  static const ULONG_PTR key = [] {
    if (!IsPortable()) return static_cast<ULONG_PTR>(1);
    // FNV-1a від шляху до .exe без урахування регістру; 0 і 1 зайняті.
    uint32_t h = 2166136261u;
    for (wchar_t c : ExePath()) {
      h ^= static_cast<uint32_t>(std::towlower(c));
      h *= 16777619u;
    }
    return static_cast<ULONG_PTR>(h < 2 ? h + 2 : h);
  }();
  return key;
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
  return out;
}

static BOOL CALLBACK FindMain(HWND hwnd, LPARAM out) {
  if (reinterpret_cast<ULONG_PTR>(::GetPropW(hwnd, kMainWindowProp)) == InstanceKey()) {
    *reinterpret_cast<HWND*>(out) = hwnd;
    return FALSE;
  }
  return TRUE;
}

bool ForwardToRunningInstance(const std::string& connect_id) {
  // Іменований м'ютекс живе, поки живе перша копія; вікно шукаємо за нашою властивістю.
  const std::wstring mutex = IsPortable() ? L"Local\\mhrd-portable-" + std::to_wstring(InstanceKey())
                                          : std::wstring(L"Local\\mhrd-main-instance");
  ::CreateMutexW(nullptr, FALSE, mutex.c_str());
  if (::GetLastError() != ERROR_ALREADY_EXISTS) return false;
  HWND main = nullptr;
  for (int i = 0; i < 50 && !main; i++) {  // перша копія може ще створювати вікно
    ::EnumWindows(FindMain, reinterpret_cast<LPARAM>(&main));
    if (!main) ::Sleep(100);
  }
  if (!main) return false;
  DWORD pid = 0;
  ::GetWindowThreadProcessId(main, &pid);
  ::AllowSetForegroundWindow(pid);
  COPYDATASTRUCT data{kCopyDataTag, static_cast<DWORD>(connect_id.size()),
                      const_cast<char*>(connect_id.data())};
  // З обмеженням часу: якщо перша копія зависла, ця не має висіти разом із нею.
  DWORD_PTR reply = 0;
  return ::SendMessageTimeoutW(main, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data),
                               SMTO_ABORTIFHUNG, 5000, &reply) != 0;
}

static ComPtr<IShellLinkW> MakeLink(const std::wstring& exe, const RecentItem& item) {
  ComPtr<IShellLinkW> link;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) {
    return nullptr;
  }
  const std::wstring args = L"--connect " + Utf8ToWide(item.id);
  link->SetPath(exe.c_str());
  link->SetArguments(args.c_str());
  link->SetIconLocation(exe.c_str(), 0);
  ComPtr<IPropertyStore> props;
  if (SUCCEEDED(link.As(&props))) {
    PROPVARIANT title;
    if (SUCCEEDED(::InitPropVariantFromString(Utf8ToWide(item.title).c_str(), &title))) {
      props->SetValue(PKEY_Title, title);
      props->Commit();
      ::PropVariantClear(&title);
    }
  }
  return link;
}

void SetRecent(const std::wstring& category, const std::vector<RecentItem>& items) {
  wchar_t exe[MAX_PATH];
  if (!::GetModuleFileNameW(nullptr, exe, MAX_PATH)) return;
  ComPtr<ICustomDestinationList> list;
  if (FAILED(::CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list)))) {
    return;
  }
  list->SetAppID(AppId());
  UINT max_slots = 0;
  ComPtr<IObjectArray> removed;
  if (FAILED(list->BeginList(&max_slots, IID_PPV_ARGS(&removed)))) return;
  ComPtr<IObjectCollection> collection;
  if (FAILED(::CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&collection)))) {
    list->AbortList();
    return;
  }
  for (const auto& item : items) {
    if (auto link = MakeLink(exe, item)) collection->AddObject(link.Get());
  }
  ComPtr<IObjectArray> array;
  if (!items.empty() && SUCCEEDED(collection.As(&array))) {
    list->AppendCategory(category.c_str(), array.Get());
  }
  list->CommitList();
}

// Назва ПК → ім'я файлу: без символів, заборонених Windows, і не задовге.
static std::wstring SafeFileName(const std::wstring& name) {
  std::wstring out;
  for (wchar_t c : name) {
    if (c < 32 || wcschr(L"<>:\"/\\|?*", c)) c = L'_';
    out += c;
  }
  while (!out.empty() && (out.back() == L' ' || out.back() == L'.')) out.pop_back();
  while (!out.empty() && out.front() == L' ') out.erase(0, 1);
  if (out.size() > 80) out.resize(80);
  return out.empty() ? std::wstring(L"PC") : out;
}

std::wstring CreateDesktopShortcut(const std::string& id, const std::string& name) {
  const std::wstring exe = ExePath();
  if (exe.empty() || id.empty()) return std::wstring();
  PWSTR desktop = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &desktop))) return std::wstring();
  const std::wstring path = std::wstring(desktop) + L"\\" + SafeFileName(Utf8ToWide(name)) + L" (MHRD).lnk";
  ::CoTaskMemFree(desktop);

  ComPtr<IShellLinkW> link;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) {
    return std::wstring();
  }
  const std::wstring args = L"--connect " + Utf8ToWide(id);
  link->SetPath(exe.c_str());
  link->SetArguments(args.c_str());
  link->SetWorkingDirectory(ExeDir().c_str());
  link->SetIconLocation(exe.c_str(), 0);
  link->SetDescription(Utf8ToWide(name).c_str());
  // Той самий AppUserModelID, що й у вікна, — інакше Windows групує ярлик окремим значком.
  ComPtr<IPropertyStore> props;
  if (SUCCEEDED(link.As(&props))) {
    PROPVARIANT app;
    if (SUCCEEDED(::InitPropVariantFromString(AppId(), &app))) {
      props->SetValue(PKEY_AppUserModel_ID, app);
      props->Commit();
      ::PropVariantClear(&app);
    }
  }
  ComPtr<IPersistFile> file;
  if (FAILED(link.As(&file)) || FAILED(file->Save(path.c_str(), TRUE))) return std::wstring();
  ::SHChangeNotify(SHCNE_CREATE, SHCNF_PATHW, path.c_str(), nullptr);
  return path;
}

bool OpenOnScreenKeyboard() {
  // osk.exe вимагає uiAccess — CreateProcess відмовить, ShellExecute запускає правильно.
  return reinterpret_cast<INT_PTR>(::ShellExecuteW(nullptr, L"open", L"osk.exe", nullptr, nullptr, SW_SHOWNORMAL)) > 32;
}

}  // namespace shell
