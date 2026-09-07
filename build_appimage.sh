#!/usr/bin/env bash
# Build multiwhatsappweb as a Linux .AppImage.
# Run this from the FLUTTER PROJECT ROOT (folder containing pubspec.yaml).
set -euo pipefail

APP_NAME="multi_whatsapp_web"
APP_ID="com.bellukstudio.multiwhatsappweb"
BUNDLE_DIR="build/linux/x64/release/bundle"
APPDIR="build/AppDir"

echo "==> 1. Flutter release build"
flutter pub get
flutter build linux --release

if [ ! -f "$BUNDLE_DIR/$APP_NAME" ]; then
  echo "ERROR: expected binary not found at $BUNDLE_DIR/$APP_NAME"
  echo "Check linux/CMakeLists.txt BINARY_NAME if you renamed it."
  exit 1
fi

echo "==> 2. Assembling AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy the whole Flutter bundle (binary + data/ + lib/) as-is.
cp -r "$BUNDLE_DIR"/* "$APPDIR/usr/bin/"

# .desktop file — required by AppImage.
#
# FIX (taskbar/dock icon stuck on a generic fallback even though the
# app launcher/grid icon is correct): StartupWMClass is what lets
# GNOME Shell (and other WM_CLASS-matching taskbars/docks) correlate
# the ACTUALLY RUNNING window back to this .desktop entry to look up
# its icon — separate from, and in addition to, the app grid/launcher
# icon lookup, which reads the .desktop file directly and was already
# working. Without it, matching falls back to weaker heuristics that
# can fail (e.g. when launched from inside a mounted AppImage, or via
# AppImageLauncher's renamed/hashed integrated .desktop file), leaving
# the taskbar/dock showing GTK's generic default icon. This value must
# match the "application-id" my_application.cc registers the GApplication
# under (see APPLICATION_ID / g_set_prgname in that file) — that's what
# GTK actually reports as the window's app ID on both X11 and Wayland.
cat > "$APPDIR/usr/share/applications/${APP_ID}.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Multi WhatsApp Web
Exec=${APP_NAME}
Icon=${APP_ID}
Categories=Network;InstantMessaging;
Terminal=false
StartupWMClass=${APP_ID}
EOF
cp "$APPDIR/usr/share/applications/${APP_ID}.desktop" "$APPDIR/"

# Icon: put your real icon at linux/appimage/icon.png (256x256 PNG) before
# running this script for a proper app icon. If it's missing, generate a
# minimal but VALID 256x256 PNG placeholder instead of an empty file —
# linuxdeploy actually parses the icon file's contents to resolve the
# .desktop file's `Icon=` entry, so a 0-byte/empty file is rejected with
# "Could not find icon executable for Icon entry", even though a file
# with that name technically exists.
ICON_SRC="linux/appimage/icon.png"
ICON_DEST_HICOLOR="$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
ICON_DEST_ROOT="$APPDIR/${APP_ID}.png"

if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$ICON_DEST_HICOLOR"
  cp "$ICON_SRC" "$ICON_DEST_ROOT"
else
  echo "WARNING: $ICON_SRC not found — generating a placeholder icon."
  echo "Add a real 256x256 PNG there and re-run for a proper icon."
  if command -v python3 >/dev/null 2>&1; then
    # Smallest reliable way to emit a valid, arbitrary-size solid PNG
    # without extra dependencies (zlib is stdlib — no ImageMagick needed).
    python3 - "$ICON_DEST_HICOLOR" << 'PYEOF'
import struct, sys, zlib

path = sys.argv[1]
size = 256
# Solid WhatsApp-green square (RGB 37,211,102) — good enough as a
# placeholder; replace with a real icon for production builds.
row = bytes([0] + [37, 211, 102] * size)
raw = row * size

def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9))
png += chunk(b"IEND", b"")

with open(path, "wb") as f:
    f.write(png)
PYEOF
    cp "$ICON_DEST_HICOLOR" "$ICON_DEST_ROOT"
  else
    echo "ERROR: python3 not found — can't generate a placeholder icon."
    echo "Either install python3, or place a real PNG at $ICON_SRC."
    exit 1
  fi
fi

# AppRun — entry point AppImage executes.
#
# FIX (symbol lookup error: /usr/lib/libsecret-1.so.0: undefined symbol:
# g_task_set_static_name, on machines other than the one it was built on):
# LD_LIBRARY_PATH previously only pointed at ${HERE}/usr/bin/lib (the
# Flutter bundle's own lib/ folder). linuxdeploy copies ALL auto-detected
# shared-library dependencies (glib, gtk, webkit2gtk, libsecret, etc.)
# into ${HERE}/usr/lib instead — a different directory that was missing
# from LD_LIBRARY_PATH. Since linuxdeploy does not overwrite an AppRun
# that already exists in the AppDir, that omission stuck: at runtime the
# app silently fell back to loading these libraries from the HOST system
# instead of the ones bundled alongside it, causing ABI mismatches.
# Adding usr/lib (checked first) fixes that.
#
# "cd" into usr/: see the WebKit binary-patch step further below — it
# turns the compile-time-hardcoded "/usr/lib/.../WebKitNetworkProcess"
# path inside libwebkit2gtk into a RELATIVE "lib/.../WebKitNetworkProcess"
# path of the same length. A relative path is resolved against the
# process's current working directory, so we set that directory to
# ${HERE}/usr here — matching where "/usr" used to point — before
# exec'ing the real binary.
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"
cd "${HERE}/usr" || exit 1
exec "${HERE}/usr/bin/multi_whatsapp_web" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "==> 3. Fetching linuxdeploy + appimagetool (if not already present)"
LINUXDEPLOY="build/linuxdeploy-x86_64.AppImage"
if [ ! -f "$LINUXDEPLOY" ]; then
  curl -L -o "$LINUXDEPLOY" \
    https://github.com/linuxdeploy/linuxdeploy/releases/latest/download/linuxdeploy-x86_64.AppImage
  chmod +x "$LINUXDEPLOY"
fi
# We can't use linuxdeploy's built-in "--output appimage" one-shot mode
# anymore (see below for why), so we package with appimagetool directly.
APPIMAGETOOL="build/appimagetool-x86_64.AppImage"
if [ ! -f "$APPIMAGETOOL" ]; then
  curl -L -o "$APPIMAGETOOL" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$APPIMAGETOOL"
fi

export VERSION="${VERSION:-1.0.4}"

echo "==> 4. Deploying shared-library dependencies into AppDir"
# NO_STRIP: linuxdeploy bundles its own (older) `strip` binary, which
# chokes on the `.relr.dyn` relocation section that modern toolchains
# (e.g. current Arch Linux) emit by default — every "unknown type [0x13]
# section .relr.dyn" error is exactly that mismatch, and it's a known
# linuxdeploy limitation, not something wrong with this project's build.
# Skipping the strip step avoids it; the AppImage will just be a bit
# larger (unstripped debug symbols kept in) rather than broken/incomplete.
#
# Deliberately NOT passing --output appimage here (unlike before): that
# flag packages the AppImage immediately after deploying dependencies,
# leaving no chance to binary-patch libwebkit2gtk in between. We deploy
# only, patch, then package separately with appimagetool in step 6.
NO_STRIP=true "$LINUXDEPLOY" --appdir "$APPDIR"

# FIX (CRITICAL: "Unable to spawn a new child process: Failed to spawn
# child process /usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/WebKitNetworkProcess
# (No such file or directory)"):
#
# This is a well-known upstream WebKitGTK + AppImage packaging limitation
# (see linuxdeploy/linuxdeploy-plugin-gtk#42) — not specific to this
# project. libwebkit2gtk spawns WebKitNetworkProcess / WebKitWebProcess
# as separate HELPER EXECUTABLES (not .so files, so linuxdeploy's `ldd`
# based scan never finds them) from a path baked into the library at
# COMPILE TIME on the ubuntu-22.04 CI runner:
# /usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/. Any machine without that
# EXACT Debian/Ubuntu multiarch path (e.g. Arch, Fedora, Manjaro) fails
# with "No such file or directory" even though the AppImage otherwise
# runs fine — because WebKitGTK re-resolves this path at every runtime,
# it can't be fixed by an env var (WEBKIT_EXEC_PATH is not honored by
# current WebKitGTK versions).
#
# The only working fix (the same one the Tauri project ships in
# production, see tauri-apps/linuxdeploy-plugin-gtk) is to:
#   1. bundle that whole webkit2gtk directory, keeping its original
#      /usr/lib/<triplet>/webkit2gtk-<ver> path structure intact under
#      the AppDir, and
#   2. binary-patch every "/usr" (4 bytes) inside the bundled
#      libwebkit2gtk*.so files into "././" (also 4 bytes — same length,
#      so the file's internal offsets aren't corrupted), turning the
#      absolute system path into a relative path that resolves inside
#      the AppImage instead. AppRun's "cd" above is what makes that
#      relative path land in the right place at runtime.
echo "==> 4b. Bundling + patching WebKitGTK helper processes"
WEBKIT_TRIPLET="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
WEBKIT_SRC_DIR=""
for candidate in \
  "/usr/lib/${WEBKIT_TRIPLET}/webkit2gtk-4.1" \
  "/usr/lib/${WEBKIT_TRIPLET}/webkit2gtk-4.0" \
  "/usr/libexec/webkit2gtk-4.1" \
  "/usr/libexec/webkit2gtk-4.0"; do
  if [ -d "$candidate" ]; then
    WEBKIT_SRC_DIR="$candidate"
    break
  fi
done

if [ -n "$WEBKIT_SRC_DIR" ]; then
  echo "Found WebKit helper dir: $WEBKIT_SRC_DIR"
  WEBKIT_DEST_DIR="$APPDIR${WEBKIT_SRC_DIR}"
  mkdir -p "$WEBKIT_DEST_DIR"
  cp -r "$WEBKIT_SRC_DIR"/* "$WEBKIT_DEST_DIR/"
else
  echo "WARNING: no webkit2gtk helper-process directory found on this"
  echo "build machine — the in-app webview will likely fail to load."
fi

echo "Binary-patching hardcoded /usr paths inside bundled libwebkit*.so"
find "$APPDIR"/usr/lib* -name 'libwebkit*' -exec sed -i -e "s|/usr|././|g" '{}' \;

echo "==> 5. Packaging AppImage"
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "${APP_NAME}-${VERSION}-x86_64.AppImage"

echo "==> Done. Look for ${APP_NAME}-${VERSION}-x86_64.AppImage in the current directory."
