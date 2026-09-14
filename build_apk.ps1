# Flutter APK 构建脚本 - 自动重命名输出文件
# 用法: .\build_apk.ps1

Write-Host ">>> 开始构建 APK..." -ForegroundColor Cyan

# 从 pubspec.yaml 读取版本号（需在构建前解析，以便通过 dart-define 注入）
$pubspec = Get-Content "pubspec.yaml" | Select-String "^version:\s*(.+)"
if ($pubspec) {
    $rawVersion = $pubspec.Matches[0].Groups[1].Value -replace '[\r\n\s]', ''
    # 解析 version+buildNumber -> version.buildNumber（保留原始格式如 001）
    if ($rawVersion -match "^([^+]+)\+(.+)$") {
        $versionName = $Matches[1]
        $buildNumber = $Matches[2]
        $fullVersion = "$versionName.$buildNumber"
    } else {
        $fullVersion = $rawVersion
    }
} else {
    Write-Host ">>> 无法读取版本号，使用默认名称" -ForegroundColor Yellow
    $fullVersion = "unknown"
}

# 清理旧构建产物
$apkDir = "build\app\outputs\flutter-apk"
if (Test-Path $apkDir) {
    Get-ChildItem $apkDir -Filter "*.apk" | Remove-Item
    Get-ChildItem $apkDir -Filter "*.sha1" | Remove-Item
}

# 执行 Flutter 构建：拆分架构打包，只生成 32 位（armeabi-v7a）与 64 位（arm64-v8a）两个 APK，
# 不打包 x86_64（模拟器架构）以控制包体，通过 dart-define 注入完整版本号
flutter build apk --release --split-per-abi --target-platform android-arm64,android-arm --dart-define=FULL_VERSION=$fullVersion
if ($LASTEXITCODE -ne 0) {
    Write-Host ">>> 构建失败!" -ForegroundColor Red
    exit 1
}

# 分别重命名 32 位 / 64 位 APK
$apkDir = "build\app\outputs\flutter-apk"
$newName64 = "ylx_boss_flutter_${fullVersion}_64.apk"
$newName32 = "ylx_boss_flutter_${fullVersion}_32.apk"

$arm64Apk = Join-Path $apkDir "app-arm64-v8a-release.apk"
$arm32Apk = Join-Path $apkDir "app-armeabi-v7a-release.apk"

# 清理旧版校验文件
Get-ChildItem $apkDir -Filter "*.sha1" -ErrorAction SilentlyContinue | Remove-Item

if (Test-Path $arm64Apk) {
    Rename-Item -Path $arm64Apk -NewName $newName64
    $sizeMB = [math]::Round((Get-Item (Join-Path $apkDir $newName64)).Length / 1MB, 2)
    Write-Host ">>> 64 位 APK: $newName64 ($sizeMB MB)" -ForegroundColor Green
} else {
    Write-Host ">>> 未找到 app-arm64-v8a-release.apk" -ForegroundColor Red
}

if (Test-Path $arm32Apk) {
    Rename-Item -Path $arm32Apk -NewName $newName32
    $sizeMB = [math]::Round((Get-Item (Join-Path $apkDir $newName32)).Length / 1MB, 2)
    Write-Host ">>> 32 位 APK: $newName32 ($sizeMB MB)" -ForegroundColor Green
} else {
    Write-Host ">>> 未找到 app-armeabi-v7a-release.apk" -ForegroundColor Red
}
