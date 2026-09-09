@echo off
rem ---------------------------------------------------------------------------
rem  Lanceur Windows de l'application GSB de 2013, SANS DOCKER.
rem  Double-clic depuis l'Explorateur.
rem
rem  Telecharge PHP 7.4 et MariaDB en version portable dans legacy\local\,
rem  puis demarre l'application. Aucun droit administrateur necessaire.
rem ---------------------------------------------------------------------------
chcp 65001 > nul
setlocal
cd /d "%~dp0"
set PORT=8089

echo.
echo   +------------------------------------------------+
echo   ^|   GSB - application de 2013, sans Docker       ^|
echo   +------------------------------------------------+
echo.
echo   Premiere execution : telechargement de PHP et MariaDB,
echo   comptez une dizaine de minutes selon le reseau.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "legacy\sans-docker\demarrer-windows.ps1" -PortWeb %PORT%
if errorlevel 1 (
    echo.
    echo   ECHEC : les messages ci-dessus indiquent a quelle etape.
    goto :fin
)

start "" "http://127.0.0.1:%PORT%"
echo.
echo   Vous pouvez fermer cette fenetre : l'application continue de tourner.
echo   Pour l'arreter, double-cliquez sur Arreter-GSB-sans-Docker-windows.bat

:fin
echo.
pause
endlocal
