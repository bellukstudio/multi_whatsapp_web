cmake_minimum_required(VERSION 3.10)
project(runner LANGUAGES CXX)

set(BINARY_NAME "multi_whatsapp_web")
set(APPLICATION_ID "com.bellukstudio.multi_whatsapp_web")

cmake_policy(SET CMP0063 NEW)
# Newer CMake (e.g. Arch's rolling-release version) defaults policies
# introduced after `cmake_minimum_required`'s version to OLD behavior.
# CMP0079 (introduced in CMake 3.13, above our 3.10 floor) needs to be
# NEW here so `flutter/generated_plugins.cmake`'s target_link_libraries
# calls can reference each plugin's target, which is defined in a
# different subdirectory scope — without this, CMake errors with
# "not built in this directory. This is allowed only when policy
# CMP0079 is set to NEW."
cmake_policy(SET CMP0079 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# --- ADDED: webkit2gtk, for the native per-account embedded WebView
# (linux/webkit_multi_view_plugin.cc). Tries webkit2gtk-4.1 first (newer
# distros, e.g. current Arch), falls back to webkit2gtk-4.0 (older/other
# distros). If your system has neither, install one via your package
# manager first (Arch: `sudo pacman -S webkit2gtk-4.1` or `webkit2gtk`).
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(WEBKIT2GTK IMPORTED_TARGET webkit2gtk-4.1)
if(NOT WEBKIT2GTK_FOUND)
  pkg_check_modules(WEBKIT2GTK REQUIRED IMPORTED_TARGET webkit2gtk-4.0)
endif()
# --- END ADDED

add_subdirectory(${FLUTTER_MANAGED_DIR})

# Applications need to update and re-run this function if they change how
# their binary is named.
set(BUILD_NUMBER "1")
if(DEFINED ENV{FLUTTER_BUILD_NUMBER})
  set(BUILD_NUMBER $ENV{FLUTTER_BUILD_NUMBER})
endif()
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")
add_compile_options(-Wno-deprecated-literal-operator)

add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and
# adding them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# By default, "installing" just means building a copy of the
# application in a location other than the build directory, so that
# it can be tested without installing on the host system.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# App icon for the running window (title bar/taskbar/dock) — see
# set_window_icon() in runner/my_application.cc, which looks for this at
# <exe_dir>/data/icon.png. Sourced from linux/appimage/icon.png so the
# AppImage launcher icon and the running-window icon are always the same
# file; only warns (doesn't fail the build) if it's missing, matching how
# the AppImage script itself falls back to a placeholder.
if(EXISTS "${CMAKE_SOURCE_DIR}/appimage/icon.png")
  install(FILES "${CMAKE_SOURCE_DIR}/appimage/icon.png"
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
    COMPONENT Runtime)
else()
  message(WARNING "linux/appimage/icon.png not found — the built app "
    "will fall back to GTK's generic default window icon. Add a "
    "256x256 PNG there and rebuild to fix this.")
endif()

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Fully re-copy the assets directory on each build to avoid having stale
# files from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/flutter_assets"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()