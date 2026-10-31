@echo off
cd /d "%~dp0"
echo ==========================================================
echo        BootOS - Windows GUI Flasher Builder
echo ==========================================================
echo Compiling bootos-flasher-gui.exe...
gcc -O2 -mwindows src\bootos-flasher-gui.c -o bootos-flasher-gui.exe -lcomctl32 -lcomdlg32
if exist bootos-flasher-gui.exe (
    copy /y bootos-flasher-gui.exe bootos-flasher.exe >nul
    echo [SUCCESS] bootos-flasher-gui.exe is compiled and ready!
) else (
    echo [BLOCKED] File was removed by Windows Defender.
    echo Please add this folder to Windows Defender Exclusions, then run this again.
)
pause
