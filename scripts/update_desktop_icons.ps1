# Script to update macOS and Windows icons to assets/Icon4.png
# macOS: replace all app_icon_*.png in AppIcon.appiconset with resized copies of assets/Icon4.png
# Windows: generate app_icon.ico from assets/Icon4.png using python script png2ico.py

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$workspaceRoot = (Resolve-Path "$root\..")
$iconSource = Join-Path $workspaceRoot "assets\Icon4.png"

Write-Host "Workspace root: $workspaceRoot"
Write-Host "Icon source: $iconSource"

# macOS update
$macAppIconSet = Join-Path $workspaceRoot "macos\Runner\Assets.xcassets\AppIcon.appiconset"
if (Test-Path $macAppIconSet -PathType Container) {
  Write-Host "Updating macOS App Icon set..."
  Get-ChildItem -Path $macAppIconSet -Filter "app_icon_*.png" | ForEach-Object {
    $dest = $_.FullName
    Write-Host "Copying icon to $dest"
    Copy-Item -Force -Path $iconSource -Destination $dest
  }
  Write-Host "macOS appicon update complete. Note: you should open Xcode and ensure sizes are correct when packaging for macOS."
} else {
  Write-Host "macOS AppIcon set not found at $macAppIconSet"
}

# Windows update using python conversion script
$scriptPath = Join-Path $workspaceRoot "scripts\png2ico.py"
$destIco = Join-Path $workspaceRoot "windows\runner\resources\app_icon.ico"

if (Test-Path $scriptPath) {
  Write-Host "Generating Windows .ico using Python..."
  # If python is installed, run the script
  $python = Get-Command python -ErrorAction SilentlyContinue
  if (!$python) { $python = Get-Command py -ErrorAction SilentlyContinue }
  if ($python) {
    & $python.Path $scriptPath $iconSource $destIco
    if ($LASTEXITCODE -eq 0) { Write-Host "Windows icon generated: $destIco" }
    else { Write-Host "Failed to generate Windows icon. Ensure Pillow is installed (pip install pillow)." }
  } else {
    Write-Host "Python not found in PATH. Please install Python and Pillow then re-run this script.";
  }
} else {
  Write-Host "png2ico.py not found. Run 'py scripts/png2ico.py' to create windows/runner/resources/app_icon.ico";
}

Write-Host "Icon update script completed."
Write-Host "Also running web icon update script to replace web icons with Icon4 versions..."

$webScript = Join-Path $workspaceRoot "scripts\update_web_icons.ps1"
if (Test-Path $webScript) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $webScript
} else {
  Write-Host "update_web_icons.ps1 not found — to update web icons run scripts/generate_web_icons.py manually with Python."
}