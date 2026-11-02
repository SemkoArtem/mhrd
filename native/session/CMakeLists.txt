# mhrd-session: окремий процес сеансу RDP над FreeRDP 3 (SPEC → «Архітектура»).
# Залежності — через vcpkg (vcpkg.json поруч), статично: один .exe без DLL FreeRDP/OpenSSL.
# Збірка: Windows — native/session/build.ps1, Linux — build.sh, Android — build-android.sh.
cmake_minimum_required(VERSION 3.21)
project(mhrd_session C)

set(CMAKE_C_STANDARD 11)
# Статичний CRT, як у триплеті vcpkg x64-windows-static.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(UNIX AND NOT APPLE AND NOT ANDROID)
  # Звук і мікрофон FreeRDP на Linux (rdpsnd/audin pulse, див. оверлей) посилаються на ціль
  # PulseAudio::PulseAudio — дає її системна libpulse через pkg-config.
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(PULSE REQUIRED IMPORTED_TARGET libpulse)
  add_library(PulseAudio::PulseAudio INTERFACE IMPORTED)
  target_link_libraries(PulseAudio::PulseAudio INTERFACE PkgConfig::PULSE)
endif()

if(ANDROID)
  # Звук і мікрофон FreeRDP на Android (rdpsnd/audin aaudio) посилаються на ціль AAudio::AAudio —
  # системна libaaudio з NDK.
  add_library(AAudio::AAudio INTERFACE IMPORTED)
  target_link_libraries(AAudio::AAudio INTERFACE aaudio)
endif()

find_package(FreeRDP-Client CONFIG REQUIRED)
find_package(FreeRDP CONFIG REQUIRED)
find_package(WinPR CONFIG REQUIRED)
find_package(cJSON CONFIG REQUIRED)

if(ANDROID)
  # Android: без власного вікна (сеанс показує застосунок) і поки без буфера обміну.
  set(MHRD_WINDOW src/window_none.c)
  set(MHRD_CLIPBOARD src/clipboard_none.c)
else()
  # Власне вікно сеансу (SDL3) і текст плашки (SDL3_ttf)
  find_package(SDL3 CONFIG REQUIRED)
  find_package(SDL3_ttf CONFIG REQUIRED)
  set(MHRD_WINDOW src/window_sdl.c)
  if(WIN32)
    set(MHRD_CLIPBOARD src/clipboard_win.c)
  else()
    # Linux (X11 і Wayland) — буфер обміну через SDL3
    set(MHRD_CLIPBOARD src/clipboard_sdl.c)
  endif()
endif()

add_executable(mhrd-session src/main.c src/proto.c src/shm.c ${MHRD_WINDOW} ${MHRD_CLIPBOARD})
target_link_libraries(mhrd-session PRIVATE freerdp-client freerdp winpr cjson)
if(ANDROID)
  # Android запускає лише файли з теки бібліотек застосунку, а туди потрапляють тільки lib*.so —
  # тож програма зветься libmhrd_session.so (це все одно виконуваний файл, PIE).
  set_target_properties(mhrd-session PROPERTIES OUTPUT_NAME "libmhrd_session.so")
  target_link_libraries(mhrd-session PRIVATE log)
else()
  target_link_libraries(mhrd-session PRIVATE SDL3::SDL3 SDL3_ttf::SDL3_ttf)
endif()
if(WIN32)
  # Іконка вікна сеансу (та сама, що в MHRD)
  target_sources(mhrd-session PRIVATE src/mhrd-session.rc)
endif()

if(WIN32)
  # Буфер обміну: OLE-об'єкт для файлів із сервера (ole32, uuid), CF_HDROP і перелік форматів (shell32).
  target_link_libraries(mhrd-session PRIVATE ole32 uuid shell32)
endif()

if(MSVC)
  target_compile_options(mhrd-session PRIVATE /W4 /utf-8)
  target_compile_definitions(mhrd-session PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
