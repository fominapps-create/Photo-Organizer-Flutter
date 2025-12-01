# Backup script for Photo Organizer Flutter repo
# Creates a zip of tracked files (git archive), a git bundle, and copies tags DB
param(
    [string]$RepoRoot = "G:\Flutter Projects\photo_organizer_flutter",
    [string]$BackupDir = "G:\backups"
)

$ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
Set-Location $RepoRoot

Write-Output "Backup started at $ts"

# Create a zip of tracked files (git archive) if this is a git repo
$zipPath = Join-Path $BackupDir "photo_organizer_flutter_$ts.zip"
$bundlePath = Join-Path $BackupDir "photo_organizer_flutter_$ts.bundle"

try {
    git -C $RepoRoot rev-parse --git-dir > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Creating git archive -> $zipPath"
        git -C $RepoRoot archive --format=zip -o $zipPath HEAD
        Write-Output "Creating git bundle -> $bundlePath"
        git -C $RepoRoot bundle create $bundlePath --all
    } else {
        throw "Not a git repo"
    }
} catch {
    Write-Output "Git archive failed (or not a git repo). Falling back to full ZIP of working tree. Error: $_"
    # Fallback: compress working tree excluding build artifact folders
    $temp = Join-Path $env:TEMP "repo_backup_$ts"
    if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
    New-Item -ItemType Directory -Path $temp | Out-Null
    # Copy everything except some large build dirs
    $excludes = @('build','\.dart_tool','\.gradle','build\\','\.idea')
    robocopy $RepoRoot $temp /MIR /XD $excludes | Out-Null
    Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $zipPath -Force
    Remove-Item $temp -Recurse -Force
}

# Copy tags_db.json if present
$tagsDbSrc = Join-Path $RepoRoot 'python-server\backend\tags_db.json'
if (Test-Path $tagsDbSrc) {
    Copy-Item $tagsDbSrc -Destination (Join-Path $BackupDir "tags_db_$ts.json") -Force
    Write-Output "Copied tags_db.json"
} else {
    Write-Output "No tags_db.json found to copy"
}

Write-Output "Backup complete. Files in ${BackupDir}:"
Get-ChildItem $BackupDir -Filter "photo_organizer_flutter_*$ts*" | Select-Object Name,Length
Write-Output "Done."