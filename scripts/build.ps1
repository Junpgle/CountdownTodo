param(
    [switch]$Android,
    [switch]$Windows,
    [switch]$All
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "  Flutter Build Script"
Write-Host "========================================"
Write-Host ""

Write-Host "[1/3] Bumping version..." -ForegroundColor Yellow
dart run scripts/bump_version.dart

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to bump version" -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host ""

$pubspec = Get-Content pubspec.yaml | Select-String "^version:" | ForEach-Object { $_.ToString().Split(":")[1].Trim() }
Write-Host "Current version: $pubspec" -ForegroundColor Green
Write-Host ""

function Build-Android {
    Write-Host "========================================"
    Write-Host "  Building Android APK..."
    Write-Host "========================================"
    flutter build apk --release
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Android build successful!" -ForegroundColor Green
        Write-Host "Output: build\app\outputs\flutter-apk\" -ForegroundColor Gray
    } else {
        Write-Host "Android build failed" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host ""
}

function Build-Windows {
    Write-Host "========================================"
    Write-Host "  Building Windows App..."
    Write-Host "========================================"
    flutter build windows --release
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Windows build successful!" -ForegroundColor Green
        Write-Host "Output: build\windows\x64\runner\Release\" -ForegroundColor Gray
    } else {
        Write-Host "Windows build failed" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host ""
}

$startTime = Get-Date

if ($All -or (-not $Android -and -not $Windows)) {
    Build-Android
    Build-Windows
} else {
    if ($Android) { Build-Android }
    if ($Windows) { Build-Windows }
}

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

Write-Host "========================================"
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "  Time: $([math]::Round($duration, 1)) seconds" -ForegroundColor Gray
Write-Host "========================================"
