# mhrd-session: окремий процес сеансу RDP над FreeRDP 3 (SPEC → «Архітектура»).
# Залежності — через vcpkg (vcpkg.json поруч), статично: один .exe без DLL FreeRDP/OpenSSL.
# Збірка на Windows: native/session/build.ps1
cmake_minimum_required(VERSION 3.21)
project(mhrd_session C)

set(CMAKE_C_STANDARD 11)
# Статичний CRT, як у триплеті vcpkg x64-windows-static.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

find_package(FreeRDP-Client CONFIG REQUIRED)
find_package(FreeRDP CONFIG REQUIRED)
find_package(WinPR CONFIG REQUIRED)
find_package(cJSON CONFIG REQUIRED)

add_executable(mhrd-session src/main.c src/proto.c src/shm.c)
target_link_libraries(mhrd-session PRIVATE freerdp-client freerdp winpr cjson)

if(MSVC)
  target_compile_options(mhrd-session PRIVATE /W4 /utf-8)
  target_compile_definitions(mhrd-session PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
