<#
    Arrête l'application GSB lancée sans Docker, sous Windows.

    Les données sont conservées dans legacy\local\mysql\data.
    Pour repartir d'une base vierge :
        .\sans-docker\demarrer-windows.ps1 -BaseNeuve
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$PortWeb  = 8089,
    [int]$PortBase = 3307
)

$ErrorActionPreference = 'Continue'

$racine = Split-Path -Parent $PSScriptRoot
$local  = Join-Path $racine 'local'

Write-Host ''
Write-Host '  Arrêt de l''application GSB (mode sans Docker)'
Write-Host ''

# Arrête le processus qui écoute sur un port, s'il vient de notre dossier.
function Stopper-SurPort([int]$Port, [string]$Etiquette) {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $conn) {
        Write-Host "  $Etiquette déjà arrêté"
        return
    }

    $proc = Get-Process -Id $conn[0].OwningProcess -ErrorAction SilentlyContinue
    if (-not $proc) { Write-Host "  $Etiquette introuvable"; return }

    # Prudence : on ne tue que ce qui a été lancé depuis legacy\local\bin,
    # jamais un PHP ou un MySQL installé par ailleurs sur le poste.
    $chemin = $null
    try { $chemin = $proc.Path } catch { }

    if ($chemin -and $chemin.StartsWith((Join-Path $local 'bin'), 'OrdinalIgnoreCase')) {
        Stop-Process -Id $proc.Id -Force
        Write-Host "  $Etiquette arrêté"
    } else {
        Write-Host "  $Etiquette : le port $Port est tenu par « $($proc.ProcessName) »," -ForegroundColor Yellow
        Write-Host "               qui ne vient pas de ce projet. Rien n'a été arrêté." -ForegroundColor Yellow
    }
}

Stopper-SurPort $PortWeb  'serveur web'
Stopper-SurPort $PortBase 'base de données'

Write-Host ''
Write-Host '  Les données saisies sont conservées.'
Write-Host '  Pour repartir d''une base vierge :'
Write-Host '      .\sans-docker\demarrer-windows.ps1 -BaseNeuve'
Write-Host ''
