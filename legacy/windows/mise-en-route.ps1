<#
    Démarre l'application GSB de 2013 sous Windows.

    Équivalent PowerShell de legacy/mise-en-route.sh, utilisé sous macOS et Linux.
    Le script est idempotent : on peut le relancer sans rien casser.

    Prérequis : Docker Desktop installé ET DÉMARRÉ.
    Voir installer-prerequis.ps1 si ce n'est pas le cas.

    Utilisation, dans une fenêtre PowerShell ordinaire, pas besoin d'être administrateur :

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        .\legacy\windows\mise-en-route.ps1
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    # Repart d'une base vierge : supprime le volume et rejoue le jeu d'essai.
    [switch]$BaseNeuve,
    # Port à publier sur le poste.
    [int]$Port = 8088
)

$ErrorActionPreference = 'Stop'

function Etape($n, $texte) { Write-Host "==> $n  $texte" -ForegroundColor Cyan }
function Info($texte)      { Write-Host "    $texte" -ForegroundColor DarkGray }
function Souci($texte)     { Write-Host "    $texte" -ForegroundColor Yellow }
function Echec($texte)     { Write-Host "    $texte" -ForegroundColor Red }

<#
    Exécute un script shell dans le conteneur web.

    Ce fichier .ps1 est enregistré avec des fins de ligne Windows. Transmises
    telles quelles à un shell Linux, elles produisent l'erreur
    « $'\r': command not found » et rien ne s'exécute. On les convertit donc
    avant de passer la commande au conteneur.
#>
function Invoke-DansConteneur([string]$Script) {
    $unix = $Script -replace "`r`n", "`n" -replace "`r", "`n"
    docker compose exec -T web sh -c $unix
}

