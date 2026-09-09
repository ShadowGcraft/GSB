<#
    Installation des prérequis Windows pour faire tourner l'application GSB de 2013.

    Ce script installe ce qui manque, et rien d'autre : il vérifie chaque outil
    avant de l'installer, et peut être relancé sans risque.

    À exécuter DANS UNE FENÊTRE POWERSHELL OUVERTE EN ADMINISTRATEUR :

        Clic droit sur le menu Démarrer, « Terminal (administrateur) », puis :
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        .\legacy\windows\installer-prerequis.ps1

    Un redémarrage est nécessaire à la fin si WSL vient d'être activé.
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    # N'installe rien, se contente d'afficher ce qui manque.
    [switch]$Verification
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------- affichage

function Ecrire-Titre($texte) {
    Write-Host ''
    Write-Host "== $texte" -ForegroundColor Cyan
}
function Ecrire-Ok($texte)      { Write-Host "   [ok]    $texte" -ForegroundColor Green }
function Ecrire-Action($texte)  { Write-Host "   [->]    $texte" -ForegroundColor Yellow }
function Ecrire-Echec($texte)   { Write-Host "   [echec] $texte" -ForegroundColor Red }
function Ecrire-Info($texte)    { Write-Host "           $texte" -ForegroundColor DarkGray }

$aRedemarrer = $false
$manquants   = @()

Write-Host ''
Write-Host '  Installation des prérequis : application GSB de 2013' -ForegroundColor White
Write-Host '  ---------------------------------------------------' -ForegroundColor DarkGray

# --------------------------------------------------------------------------- 1. droits

Ecrire-Titre 'Droits administrateur'
$identite = [Security.Principal.WindowsIdentity]::GetCurrent()
$estAdmin = ([Security.Principal.WindowsPrincipal]$identite).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if ($estAdmin) {
    Ecrire-Ok 'La fenêtre est ouverte en administrateur.'
} elseif ($Verification) {
    Ecrire-Action 'Pas administrateur, mais le mode vérification n''installe rien.'
} else {
    Ecrire-Echec 'Cette fenêtre n''est pas administrateur.'
    Ecrire-Info  'Fermez-la, faites un clic droit sur le menu Démarrer,'
    Ecrire-Info  'choisissez « Terminal (administrateur) », puis relancez le script.'
    exit 1
}

# --------------------------------------------------------------------------- 2. version de Windows

Ecrire-Titre 'Version de Windows'
$os    = Get-CimInstance Win32_OperatingSystem
$build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber

Ecrire-Info "$($os.Caption), build $build"
if ($build -lt 19041) {
    Ecrire-Echec 'Windows 10 version 2004 (build 19041) ou plus récent est nécessaire.'
    Ecrire-Info  'WSL 2, dont Docker Desktop dépend, n''existe pas avant cette version.'
    Ecrire-Info  'Passez par Windows Update avant de continuer.'
    exit 1
}
Ecrire-Ok 'Version suffisante pour WSL 2 et Docker Desktop.'

# --------------------------------------------------------------------------- 3. virtualisation

Ecrire-Titre 'Virtualisation matérielle'
if ($os.HypervisorPresent -or (Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled -eq $true) {
    Ecrire-Ok 'Activée.'
} else {
    Ecrire-Action 'Elle semble désactivée.'
    Ecrire-Info   'Docker ne pourra pas démarrer sans elle. Elle s''active dans le BIOS'
    Ecrire-Info   'ou l''UEFI, sous un nom du type « Intel VT-x », « AMD-V » ou « SVM ».'
    Ecrire-Info   'Ce n''est pas bloquant pour la suite de l''installation.'
}

# --------------------------------------------------------------------------- 4. winget

Ecrire-Titre 'winget, le gestionnaire de paquets de Windows'
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Ecrire-Ok "Présent : $((winget --version) 2>$null)"
} else {
    Ecrire-Echec 'Absent.'
    Ecrire-Info  'winget est livré avec « Programme d''installation d''application ».'
    Ecrire-Info  'Installez-le depuis le Microsoft Store, puis relancez ce script.'
    Ecrire-Info  'Store : https://apps.microsoft.com/detail/9nblggh4nns1'
    exit 1
}

