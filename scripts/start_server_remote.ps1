#!/usr/bin/env pwsh
# Start the Photo Organizer API server in 'remote/testing' mode
# WARNING: This binds the server to 0.0.0.0 (LAN accessible) — only use for testing
param(
    [string]$Token = "testtoken",
    [switch]$Persist,
    [string]$AllowOrigins = ""
)

Push-Location -Path "$PSScriptRoot/.."
Set-Location -Path "python-server"
Write-Host "Starting Photo Organizer API in remote (LAN) mode..."

$argsList = @()
if ($Token -ne "") { $argsList += "--upload-token \"$Token\"" }
if ($Persist) { $argsList += "--persist-uploads" }
if ($AllowOrigins -ne "") { $argsList += "--allow-origins \"$AllowOrigins\"" }
$argsList += "--allow-remote"

$argString = $argsList -join ' '
python run_server.py $argString
Pop-Location
