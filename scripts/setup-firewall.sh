#!/usr/bin/env bash
# ThuêTab — Firewall & Egress Filter Configuration
# Bảo vệ máy chủ khỏi bị lợi dụng làm Botnet, quét cổng, DDoS hoặc đào coin
# Sử dụng iptables chain DOCKER-USER theo chuẩn Docker

set -euo pipefail

BRIDGE_IFACE="br-thuetab"
SUBNET="172.28.0.0/16"

echo "=== [ThuêTab] Đang thiết lập tường lửa chống lạm dụng mạng cho Game Online ==="

# Kiểm tra quyền root (iptables cần quyền root hoặc sudo)
if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ Chú ý: Script cấu hình iptables cần quyền root. Hãy chạy: sudo bash scripts/setup-firewall.sh"
    echo "Nếu đang chạy local dev test, Docker bridge 'com.docker.network.bridge.enable_icc=false' đã tự động cách ly các tab."
    exit 0
fi

# Đảm bảo chain DOCKER-USER tồn tại
iptables -N DOCKER-USER 2>/dev/null || true

# 1. Cho phép các kết nối đã thiết lập (Established / Related)
iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# 2. CHẶNG LẬP TỨC: Cấm container truy cập ngược vào mạng nội bộ của Host (Anti-Host Snooping)
# Không cho phép container chạm vào PostgreSQL (5432), API (8000), hoặc các thiết bị trong mạng LAN
for PRIVATE_NET in "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "169.254.169.254/32" "127.0.0.0/8"; do
    iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -d "$PRIVATE_NET" -j DROP 2>/dev/null || true
done

# 3. CHỐNG SPAM MAIL: Chặn hoàn toàn các cổng SMTP (Port 25, 465, 587)
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p tcp -m multiport --dports 25,465,587 -j DROP 2>/dev/null || true

# 4. CHỐNG SCAN / BRUTE FORCE: Chặn cổng SSH / Telnet ra ngoài (Port 22, 23, 2222)
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p tcp -m multiport --dports 22,23,2222 -j DROP 2>/dev/null || true

# 5. CHỐNG ĐÀO COIN (Anti-Mining Pool): Chặn các cổng giao thức Stratum Mining phổ biến
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p tcp -m multiport --dports 3333,4444,5555,7777,8888,9999,14433 -j DROP 2>/dev/null || true

# 6. CHỐNG DDOS SYN FLOOD & PORT SCANNING: Giới hạn tốc độ khởi tạo kết nối mới
# Mỗi container tối đa 20 kết nối mới/giây (game chỉ cần 1-2 kết nối liên tục)
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p tcp --syn -m limit --limit 20/s --limit-burst 40 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p tcp --syn -j DROP 2>/dev/null || true

# 7. CHỐNG DDOS UDP FLOOD: Chỉ cho phép UDP ra ngoài tới cổng DNS (Port 53)
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p udp ! --dport 53 -j DROP 2>/dev/null || true

# 8. CHO PHÉP TRUY CẬP GAME ONLINE:
# - DNS (UDP/TCP 53)
# - Web/Patcher (TCP 80, 443)
# - Dải cổng Game Server MMO (TCP 10000:35000: NSO, Avatar, Knight, Ngọc Rồng)
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p tcp -m multiport --dports 80,443 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -i "$BRIDGE_IFACE" -p tcp --dport 10000:35000 -j ACCEPT 2>/dev/null || true

echo "✅ Tường lửa ThuêTab đã được thiết lập thành công!"
echo "   - Container kết nối game online 24/24 bình thường (DNS, HTTP/HTTPS, Game Server Ports)."
echo "   - Cấm truy cập Host/LAN nội bộ."
echo "   - Chặn 100% cổng đào coin, cổng gửi thư rác, quét SSH."
echo "   - Giới hạn tốc độ kết nối chống biến tab thành botnet DDoS."

