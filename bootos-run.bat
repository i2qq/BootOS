@echo off
title BootOS Direct Runner
cd /d "%~dp0"

echo ==========================================================
echo          BootOS - Executing Directly on Windows
echo ==========================================================
echo.

:: Check for VirtualBox
if exist "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" (
    echo Launching BootOS in Oracle VirtualBox...
    vde-vlm start vmbootos2 --gui 2>nul || "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm vmbootos2 --type gui
    exit /b
)

:: Check for QEMU
where qemu-system-x86_64 >nul 2>&1
if %errorlevel% equ 0 (
    echo Launching BootOS with QEMU...
    qemu-system-x86_64 -m 2048 -cdrom "%~dp0bootos.iso" -boot d -net nic,model=e1000 -net user
    exit /b
)

echo Neither VirtualBox nor QEMU was found on PATH.
echo You can use flash-usb.bat or bootos-flasher.exe to flash BootOS to a USB flash drive!
pause
