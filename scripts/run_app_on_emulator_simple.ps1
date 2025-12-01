#!/usr/bin/env pwsh
<#
A minimal script: launch the first configured emulator (via `flutter emulators --launch`) and run the Flutter app.
No guards, no checks, no fancy fallbacks — exactly one line to start the emulator + run the app.
Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_app_on_emulator_simple.ps1
#>
param(
  [string]$FlutterCmd = 'flutter',
  [int]$TimeoutSeconds = 30
)

Write-Host "Launch first configured flutter emulator (if any) and run the app"
# Use flutter to get configured emulators and launch the first one
$emulators = Invoke-Expression "$FlutterCmd emulators"
$first = $emulators | Select-String '•' | Select-Object -First 1
if ($first) {
    $emuName = ($first -split ' ')[1]
    Write-Host "Launching emulator: $emuName"
    Invoke-Expression "$FlutterCmd emulators --launch $emuName"
    Start-Sleep -Seconds 8
}
# Wait for an Android emulator/device to appear
Write-Host "Waiting for Android device to appear (timeout: $TimeoutSeconds s)..."
$foundDevice = $false
$wait = 0
while ($wait -lt $TimeoutSeconds) {
  try {
  $devicesOut = Invoke-Expression "$FlutterCmd devices --machine"
    $devices = $null
    if ($devicesOut -ne $null -and $devicesOut -ne '') {
      try { $devices = $devicesOut | ConvertFrom-Json } catch { $devices = @() }
    }
    foreach ($d in $devices) {
      if ($d.targetPlatform -and $d.targetPlatform -match 'android') { $foundDevice = $true; break }
    }
  } catch { }
  if ($foundDevice) { Write-Host "Android device found"; break }
  Start-Sleep -Seconds 1
  $wait++
}
if (-not $foundDevice) {
  Write-Warning "No Android device found after $TimeoutSeconds seconds. To avoid running on Windows desktop, aborting. Start an emulator first or run the more robust `dev_start_all.ps1`."
  exit 1
}

Push-Location -Path "$PSScriptRoot/.."
# Determine the Android device ID and explicitly run against it to avoid Windows desktop launch
$deviceId = $null
try {
  $devsOut = Invoke-Expression "$FlutterCmd devices --machine"
  if ($devsOut -and $devsOut -ne '') { $devs = $devsOut | ConvertFrom-Json } else { $devs = @() }
  foreach ($d in $devs) { if ($d.targetPlatform -and $d.targetPlatform -match 'android') { $deviceId = $d.id; break } }
} catch { }
if ($deviceId) { Write-Host "Starting app on device: $deviceId"; Invoke-Expression "$FlutterCmd run -d $deviceId" } else { Write-Warning "Unable to find Android device; running flutter run (default)"; Invoke-Expression "$FlutterCmd run" }
Pop-Location