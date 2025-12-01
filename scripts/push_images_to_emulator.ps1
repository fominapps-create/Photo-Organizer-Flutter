# Push up to N images from a local folder into the Android emulator's SD card.
# Usage: run from PowerShell: `.	ools\push_images_to_emulator.ps1` or run via the wrapper.

$SourceRoot = 'F:\Screenshots'
$Max = 500
$Counts = @{
  'DCIM_Camera' = 140
  'Pictures' = 110
  'Download' = 70
  'WhatsApp' = 180
}
$TmpRoot = Join-Path $env:TEMP 'emulator_push_images'

$Subdirs = @('DCIM_Camera','Pictures','Download','WhatsApp')
$RemoteMap = @{
  'DCIM_Camera' = '/sdcard/DCIM/Camera'
  'Pictures' = '/sdcard/Pictures'
  'Download' = '/sdcard/Download'
  'WhatsApp' = '/sdcard/WhatsApp/Media/WhatsApp Images'
}

$exts = '*.jpg','*.jpeg','*.png','*.webp'
Write-Host "Searching for images under $SourceRoot (extensions: $($exts -join ', '))..."
$files = Get-ChildItem -Path $SourceRoot -Recurse -File -Include $exts -ErrorAction SilentlyContinue | Select-Object -First $Max
if (!$files -or $files.Count -eq 0) {
  Write-Error "No images found under $SourceRoot. Aborting."
  exit 1
}

# Prepare temporary folders
if (Test-Path $TmpRoot) { Remove-Item -Recurse -Force $TmpRoot -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $TmpRoot | Out-Null
foreach ($d in $Subdirs) { New-Item -ItemType Directory -Path (Join-Path $TmpRoot $d) | Out-Null }

# Distribute files according to configured counts per folder
$assigned = 0
$idx = 1
foreach ($sub in $Subdirs) {
  $count = 0
  if ($Counts.ContainsKey($sub)) { $count = [int]$Counts[$sub] }
  if ($count -le 0) { continue }
  $destDir = Join-Path $TmpRoot $sub
  for ($j = 0; $j -lt $count; $j++) {
    if ($assigned -ge $files.Count) { break }
    $f = $files[$assigned]
    $ext = $f.Extension
    $destName = ('img_{0:D4}{1}' -f $idx, $ext)
    $destPath = Join-Path $destDir $destName
    Copy-Item -Path $f.FullName -Destination $destPath -ErrorAction SilentlyContinue
    $assigned++
    $idx++
  }
}
Write-Host "Copied $assigned files into $TmpRoot across $($Subdirs.Count) subfolders."

# Check adb availability and connected devices
Write-Host "Checking ADB devices..."
adb devices

# Push files to emulator
foreach ($sub in $Subdirs) {
  $localDir = Join-Path $TmpRoot $sub
  $remote = $RemoteMap[$sub]
  Write-Host "Ensuring remote dir $remote"
  adb shell mkdir -p "$remote"
  $localFiles = Get-ChildItem -Path $localDir -File
  Write-Host "Pushing $($localFiles.Count) files to $remote ..."
  foreach ($lf in $localFiles) {
    Write-Host "Pushing $($lf.Name) -> $remote/"
    $pushResult = adb push "$($lf.FullName)" "$remote/" 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Push to $remote failed; attempting alternate WhatsApp Pictures path..."
      if ($sub -eq 'WhatsApp') {
        $alt = '/sdcard/Pictures/WhatsApp'
        adb shell mkdir -p "$alt"
        adb push "$($lf.FullName)" "$alt/" | Out-Null
      }
    }
  }
  # Trigger media scan for first file to prompt MediaStore update
  if ($localFiles.Count -gt 0) {
    $first = $localFiles[0].Name
    $remoteFile = "$remote/$first"
    Write-Host "Triggering media scan for $remoteFile"
    adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$remoteFile" >/dev/null 2>&1
  }
}

Write-Host "Push complete. Listing target folders (first few entries):"
Write-Host "--- /sdcard/DCIM/Camera ---"
adb shell ls -l /sdcard/DCIM/Camera | Out-String | Write-Host
Write-Host "--- /sdcard/Pictures ---"
adb shell ls -l /sdcard/Pictures | Out-String | Write-Host
Write-Host "--- /sdcard/Download ---"
adb shell ls -l /sdcard/Download | Out-String | Write-Host
Write-Host "--- /sdcard/WhatsApp/Media/WhatsApp Images ---"
adb shell ls -l '/sdcard/WhatsApp/Media/WhatsApp Images' 2>$null | Out-String | Write-Host

Write-Host "Done. Temporary files are under: $TmpRoot"

# Exit with success
exit 0
