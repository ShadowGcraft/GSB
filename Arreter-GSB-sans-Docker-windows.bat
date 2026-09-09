@echo off
rem Arrete l'application GSB lancee sans Docker. Double-clic depuis l'Explorateur.
chcp 65001 > nul
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "legacy\sans-docker\arreter-windows.ps1"
pause
endlocal
