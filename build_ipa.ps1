# Flutter iOS 测试辅助脚本（Windows 可用，无需 Mac）
# 作用: 云构建产出的 .ipa 下载到本机后，按版本号重命名，并输出安装到 iPhone 的指引
# 用法: .\build_ipa.ps1 [-IpaPath <ipa文件路径>]
#       不带参数时自动搜索: 当前目录、项目 build\ios、系统下载目录中最近的 .ipa
# 前提: iOS 包必须由云构建产出（配置见 codemagic.yaml），本机 Windows 无法直接编译 iOS

param(
    [string]$IpaPath = ""
)

Write-Host ">>> iOS 测试辅助脚本（无 Mac 环境）..." -ForegroundColor Cyan

# 从 pubspec.yaml 读取版本号（与 build_apk.ps1 一致的解析逻辑）
$pubspec = Get-Content "pubspec.yaml" | Select-String "^version:\s*(.+)"
if ($pubspec) {
    $rawVersion = $pubspec.Matches[0].Groups[1].Value -replace '[\r\n\s]', ''
    if ($rawVersion -match "^([^+]+)\+(.+)$") {
        $fullVersion = "$($Matches[1]).$($Matches[2])"
    } else {
        $fullVersion = $rawVersion
    }
} else {
    Write-Host ">>> 无法读取版本号，使用默认名称" -ForegroundColor Yellow
    $fullVersion = "unknown"
}

# 定位 .ipa 文件
if (-not $IpaPath) {
    $searchDirs = @(
        (Get-Location).Path,
        (Join-Path (Get-Location).Path "build\ios"),
        (Join-Path $env:USERPROFILE "Downloads")
    )
    $ipaFile = $null
    foreach ($dir in $searchDirs) {
        $candidate = Get-ChildItem -Path $dir -Filter "*.ipa" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) { $ipaFile = $candidate; break }
    }
} else {
    $ipaFile = Get-Item $IpaPath -ErrorAction SilentlyContinue
}

if (-not $ipaFile) {
    Write-Host ">>> 未找到 .ipa 文件" -ForegroundColor Red
    Write-Host ">>> 请先在 Codemagic (https://codemagic.io) 云构建下载 ipa，再运行本脚本" -ForegroundColor Yellow
    exit 1
}

# 按版本号复制重命名（保留原始下载文件）
$newName = "ylx_boss_flutter_$fullVersion.ipa"
$targetPath = Join-Path $ipaFile.DirectoryName $newName
if ($ipaFile.FullName -ne $targetPath) {
    Copy-Item -Path $ipaFile.FullName -Destination $targetPath -Force
    $sizeMB = [math]::Round((Get-Item $targetPath).Length / 1MB, 2)
    Write-Host ">>> 已重命名: $targetPath ($sizeMB MB)" -ForegroundColor Green
} else {
    Write-Host ">>> 文件已是最新命名: $targetPath" -ForegroundColor Green
}

Write-Host ""
Write-Host ">>> 安装到 iPhone 步骤（无需 Mac）:" -ForegroundColor Cyan
Write-Host "  1. Windows 安装 Sideloadly (https://sideloadly.io) 并打开" -ForegroundColor White
Write-Host "  2. iPhone 用数据线连接电脑，解锁并点击「信任此电脑」" -ForegroundColor White
Write-Host "  3. iPhone 开启开发者模式（iOS16+）: 设置 → 隐私与安全性 → 开发者模式 → 开启并重启" -ForegroundColor White
Write-Host "  4. Sideloadly 中: 拖入 $newName，输入你的 Apple ID 和密码（免费账号即可），点击 Start" -ForegroundColor White
Write-Host "  5. 安装完成后: 设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID" -ForegroundColor White
Write-Host "  6. 打开 App 测试。注意: 免费签名 7 天过期，过期后重复第 4 步重装即可" -ForegroundColor White
