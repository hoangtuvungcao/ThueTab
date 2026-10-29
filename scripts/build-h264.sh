#!/usr/bin/env bash
# Build the app's H.264 decoder (GDExtension, native-ext/) for every platform into native/h264/bin/.
# Needs: gcc (Linux), x86_64-w64-mingw32-gcc (Windows), Android NDK (Android + macOS: its clang, ld64.lld, llvm-lipo).
#
#   bash scripts/build-h264.sh [--ndk /path/to/ndk]
#
# The prebuilt libraries are committed, so this only has to run after changing native-ext/.
set -euo pipefail
cd "$(dirname "$0")/../native-ext"
NDK_ROOT="${ANDROID_NDK_ROOT:-$(ls -d "$HOME"/Android/Sdk/ndk/* 2>/dev/null | sort -V | tail -1)}"
[ "${1:-}" = "--ndk" ] && NDK_ROOT="$2"
NDK="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
[ -x "$NDK/clang" ] || { echo "Không tìm thấy Android NDK; dùng --ndk /đường/dẫn/ndk" >&2; exit 1; }
OUT=../native/h264/bin
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SRC=(gd_h264.c tt_h264.c h264bsd/*.c)
mkdir -p "$OUT"

echo "==> Linux x86_64"
gcc -O2 -fPIC -shared -fvisibility=hidden -w -I. -o "$OUT/libthuetab_h264.linux.x86_64.so" "${SRC[@]}" -lm

echo "==> Windows x86_64"
x86_64-w64-mingw32-gcc -O2 -shared -w -I. -static-libgcc -o "$OUT/thuetab_h264.windows.x86_64.dll" "${SRC[@]}"

echo "==> Android arm64 / arm32"
"$NDK/clang" --target=aarch64-linux-android24 -O2 -fPIC -shared -fvisibility=hidden -w -I. -Wl,-z,max-page-size=16384 \
  -o "$OUT/libthuetab_h264.android.arm64.so" "${SRC[@]}" -lm
"$NDK/clang" --target=armv7a-linux-androideabi24 -O2 -fPIC -shared -fvisibility=hidden -w -I. \
  -o "$OUT/libthuetab_h264.android.arm32.so" "${SRC[@]}" -lm

# macOS without the Apple SDK: libc comes from macos-shim/ (malloc/memcpy… resolved from libSystem at load time).
echo "==> macOS universal (arm64 + x86_64)"
RES="$("$NDK/clang" -print-resource-dir)"
for A in arm64 x86_64; do
  "$NDK/clang" -target "$A-apple-macos11" -O2 -fPIC -shared -fvisibility=hidden -fno-stack-protector -w \
    -ffreestanding -nostdinc -nostdlib -isystem "$RES/include" -isystem macos-shim -I. -fuse-ld=lld \
    -Wl,-undefined,dynamic_lookup -Wl,-platform_version,macos,11.0,11.0 \
    -Wl,-install_name,@rpath/libthuetab_h264.macos.universal.dylib -o "$TMP/h264-$A.dylib" "${SRC[@]}"
done
"$NDK/llvm-lipo" -create -output "$OUT/libthuetab_h264.macos.universal.dylib" "$TMP/h264-arm64.dylib" "$TMP/h264-x86_64.dylib"

"$NDK/llvm-strip" "$OUT"/*.so
ls -lh "$OUT"
