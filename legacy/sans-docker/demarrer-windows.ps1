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
    [switch]$BaseNeuve,
    # Affiche le détail de chaque étape, utile pour diagnostiquer un blocage.
    [switch]$Verbeux
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
# PHP 7.4 pour Windows ne fournit PAS l'extension zip : verifie, l'archive
# officielle ne contient aucun php_zip.dll. Composer ne peut alors extraire
# aucune dependance, sauf s'il trouve 7z ou unzip dans le PATH. On embarque
# donc 7-Zip autonome, 385 Ko, sous licence LGPL.
$Url7zip = 'https://www.7-zip.org/a/7za920.zip'

# Journal complet du deroulement, pour pouvoir diagnostiquer apres coup.
$script:Journal = $null

function Tracer($t) {
    if ($script:Journal) {
        $horodatage = (Get-Date).ToString('HH:mm:ss')
        Add-Content -Path $script:Journal -Value "$horodatage  $t" -Encoding UTF8
    }
}
function Titre($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan;   Tracer "== $t" }
function Info($t)  { Write-Host "    $t" -ForegroundColor DarkGray;              Tracer "   $t" }
function Detail($t) {
    Tracer "   . $t"
    if ($Verbeux) { Write-Host "      $t" -ForegroundColor DarkGray }
}
function Souci($t) { Write-Host "    $t" -ForegroundColor Yellow;                Tracer "!  $t" }

function Echouer($t) {
    Write-Host "    $t" -ForegroundColor Red
    Tracer "ECHEC $t"
    if ($script:Journal) {
        Write-Host ''
        Write-Host "    Journal complet : $script:Journal" -ForegroundColor Yellow
    }
    exit 1
}

# Affiche les dernieres lignes utiles d'un fichier de journal.
function Montrer-Journal($chemin, $titre, $lignes = 25) {
    if (-not (Test-Path $chemin)) { Write-Host "    ($titre : fichier absent)" -ForegroundColor DarkGray; return }
    $contenu = Get-Content $chemin -Tail $lignes -ErrorAction SilentlyContinue
    if (-not $contenu) { Write-Host "    ($titre : vide)" -ForegroundColor DarkGray; return }
    Write-Host ''
    Write-Host "    --- $titre ---" -ForegroundColor Yellow
    $contenu | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray; Tracer "     | $_" }
    Write-Host "    --- fin ---" -ForegroundColor Yellow
}

# Convertit les fins de ligne : les fichiers SQL du dépôt sont en LF, et les
# commandes envoyées à des outils Unix ne supportent pas les CRLF.
function Sans-CR([string]$s) { return ($s -replace "`r`n", "`n" -replace "`r", "`n") }

