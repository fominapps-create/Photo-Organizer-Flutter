#!/usr/bin/env pwsh
# Stop the FastAPI server that listens on a port (default 8000)
param(
    [int]$Port = 8000
)

Write-Output "Finding process listening on port $Port..."
$entry = netstat -ano | Select-String ":$Port\s"
if (-not $entry) {
    Write-Output "No process appears to be listening on port $Port; nothing to stop."
    exit 0
}

# Parse PID (last column of netstat line
$pid = ($entry -split '\s+')[-1]
try {
    Stop-Process -Id $pid -Force -ErrorAction Stop
    Write-Output "Stopped process $pid listening on port $Port"
} catch {
    Write-Warning "Failed to stop process $pid: $_. Please stop manually or use Task Manager"
}
# Stop the FastAPI server (run_server.py) by finding python processes with run_server.py in the commandline
# Usage: Stop-Server.ps1
$procs = Get-WmiObject Win32_Process -Filter "Name = 'python.exe'" | Where-Object { $_.CommandLine -like '*run_server.py*' }
if (-not $procs) {
    Write-Host "No run_server.py Python processes found."
    exit 0
}
foreach ($p in $procs) {
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        Write-Host "Stopped process $($p.ProcessId) (run_server.py)"
    } catch {
        Write-Host "Failed to stop $($p.ProcessId): $_"
    }
}
