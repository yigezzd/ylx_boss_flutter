$fso = New-Object -ComObject Scripting.FileSystemObject
$short = $fso.GetFolder("C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot").ShortPath
Write-Host "SHORT_PATH:$short"
