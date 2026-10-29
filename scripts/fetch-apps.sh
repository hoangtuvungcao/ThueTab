#!/usr/bin/env bash
# Download the app builds of the latest GitHub release into data/downloads/; the server then serves them itself
# on the "Tải ứng dụng" page (works with a private repo).
#
#   GITHUB_TOKEN=<token> bash scripts/fetch-apps.sh [data_dir]      (default data_dir: ./data)
#
# GITHUB_TOKEN: needed when the repo is private — a fine-grained token with "Contents: Read-only" on the repo.
# Flaky links: each file resumes where it stopped and is only kept once its size matches the release.
set -euo pipefail
REPO="${THUETAB_REPO:-hoangtuvungcao/ThueTab}"
DEST="${1:-$(cd "$(dirname "$0")/.." && pwd)/data}/downloads"
TOKEN="${GITHUB_TOKEN:-}"
mkdir -p "$DEST"
AUTH=(); [ -n "$TOKEN" ] && AUTH=(-H "Authorization: Bearer $TOKEN")

RELEASE="$(curl -4 -fsSL --retry 5 "${AUTH[@]}" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/latest")" || {
  echo "Không đọc được bản phát hành của $REPO (repo riêng tư cần GITHUB_TOKEN)." >&2; exit 1; }

# One line per app build: <asset id> <size> <name>
python3 -c '
import json,sys
for a in json.load(sys.stdin).get("assets",[]):
    if a["name"].startswith("ThueTab-"): print(a["id"], a["size"], a["name"])
' <<<"$RELEASE" | while read -r ID SIZE NAME; do
  FILE="$DEST/$NAME"
  if [ -f "$FILE" ] && [ "$(stat -c%s "$FILE")" = "$SIZE" ]; then echo "✓ $NAME (đã có)"; continue; fi
  echo "-> $NAME ($((SIZE / 1048576)) MB)"
  for TRY in $(seq 1 60); do
    curl -4 -fL -C - --retry 3 --speed-limit 1024 --speed-time 30 "${AUTH[@]}" -H "Accept: application/octet-stream" \
      -o "$FILE.part" "https://api.github.com/repos/$REPO/releases/assets/$ID" || true
    GOT=$(stat -c%s "$FILE.part" 2>/dev/null || echo 0)
    if [ "$GOT" = "$SIZE" ]; then mv "$FILE.part" "$FILE"; echo "✓ $NAME"; break; fi
    [ "$GOT" -gt "$SIZE" ] && rm -f "$FILE.part"   # corrupt resume: start over
    echo "   đứt ở $((GOT / 1048576))/$((SIZE / 1048576)) MB — tải tiếp (lần $TRY)"; sleep 3
  done
done
chmod +x "$DEST/ThueTab-Linux.x86_64" 2>/dev/null || true
ls -lh "$DEST"
