Write-Host "Downloading Flutter SDK 3.41.0..."
$url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.41.0-stable.zip"
$zip = "D:\flutter_sdk.zip"

try {
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 900
    Write-Host "Download complete!"
} catch {
    Write-Host "Primary source failed, trying mirror..."
    $url2 = "https://mirrors.tuna.tsinghua.edu.cn/flutter/flutter_infra_release/releases/stable/windows/flutter_windows_3.41.0-stable.zip"
    try {
        Invoke-WebRequest -Uri $url2 -OutFile $zip -UseBasicParsing -TimeoutSec 900
        Write-Host "Mirror download complete!"
    } catch {
        Write-Host "Download failed: $_"
    }
}
