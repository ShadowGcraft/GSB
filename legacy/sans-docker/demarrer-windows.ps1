<#
    Démarre l'application GSB de 2013 SANS DOCKER, sous Windows.

    Tout est portable : PHP 7.4 et MariaDB sont téléchargés en archive dans
    legacy\local\, jamais installés sur le poste. Aucun droit administrateur
    n'est nécessaire, ce qui convient aux salles de cours.

    Rien n'est modifié en dehors du dossier legacy\local\. Une installation
    PHP, WAMP, XAMPP ou MariaDB déjà présente n'est pas touchée.

    Le script est idempotent : on peut le relancer sans risque.

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        .\legacy\sans-docker\demarrer-windows.ps1
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$PortWeb  = 8089,
    [int]$PortBase = 3307,
    # Repart d'une base vierge : efface les données et rejoue le jeu d'essai.
    [switch]$BaseNeuve
)

$ErrorActionPreference = 'Stop'
# Sans cette ligne, les téléchargements échouent sur les postes qui refusent
# encore TLS 1.2 par défaut.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Versions figées : ce sont celles validées avec cette application.
$VersionPhp     = '7.4.33'
$VersionMariaDb = '10.6.21'
$UrlPhp     = "https://windows.php.net/downloads/releases/archives/php-$VersionPhp-Win32-vc15-x64.zip"
$UrlMariaDb = "https://archive.mariadb.org/mariadb-$VersionMariaDb/winx64-packages/mariadb-$VersionMariaDb-winx64.zip"
$UrlComposer = 'https://getcomposer.org/composer-stable.phar'

function Titre($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan }
function Info($t)  { Write-Host "    $t" -ForegroundColor DarkGray }
function Souci($t) { Write-Host "    $t" -ForegroundColor Yellow }
function Echouer($t) { Write-Host "    $t" -ForegroundColor Red; exit 1 }

# Convertit les fins de ligne : les fichiers SQL du dépôt sont en LF, et les
# commandes envoyées à des outils Unix ne supportent pas les CRLF.
function Sans-CR([string]$s) { return ($s -replace "`r`n", "`n" -replace "`r", "`n") }

