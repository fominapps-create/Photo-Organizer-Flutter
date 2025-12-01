#!/usr/bin/env pwsh
# Try to start an emulator device (if none running) and run the Flutter app on the first available device.
param(
    [string]$FlutterCmd = 'flutter',
    [switch]$AllowDesktop = $false,
    [switch]$PreferAndroid = $true
)

Write-Output "Checking for connected Flutter devices..."
$flutterExists = (Get-Command $FlutterCmd -ErrorAction SilentlyContinue) -ne $null
if ($flutterExists) {
    $devicesOut = & $FlutterCmd devices 2>&1
} else {
    $devicesOut = ""
}
if (-not $flutterExists -or $devicesOut -match 'No devices') {
    Write-Output "No devices found. Trying to start a device via flutter emulators..."
    if (-not $flutterExists) { Write-Warning "Flutter tool not found on PATH - attempting Android 'emulator' fallback" }
    $emulators = @()
    if ($flutterExists) { $emulators = & $FlutterCmd emulators 2>&1 }
    $first = $emulators | Select-String '•' | Select-Object -First 1
    if (-not $first) {
        # Fallback: try launching the Android SDK emulator directly if `emulator` is present
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
                exit 1
            }
        } else {
            Write-Warning "No emulators configured (flutter not available). Start an emulator or connect a device then run this script again."
            exit 1
        }
    } else {
        $emuName = ($first -split ' ')[1]
        Write-Output "Attempting: flutter emulators --launch $emuName"
        & $FlutterCmd emulators --launch $emuName
    }
    Start-Sleep -Seconds 4
}

Write-Output 'Listing devices:'
if ($flutterExists) {
    Write-Output 'Using flutter to detect devices (machine-readable).'
    # Using flutter's machine JSON output to robustly parse device IDs
    # Parse the machine-readable devices JSON as an array for robust selection
    $devicesJson = & $FlutterCmd devices --machine 2>&1
    try {
        $devicesObj = $devicesJson | ConvertFrom-Json
    } catch {
        $devicesObj = @()
    }
    $deviceId = $null
    foreach ($obj in $devicesObj) {
        if ($null -eq $obj) { continue }
        $candidateId = $obj.id
        $platform = if ($obj.targetPlatform) { $obj.targetPlatform.ToLower() } else { '' }
        if ($platform -match 'android' -or ($obj.name -and $obj.name.ToLower() -match 'emulator')) {
            $deviceId = $candidateId
            break
        }
        if (-not $deviceId) { $deviceId = $candidateId }
    }
} else {
    Write-Output "Flutter not available; falling back to 'adb devices'."
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adb) {
        Write-Warning "Neither flutter nor adb found on PATH. Please install Flutter or Android platform-tools and try again."
        exit 1
    }
    $adbDevices = & adb devices 2>&1
    # Parse adb devices output; pick first device with status 'device'
    $deviceId = $null
    foreach ($line in $adbDevices) {
        if ($line -match '\s*(\S+)\s+device\b') {
            $deviceId = $Matches[1]
            break
        }
    }
}
if (-not $deviceId) {
    Write-Warning 'Unable to find a device to run the app on. Please start an emulator or connect a device.'
    exit 1
}
Function Find-Adb {
    $found = @()
    # all adb commands on PATH
    $cmds = Get-Command adb -All -ErrorAction SilentlyContinue
    if ($cmds) { $found += $cmds | ForEach-Object { $_.Source } }
    # Look in common SDK locations
    $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "$env:LOCALAPPDATA\Android\Sdk")
    foreach ($root in $sdkRoots) {
        if ($root -and (Test-Path $root)) {
            $p = Join-Path $root 'platform-tools\adb.exe'
            if (Test-Path $p) { $found += $p }
        }
    }
    # Prefer SDK-located adb first
    $ordered = @()
    # Check for SDK roots
    $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "$env:LOCALAPPDATA\Android\Sdk")
    foreach ($root in $sdkRoots) {
        if ($root -and (Test-Path $root)) {
            $p = Join-Path $root 'platform-tools\adb.exe'
            if (Test-Path $p -and -not ($ordered -contains $p)) { $ordered += $p }
        }
    }
    # then PATH-based locations
    foreach ($p in $found) { if (-not ($ordered -contains $p)) { $ordered += $p } }
    return $ordered | Select-Object -Unique
}

# Find adb and log locations so we can see if Android Studio's adb differs
# Find available adb instances and prefer any SDK root ones
$adbs = Find-Adb
if ($adbs.Count -eq 0) {
    Write-Output "No adb found on PATH or common SDK paths. If Android Studio can see your emulator, ensure that its SDK is added to PATH or pass the adb path to this script."
} else {
    Write-Output "Found adb executables:"; $adbs | ForEach-Object { Write-Output "  $_" }
    $adb = $adbs[0]
    Write-Output "Using adb at: $adb"
}
# If the selected device is Windows (desktop) and the caller doesn't allow desktop runs,
# bail out and ask the developer to start an Android emulator explicitly.
Write-Output "Selected device ID: $deviceId"
if ($deviceId -match 'windows' -and -not $AllowDesktop) {
    Write-Warning "Selected device appears to be a Windows desktop target. To avoid accidentally running on your dev machine instead of an emulator, desktop runs are disabled by default. Rerun with -AllowDesktop if you really want this."
    exit 1
}
Write-Output "Running flutter app on device: $deviceId from project root"
Push-Location -Path "$PSScriptRoot/.."
if ($flutterExists) {
    & $FlutterCmd run -d $deviceId
} else {
    # Fallback: if we have a built APK, attempt to install and launch it using adb
    $possibleApks = @("build\app\outputs\flutter-apk\app-debug.apk", "build\app\outputs\apk\debug\app-debug.apk")
    $apkFound = $null
    foreach ($apk in $possibleApks) {
        if (Test-Path $apk) { $apkFound = $apk; break }
    }
    if (-not $apkFound) {
        Write-Warning "Flutter is not available and no APK was found at expected locations. Please install Flutter or build an APK via 'flutter build apk'."
        Pop-Location
        exit 1
    }
    Write-Output "Installing APK: $apkFound"
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adb) { Write-Warning "adb not found; unable to install APK"; Pop-Location; exit 1 }
    & $adb install -r $apkFound
    # Try to find the package name from AndroidManifest
    $manifestPath = "android\app\src\main\AndroidManifest.xml"
    $packageName = $null
    if (Test-Path $manifestPath) {
        $manifest = Get-Content $manifestPath -Raw
        if ($manifest -match 'package="([^"]+)"') { $packageName = $Matches[1] }
    }
    if ($packageName) {
        Write-Output "Launching package: $packageName"
        & $adb shell monkey -p $packageName -c android.intent.category.LAUNCHER 1
    } else {
        Write-Warning "Could not find package name in AndroidManifest.xml; APK installed but unable to launch automatically. Open the app on the device manually."
    }
}
Pop-Location
