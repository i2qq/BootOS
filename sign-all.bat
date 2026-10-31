@echo off
cd /d "%~dp0"
title BootOS Binary Signer
echo ==========================================================
echo       BootOS - Sign Binaries with Developer Cert
echo ==========================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\sign-binaries.ps1"
pause
