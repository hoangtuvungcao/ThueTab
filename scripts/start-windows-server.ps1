# ThuêTab — Windows Server Production Launcher
# Khởi chạy toàn bộ hệ thống trên Windows Server (API + Runner Worker + Web Frontend)
# Chạy trong PowerShell: powershell -ExecutionPolicy Bypass -File scripts\start-windows-server.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

Write-Host "=== [ThuêTab] Khởi chạy trên Windows Server ===" -ForegroundColor Green

# 1. Kiểm tra Python
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python chưa được cài đặt hoặc chưa được thêm vào PATH. Vui lòng cài đặt Python 3.11+."
    exit 1
}

# 2. Kiểm tra Docker
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Warning "Docker chưa được phát hiện. Đảm bảo Docker Desktop hoặc Docker Engine đang chạy trên Windows Server!"
}

# 3. Tạo môi trường ảo nếu chưa có
if (-not (Test-Path ".venv")) {
    Write-Host "Đang khởi tạo môi trường Python virtualenv..." -ForegroundColor Yellow
    python -m venv .venv
}

$py = ".\.venv\Scripts\python.exe"

# 4. Cài đặt thư viện
Write-Host "Đang cập nhật thư viện backend..." -ForegroundColor Yellow
& $py -m pip install --quiet -r backend\requirements.txt

# 5. Build Web Frontend nếu chưa có thư mục dist
if (-not (Test-Path "web\dist")) {
    Write-Host "Đang build Web Frontend Production..." -ForegroundColor Yellow
    npm --prefix web run build
}

# 6. Khởi chạy Tường lửa bảo vệ nếu chạy với quyền Admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    & powershell -ExecutionPolicy Bypass -File scripts\setup-firewall-windows.ps1
} else {
    Write-Warning "Chưa chạy quyền Administrator. Bỏ qua cấu hình tường lửa Windows Server (có thể chạy sau)."
}

# 7. Khởi chạy hệ thống qua local.py hoặc production
& $py scripts\local.py --setup

