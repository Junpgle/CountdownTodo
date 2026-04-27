param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$RunArgs
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "  Flutter Run (Auto Version Bump)"
Write-Host "========================================"
Write-Host ""

Write-Host "[1/2] Bumping version..." -ForegroundColor Yellow
dart run scripts/bump_version.dart

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to bump version" -ForegroundColor Red
    exit $LASTEXITCODE
}

$pubspec = Get-Content pubspec.yaml | Select-String "^version:" | ForEach-Object { $_.ToString().Split(":")[1].Trim() }
Write-Host "New version: $pubspec" -ForegroundColor Green
Write-Host ""

Write-Host "[2/2] Running app..." -ForegroundColor Cyan
Write-Host "========================================"
Write-Host ""

flutter run @RunArgs
