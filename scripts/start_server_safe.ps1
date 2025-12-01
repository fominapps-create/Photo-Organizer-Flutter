#!/usr/bin/env pwsh
# Start the Photo Organizer API server in safe (local-only, ephemeral) mode

Push-Location -Path "$PSScriptRoot/.."
Set-Location -Path "python-server"
Write-Host "Starting Photo Organizer API in safe mode (localhost, ephemeral uploads)..."
python run_server.py --no-reload --port 8000
Pop-Location
