@echo off
title BootOS USB Flasher
cd /d "%~dp0"

:: Check for Administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges to access USB physical drive...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

if exist "%~dp0bootos-flasher-gui.exe" (
    "%~dp0bootos-flasher-gui.exe"
) else if exist "%~dp0bootos-flasher.exe" (
    "%~dp0bootos-flasher.exe"
) else if exist "%~dp0bootos.exe" (
    "%~dp0bootos.exe"
) else (
    powershell -ExecutionPolicy Bypass -File "%~dp0scripts\flash-usb.ps1"
)
