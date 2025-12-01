# Push screenshots from F:\Screenshots into Android emulator DCIM/Camera and trigger media scan
# Usage: run from project root. Requires adb on PATH and an emulator/device connected.

$ErrorActionPreference = 'Stop'

$src = 'F:\Screenshots'
$temp = Join-Path $PSScriptRoot '..\temp_emulator_photos'

Write-Host "Source: $src"
Write-Host "Temp folder: $temp"

if (-not (Test-Path $src)) {
    Write-Host "ERROR: Source folder $src not found." -ForegroundColor Red
    exit 1
}

# Prepare temp folder
if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
New-Item -ItemType Directory -Path $temp | Out-Null

# Collect image files
$files = Get-ChildItem -Path $src -Recurse -File -Include *.jpg,*.jpeg,*.png | Sort-Object LastWriteTime -Descending
if ($files.Count -eq 0) {
    Write-Host "No image files found under $src" -ForegroundColor Yellow
    exit 0
}

# Copy and flatten names
$i = 0
foreach ($f in $files) {
    $i++
    $ext = $f.Extension.ToLower()
    $dest = Join-Path $temp ("img$i$ext")
    Copy-Item -Path $f.FullName -Destination $dest -Force
    Write-Host "Copied: $($f.FullName) -> $dest"
}
Write-Host "Prepared $i files in $temp"

# Locate adb (try PATH, ANDROID_SDK_ROOT, ANDROID_HOME, common SDK location)
Write-Host "Locating adb..."
$adb = $null
try { $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source } catch {}
if (-not $adb) {
    if ($env:ANDROID_SDK_ROOT) {
        $candidate = Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'
        if (Test-Path $candidate) { $adb = $candidate }
    }
}
if (-not $adb -and $env:ANDROID_HOME) {
    $candidate = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
    if (Test-Path $candidate) { $adb = $candidate }
}
if (-not $adb) {
    $candidate2 = Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk\platform-tools\adb.exe'
    if (Test-Path $candidate2) { $adb = $candidate2 }
}
if (-not $adb) {
    Write-Host "ERROR: adb not found in PATH or common SDK locations. Ensure Android platform-tools are installed and adb is on PATH." -ForegroundColor Red
    exit 1
}

Write-Host "Using adb at: $adb"
Write-Host "Checking adb devices..."
$adbDevices = & $adb devices
Write-Host $adbDevices
if ($adbDevices -notmatch 'device') {
    Write-Host "No adb device found. Start an emulator or connect a device and retry." -ForegroundColor Red
    exit 1
}

# Push files to emulator
Write-Host "Pushing files to emulator /sdcard/DCIM/Camera/ ..."
& $adb push "$temp\*" /sdcard/DCIM/Camera/ | ForEach-Object { Write-Host $_ }
Write-Host "Push complete. Triggering media scanner for each file..."

# Trigger media scanner for each file
Get-ChildItem -Path $temp -File | ForEach-Object {
    $name = $_.Name
    Write-Host "Scanning /sdcard/DCIM/Camera/$name"
    & $adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/DCIM/Camera/$name" | ForEach-Object { Write-Host $_ }
}

Write-Host "Done. You can now run the app on emulator and verify the Gallery." -ForegroundColor Green
