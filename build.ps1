# ==============================================================================
# BootOS - One-Click Build Script for Windows
# ==============================================================================
# This script builds bootos.iso automatically.

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "             BootOS - ISO Build Tool" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$workspacePath = Get-Location
Write-Host "Workspace: $workspacePath" -ForegroundColor Gray

# Check if WSL is available
$wslCheck = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCheck) {
    Write-Error "WSL is required to assemble the Linux kernel and ISO image."
    exit 1
}

Write-Host "Building bootos.iso (100% RAM resident)..." -ForegroundColor Yellow
$wslPath = wsl -d Ubuntu -u root -e wslpath "$workspacePath"
wsl -d Ubuntu -u root -e bash -c "chmod +x '$wslPath/scripts/build-iso.sh' && '$wslPath/scripts/build-iso.sh'"

if (Test-Path "$workspacePath\bootos.iso") {
    $iso = Get-Item "$workspacePath\bootos.iso"
    $sizeMB = [math]::Round($iso.Length / 1MB, 2)
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " [SUCCESS] bootos.iso is ready!" -ForegroundColor Green
    Write-Host " File: $($iso.FullName)" -ForegroundColor White
    Write-Host " Size: $sizeMB MB (Well under 1 GB, fits easily on a 2GB USB)" -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "`nTo flash to your USB drive, use Rufus (rufus.ie), BalenaEtcher, or Ventoy." -ForegroundColor Cyan
} else {
    Write-Host "`nBuild failed or bootos.iso not found." -ForegroundColor Red
}
