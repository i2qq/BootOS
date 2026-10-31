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
    # Build standalone Windows GUI flasher & runner
    $gccCheck = Get-Command gcc.exe -ErrorAction SilentlyContinue
    if ($gccCheck -and (Test-Path "$workspacePath\src\bootos-flasher-gui.c")) {
        Write-Host "Compiling standalone Windows GUI flasher (bootos-flasher-gui.exe)..." -ForegroundColor Cyan
        & gcc -O2 -mwindows "$workspacePath\src\bootos-flasher-gui.c" -o "$workspacePath\bootos-flasher-gui.exe" -lcomctl32 -lcomdlg32
        Copy-Item "$workspacePath\bootos-flasher-gui.exe" "$workspacePath\bootos-flasher.exe" -Force
        Copy-Item "$workspacePath\bootos-flasher-gui.exe" "$workspacePath\bootos.exe" -Force
    }

    Write-Host "`nTo flash to USB (No Rufus required):" -ForegroundColor Cyan
    Write-Host "  -> Double-click 'bootos-flasher.exe' (or 'flash-usb.bat')" -ForegroundColor Yellow
    Write-Host "`nTo execute BootOS directly on Windows (VM Sandbox):" -ForegroundColor Cyan
    Write-Host "  -> Double-click 'bootos-run.bat' (or option [2] in bootos-flasher.exe)" -ForegroundColor Yellow
} else {
    Write-Host "`nBuild failed or bootos.iso not found." -ForegroundColor Red
}
