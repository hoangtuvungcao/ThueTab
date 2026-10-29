#!/usr/bin/env bash
# Download the app builds of the latest GitHub release into data/downloads/ (shown on the "Tải ứng dụng" page).
#   bash scripts/fetch-apps.sh [data_dir]      (default: ./data)
set -euo pipefail
REPO="${THUETAB_REPO:-hoangtuvungcao/ThueTab}"
DEST="${1:-$(cd "$(dirname "$0")/.." && pwd)/data}/downloads"
mkdir -p "$DEST"
for f in ThueTab-Android.apk ThueTab-Windows.exe ThueTab-Linux.x86_64 ThueTab-macOS.zip; do
  echo "-> $f"
  # Resumable: flaky links continue where they stopped; a partial file is only moved in when complete.
  if curl -fL -C - --retry 5 --retry-delay 3 -o "$DEST/$f.part" "https://github.com/$REPO/releases/latest/download/$f"; then
    mv "$DEST/$f.part" "$DEST/$f"
  else
    echo "   bỏ qua $f (chưa có trong bản phát hành hoặc lỗi mạng)" >&2
  fi
done
chmod +x "$DEST/ThueTab-Linux.x86_64" 2>/dev/null || true
ls -lh "$DEST"
