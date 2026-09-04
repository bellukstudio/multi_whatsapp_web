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
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/multi_whatsapp_web" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "==> 3. Fetching linuxdeploy (if not already present)"
LINUXDEPLOY="build/linuxdeploy-x86_64.AppImage"
if [ ! -f "$LINUXDEPLOY" ]; then
  curl -L -o "$LINUXDEPLOY" \
    https://github.com/linuxdeploy/linuxdeploy/releases/latest/download/linuxdeploy-x86_64.AppImage
  chmod +x "$LINUXDEPLOY"
fi

echo "==> 4. Packaging AppImage"
export VERSION="${VERSION:-1.0.4}"
# NO_STRIP: linuxdeploy bundles its own (older) `strip` binary, which
# chokes on the `.relr.dyn` relocation section that modern toolchains
# (e.g. current Arch Linux) emit by default — every "unknown type [0x13]
# section .relr.dyn" error above is exactly that mismatch, and it's a
# known linuxdeploy limitation, not something wrong with this project's
# build. Skipping the strip step avoids it entirely; the AppImage will
# just be a bit larger (unstripped debug symbols kept in) rather than
# broken/incomplete.
NO_STRIP=true "$LINUXDEPLOY" --appdir "$APPDIR" --output appimage

echo "==> Done. Look for ${APP_NAME}-${VERSION}-x86_64.AppImage in the current directory."