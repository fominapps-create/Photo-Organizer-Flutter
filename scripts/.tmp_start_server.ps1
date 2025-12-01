Push-Location 'python-server'
$p = Start-Process -FilePath python -ArgumentList 'run_server.py','--no-reload','--port','8000' -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2
Write-Output "SERVER_PID=$($p.Id)"
Try {
  $res = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/' -TimeoutSec 4 -ErrorAction Stop
  Write-Output "HEALTH: $res"
} Catch {
  Write-Output 'HEALTH: UNREACHABLE'
}
Pop-Location
