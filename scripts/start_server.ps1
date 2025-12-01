#!/usr/bin/env pwsh
# Start the Python FastAPI server (uvicorn) in a detached process
param(
    [string]$PythonExe = "python",
    [int]$Port = 8000,
    [string]$UploadToken = "",
    [switch]$AllowRemote,
    [switch]$PersistUploads,
    [string]$AllowOrigins = "",
    [switch]$NoWindow
)

Push-Location -Path "$PSScriptRoot/.."
Set-Location -Path "python-server"
Write-Output "Starting Photo Organizer API server on port $Port (detached)..."
# Build run_server args
$argsList = @()
if ($UploadToken -ne "") { $argsList += "--upload-token \"$UploadToken\"" }
if ($AllowRemote) { $argsList += "--allow-remote" }
if ($PersistUploads) { $argsList += "--persist-uploads" }
if ($AllowOrigins -ne "") { $argsList += "--allow-origins \"$AllowOrigins\"" }
$argsList += "--port $Port"

# Start the server detached, capture process and show PID
$proc = Start-Process -FilePath $PythonExe -ArgumentList ("run_server.py " + ($argsList -join ' ')) -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 1
Write-Output "Started server (PID: $($proc.Id)). Use stop_server.ps1 to stop it or netstat to find port listeners."
Start-Sleep -Seconds 1
Write-Output "Started; use stop_server.ps1 to stop the server."
Pop-Location
# Start the FastAPI server in the python-server folder in a new PowerShell window
# When $NoWindow flag is set, run in the current window.
$root = Split-Path -Parent $PSScriptRoot
$cwd = Join-Path $root 'python-server'
$python = 'python'
if ($NoWindow) {
    # Run in current window (blocking)
    cd $cwd
    & $python run_server.py $argsList
} else {
    # Spawn a new PowerShell that runs the server and redirects logs to server.log
    $startCmd = "cd `"$cwd`"; & $python run_server.py $argsList > server.log 2>&1"
    Start-Process -FilePath powershell -ArgumentList "-NoProfile", "-NoExit", "-Command", $startCmd -WindowStyle Normal
}
Write-Host "Server start requested.\nIf no window is visible, check server.log under python-server for output."