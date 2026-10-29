#!/usr/bin/env bash
# One-shot install of ThuêTab on a fresh Debian 12/13 machine (VM or VPS); installs Docker if missing.
# Lightweight setup for small machines: SQLite instead of PostgreSQL, zram swap, capacity sized from RAM/CPU.
#
#   sudo bash deploy/install-debian.sh --origin https://thuetab.pages.dev --listen 0.0.0.0 --port 8080 \
#        [--cf-token <Cloudflare Tunnel token>] [--capacity N]
#
# --origin   the web front-end URL(s) users open (comma-separated); cookies/WebSockets are only accepted from them.
# --listen   address uvicorn binds (127.0.0.1 behind a tunnel on this machine, 0.0.0.0 for LAN/NAT forwarding).
# --port     API port (default 8080).
# --cf-token install cloudflared and run the tunnel created in the Cloudflare dashboard (Zero Trust → Tunnels).
# --capacity override the automatic number of game tabs.
# --with-web also build and serve the web front-end from this machine (not needed with Cloudflare Pages).
set -euo pipefail

ORIGIN=""; LISTEN="127.0.0.1"; PORT=8080; CF_TOKEN=""; CAPACITY=""; WITH_WEB=0
while [ $# -gt 0 ]; do
  case "$1" in
    --origin) ORIGIN="$2"; shift 2 ;;
    --listen) LISTEN="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --cf-token) CF_TOKEN="$2"; shift 2 ;;
    --with-web) WITH_WEB=1; shift ;;
    --capacity) CAPACITY="$2"; shift 2 ;;
    *) echo "Tham số không hợp lệ: $1" >&2; exit 1 ;;
  esac
done
[ -n "$ORIGIN" ] || { echo "Thiếu --origin: domain giao diện web (ví dụ --origin https://thuetab.pages.dev)" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "Hãy chạy bằng root: sudo bash $0 ..." >&2; exit 1; }

SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP=/opt/thuetab
echo "==> Cài gói hệ thống"
# VMs behind NAT (e.g. VirtualBox) often resolve IPv6 mirrors they cannot reach: make apt use IPv4 then.
if ! ip -6 route show default 2>/dev/null | grep -q .; then
  echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
fi
apt-get update -qq
apt-get install -y -qq python3-venv python3-pip rsync zram-tools curl ca-certificates >/dev/null
if ! command -v docker >/dev/null; then
  echo "==> Cài Docker (gói docker.io của Debian)"
  apt-get install -y -qq docker.io >/dev/null
fi
# BuildKit is needed for the game image (ADD --checksum); Debian ships it as docker-buildx where available.
apt-get install -y -qq docker-buildx >/dev/null 2>&1 || true
export DOCKER_BUILDKIT=1
systemctl enable --now docker >/dev/null 2>&1 || true
docker info >/dev/null 2>&1 || { echo "Docker không chạy được — xem: systemctl status docker" >&2; exit 1; }

echo "==> Chép mã nguồn vào $APP"
mkdir -p "$APP"
if [ "$SRC" != "$APP" ]; then
  rsync -a --delete --exclude .venv --exclude web/node_modules --exclude .godot --exclude data \
    --exclude .staging --exclude exports "$SRC"/ "$APP"/
fi
id thuetab >/dev/null 2>&1 || useradd -r -d "$APP" -s /usr/sbin/nologin thuetab
usermod -aG docker thuetab
mkdir -p "$APP/data"

echo "==> Môi trường Python"
[ -x "$APP/.venv/bin/python" ] || python3 -m venv "$APP/.venv"
"$APP/.venv/bin/pip" install -q --upgrade pip
"$APP/.venv/bin/pip" install -q -r "$APP/backend/requirements.txt"

# The web front-end is served by Cloudflare Pages; build it here only when asked (--with-web) to also
# serve it from this machine.
if [ "$WITH_WEB" = 1 ] && [ ! -f "$APP/web/dist/index.html" ]; then
  echo "==> Build giao diện web"
  apt-get install -y -qq nodejs npm >/dev/null
  (cd "$APP/web" && npm ci --silent && npm run build --silent)
fi

echo "==> Build image game (vài phút lần đầu)"
docker build -q -f "$APP/runner/Dockerfile.game" -t thuetab-java:local "$APP" >/dev/null

