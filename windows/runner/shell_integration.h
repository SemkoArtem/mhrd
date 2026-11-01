#ifndef RUNNER_SHELL_INTEGRATION_H_
#define RUNNER_SHELL_INTEGRATION_H_

// Інтеграція з оболонкою Windows: один екземпляр MHRD і список «Недавні» на значку в панелі
// завдань (Jump List, правий клік). Клік по ПК у списку запускає `mhrd.exe --connect <id>`:
// якщо MHRD уже відкритий, аргументи передаються йому (WM_COPYDATA), а новий процес завершується.

#include <windows.h>

#include <string>
#include <vector>

namespace shell {

// Ідентифікатор застосунку для панелі завдань — однаковий для вікна й Jump List.
inline constexpr wchar_t kAppId[] = L"mhrd.desktop";

// Ознака головного вікна MHRD (властивість вікна), щоб друга копія його знайшла.
inline constexpr wchar_t kMainWindowProp[] = L"MHRD_MAIN_WINDOW";

// dwData у WM_COPYDATA: «MHRD».
inline constexpr ULONG_PTR kCopyDataTag = 0x4D485244;

// Якщо MHRD уже працює — передає йому id ПК (порожній — просто показати вікно) і повертає true.
bool ForwardToRunningInstance(const std::string& connect_id);

struct RecentItem {
  std::string id;
  std::string title;
};

// Перебудовує список «Недавні» на значку MHRD у панелі завдань.
void SetRecent(const std::wstring& category, const std::vector<RecentItem>& items);

std::wstring Utf8ToWide(const std::string& s);

}  // namespace shell

#endif  // RUNNER_SHELL_INTEGRATION_H_
