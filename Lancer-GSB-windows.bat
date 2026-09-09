@echo off
rem ---------------------------------------------------------------------------
rem  Lanceur Windows de l'application GSB de 2013.
rem
rem  Se lance d'un double-clic depuis l'Explorateur. Il n'y a rien a taper.
rem
rem  Le script demarre Docker si besoin, met l'application en route, puis ouvre
rem  le navigateur. Si les prerequis manquent, il le dit et indique quoi faire.
rem ---------------------------------------------------------------------------

rem Affichage des accents dans la console
chcp 65001 > nul
setlocal
cd /d "%~dp0"

set PORT=8088
set ADRESSE=http://localhost:%PORT%

echo.
echo   +------------------------------------------------+
echo   ^|   GSB - application de 2013                    ^|
echo   +------------------------------------------------+
echo.

rem --- Docker est-il installe ? ----------------------------------------------

where docker >nul 2>&1
if errorlevel 1 (
    echo   ECHEC : Docker n'est pas installe.
    echo.
    echo   Ouvrez PowerShell EN ADMINISTRATEUR, placez-vous dans ce dossier
    echo   et executez :
    echo.
    echo       Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    echo       .\legacy\windows\installer-prerequis.ps1
    echo.
    goto :fin
)

rem --- PowerShell fait le reste ----------------------------------------------

echo   Mise en route, cela peut prendre plusieurs minutes la premiere fois...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "legacy\windows\mise-en-route.ps1" -Port %PORT%
if errorlevel 1 (
    echo.
    echo   ECHEC : la mise en route n'a pas abouti.
    echo   Les messages ci-dessus indiquent a quelle etape.
    goto :fin
)

rem --- navigateur -------------------------------------------------------------

echo   Ouverture du navigateur sur %ADRESSE%
start "" "%ADRESSE%"

echo.
echo   ------------------------------------------------
echo   L'application tourne. Vous pouvez fermer cette fenetre :
echo   elle continuera de fonctionner en arriere-plan.
echo.
echo   Pour l'arreter plus tard, double-cliquez sur Arreter-GSB-windows.bat
echo   ------------------------------------------------

:fin
echo.
pause
endlocal
