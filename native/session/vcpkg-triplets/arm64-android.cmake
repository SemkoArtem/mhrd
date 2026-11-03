# MHRD: як вбудований триплет vcpkg, але Android 7 (API 24) замість 9 — щоб модуль сеансу працював і
# на старих телефонах. Звук FreeRDP тоді — OpenSL ES (AAudio з'явився лише в API 26).
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_CMAKE_SYSTEM_VERSION 24)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DANDROID_ABI=arm64-v8a)
