#!/usr/bin/env pwsh
<#
Simple launcher: start the backend server (new window), ensure it's healthy,
configure adb reverse for emulator networking, launch an Android emulator if
needed, then run `flutter run` in the current terminal so logs are visible.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_emulator_and_app.ps1

Notes:
- Requires `python`, `flutter`, and `adb` on PATH for full automation.
- The server is started in a separate PowerShell window so this script can
  continue to run `flutter run` interactively in the current terminal.
#>

param(
  [string]$FlutterCmd = 'flutter',
  [int]$Port = 8000,
  [int]$TimeoutSeconds = 30
)

function Write-Info($m) { Write-Host "[info] $m" -ForegroundColor Cyan }
function Write-Err($m) { Write-Host "[warn] $m" -ForegroundColor Yellow }

Write-Info "Launcher starting: server -> adb reverse -> emulator -> flutter run"

# Start server in a new window (so current terminal stays interactive for flutter)
$serverPath = Join-Path $PSScriptRoot '..\python-server\run_server.py'
if (Test-Path $serverPath) {
  Write-Info "Starting server in new window (port $Port)"
  $cmd = "python \"$serverPath\" --no-reload --port $Port"
  Start-Process -FilePath powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-Command',$cmd -WindowStyle Normal
  Start-Sleep -Seconds 2
} else {
  Write-Err "Server entrypoint not found at $serverPath. Start server manually and re-run this script."
}

# Wait for server health
$healthUrl = "http://127.0.0.1:$Port/"
$wait = 0
Write-Info "Waiting for server health at $healthUrl (timeout: $TimeoutSeconds s)"
while ($wait -lt $TimeoutSeconds) {
  try {
    $res = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2 -ErrorAction Stop
    Write-Info "Server healthy: $res"
    break
  } catch {
    Start-Sleep -Seconds 1; $wait++
  }
}
if ($wait -ge $TimeoutSeconds) { Write-Err "Server did not respond within $TimeoutSeconds seconds. Continuing anyway." }

# Configure adb reverse so Android emulator can reach host:10.0.2.2 -> localhost
$adbCmd = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCmd) {
  Write-Info "Configuring adb reverse tcp:$Port -> tcp:$Port"
  & $adbCmd.Source reverse tcp:$Port tcp:$Port 2>$null
  Write-Info "adb reverse attempted"
} else {
  Write-Err "adb not found on PATH. If you plan to use an Android emulator, add Android platform-tools to PATH or run adb manualy."
}

# Find or launch emulator and run flutter
$flutterExists = (Get-Command $FlutterCmd -ErrorAction SilentlyContinue) -ne $null
if (-not $flutterExists) { Write-Err "Flutter not found on PATH. Install Flutter or add it to PATH to proceed."; exit 1 }

# Attempt to find an Android device first
function Get-AndroidDeviceId() {
  try {
    $devsOut = & $FlutterCmd devices --machine 2>$null
    if ($devsOut -and $devsOut -ne '') { $devs = $devsOut | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $devs = @() }
    foreach ($d in $devs) {
      if ($d.targetPlatform -and $d.targetPlatform -match 'android') { return $d.id }
      if ($d.name -and $d.name.ToLower() -match 'emulator') { return $d.id }
    }
  } catch { }
  return $null
}

$deviceId = Get-AndroidDeviceId
if (-not $deviceId) {
  Write-Info "No Android device found. Attempting to launch the first configured flutter emulator."
  try {
    $emList = & $FlutterCmd emulators 2>$null
    $first = $emList | Select-String '•' | Select-Object -First 1
    if ($first) {
      $emuName = ($first -split ' ')[1]
      Write-Info "Launching emulator: $emuName"
      & $FlutterCmd emulators --launch $emuName
      Start-Sleep -Seconds 6
    } else {
      Write-Err "No configured flutter emulators found. Please create one with 'flutter emulators --create' or start an AVD in Android Studio."
    }
  } catch { Write-Err "Error launching emulator: $_" }

  # Wait for device to appear
  $waitDev = 0
  while ($waitDev -lt $TimeoutSeconds) {
    $deviceId = Get-AndroidDeviceId
    if ($deviceId) { break }
    Start-Sleep -Seconds 1; $waitDev++
  }
  if (-not $deviceId) { Write-Err "No Android device available after waiting $TimeoutSeconds s."; exit 1 }
}

Write-Info "Using Android device: $deviceId"
Write-Info "Running: $FlutterCmd run -d $deviceId"
& $FlutterCmd run -d $deviceId
