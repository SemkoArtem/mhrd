#include "shell_integration.h"

#include <objectarray.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shobjidl.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace shell {

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
  return out;
}

static BOOL CALLBACK FindMain(HWND hwnd, LPARAM out) {
  if (::GetPropW(hwnd, kMainWindowProp)) {
    *reinterpret_cast<HWND*>(out) = hwnd;
    return FALSE;
  }
  return TRUE;
}

bool ForwardToRunningInstance(const std::string& connect_id) {
  // Іменований м'ютекс живе, поки живе перша копія; вікно шукаємо за нашою властивістю.
  ::CreateMutexW(nullptr, FALSE, L"Local\\mhrd-main-instance");
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
  ::SendMessageW(main, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data));
  return true;
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
  list->SetAppID(kAppId);
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

}  // namespace shell