# Measured per tab (Ninja School): ~150 MB host RAM including container overhead, ~10-15% of one vCPU.
# Reserve ~700 MB for Debian, Docker, API and worker; keep CPU headroom for viewers' streams.
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
CPUS=$(nproc)
BY_RAM=$(( (MEM_MB - 700) / 150 ))
BY_CPU=$(( (CPUS * 100 - 30) / 14 ))
AUTO=$(( BY_RAM < BY_CPU ? BY_RAM : BY_CPU ))
[ "$AUTO" -ge 1 ] || AUTO=1
CAPACITY="${CAPACITY:-$AUTO}"
echo "    RAM ${MEM_MB} MB, ${CPUS} CPU → theo RAM ${BY_RAM} tab, theo CPU ${BY_CPU} tab → dùng ${CAPACITY} tab"

if [ ! -f "$APP/.env" ]; then
  echo "==> Tạo $APP/.env"
  SECURE=false; case "$ORIGIN" in https://*) SECURE=true ;; esac
  cat > "$APP/.env" <<EOF
DATABASE_URL=sqlite:///$APP/data/thuetab.db
WORKER_TOKEN=$(head -c 48 /dev/urandom | base64 | tr -d '/+=' | head -c 48)
WORKER_ID=local-1
WORKER_CAPACITY=$CAPACITY
PUBLIC_ORIGIN=$ORIGIN
COOKIE_SECURE=$SECURE
API_PORT=$PORT
TRUSTED_PROXIES=127.0.0.1/32,::1/128,172.16.0.0/12
JAR_AUTO_APPROVE=true
ALLOW_FILTERED_EGRESS=true
TRIAL_MINUTES=60
# Điền để bật nạp tiền tự động:
SEPAY_API_KEY=
SEPAY_API_TOKEN=
BANK_ACCOUNT=
BANK_ACCOUNT_NAME=
BANK_NAME=
BANK_CODE=
SUPPORT_ZALO=
SUPPORT_TELEGRAM=
SUPPORT_EMAIL=
EOF
else
  echo "==> Giữ nguyên $APP/.env đã có"
fi
chmod 600 "$APP/.env"
chown -R thuetab:thuetab "$APP"

echo "==> zram (RAM nén) cho máy RAM nhỏ"
printf 'ALGO=zstd\nPERCENT=50\nPRIORITY=100\n' > /etc/default/zramswap
systemctl restart zramswap || true

echo "==> Dịch vụ systemd"
cat > /etc/systemd/system/thuetab-api.service <<EOF
[Unit]
Description=ThuêTab API + web
After=network-online.target

[Service]
User=thuetab
WorkingDirectory=$APP
EnvironmentFile=$APP/.env
ExecStart=$APP/.venv/bin/uvicorn backend.app:app --host $LISTEN --port $PORT --no-server-header --no-access-log
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
sed "s|API_URL=http://127.0.0.1:8000|API_URL=http://127.0.0.1:$PORT|" "$APP/deploy/thuetab-worker.service" > /etc/systemd/system/thuetab-worker.service
systemctl daemon-reload
systemctl enable --now thuetab-api >/dev/null
for i in $(seq 1 30); do curl -sf "http://127.0.0.1:$PORT/api/health" >/dev/null && break; sleep 1; done
systemctl enable --now thuetab-worker >/dev/null

if ! "$APP/.venv/bin/python" - <<EOF
import sqlite3,sys
c=sqlite3.connect('$APP/data/thuetab.db')
sys.exit(0 if c.execute("select count(*) from users where role='admin'").fetchone()[0] else 1)
EOF
then
  echo "==> Tạo tài khoản quản trị"
  read -rp "Email admin: " ADMIN_EMAIL
  runuser -u thuetab -- bash -c 'set -a; . "$0/.env"; set +a; cd "$0" && .venv/bin/python scripts/manage.py create-admin --email "$1"' "$APP" "$ADMIN_EMAIL"
fi

if [ -n "$CF_TOKEN" ]; then
  echo "==> Cloudflare Tunnel"
  if ! command -v cloudflared >/dev/null; then
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" > /etc/apt/sources.list.d/cloudflared.list
    apt-get update -qq && apt-get install -y -qq cloudflared >/dev/null
  fi
  cloudflared service install "$CF_TOKEN" >/dev/null 2>&1 || systemctl restart cloudflared
fi

echo
echo "Xong. Trạng thái: $(curl -s "http://127.0.0.1:$PORT/api/status")"
echo "Mở: $ORIGIN   ·   Nhật ký: journalctl -u thuetab-api -u thuetab-worker -f"
echo "Sức chứa đổi được trong Quản trị → Máy chủ. Tường lửa cho tab game: sudo bash $APP/scripts/setup-firewall.sh"