# Le script vit dans legacy\windows\ ; le fichier de composition est un cran au-dessus.
$racine = Split-Path -Parent $PSScriptRoot
Push-Location $racine
try {

    # ----------------------------------------------------------------- 1. Docker

    Etape '1/7' 'Vérification de Docker'
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Echec 'La commande docker est introuvable.'
        Info  'Exécutez d''abord : .\windows\installer-prerequis.ps1'
        exit 1
    }

    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Souci 'Docker est installé mais son moteur ne répond pas.'
        Info  'Tentative de démarrage de Docker Desktop...'
        $exe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $exe) { Start-Process $exe | Out-Null }

        $pret = $false
        foreach ($i in 1..60) {
            Start-Sleep -Seconds 5
            docker info 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $pret = $true; break }
            if ($i % 6 -eq 0) { Info "toujours en attente... ($($i * 5) s)" }
        }
        if (-not $pret) {
            Echec 'Docker n''a pas démarré au bout de cinq minutes.'
            Info  'Ouvrez Docker Desktop à la main, attendez que la baleine se stabilise,'
            Info  'puis relancez ce script.'
            exit 1
        }
    }
    Info 'moteur Docker opérationnel'

    # ----------------------------------------------------------------- 2. port

    Etape '2/7' "Vérification du port $Port"
    $occupe = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($occupe) {
        $proc = (Get-Process -Id $occupe[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Souci "Le port $Port est déjà utilisé par « $proc »."
        Info  "Fermez ce programme, ou relancez avec un autre port :"
        Info  "  .\windows\mise-en-route.ps1 -Port 8090"
        Info  "Dans ce cas, modifiez aussi la ligne ports de docker-compose.yml."
        exit 1
    }
    Info "port $Port disponible"

    # ----------------------------------------------------------------- 3. base neuve

    if ($BaseNeuve) {
        Etape '3/7' 'Suppression du volume de données'
        docker compose down -v
        Info 'le jeu d''essai sera rechargé au démarrage'
    } else {
        Etape '3/7' 'Conservation des données existantes'
        Info 'utilisez -BaseNeuve pour repartir d''une base vierge'
    }

    # ----------------------------------------------------------------- 4. démarrage

    Etape '4/7' 'Construction de l''image et démarrage des services'
    docker compose build
    if ($LASTEXITCODE -ne 0) { Echec 'La construction de l''image a échoué.'; exit 1 }
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { Echec 'Le démarrage des conteneurs a échoué.'; exit 1 }

    Etape '5/7' 'Attente de la base de données'
    $baseOk = $false
    foreach ($i in 1..30) {
        docker compose exec -T db mariadb -uroot -proot -e "SELECT 1" bd_gsb 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $baseOk = $true; break }
        Start-Sleep -Seconds 3
    }
    if (-not $baseOk) {
        Echec 'La base n''a pas répondu.'
        Info  'Journaux : docker compose logs db'
        exit 1
    }
    Info 'base prête'

    # ----------------------------------------------------------------- 6. Symfony

    Etape '6/7' 'Dépendances et fichiers générés'

    if (-not (Test-Path 'app\vendor')) {
        Info 'installation de Symfony 2.8, comptez plusieurs minutes'
        # Le squelette Symfony n'est pas versionné en entier : on le réinstalle
        # à côté, puis on ne reprend que ce qui manque.
        Invoke-DansConteneur @'
cd /var/www/html
if [ ! -f composer.json ]; then
    composer create-project symfony/framework-standard-edition /tmp/sf "2.8.*" \
        --no-interaction --prefer-dist --no-scripts
    cp -an /tmp/sf/. /var/www/html/
fi
composer install --no-interaction --no-scripts
'@
        if ($LASTEXITCODE -ne 0) { Echec 'L''installation des dépendances a échoué.'; exit 1 }
    } else {
        Info 'dépendances déjà installées'
    }

    # Le mode sans Docker fait pointer la connexion vers 127.0.0.1 : on la remet
    # sur le service « db » du compose, pour que les deux modes cohabitent.
    $services = 'app\src\Pg\GsbFraisBundle\Resources\config\services.yml'
    $contenu  = (Get-Content $services -Raw) -replace 'db\.host: mysql:host=[^\r\n]*', 'db.host: mysql:host=db'
    Set-Content -Path $services -Value ($contenu -replace "`r`n", "`n") -Encoding UTF8 -NoNewline

    Invoke-DansConteneur @'
cd /var/www/html
[ -f app/config/parameters.yml ] || cp app/config/parameters.yml.dist app/config/parameters.yml
composer dump-autoload --quiet
php vendor/sensio/distribution-bundle/Sensio/Bundle/DistributionBundle/Resources/bin/build_bootstrap.php app
php app/console assets:install web --symlink --env=prod --no-debug --quiet
[ -e web/bundles/gsbfrais ] || ln -s ../../src/Pg/GsbFraisBundle/Resources/public web/bundles/gsbfrais
rm -rf app/cache/*
chmod -R 777 app/cache app/logs 2>/dev/null || true
'@
    Info 'paramètres, amorçage et ressources en place'

    # ----------------------------------------------------------------- 7. vérification

    Etape '7/7' 'Vérification'
    $adresse = "http://localhost:$Port"
    $code = 0
    foreach ($i in 1..10) {
        try {
            $r = Invoke-WebRequest -Uri "$adresse/accueil" -UseBasicParsing -TimeoutSec 10
            $code = $r.StatusCode
            if ($code -eq 200) { break }
        } catch {
            $code = 0
        }
        Start-Sleep -Seconds 3
    }

    Write-Host ''
    if ($code -eq 200) {
        Write-Host "    L'application répond : $adresse" -ForegroundColor Green
        Write-Host ''
        Write-Host '    Comptes de démonstration' -ForegroundColor White
        Write-Host '      dandre  / oppg5    David André, quatre fiches, tous les états'
        Write-Host '      cbedos  / gvide    Christian Bedos, trois fiches'
        Write-Host '      pbentot / doypa    Pascal Bentot, une seule fiche'
        Write-Host ''
        Write-Host "    Mode développement : $adresse/app_dev.php/accueil"
        Write-Host '    Pour arrêter : docker compose down'
        Write-Host ''
    } else {
        Echec "La page d'accueil ne répond pas, code $code."
        Info  'Journaux du serveur : docker compose logs web'
        Info  'Journaux de la base  : docker compose logs db'
        exit 1
    }

} finally {
    Pop-Location
}
