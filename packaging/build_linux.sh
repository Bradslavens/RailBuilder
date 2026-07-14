#!/usr/bin/env bash
# Build the Linux release: a Godot export plus a self-contained AppImage.
#
#   ./packaging/build_linux.sh            # export + AppImage  -> dist/
#   VERSION=0.2.0 ./packaging/build_linux.sh
#
# Output:
#   build/linux/RailBuilder.x86_64            plain binary (pck embedded)
#   dist/RailBuilder-<version>-x86_64.AppImage  what you hand to players / itch.io
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-0.1.0}"
GODOT="${GODOT:-godot4}"
PRESET="Linux"
APPDIR="build/RailBuilder.AppDir"
TOOLS="build/tools"

# An AppImage is just: [ELF runtime] + [squashfs image of the AppDir], concatenated.
# We assemble it directly rather than via appimagetool, whose continuous build
# ships a broken libgio. This runtime is statically linked, so the finished
# AppImage runs on distros that ship only fuse3 (Ubuntu 24.04+), no libfuse2 needed.
RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64"

command -v mksquashfs >/dev/null || { echo "!! need mksquashfs (apt install squashfs-tools)"; exit 1; }

mkdir -p "$TOOLS" build/linux dist

if [ ! -x "$TOOLS/runtime-x86_64" ]; then
  echo ">> fetching AppImage runtime"
  curl -fsSL -o "$TOOLS/runtime-x86_64" "$RUNTIME_URL"
  chmod +x "$TOOLS/runtime-x86_64"
fi

echo ">> importing assets"
"$GODOT" --headless --import >/dev/null 2>&1 || true

echo ">> exporting $PRESET (release)"
rm -f build/linux/RailBuilder.x86_64
"$GODOT" --headless --export-release "$PRESET" | tail -1
[ -f build/linux/RailBuilder.x86_64 ] || { echo "!! export produced no binary"; exit 1; }

echo ">> staging AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp build/linux/RailBuilder.x86_64 "$APPDIR/usr/bin/RailBuilder"
cp packaging/AppRun "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun" "$APPDIR/usr/bin/RailBuilder"
cp packaging/RailBuilder.desktop "$APPDIR/RailBuilder.desktop"
cp packaging/railbuilder-256.png "$APPDIR/railbuilder.png"
cp packaging/railbuilder-256.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/railbuilder.png"

echo ">> building AppImage"
OUT="dist/RailBuilder-${VERSION}-x86_64.AppImage"
rm -f "$OUT" build/RailBuilder.squashfs
mksquashfs "$APPDIR" build/RailBuilder.squashfs \
  -root-owned -noappend -no-progress -quiet -comp zstd -Xcompression-level 19 -b 1M
cat "$TOOLS/runtime-x86_64" build/RailBuilder.squashfs > "$OUT"
chmod +x "$OUT"
rm -f build/RailBuilder.squashfs

[ -f "$OUT" ] || { echo "!! AppImage build failed"; exit 1; }
echo
echo "== done: $OUT ($(du -h "$OUT" | cut -f1))"
