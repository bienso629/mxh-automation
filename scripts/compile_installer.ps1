# Script biên dịch file cài đặt Inno Setup bằng PowerShell
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$issFile = Join-Path $scriptDir "installer_windows.iss"
$distDir = Join-Path $scriptDir "..\dist-flutter"

# Tìm kiếm ISCC.exe
$isccCandidates = @(
    (Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)

$isccPath = $null
foreach ($candidate in $isccCandidates) {
    if ($candidate -and (Test-Path $candidate)) {
        $isccPath = $candidate
        break
    }
}

if ($isccPath) {
    Write-Host "Đang biên dịch Setup Installer bằng: $isccPath"
    & "$isccPath" "$issFile"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[THÀNH CÔNG] Đã tạo file cài đặt: $distDir\MXH-Tu-Dong-Setup-x64.exe"
    } else {
        Write-Host "[CẢNH BÁO] Inno Setup kết thúc với mã lỗi: $LASTEXITCODE"
    }
} else {
    Write-Host "[CHÚ Ý] Không tìm thấy Inno Setup 6 (ISCC.exe). Bỏ qua bước tạo Setup .exe."
}
