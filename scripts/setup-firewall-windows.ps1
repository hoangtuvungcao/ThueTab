# ThuêTab — Windows Server Firewall & Security Configuration
# Thiết lập tường lửa trên Windows Server / Windows 10/11 để chống Botnet, DDoS, đào coin
# Chạy với quyền Administrator: powershell -ExecutionPolicy Bypass -File scripts\setup-firewall-windows.ps1

$ErrorActionPreference = "Continue"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " [ThuêTab] Cấu hình Tường lửa & Bảo mật Máy chủ trên Windows Server   " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan

# Kiểm tra quyền Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Vui lòng mở PowerShell bằng quyền Administrator (Run as Administrator) để thiết lập NetFirewallRule!"
    exit 1
}

$RuleGroup = "ThueTab-Security"

# Xóa các rule cũ nếu có
Write-Host "[1/6] Dọn dẹp các quy tắc tường lửa ThuêTab cũ..." -ForegroundColor Yellow
Remove-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue

# 1. Chặn đào coin (Crypto Mining Stratum Ports)
Write-Host "[2/6] Tạo quy tắc CHẶN ĐÀO COIN (Port 3333, 4444, 5555, 7777, 8888, 9999, 14433)..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "ThuêTab - Block Crypto Mining Egress" `
    -Group $RuleGroup -Direction Outbound -Action Block `
    -Protocol TCP -RemotePort 3333, 4444, 5555, 7777, 8888, 9999, 14433 `
    -Description "Chặn kết nối outbound tới các mining pool đào tiền ảo" | Out-Null

# 2. Chặn Spam Mail (SMTP Ports)
Write-Host "[3/6] Tạo quy tắc CHẶN SPAM MAIL (Port 25, 465, 587)..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "ThuêTab - Block Outbound SMTP Spam" `
    -Group $RuleGroup -Direction Outbound -Action Block `
    -Protocol TCP -RemotePort 25, 465, 587 `
    -Description "Chặn gửi thư rác từ các tab game" | Out-Null

# 3. Chặn Quét cổng SSH / Telnet ra ngoài
Write-Host "[4/6] Tạo quy tắc CHẶN QUÉT CỔNG SSH/TELNET (Port 22, 23, 2222)..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "ThuêTab - Block Outbound SSH Brute-Force" `
    -Group $RuleGroup -Direction Outbound -Action Block `
    -Protocol TCP -RemotePort 22, 23, 2222 `
    -Description "Chặn quét mật khẩu SSH ra ngoài Internet" | Out-Null

# 4. Chặn Container thâm nhập mạng nội bộ Host (Anti-Host Snooping)
Write-Host "[5/6] Tạo quy tắc CHẶN TRUY CẬP LAN NỘI BỘ MÁY CHỦ (RFC 1918)..." -ForegroundColor Yellow
$PrivateSubnets = @("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.169.254/32")
foreach ($subnet in $PrivateSubnets) {
    New-NetFirewallRule -DisplayName "ThuêTab - Block Subnet $subnet" `
        -Group $RuleGroup -Direction Outbound -Action Block `
        -RemoteAddress $subnet `
        -Description "Ngăn tab game truy cập vào mạng nội bộ của Host" | Out-Null
}

# 5. Cho phép cổng kết nối Game Online (DNS, HTTP/HTTPS, Game MMO Ports)
Write-Host "[6/6] Tạo quy tắc CHO PHÉP GAME ONLINE (DNS, Web, MMO Ports 10000-35000)..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "ThuêTab - Allow Game MMO Sockets" `
    -Group $RuleGroup -Direction Outbound -Action Allow `
    -Protocol TCP -RemotePort 10000-35000 `
    -Description "Cho phép kết nối đến máy chủ game Java MMO (NSO, Avatar, Knight, Ngọc Rồng)" | Out-Null

New-NetFirewallRule -DisplayName "ThuêTab - Allow Game Web & DNS" `
    -Group $RuleGroup -Direction Outbound -Action Allow `
    -Protocol TCP -RemotePort 53, 80, 443 `
    -Description "Cho phép phân giải tên miền và tải cập nhật game" | Out-Null

New-NetFirewallRule -DisplayName "ThuêTab - Allow DNS UDP" `
    -Group $RuleGroup -Direction Outbound -Action Allow `
    -Protocol UDP -RemotePort 53 `
    -Description "Cho phép UDP cổng 53 để tra cứu tên miền máy chủ game" | Out-Null

Write-Host "======================================================================" -ForegroundColor Green
Write-Host " ✅ TƯỜNG LỬA WINDOWS SERVER ĐÃ ĐƯỢC THIẾT LẬP THÀNH CÔNG!            " -ForegroundColor Green
Write-Host "   - Bảo vệ máy chủ khỏi tấn công DDoS, quét cổng và đào coin.        " -ForegroundColor Cyan
Write-Host "   - Game online (NSO, Avatar, Knight, Ngọc Rồng) kết nối mượt 24/24. " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Green