$racine = Split-Path -Parent $PSScriptRoot          # -> legacy
Push-Location $racine
try {
    $local = Join-Path $racine 'local'
    $binaires = Join-Path $local 'bin'
    New-Item -ItemType Directory -Force -Path $local, $binaires, "$local\log" | Out-Null

    $script:Journal = Join-Path $local 'log\demarrage.log'
    "=== Demarrage GSB sans Docker, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" |
        Set-Content -Path $script:Journal -Encoding UTF8
    Tracer "PowerShell $($PSVersionTable.PSVersion)  |  port web $PortWeb  |  port base $PortBase"
    Write-Host "    journal : $script:Journal" -ForegroundColor DarkGray

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
    $mdbBin    = Join-Path $dossierMdb "mariadb-$VersionMariaDb-winx64\bin"
    # Le client cherche ses greffons d'authentification a cote de lui. Lance
    # depuis un autre dossier, il ne les trouve pas et echoue sur un message
    # trompeur du type « Plugin caching_sha2_password could not be loaded ».
    $mdbPlugins = Join-Path $dossierMdb "mariadb-$VersionMariaDb-winx64\lib\plugin"

    # ------------------------------------------------------------------ 2

    Titre '2/6  Configuration de PHP'

    $php_ini = Join-Path $dossierPhp 'php.ini'
    $dossierExt = Join-Path $dossierPhp 'ext'

    # L'archive Windows ne fournit qu'un modele, sans extension activee. On
    # n'active que les extensions reellement presentes dans ext\ : la liste
    # varie d'une version de PHP a l'autre, et activer une DLL absente fait
    # echouer PHP au demarrage.
    $souhaitees = @('pdo_mysql','mysqli','mbstring','openssl','intl','curl','fileinfo','sodium','opcache')
    $activees = @()
    foreach ($ext in $souhaitees) {
        if (Test-Path (Join-Path $dossierExt "php_$ext.dll")) { $activees += $ext }
    }

    $lignes = @(
        "; Configuration PHP pour l'application GSB de 2013.",
        "; Genere par sans-docker\demarrer-windows.ps1",
        "extension_dir = `"$dossierExt`""
    )
    $lignes += ($activees | ForEach-Object { "extension=$_" })
    $lignes += @('date.timezone = Europe/Paris', 'memory_limit = 512M')
    $lignes -join "`r`n" | Set-Content -Path $php_ini -Encoding ASCII
    Info "php.ini ecrit, $($activees.Count) extensions activees : $($activees -join ', ')" 

    # Un avertissement ecrit par php.exe sur la sortie d'erreur devient une
    # exception fatale quand ErrorActionPreference vaut Stop. On l'abaisse
    # localement, et on ne juge que sur la valeur renvoyee.
    function Invoke-Php {
        param([string[]]$Arguments)
        $ancien = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $sortie = & $php @Arguments 2>&1
            return (($sortie | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join '').Trim()
        } finally {
            $ErrorActionPreference = $ancien
        }
    }

    $versionPhpReelle = Invoke-Php @('-n', '-r', 'echo PHP_VERSION;')
    if (-not $versionPhpReelle) { Echouer 'PHP ne repond pas.' }
    Info "PHP $versionPhpReelle"

    # zip ne figure pas dans cette liste : PHP 7.4 pour Windows ne la fournit
    # pas, et c'est 7-Zip qui prend le relais pour Composer.
    $manquantes = @()
    foreach ($ext in @('pdo_mysql', 'mbstring')) {
        if ((Invoke-Php @('-r', "echo extension_loaded('$ext') ? 'oui' : 'non';")) -ne 'oui') {
            $manquantes += $ext
        }
    }
    if ($manquantes.Count) { Echouer "Extensions PHP indispensables absentes : $($manquantes -join ', ')" }
    Info 'extensions indispensables chargees'

    # 7-Zip autonome : Composer s'en sert pour extraire les dependances.
    $dossier7z = Join-Path $binaires '7zip'
    $exe7z     = Join-Path $dossier7z '7za.exe'
    if (-not (Test-Path $exe7z)) {
        $zip7 = Join-Path $local '7zip.zip'
        if (-not (Test-Path $zip7)) {
            Info 'telechargement de 7-Zip autonome, 385 Ko'
            Invoke-WebRequest -Uri $Url7zip -OutFile $zip7 -UseBasicParsing
        }
        Expand-Archive -Path $zip7 -DestinationPath $dossier7z -Force
    }
    if (-not (Test-Path $exe7z)) { Echouer '7-Zip introuvable apres extraction.' }
    # Composer cherche « 7z » ou « 7za » dans le PATH du processus.
    $env:PATH = "$dossier7z;$env:PATH"
    Info '7-Zip disponible pour Composer'

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

    $journalErreur = Join-Path $local 'log\mariadb-sortie.log'
    $journalInit   = Join-Path $local 'log\init-db.log'

    if (-not (Test-Path (Join-Path $donnees 'mysql'))) {
        Info "initialisation des donnees, une seule fois (peut prendre une minute)"
        Detail "mysql_install_db.exe --datadir=$donnees"

        $ancien = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & (Join-Path $mdbBin 'mysql_install_db.exe') "--datadir=$donnees" "--password=root" 2>&1 |
                Out-File -FilePath $journalInit -Encoding UTF8
        } finally { $ErrorActionPreference = $ancien }

        if (-not (Test-Path (Join-Path $donnees 'mysql'))) {
            Montrer-Journal $journalInit "initialisation de la base"
            Echouer "L'initialisation de la base a echoue."
        }
        Info 'donnees initialisees'
    } else {
        Detail 'donnees deja initialisees'
    }

    <#
        Appelle le client MariaDB en lui donnant tout ce dont il a besoin : le
        dossier de ses greffons, une methode d'authentification simple, et
        surtout un DELAI D'ATTENTE. Sans lui, le client peut rester bloque
        indefiniment quand le serveur ne repond pas, et le script parait fige.
    #>
    function Invoke-Mysql {
        param(
            [string]$Requete,
            [string]$MotDePasse = 'root',
            [string]$Base = '',
            [switch]$Silencieux
        )
        $parametres = @(
            "--host=127.0.0.1", "--port=$PortBase", "--user=root",
            "--plugin-dir=$mdbPlugins", "--default-auth=mysql_native_password",
            "--protocol=tcp", "--skip-ssl", "--connect-timeout=5", "-N", "-B"
        )
        if ($MotDePasse) { $parametres += "--password=$MotDePasse" }
        if ($Base)       { $parametres += $Base }
        $parametres += @("-e", $Requete)

        $ancien = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $sortie = & (Join-Path $mdbBin 'mysql.exe') @parametres 2>&1
            $script:MysqlCode = $LASTEXITCODE
            $texte   = ($sortie | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
            $erreurs = ($sortie | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] }) -join ' '
            $extrait = $Requete -replace "\s+", ' '
            if ($extrait.Length -gt 60) { $extrait = $extrait.Substring(0, 60) + '...' }
            Tracer "   mysql[$($script:MysqlCode)] $extrait"
            if ($erreurs) { Tracer "   mysql erreur : $erreurs" }
            if (-not $Silencieux -and $script:MysqlCode -ne 0 -and $erreurs) { Info "  (client : $erreurs)" }
            return $texte.Trim()
        } finally { $ErrorActionPreference = $ancien }
    }

    # Le serveur repond-il deja, et est-ce bien le notre ?
    Detail 'test de connexion au serveur'
    $version  = Invoke-Mysql -Requete "SELECT VERSION();" -Silencieux
    $enMarche = ($script:MysqlCode -eq 0 -and $version)

    if (-not $enMarche) {
        $version  = Invoke-Mysql -Requete "SELECT VERSION();" -MotDePasse '' -Silencieux
        $enMarche = ($script:MysqlCode -eq 0 -and $version)
    }

    if (-not $enMarche) {
        # Le port est-il tenu par un programme etranger au projet ?
        $occupe = Get-NetTCPConnection -LocalPort $PortBase -State Listen -ErrorAction SilentlyContinue
        if ($occupe) {
            $proc = Get-Process -Id $occupe[0].OwningProcess -ErrorAction SilentlyContinue
            $chemin = $null
            try { $chemin = $proc.Path } catch { }
            Detail "port $PortBase deja ecoute par $($proc.ProcessName) ($chemin)"
            if ($chemin -and -not $chemin.StartsWith($binaires, 'OrdinalIgnoreCase')) {
                Echouer "Le port $PortBase est occupe par « $($proc.ProcessName) », etranger au projet :
           $chemin
           Relancez sur un autre port :
             .\sans-docker\demarrer-windows.ps1 -PortBase 3309"
            }
        }

        Info "demarrage du serveur sur le port $PortBase"
        Detail "mysqld.exe --defaults-file=$mycnf --datadir=$donnees"

        # --console fait ecrire les erreurs sur la sortie standard, que l'on
        # capture : sans cela, un demarrage rate ne laisse aucune trace visible.
        $processus = Start-Process -FilePath (Join-Path $mdbBin 'mysqld.exe') `
            -ArgumentList "--defaults-file=`"$mycnf`"", "--datadir=`"$donnees`"", "--console" `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $journalErreur `
            -RedirectStandardError  "$journalErreur.err"

        Detail "processus mysqld demarre, identifiant $($processus.Id)"

        $enMarche = $false
        foreach ($i in 1..20) {
            Start-Sleep -Seconds 2

            # Le processus a-t-il rendu l'ame ? Inutile d'attendre la fin du delai.
            if ($processus.HasExited) {
                Souci "mysqld s'est arrete tout seul, code $($processus.ExitCode)."
                Montrer-Journal "$journalErreur.err" 'sortie d''erreur de mysqld'
                Montrer-Journal $journalErreur        'sortie de mysqld'
                $err = Get-ChildItem $donnees -Filter '*.err' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($err) { Montrer-Journal $err.FullName "journal MariaDB ($($err.Name))" }
                Echouer "Le serveur de base de donnees n'a pas pu demarrer."
            }

            $version = Invoke-Mysql -Requete "SELECT VERSION();" -Silencieux
            if ($script:MysqlCode -eq 0 -and $version) { $enMarche = $true; break }
            $version = Invoke-Mysql -Requete "SELECT VERSION();" -MotDePasse '' -Silencieux
            if ($script:MysqlCode -eq 0 -and $version) { $enMarche = $true; break }

            if ($i % 3 -eq 0) { Info "  toujours en attente... $($i * 2) s" }
        }

        if (-not $enMarche) {
            Souci "Le serveur n'a pas repondu au bout de 40 secondes."
            Montrer-Journal "$journalErreur.err" 'sortie d''erreur de mysqld'
            Montrer-Journal $journalErreur        'sortie de mysqld'
            $err = Get-ChildItem $donnees -Filter '*.err' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($err) { Montrer-Journal $err.FullName "journal MariaDB ($($err.Name))" }
            Echouer "La base n'a pas repondu."
        }
    }
    Info "base en marche : MariaDB $version"

    # Les comptes root doivent exister pour localhost ET 127.0.0.1, avec une
    # authentification par mot de passe classique. Sans cela, la connexion TCP
    # de PHP est refusee, ou reclame un greffon absent.
    $sansMdp = Invoke-Mysql -Requete "SELECT 1;" -MotDePasse '' -Silencieux
    $motDePasseCourant = if ($script:MysqlCode -eq 0 -and $sansMdp) { '' } else { 'root' }

    $sql = @"
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY 'root';
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY 'root';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('root');
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('root');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"@
    Invoke-Mysql -Requete (Sans-CR $sql) -MotDePasse $motDePasseCourant -Silencieux | Out-Null
    Info 'comptes root verifies'

    # ------------------------------------------------------------------ 4

    Titre "4/6  Schema et jeu d'essai"

    $compte = Invoke-Mysql -Requete "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='bd_gsb';"
    if ($script:MysqlCode -ne 0) { Echouer "Connexion a la base impossible apres configuration des comptes." }

    if ([string]::IsNullOrWhiteSpace($compte) -or [int]$compte -lt 6) {
        Invoke-Mysql -Requete "CREATE DATABASE IF NOT EXISTS bd_gsb CHARACTER SET utf8;" | Out-Null

        foreach ($f in @('sql\01-schema.sql', 'sql\02-donnees.sql')) {
            $sqlFichier = Sans-CR (Get-Content $f -Raw)
            Invoke-Mysql -Requete $sqlFichier -Base 'bd_gsb' | Out-Null
            if ($script:MysqlCode -ne 0) { Echouer "Le chargement de $f a echoue." }
            Info "$f charge"
        }
    } else {
        Info "base deja peuplee, $compte tables"
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
                & $php -c $php_ini $composer create-project symfony/framework-standard-edition `
                    "$env:TEMP\gsb-sf" "2.8.*" --no-interaction --prefer-dist --no-scripts
                Copy-Item "$env:TEMP\gsb-sf\*" -Destination . -Recurse -Force
                Remove-Item "$env:TEMP\gsb-sf" -Recurse -Force
            }
            & $php -c $php_ini $composer install --no-interaction --no-scripts
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
        & $php -c $php_ini $composer dump-autoload --quiet 2>&1 |
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