# --------------------------------------------------------------------------- 5. installation

function Installer-Paquet {
    param(
        [string]$Nom,          # nom lisible
        [string]$Id,           # identifiant winget
        [string]$Commande,     # commande à tester pour savoir s'il est déjà là
        [string]$CheminTest    # ou chemin de fichier à tester
    )

    $present = $false
    if ($Commande -and (Get-Command $Commande -ErrorAction SilentlyContinue)) { $present = $true }
    if ($CheminTest -and (Test-Path $CheminTest))                            { $present = $true }

    if ($present) { Ecrire-Ok "$Nom déjà installé."; return $true }

    $script:manquants += $Nom
    if ($Verification) { Ecrire-Action "$Nom manquant."; return $false }

    Ecrire-Action "Installation de $Nom, cela peut prendre plusieurs minutes."
    winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) { Ecrire-Ok "$Nom installé."; return $true }

    Ecrire-Echec "L'installation de $Nom a échoué, code $LASTEXITCODE."
    return $false
}

Ecrire-Titre 'Git'
Installer-Paquet -Nom 'Git' -Id 'Git.Git' -Commande 'git' | Out-Null

Ecrire-Titre 'Docker Desktop'
$dockerExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
$dockerOk  = Installer-Paquet -Nom 'Docker Desktop' -Id 'Docker.DockerDesktop' `
                              -Commande 'docker' -CheminTest $dockerExe

# --------------------------------------------------------------------------- 6. WSL 2

Ecrire-Titre 'WSL 2, le sous-système Linux utilisé par Docker'
$wslPresent = $null -ne (Get-Command wsl -ErrorAction SilentlyContinue)

if (-not $wslPresent) {
    if ($Verification) {
        Ecrire-Action 'WSL manquant.'
        $manquants += 'WSL 2'
    } else {
        Ecrire-Action 'Activation de WSL, puis installation du noyau.'
        wsl --install --no-distribution
        if ($LASTEXITCODE -eq 0) {
            Ecrire-Ok 'WSL activé. Un redémarrage sera nécessaire.'
            $aRedemarrer = $true
        } else {
            Ecrire-Echec "L'activation de WSL a échoué, code $LASTEXITCODE."
            Ecrire-Info  'Activez à la main : Panneau de configuration, Programmes,'
            Ecrire-Info  'Activer ou désactiver des fonctionnalités Windows,'
            Ecrire-Info  'puis cochez « Sous-système Windows pour Linux » et'
            Ecrire-Info  '« Plateforme de machine virtuelle ».'
        }
    }
} else {
    Ecrire-Ok 'WSL présent.'
    if (-not $Verification) {
        wsl --update 2>$null | Out-Null
        Ecrire-Info 'Noyau mis à jour si nécessaire.'
    }
}

# --------------------------------------------------------------------------- 7. bilan

Ecrire-Titre 'Bilan'

if ($Verification) {
    if ($manquants.Count -eq 0) {
        Ecrire-Ok 'Tous les prérequis sont présents.'
    } else {
        Ecrire-Action "Manquants : $($manquants -join ', ')"
        Ecrire-Info   'Relancez ce script sans -Verification pour les installer.'
    }
    exit 0
}

if ($aRedemarrer) {
    Write-Host ''
    Write-Host '   REDÉMARRAGE NÉCESSAIRE' -ForegroundColor Yellow
    Write-Host '   WSL vient d''être activé : redémarrez le poste, puis :' -ForegroundColor Yellow
    Write-Host '     1. lancez Docker Desktop et attendez que la baleine soit stable ;' -ForegroundColor Yellow
    Write-Host '     2. exécutez  .\legacy\windows\mise-en-route.ps1' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

Ecrire-Ok 'Prérequis en place.'
Write-Host ''
Write-Host '   Étapes suivantes :' -ForegroundColor White
Write-Host '     1. lancez Docker Desktop et attendez que l''icône baleine cesse de bouger ;'
Write-Host '     2. exécutez  .\legacy\windows\mise-en-route.ps1'
Write-Host ''
