#!/usr/bin/env pwsh
<#
Dev helper script: start the server (safe defaults), ensure it's responsive,
set adb reverse so the emulator can reach the host server, then run the Flutter
app on the first available emulator/device.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev_start_all.ps1

This script is intended for local development on Windows; it assumes `python`,
`flutter`, and `adb` are available on PATH.
#>

param(
  [switch]$NoServer = $false,
  [string]$ServerScript = '.\scripts\start_server_safe.ps1',
  [int]$Port = 8000,
  [int]$TimeoutSeconds = 30,
  [string]$FlutterCmd = 'flutter'
)

Write-Host "Dev start: server -> adb reverse -> run emulator app"
Push-Location -Path "$PSScriptRoot/.."
$flutterExists = (Get-Command $FlutterCmd -ErrorAction SilentlyContinue) -ne $null
if (-not $flutterExists) { Write-Warning "Flutter command not found on PATH. The script will still attempt to start an emulator via the Android SDK 'emulator' tool and use adb to install any APKs." }

function Test-ServerReady($url) {
  try {
    $r = Invoke-RestMethod -Uri $url -TimeoutSec 2 -ErrorAction Stop
    return $true
  } catch {
    return $false
  }
}

Function Find-Adb {
  $found = @()
  $cmds = Get-Command adb -All -ErrorAction SilentlyContinue
  if ($cmds) { $found += $cmds | ForEach-Object { $_.Source } }
  $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "$env:LOCALAPPDATA\Android\Sdk")
  foreach ($root in $sdkRoots) {
      if ($root -and (Test-Path $root)) {
          $p = Join-Path $root 'platform-tools\adb.exe'
          if (Test-Path $p) { $found += $p }
      }
  }
  # Prefer SDK-located adb first, then PATH-based
  $ordered = @()
  foreach ($root in $sdkRoots) {
      if ($root -and (Test-Path $root)) {
          $p = Join-Path $root 'platform-tools\adb.exe'
          if (Test-Path $p -and -not ($ordered -contains $p)) { $ordered += $p }
      }
  }
  foreach ($p in $found) { if (-not ($ordered -contains $p)) { $ordered += $p } }
  return $ordered | Select-Object -Unique
}

# Start server in a new PowerShell window so it keeps running
if (-not $NoServer) {
  Write-Host "Starting server (safe mode) using $ServerScript"
  $startCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $ServerScript"
  Start-Process -FilePath powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-Command","& { $startCmd }" -WindowStyle Normal
  Start-Sleep -Seconds 2
} else {
  Write-Host "Skipping server start (--NoServer specified)"
}

# Wait for server to respond
$url = "http://127.0.0.1:$Port/"
$wait = 0
while ($wait -lt $TimeoutSeconds) {
  if (Test-ServerReady $url) {
    Write-Host "Server is ready at $url"
    break
  }
  Write-Host "Waiting for server to be ready... ($wait/$TimeoutSeconds)"
  Start-Sleep -Seconds 1
  $wait++
}
if ($wait -ge $TimeoutSeconds) {
  Write-Warning "Server did not start within $TimeoutSeconds s. Check python-server/server.log or run run_server.py manually for debug."
}

# Ensure adb can reverse the port so emulator can reach server at http://10.0.2.2:$Port
  Write-Host "Ensuring adb reverse.."
