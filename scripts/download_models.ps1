# Download model files into `python-server/models/`
# Edit the $modelUrls list to include real download URLs for your models.

$modelsDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\python-server\models"
if (-not (Test-Path $modelsDir)) { New-Item -ItemType Directory -Path $modelsDir | Out-Null }

# Replace these placeholder URLs with real ones.
$modelUrls = @(
    @{ name = 'yolov8n.pt'; url = 'https://example.com/path/to/yolov8n.pt' },
    @{ name = 'yolov8m.pt'; url = 'https://example.com/path/to/yolov8m.pt' }
)

foreach ($m in $modelUrls) {
    $dest = Join-Path $modelsDir $($m.name)
    Write-Output "Downloading $($m.name) to $dest"
    try {
        Invoke-WebRequest -Uri $m.url -OutFile $dest -UseBasicParsing
        Write-Output "Downloaded $($m.name)"
    } catch {
        Write-Output "Failed to download $($m.name): $_"
    }
}

Write-Output "Done. Move or copy model files into python-server/ if your server expects them in the project root."