$racine = Split-Path -Parent $PSScriptRoot          # -> legacy
Push-Location $racine
try {
    $local = Join-Path $racine 'local'
    $binaires = Join-Path $local 'bin'
    New-Item -ItemType Directory -Force -Path $local, $binaires, "$local\log" | Out-Null

    # ------------------------------------------------------------------ 1

    Titre '1/6  Outils portables'

    function Obtenir-Archive($Nom, $Url, $Destination, $TestChemin) {
        if (Test-Path $TestChemin) { Info "$Nom déjà présent"; return }

        $zip = Join-Path $local "$Nom.zip"
        if (-not (Test-Path $zip)) {
            Info "téléchargement de $Nom, cela peut prendre plusieurs minutes"
            try {
                Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing
            } catch {
                Echouer "Téléchargement de $Nom impossible : $($_.Exception.Message)
           Vérifiez le réseau. En salle, le proxy se configure avec :
             `$env:HTTP_PROXY  = 'http://172.16.63.130:3128'
             `$env:HTTPS_PROXY = 'http://172.16.63.130:3128'"
            }
        }
        Info "extraction de $Nom"
        Expand-Archive -Path $zip -DestinationPath $Destination -Force
        if (-not (Test-Path $TestChemin)) { Echouer "$Nom extrait mais introuvable à $TestChemin" }
    }

    # PHP : l'archive n'a pas de dossier racine, on l'extrait dans le sien.
    $dossierPhp = Join-Path $binaires 'php'
    $php        = Join-Path $dossierPhp 'php.exe'
    Obtenir-Archive 'php' $UrlPhp $dossierPhp $php

    # MariaDB : l'archive contient un dossier mariadb-<version>-winx64.
    $dossierMdb = Join-Path $binaires 'mariadb'
    Obtenir-Archive 'mariadb' $UrlMariaDb $dossierMdb `
        (Join-Path $dossierMdb "mariadb-$VersionMariaDb-winx64\bin\mysqld.exe")
    $mdbBin = Join-Path $dossierMdb "mariadb-$VersionMariaDb-winx64\bin"

    # ------------------------------------------------------------------ 2

    Titre '2/6  Configuration de PHP'

    $php_ini = Join-Path $dossierPhp 'php.ini'
    if (-not (Test-Path $php_ini)) {
        # L'archive Windows ne fournit que des modèles, sans extension activée.
        @"
; Configuration PHP pour l'application GSB de 2013.
; Genere par sans-docker\demarrer-windows.ps1
extension_dir = "$($dossierPhp -replace '\\','\\')\\ext"
extension=pdo_mysql
extension=mysqli
extension=mbstring
extension=openssl
extension=intl
extension=curl
extension=fileinfo
extension=zip
date.timezone = Europe/Paris
memory_limit = 512M
"@ | Set-Content -Path $php_ini -Encoding ASCII
        Info 'php.ini écrit, extensions activées'
    } else {
        Info 'php.ini déjà présent'
    }

    $versionPhpReelle = (& $php -r 'echo PHP_VERSION;' 2>$null)
    if (-not $versionPhpReelle) { Echouer 'PHP ne répond pas.' }
    Info "PHP $versionPhpReelle"

    $manquantes = @()
    foreach ($ext in @('pdo_mysql', 'mbstring', 'intl', 'zip')) {
        $sortie = & $php -r "echo extension_loaded('$ext') ? 'oui' : 'non';" 2>$null
        if ($sortie -ne 'oui') { $manquantes += $ext }
    }
    if ($manquantes.Count) { Echouer "Extensions PHP absentes : $($manquantes -join ', ')" }
    Info 'extensions requises chargées'

    # ------------------------------------------------------------------ 3

    Titre '3/6  Base de données'

    $donnees = Join-Path $local 'mysql\data'
    $mycnf   = Join-Path $local 'mysql\my.ini'
    New-Item -ItemType Directory -Force -Path (Join-Path $local 'mysql') | Out-Null

    if ($BaseNeuve -and (Test-Path $donnees)) {
        Info 'suppression des données existantes'
        Remove-Item -Recurse -Force $donnees
    }

    if (-not (Test-Path $mycnf)) {
        @"
# Instance MariaDB dediee a l'application GSB de 2013, isolee du poste.
[mysqld]
port                    = $PortBase
bind-address            = 127.0.0.1
# Le code de 2013 insere une chaine vide dans une colonne entiere
# auto-incrementee : MySQL le tolerait, le mode strict le refuse.
sql_mode                =
# Le code ecrit tantot « etat », tantot « Etat ». Sous Windows la casse est
# ignoree par defaut, ce reglage la fixe explicitement.
lower_case_table_names  = 1
skip-name-resolve
"@ | Set-Content -Path $mycnf -Encoding ASCII
        Info 'configuration écrite'
    }

    if (-not (Test-Path (Join-Path $donnees 'mysql'))) {
        Info 'initialisation des données, une seule fois'
        & (Join-Path $mdbBin 'mysql_install_db.exe') `
            "--datadir=$donnees" "--password=root" 2>&1 |
            Out-File (Join-Path $local 'log\init-db.log')
        if (-not (Test-Path (Join-Path $donnees 'mysql'))) {
            Echouer "L'initialisation a échoué. Voir local\log\init-db.log"
        }
    }

    # Le serveur tourne-t-il déjà ?
    $enMarche = $false
    try {
        $test = Test-NetConnection -ComputerName 127.0.0.1 -Port $PortBase `
                    -InformationLevel Quiet -WarningAction SilentlyContinue
        $enMarche = $test
    } catch { $enMarche = $false }

    if (-not $enMarche) {
        Info "démarrage sur le port $PortBase"
        Start-Process -FilePath (Join-Path $mdbBin 'mysqld.exe') `
            -ArgumentList "--defaults-file=`"$mycnf`"", "--datadir=`"$donnees`"" `
            -WindowStyle Hidden

        $pret = $false
        foreach ($i in 1..30) {
            Start-Sleep -Seconds 2
            try {
                if (Test-NetConnection -ComputerName 127.0.0.1 -Port $PortBase `
                        -InformationLevel Quiet -WarningAction SilentlyContinue) { $pret = $true; break }
            } catch { }
        }
        if (-not $pret) { Echouer "La base n'a pas démarré. Voir local\log" }
    }
    Info 'base de données en marche'

    # ------------------------------------------------------------------ 4

    Titre '4/6  Schéma et jeu d''essai'

    $mysql = Join-Path $mdbBin 'mysql.exe'
    $compte = & $mysql "-h127.0.0.1" "-P$PortBase" "-uroot" "-proot" "-sN" `
        "-e" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='bd_gsb';" 2>$null

    if ([string]::IsNullOrWhiteSpace($compte) -or [int]$compte -lt 6) {
        & $mysql "-h127.0.0.1" "-P$PortBase" "-uroot" "-proot" `
            "-e" "CREATE DATABASE IF NOT EXISTS bd_gsb CHARACTER SET utf8;" 2>$null

        foreach ($f in @('sql\01-schema.sql', 'sql\02-donnees.sql')) {
            # Le contenu est passé sur l'entrée standard, débarrassé des CRLF.
            $sql = Sans-CR (Get-Content $f -Raw)
            $sql | & $mysql "-h127.0.0.1" "-P$PortBase" "-uroot" "-proot" "bd_gsb"
            if ($LASTEXITCODE -ne 0) { Echouer "Le chargement de $f a échoué." }
            Info "$f chargé"
        }
    } else {
        Info "base déjà peuplée, $compte tables"
    }

    # ------------------------------------------------------------------ 5

    Titre '5/6  Application Symfony'

    $composer = Join-Path $local 'composer.phar'
    if (-not (Test-Path $composer)) {
        Info 'téléchargement de Composer'
        Invoke-WebRequest -Uri $UrlComposer -OutFile $composer -UseBasicParsing
    }

    if (-not (Test-Path 'app\vendor')) {
        Info 'installation des dépendances, comptez plusieurs minutes'
        Push-Location 'app'
        try {
            if (-not (Test-Path 'composer.json')) {
                & $php $composer create-project symfony/framework-standard-edition `
                    "$env:TEMP\gsb-sf" "2.8.*" --no-interaction --prefer-dist --no-scripts
                Copy-Item "$env:TEMP\gsb-sf\*" -Destination . -Recurse -Force
                Remove-Item "$env:TEMP\gsb-sf" -Recurse -Force
            }
            & $php $composer install --no-interaction --no-scripts
        } finally { Pop-Location }
    } else {
        Info 'dépendances déjà installées'
    }

    @"
# Genere par sans-docker\demarrer-windows.ps1 : instance MariaDB locale.
parameters:
    database_host:     127.0.0.1
    database_port:     $PortBase
    database_name:     bd_gsb
    database_user:     root
    database_password: root
    mailer_transport:  smtp
    mailer_host:       127.0.0.1
    mailer_user:       ~
    mailer_password:   ~
    secret:            GsbDeuxMilleTreizeSansDocker
"@ -replace "`r`n", "`n" | Set-Content -Path 'app\app\config\parameters.yml' -Encoding UTF8 -NoNewline

    # La connexion pointe vers l'instance locale, pas vers le service Docker.
    $services = 'app\src\Pg\GsbFraisBundle\Resources\config\services.yml'
    $contenu  = Get-Content $services -Raw
    $contenu  = $contenu -replace 'db\.host: mysql:host=[^\r\n]*', "db.host: mysql:host=127.0.0.1;port=$PortBase"
    Set-Content -Path $services -Value ($contenu -replace "`r`n", "`n") -Encoding UTF8 -NoNewline
    Info "connexion dirigée vers 127.0.0.1:$PortBase"

    Push-Location 'app'
    try {
        # L'avertissement « continue targeting switch » vient de Symfony et de
        # Doctrine sur PHP 7.4. Sans conséquence, mais très bavard : on le filtre.
        & $php $composer dump-autoload --quiet 2>&1 |
            Where-Object { $_ -notmatch 'continue.*targeting switch' } | Out-Null
        & $php 'vendor\sensio\distribution-bundle\Sensio\Bundle\DistributionBundle\Resources\bin\build_bootstrap.php' app 2>&1 |
            Where-Object { $_ -notmatch 'continue.*targeting switch' } | Out-Null
        & $php 'app\console' assets:install web --env=prod --no-debug --quiet 2>&1 |
            Where-Object { $_ -notmatch 'continue.*targeting switch' } | Out-Null
        if (Test-Path 'app\cache') { Remove-Item 'app\cache\*' -Recurse -Force -ErrorAction SilentlyContinue }
    } finally { Pop-Location }

    # Sous Windows, assets:install copie les fichiers faute de liens
    # symboliques. Les gabarits de 2013 attendent « gsbfrais », alors que le
    # bundle publie sous « pggsbfrais » : on duplique sous le nom attendu.
    $source = 'app\src\Pg\GsbFraisBundle\Resources\public'
    $cible  = 'app\web\bundles\gsbfrais'
    if (Test-Path $source) {
        New-Item -ItemType Directory -Force -Path $cible | Out-Null
        Copy-Item "$source\*" -Destination $cible -Recurse -Force
    }
    Info 'ressources publiées'

    # ------------------------------------------------------------------ 6

    Titre '6/6  Serveur web'

    $occupe = Get-NetTCPConnection -LocalPort $PortWeb -State Listen -ErrorAction SilentlyContinue
    if ($occupe) {
        $proc = (Get-Process -Id $occupe[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Souci "Le port $PortWeb est occupé par « $proc »."
        Souci "Relancez avec un autre port :  .\sans-docker\demarrer-windows.ps1 -PortWeb 8091"
        exit 1
    }

    $routeur = Join-Path $PSScriptRoot 'routeur.php'
    Start-Process -FilePath $php `
        -ArgumentList "-c", "`"$php_ini`"", "-S", "127.0.0.1:$PortWeb", "-t", "`"$racine\app\web`"", "`"$routeur`"" `
        -WindowStyle Hidden `
        -RedirectStandardError (Join-Path $local 'log\php-server.log')

    $code = 0
    foreach ($i in 1..15) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$PortWeb/accueil" -UseBasicParsing -TimeoutSec 10
            $code = $r.StatusCode
            if ($code -eq 200) { break }
        } catch { $code = 0 }
    }

    Write-Host ''
    if ($code -eq 200) {
        Write-Host "    L'application répond : http://127.0.0.1:$PortWeb" -ForegroundColor Green
        Write-Host ''
        Write-Host '    Comptes de démonstration'
        Write-Host '      dandre  / oppg5    David André, quatre fiches, tous les états'
        Write-Host '      cbedos  / gvide    Christian Bedos, trois fiches'
        Write-Host '      pbentot / doypa    Pascal Bentot, une seule fiche'
        Write-Host ''
        Write-Host '    Pour arrêter :  .\sans-docker\arreter-windows.ps1'
        Write-Host ''
    } else {
        Echouer "La page d'accueil ne répond pas, code $code. Voir local\log\php-server.log"
    }

} finally {
    Pop-Location
}
