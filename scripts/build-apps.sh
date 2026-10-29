#!/usr/bin/env bash
# Build the native apps (Android, Windows, Linux, macOS) and publish them to data/downloads/,
# where the web "Tải ứng dụng" page picks them up. iOS uses the web app (PWA) instead.
#
#   bash scripts/build-apps.sh --api https://thuetab.example.vn [--godot /path/to/Godot] [--only Android,Linux]
#
# --api is baked into the apps: the server URL they talk to (same as PUBLIC_ORIGIN).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
API=""; GODOT="${GODOT:-}"; ONLY="Linux,Windows,Android,macOS"
while [ $# -gt 0 ]; do
  case "$1" in
    --api) API="$2"; shift 2 ;;
    --godot) GODOT="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    *) echo "Tham số không hợp lệ: $1" >&2; exit 1 ;;
  esac
done
[ -n "$API" ] || { echo "Thiếu --api (địa chỉ server mà app sẽ kết nối)" >&2; exit 1; }
GODOT="${GODOT:-$(command -v godot || command -v godot4 || true)}"
[ -x "$GODOT" ] || { echo "Không tìm thấy Godot 4.7; dùng --godot /đường/dẫn/Godot" >&2; exit 1; }

STAGE="$ROOT/.staging/native"
OUT="$ROOT/exports"
mkdir -p "$OUT" "$ROOT/data/downloads"
.venv/bin/python scripts/prepare-native.py >/dev/null
# The server URL is the only configuration baked into the app.
printf '{"api_url": "%s"}\n' "$API" > "$STAGE/native/client.json"

# Release keystore for Android: created once and kept in data/ (secret). Every future APK must be signed
# with the same key or phones refuse to install the update.
KS="$ROOT/data/android-release.keystore"; KSINFO="$ROOT/data/android-keystore.txt"
if [[ ",$ONLY," == *",Android,"* ]] && [ ! -f "$KS" ]; then
  PASS="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24)"
  keytool -genkeypair -keystore "$KS" -alias thuetab -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$PASS" -keypass "$PASS" -dname "CN=ThueTab, O=ThueTab, C=VN" >/dev/null 2>&1
  printf 'Android release keystore — GIỮ BÍ MẬT, sao lưu cẩn thận\nfile: %s\nalias: thuetab\npassword: %s\n' "$KS" "$PASS" > "$KSINFO"
  chmod 600 "$KS" "$KSINFO"
fi
if [ -f "$KSINFO" ]; then
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER=thuetab
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(sed -n 's/^password: //p' "$KSINFO")"
fi

# Import resources once, then export each platform.
"$GODOT" --headless --path "$STAGE" --import >/dev/null 2>&1 || true
# Windows/Linux ship as an archive: the executable plus the H.264 decoder library (native/h264) next to it.
declare -A EXT=([Linux]=x86_64 [Windows]=exe [Android]=apk [macOS]=zip)
declare -A PKG=([Linux]=ThueTab-Linux.tar.gz [Windows]=ThueTab-Windows.zip [Android]=ThueTab-Android.apk [macOS]=ThueTab-macOS.zip)
IFS=',' read -ra TARGETS <<< "$ONLY"
FAILED=()
for P in "${TARGETS[@]}"; do
  DIR="$OUT/$P/ThueTab"
  rm -rf "$OUT/$P" "$OUT/${PKG[$P]}"
  mkdir -p "$DIR"
  FILE="$DIR/ThueTab.${EXT[$P]}"
  echo "==> $P"
  if "$GODOT" --headless --path "$STAGE" --export-release "$P" "$FILE" > "$OUT/build-$P.log" 2>&1 && [ -s "$FILE" ]; then
    case "$P" in
      Windows) (cd "$OUT/$P" && python3 -c 'import shutil;shutil.make_archive("../ThueTab-Windows","zip",".","ThueTab")') ;;
      Linux) tar -C "$OUT/$P" -czf "$OUT/${PKG[$P]}" ThueTab ;;
      *) mv "$FILE" "$OUT/${PKG[$P]}" ;;
    esac
    rm -rf "$OUT/$P"
    cp "$OUT/${PKG[$P]}" "$ROOT/data/downloads/"
    ls -lh "$OUT/${PKG[$P]}" | awk '{print "    " $5 "  " $9}'
  else
    FAILED+=("$P"); echo "    LỖI — xem $OUT/build-$P.log"
  fi
done
[ ${#FAILED[@]} -eq 0 ] || { echo "Build lỗi: ${FAILED[*]}"; exit 1; }
echo "Đã đăng lên trang Tải ứng dụng (data/downloads/)."
echo "Phát hành cho server tải về: gh release create vX.Y.Z exports/ThueTab-{Android.apk,Windows.zip,Linux.tar.gz,macOS.zip}"
