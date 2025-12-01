param(
  [string]$WorkspaceRoot = (Resolve-Path "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..")
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$workspaceRoot = (Resolve-Path "$root\..")
$iconSource = Join-Path $workspaceRoot "assets\Icon4.png"

Write-Host "Workspace root: $workspaceRoot"
Write-Host "Web icon source: $iconSource"

if (!(Test-Path $iconSource)) {
  Write-Host "Icon not found: $iconSource"; exit 1
}

$scriptPath = Join-Path $workspaceRoot "scripts\generate_web_icons.py"
if (Test-Path $scriptPath) {
  $python = Get-Command python -ErrorAction SilentlyContinue
  if (!$python) { $python = Get-Command py -ErrorAction SilentlyContinue }
  if ($python) {
    & $python.Path $scriptPath $iconSource $workspaceRoot
    if ($LASTEXITCODE -eq 0) { Write-Host "Web icons generated" }
    else { Write-Host "Generating web icons failed (check python/pillow)" }
  } else {
    Write-Host "Python not found in PATH. Please install Python and Pillow (pip install pillow)";
    exit 2
  }
} else {
  Write-Host "generate_web_icons.py not found at $scriptPath"
}

Write-Host "Web icon update complete."
