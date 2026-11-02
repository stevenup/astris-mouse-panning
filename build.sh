#!/bin/bash
# 编译注入用的 dylib。不会修改 Astris.app 内任何文件。
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${ASTRIS_APP:-/Applications/Astris.app}"
FRAMEWORKS="$APP/Contents/Frameworks"
OUT="$DIR/build"

if [ ! -f "$FRAMEWORKS/libryujinx.dylib" ]; then
  echo "找不到 $FRAMEWORKS/libryujinx.dylib（可用 ASTRIS_APP 指定 Astris.app 路径）" >&2
  exit 1
fi

mkdir -p "$OUT"

clang -c -O2 -target arm64-apple-macos15.0 -Wall \
  -I"$DIR/Sources" "$DIR/Sources/interpose.c" -o "$OUT/interpose.o"

swiftc -O -swift-version 5 -target arm64-apple-macos15.0 \
  -emit-library -module-name AstrisMouse \
  -import-objc-header "$DIR/Sources/bridge.h" \
  "$DIR/Sources/AstrisMouse.swift" "$OUT/interpose.o" \
  -framework AppKit -framework QuartzCore \
  -L"$FRAMEWORKS" -lryujinx \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -install_name -Xlinker @rpath/libAstrisMouse.dylib \
  -o "$OUT/libAstrisMouse.dylib"

codesign --force --sign - "$OUT/libAstrisMouse.dylib"

clang -O2 -target arm64-apple-macos15.0 -Wall "$DIR/Sources/launcher.c" -o "$OUT/astris-launch"
codesign --force --sign - "$OUT/astris-launch"

echo "OK: $OUT/libAstrisMouse.dylib"
echo "OK: $OUT/astris-launch"
