@echo off
title BootOS VirtualBox Runner
cd /d "%~dp0"

echo ==========================================================
echo          BootOS - Executing in Oracle VirtualBox
echo ==========================================================
echo.

:: Check for VirtualBox
if exist "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" (
    echo Launching BootOS in Oracle VirtualBox...
    vde-vlm start vmbootos2 --gui 2>nul || "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm vmbootos2 --type gui
    exit /b
)

echo Oracle VirtualBox was not found at C:\Program Files\Oracle\VirtualBox\VBoxManage.exe.
echo Please install Oracle VirtualBox or use bootos-flasher-gui.exe to prepare your USB drive!
pause