try {
  $adbCmd = Get-Command adb -ErrorAction SilentlyContinue
  # Show where adb is found and try to reconcile with Android Studio's SDK path
  $adbs = Find-Adb
  if ($adbs.Count -gt 0) { Write-Host "Detected adb executables: $($adbs -join ', ')" } else { Write-Host "No adb executables detected on PATH or common SDK locations." }
  if (-not $adbCmd) { Write-Warning "adb not found on PATH. We'll try to use SDK-specific adb if available. If no adb is found at all, the emulator may not be able to connect to this host via reverse." }
  $adb = $null
  if ($adbs.Count -gt 0) { $adb = $adbs[0] }
    else {
      # Start an emulator if none are running
      if ($adb) { $adbDevices = & $adb devices 2>&1 } else { $adbDevices = & adb devices 2>&1 }
      $hasDevice = $false
      foreach ($line in $adbDevices) { if ($line -match '\s*(\S+)\s+device\b') { $hasDevice = $true; break } }
      if (-not $hasDevice) {
        if ($flutterExists) {
          Write-Host "No running devices found. Attempting to launch emulator using flutter emulators..."
          $emulators = & $FlutterCmd emulators 2>&1
          $firstEmu = $emulators | Select-String '•' | Select-Object -First 1
          if ($firstEmu) {
            $emuName = ($firstEmu -split ' ')[1]
            Write-Host "Launching emulator: $emuName"
            & $FlutterCmd emulators --launch $emuName
            Start-Sleep -Seconds 6
          } else {
            # Try native emulator as fallback
            $emulatorExec = Get-Command emulator -ErrorAction SilentlyContinue
            if ($emulatorExec) {
              Write-Output "Found Android SDK 'emulator' at $($emulatorExec.Path). Listing AVDs..."
              $avds = & emulator -list-avds 2>&1
              $firstAvd = $avds | Select-Object -First 1
              if ($firstAvd) {
                Write-Output "Launching AVD: $firstAvd"
                Start-Process -FilePath $emulatorExec.Path -ArgumentList "-avd", "$firstAvd" -NoNewWindow -PassThru
                Start-Sleep -Seconds 8
              } else {
                Write-Warning "No AVDs found. Create an emulator with AVD Manager or 'flutter emulators --create' and try again."
              }
            } else {
              Write-Warning "No emulator configured. Please start one or connect a device."
            }
          }
        } else {
          # Attempt to use Android SDK emulator
          $emulatorExec = Get-Command emulator -ErrorAction SilentlyContinue
          if ($emulatorExec) {
            Write-Output "Found Android SDK 'emulator' at $($emulatorExec.Path). Listing AVDs..."
            $avds = & emulator -list-avds 2>&1
            $firstAvd = $avds | Select-Object -First 1
            if ($firstAvd) {
              Write-Output "Launching AVD: $firstAvd"
              Start-Process -FilePath $emulatorExec.Path -ArgumentList "-avd", "$firstAvd" -NoNewWindow -PassThru
              Start-Sleep -Seconds 8
            } else {
              Write-Warning "No AVDs found. Create an emulator with AVD Manager or 'flutter emulators --create' and try again."
            }
          } else {
            Write-Warning "No emulator configured and flutter not present. Please start an emulator or connect a device."
          }
        }
      }
      # If no device detected yet and we have a selected adb, try restarting its server (useful for Android Studio-managed adb instances)
      if (-not $hasDevice -and $adb) {
        Write-Host "Restarting adb server using $adb to allow the emulator to show up..."
        try {
          & $adb kill-server 2>$null; Start-Sleep -Seconds 1
          & $adb start-server 2>$null; Start-Sleep -Seconds 1
          $adbDevices = & $adb devices 2>&1
          foreach ($line in $adbDevices) { if ($line -match '\s*(\S+)\s+device\b') { $hasDevice = $true; break } }
        } catch {
          Write-Warning "Restart adb attempt via $adb failed: $_"
        }
      }

    }
    # Now call adb reverse
    Write-Host "Running adb reverse tcp:$Port tcp:$Port (using $adb)"
    if ($adb) { & $adb reverse tcp:$Port tcp:$Port 2>$null } else { Write-Warning "Cannot run adb reverse because no adb was detected: $($adbs -join ', ')" }
    Write-Host "adb reverse configured (if adb is present and an emulator/device connected)."
  }
  catch {
  Write-Warning "adb reverse failed: $_"
}

# Wait for an Android device/emulator to appear (unless user doesn't care)
Write-Host "Waiting for an Android emulator/device to become available (timeout: $TimeoutSeconds sec)"
$waitDevice = 0
$deviceFound = $false
while ($waitDevice -lt $TimeoutSeconds) {
  if ($flutterExists) {
    $deviceList = & $FlutterCmd devices --machine 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($deviceList -and $deviceList.Count -gt 0) {
      foreach ($d in $deviceList) { if ($d.targetPlatform -and $d.targetPlatform -match 'android') { $deviceFound = $true; break } }
    }
  } else {
    if ($adb) {
      $adbDevices = & $adb devices 2>&1
      foreach ($line in $adbDevices) { if ($line -match '\s*(\S+)\s+device\b') { $deviceFound = $true; break } }
    } else {
      $adbTmp = Get-Command adb -ErrorAction SilentlyContinue
      if ($adbTmp) {
        $adbDevices = & adb devices 2>&1
        foreach ($line in $adbDevices) { if ($line -match '\s*(\S+)\s+device\b') { $deviceFound = $true; break } }
      }
    }
  }
  if ($deviceFound) { Write-Host "Android device found"; break }
  Write-Host "No Android device yet, waiting... ($waitDevice/$TimeoutSeconds)"
  Start-Sleep -Seconds 1
  $waitDevice++
}
if (-not $deviceFound) { Write-Warning "No Android emulator/device found within $TimeoutSeconds seconds; the app launch may pick the Windows desktop target instead." }

# Finally run Flutter app on emulator/device; prefer Android devices by default
Write-Host "Launching Flutter app on available emulator/device (this will build & deploy the app). PreferAndroid: $true"
if ($flutterExists) {
  & $PSScriptRoot\run_app_on_emulator.ps1 -FlutterCmd $FlutterCmd -PreferAndroid
} else {
  & $PSScriptRoot\run_app_on_emulator.ps1 -PreferAndroid
}

Pop-Location
Write-Host "Dev start orchestration complete. Check server/ emulator windows for status." 
