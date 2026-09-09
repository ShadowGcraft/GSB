@echo off
rem ---------------------------------------------------------------------------
rem  Arrete l'application GSB de 2013. Double-clic depuis l'Explorateur.
rem
rem  Les donnees saisies sont conservees : on les retrouve au prochain demarrage.
rem  Pour repartir d'une base vierge, ouvrez PowerShell dans ce dossier et tapez :
rem      .\legacy\windows\mise-en-route.ps1 -BaseNeuve
rem ---------------------------------------------------------------------------

chcp 65001 > nul
setlocal
cd /d "%~dp0"

echo.
echo   Arret de l'application GSB...
echo.

docker info >nul 2>&1
if errorlevel 1 (
    echo   Docker ne tourne pas : il n'y a rien a arreter.
    goto :fin
)

pushd legacy
docker compose down
popd

echo.
echo   Application arretee. Les donnees sont conservees.
echo.
echo   Docker Desktop continue de tourner. Pour liberer la memoire, quittez-le
echo   depuis son icone dans la zone de notification.

:fin
echo.
pause
endlocal
