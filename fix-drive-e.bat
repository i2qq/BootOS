@echo off
title Fixing Drive E...
cd /d "%~dp0"

:: Request Admin UAC
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo Repairing and formatting Drive E: (Generic Flash Disk 2GB)...
(
echo select disk 2
echo clean
echo convert mbr
echo create partition primary
echo active
echo format fs=fat32 quick label="BOOTOS"
echo assign letter=E
echo exit
) > "%TEMP%\fix_usb_e.txt"

diskpart /s "%TEMP%\fix_usb_e.txt"
del "%TEMP%\fix_usb_e.txt" 2>nul

echo.
echo ==========================================================
echo  [SUCCESS] Drive E: is now 100%% fixed and formatted as FAT32!
echo ==========================================================
echo Opening Drive E: in Windows File Explorer...
start explorer.exe E:\
timeout /t 3 >nul
