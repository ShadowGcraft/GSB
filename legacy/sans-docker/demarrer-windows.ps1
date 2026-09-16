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
    # opcache est volontairement absente : c'est une extension Zend, qui se
    # declare avec « zend_extension » et non « extension ». Elle n'apporte rien
    # a un serveur de demonstration, et sa mauvaise declaration provoquait un
    # avertissement a chaque appel de PHP.
    $souhaitees = @('pdo_mysql','mysqli','mbstring','openssl','intl','curl','fileinfo','sodium')
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
            $script:PhpCode = $LASTEXITCODE
            $texte   = ($sortie | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
            $erreurs = ($sortie | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] }) -join ' '
            Tracer "   php[$($script:PhpCode)] $($Arguments -join ' ')"
            if ($texte)   { Tracer "     sortie : $($texte -replace "`n", ' | ')" }
            if ($erreurs) { Tracer "     erreur : $erreurs" }
            return $texte.Trim()
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

    # Aucun serveur du projet detecte tant que la recherche n a pas eu lieu.
    $reutilisable = $false

    $donnees = Join-Path $local 'mysql\data'
    $mycnf   = Join-Path $local 'mysql\my.ini'
    New-Item -ItemType Directory -Force -Path (Join-Path $local 'mysql') | Out-Null

    if ($BaseNeuve -and (Test-Path $donnees)) {
        Info 'suppression des données existantes'
        Remove-Item -Recurse -Force $donnees
    }

    <#
        Le port est-il reellement utilisable ?

        Windows reserve des plages entieres de ports au profit d'Hyper-V et de
        WSL, souvent autour de 3300. Un port de ces plages n'est pas « occupe »
        au sens habituel : rien ne l'ecoute, mais toute tentative d'ecoute est
        refusee avec l'erreur 10013. Le seul test fiable est d'essayer.
    #>
    function Test-PortUtilisable([int]$Port) {
        $ecouteur = $null
        try {
            $ecouteur = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
            $ecouteur.Start()
            return $true
        } catch {
            Tracer "   port $Port refuse : $($_.Exception.Message)"
            return $false
        } finally {
            if ($ecouteur) { try { $ecouteur.Stop() } catch { } }
        }
    }

    # Cherche un port utilisable, en commencant par celui demande.
    function Trouver-Port([int]$Souhaite, [int[]]$Secours) {
        if (Test-PortUtilisable $Souhaite) { return $Souhaite }

        Souci "Le port $Souhaite est inutilisable sur ce poste."
        foreach ($p in $Secours) {
            if ($p -ne $Souhaite -and (Test-PortUtilisable $p)) {
                Info "port de remplacement retenu : $p"
                return $p
            }
        }
        return 0
    }

    <#
        Une instance du projet tourne-t-elle deja ?

        Les fichiers de donnees d'InnoDB n'admettent qu'un seul serveur a la
        fois. En demarrer un second, meme sur un autre port, echoue avec
        « The data file './ibdata1' must be writable », message qui ne dit rien
        du vrai probleme.

        Le port reel est lu sur le PROCESSUS, jamais dans le fichier de
        configuration : celui-ci a pu etre reecrit depuis, et indiquer un port
        que le serveur vivant n'ecoute pas.
    #>
    function Get-ServeurDuProjet {
        $processus = @(Get-Process -Name 'mysqld' -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($binaires, 'OrdinalIgnoreCase') } catch { $false }
        })
        if (-not $processus) { return $null }

        $p = $processus[0]
        $port = 0
        $ecoute = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                  Where-Object { $_.OwningProcess -eq $p.Id } | Select-Object -First 1
        if ($ecoute) { $port = $ecoute.LocalPort }

        return [pscustomobject]@{ Processus = $p; Port = $port }
    }

    $serveur = Get-ServeurDuProjet

    if ($serveur) {
        Tracer "instance du projet : pid $($serveur.Processus.Id), port $($serveur.Port)"

        $reutilisable = $false
        if ($serveur.Port -gt 0) {
            $PortBase = $serveur.Port
            $v = Invoke-Mysql -Requete "SELECT VERSION();" -Silencieux
            if ($script:MysqlCode -ne 0) { $v = Invoke-Mysql -Requete "SELECT VERSION();" -MotDePasse '' -Silencieux }
            $reutilisable = ($script:MysqlCode -eq 0 -and $v)
        }

        if ($reutilisable) {
            Info "un serveur du projet ecoute deja le port $PortBase, il est reutilise"
        } else {
            # Notre propre serveur, mais injoignable : port inconnu, ou demarre
            # avec une configuration qui ne correspond plus. On l'arrete pour
            # repartir proprement. Seuls les processus de ce dossier sont vises.
            Souci "Un serveur du projet tourne (pid $($serveur.Processus.Id)) mais ne repond pas."
            Info  'arret de cette instance pour repartir proprement'

            # Arret PROPRE d'abord. Tuer le processus laisse les journaux du
            # moteur Aria dans un etat incoherent, et le serveur refuse ensuite
            # de redemarrer avec « Aria recovery failed ».
            $arrete = $false
            $admin = Join-Path $mdbBin 'mysqladmin.exe'
            if (Test-Path $admin) {
                foreach ($mdp in @('root', '')) {
                    $parametres = @("--host=127.0.0.1", "--protocol=tcp", "--user=root",
                                    "--connect-timeout=5", "--plugin-dir=$mdbPlugins")
                    if ($serveur.Port -gt 0) { $parametres += "--port=$($serveur.Port)" }
                    if ($mdp) { $parametres += "--password=$mdp" }
                    $parametres += 'shutdown'
                    $ancienEA = $ErrorActionPreference
                    $ErrorActionPreference = 'Continue'
                    try { & $admin @parametres 2>&1 | Out-Null } finally { $ErrorActionPreference = $ancienEA }
                    Start-Sleep -Seconds 3
                    if ($serveur.Processus.HasExited) { $arrete = $true; Detail 'arret propre reussi'; break }
                }
            }

            if (-not $arrete) {
                Souci "L'arret propre a echoue, le processus va etre force."
                Souci "Les journaux du moteur Aria peuvent en souffrir ; le script les repare si besoin."
                try {
                    Stop-Process -Id $serveur.Processus.Id -Force -ErrorAction Stop
                    Start-Sleep -Seconds 3
                } catch {
                    Echouer "Impossible d'arreter le serveur (pid $($serveur.Processus.Id)) : $($_.Exception.Message)
           Arretez-le a la main, puis relancez :
             .\sans-docker\arreter-windows.ps1"
                }
            }
            $serveur = Get-ServeurDuProjet
            if ($serveur) {
                Echouer "Le serveur du projet est toujours en memoire (pid $($serveur.Processus.Id)).
           Arretez-le depuis le Gestionnaire des taches, puis relancez."
            }
            Info 'instance precedente arretee'
        }
    }

    $portDemande = $PortBase
    if (-not $reutilisable) {
        $PortBase = Trouver-Port $PortBase @(3307, 3309, 3310, 3316, 13306, 23306, 33306)
    }
    if ($PortBase -eq 0) {
        Write-Host ''
        Souci "Aucun port de base de donnees disponible."
        Write-Host '    Plages de ports que Windows reserve, et donc interdites :' -ForegroundColor Yellow
        try {
            netsh interface ipv4 show excludedportrange protocol=tcp 2>&1 |
                ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        } catch { }
        Echouer "Relancez en choisissant un port hors de ces plages :
           .\sans-docker\demarrer-windows.ps1 -PortBase 33306"
    }
    if ($PortBase -ne $portDemande) {
        Tracer "port de base : $portDemande demande, $PortBase retenu"
    }

    # La configuration est reecrite a chaque lancement, sauf si un serveur tourne
    # deja : sans cela, un port choisi au premier demarrage resterait fige dans
    # le fichier, et le serveur ecouterait l'ancien pendant que le client
    # interroge le nouveau.
    if (-not $reutilisable) {
    @"
# Instance MariaDB dediee a l'application GSB de 2013, isolee du poste.
# Fichier regenere a chaque lancement par sans-docker\demarrer-windows.ps1.
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
        Info "configuration ecrite, port $PortBase"
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

    <#
        Repare les journaux du moteur Aria.

        MariaDB stocke ses tables systeme avec le moteur Aria. Si le serveur est
        arrete brutalement, ses journaux restent incoherents et le demarrage
        suivant echoue sur « Aria recovery failed ». La procedure indiquee par
        MariaDB elle-meme consiste a ecarter ces journaux : ils seront recrees.

        Les fichiers sont deplaces, jamais supprimes, pour pouvoir revenir en
        arriere. Les donnees des tables, elles, ne sont pas touchees.
    #>
    function Repair-JournauxAria {
        $rebut = Join-Path $local ("mysql\aria-ecartes-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $fichiers = @(Get-ChildItem $donnees -Filter 'aria_log*' -ErrorAction SilentlyContinue)
        if (-not $fichiers) { return $false }

        New-Item -ItemType Directory -Force -Path $rebut | Out-Null
        foreach ($f in $fichiers) {
            Move-Item $f.FullName (Join-Path $rebut $f.Name) -Force -ErrorAction SilentlyContinue
            Tracer "   journal Aria ecarte : $($f.Name)"
        }
        Info "journaux du moteur Aria ecartes vers $rebut"
        return $true
    }

    function Start-Serveur {
        Start-Process -FilePath (Join-Path $mdbBin 'mysqld.exe') `
            -ArgumentList "--defaults-file=`"$mycnf`"", "--datadir=`"$donnees`"", "--console" `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $journalErreur `
            -RedirectStandardError  "$journalErreur.err"
    }

        Info "demarrage du serveur sur le port $PortBase"
        Detail "mysqld.exe --defaults-file=$mycnf --datadir=$donnees"

        # --console fait ecrire les erreurs sur la sortie standard, que l'on
        # capture : sans cela, un demarrage rate ne laisse aucune trace visible.
        $processus = Start-Serveur
        Detail "processus mysqld demarre, identifiant $($processus.Id)"

        $enMarche = $false
        $reparationTentee = $false
        foreach ($i in 1..20) {
            Start-Sleep -Seconds 2

            # Le processus a-t-il rendu l'ame ? Inutile d'attendre la fin du delai.
            if ($processus.HasExited) {
                $sortieBrute = Get-Content "$journalErreur.err" -Raw -ErrorAction SilentlyContinue

                # Journaux Aria incoherents : on les ecarte et on reessaie, une
                # seule fois, avant de declarer forfait.
                if (-not $reparationTentee -and $sortieBrute -match 'Aria recovery failed|Unknown storage engine ''Aria''') {
                    $reparationTentee = $true
                    Souci "Les journaux du moteur Aria sont incoherents, sequelle d'un arret brutal."
                    if (Repair-JournauxAria) {
                        Info 'nouvelle tentative de demarrage'
                        $processus = Start-Serveur
                        Detail "processus mysqld redemarre, identifiant $($processus.Id)"
                        continue
                    }
                }

                $code = if ($null -ne $processus.ExitCode) { $processus.ExitCode } else { 'inconnu' }
                Souci "mysqld s'est arrete tout seul, code $code."
                Montrer-Journal "$journalErreur.err" 'sortie d''erreur de mysqld'
                Montrer-Journal $journalErreur        'sortie de mysqld'
                $err = Get-ChildItem $donnees -Filter '*.err' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($err) { Montrer-Journal $err.FullName "journal MariaDB ($($err.Name))" }
                    $sortieErr = Get-Content "$journalErreur.err" -Raw -ErrorAction SilentlyContinue
                if ($sortieErr -match 'must be writable|Unknown/unsupported storage engine') {
                    Write-Host ''
                    Souci "Les fichiers de donnees sont deja utilises par un autre serveur."
                    Write-Host '    Un serveur MariaDB de ce projet tourne encore, sans doute' -ForegroundColor Yellow
                    Write-Host '    lance par une execution precedente. Arretez-le :' -ForegroundColor Yellow
                    Write-Host '      .\sans-docker\arreter-windows.ps1' -ForegroundColor Yellow
                    Write-Host '    puis relancez ce script.' -ForegroundColor Yellow
                    $autres = Get-Process -Name 'mysqld' -ErrorAction SilentlyContinue
                    if ($autres) {
                        Write-Host '    Processus mysqld actuellement en memoire :' -ForegroundColor Yellow
                        $autres | ForEach-Object {
                            $c = try { $_.Path } catch { '(chemin inconnu)' }
                            Write-Host "      pid $($_.Id)  $c" -ForegroundColor DarkGray
                        }
                    }
                }
                if ($sortieErr -match '10013') {
                    Write-Host ''
                    Souci "L'erreur 10013 signifie que Windows INTERDIT l'ecoute sur ce port."
                    Write-Host '    Ce n''est pas qu''un autre serveur l''occupe : Hyper-V et WSL' -ForegroundColor Yellow
                    Write-Host '    reservent des plages entieres, souvent autour de 3300.' -ForegroundColor Yellow
                    Write-Host '    Plages reservees sur ce poste :' -ForegroundColor Yellow
                    try {
                        netsh interface ipv4 show excludedportrange protocol=tcp 2>&1 |
                            ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray; Tracer "     | $_" }
                    } catch { }
                    Write-Host '    Choisissez un port hors de ces plages :' -ForegroundColor Yellow
                    Write-Host '      .\sans-docker\demarrer-windows.ps1 -PortBase 33306' -ForegroundColor Yellow
                }
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
            Souci "Si le probleme persiste, repartez d'une base vierge :"
            Souci "  .\sans-docker\demarrer-windows.ps1 -BaseNeuve"
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

    <#
        Un dossier accepte-t-il l'ecriture d'une archive ?

        Composer telecharge chaque dependance dans un fichier .zip temporaire.
        Deux mecanismes de Windows l'en empechent souvent : la synchronisation
        OneDrive du dossier Documents, qui verrouille les fichiers, et les
        antivirus, qui refusent l'ecriture d'archives dans un dossier surveille.
        Le symptome est un « Permission denied » sur un fichier tmp-....zip.
    #>
    function Test-EcritureZip([string]$Dossier) {
        # Les dossiers crees pour l'essai sont retires ensuite : en laisser un
        # ferait croire au lancement suivant que l'installation a eu lieu.
        $aCreer = @()
        $courant = $Dossier
        while ($courant -and -not (Test-Path $courant)) {
            $aCreer += $courant
            $courant = Split-Path -Parent $courant
        }
        try {
            New-Item -ItemType Directory -Force -Path $Dossier | Out-Null
            $essai = Join-Path $Dossier ("essai-" + [guid]::NewGuid().ToString('N') + ".zip")
            $entete = [byte[]](0x50, 0x4B, 0x05, 0x06)
            [System.IO.File]::WriteAllBytes($essai, $entete + (New-Object byte[] 18))
            Remove-Item $essai -Force
            return $true
        } catch {
            Tracer "   ecriture zip refusee dans $Dossier : $($_.Exception.Message)"
            return $false
        } finally {
            foreach ($d in $aCreer) {
                Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    <#
        Les PAQUETS sont-ils installes ?

        On ne regarde ici que les bibliotheques elles-memes. Le fichier
        autoload.php n'en fait volontairement pas partie : l'installation est
        lancee avec --no-autoloader, et l'autoloader est genere ensuite, une
        fois vendor a sa place definitive. Le reclamer ici ferait echouer une
        installation pourtant reussie.

        La presence du dossier vendor ne prouve rien : une installation
        interrompue le laisse derriere elle, vide.
    #>
    function Test-PaquetsInstalles {
        $temoins = @(
            'app\vendor\composer\installed.json',
            'app\vendor\symfony\symfony',
            'app\vendor\doctrine\annotations',
            'app\vendor\twig\twig'
        )
        $absents = @($temoins | Where-Object { -not (Test-Path $_) })
        if ($absents) {
            Tracer "   paquets manquants : $($absents -join ', ')"
            return $false
        }
        return $true
    }

    <#
        Installe les dependances dans un dossier donne.

        Composer y a besoin de composer.json et composer.lock, rien d'autre :
        les scripts et l'autoloader sont volontairement laisses de cote, ce
        dernier etant regenere plus loin, une fois vendor a sa place definitive.
    #>
    function Install-Dependances([string]$Atelier) {
        New-Item -ItemType Directory -Force -Path $Atelier | Out-Null
        if ($Atelier -ne (Join-Path $racine 'app')) {
            Copy-Item 'app\composer.json', 'app\composer.lock' -Destination $Atelier -Force
        }
        Push-Location $Atelier
        try {
            Detail "composer install dans $Atelier"
            Invoke-Php @('-c', $php_ini, $composer, 'install',
                         '--no-interaction', '--no-scripts', '--no-autoloader', '--no-progress') |
                ForEach-Object { Detail $_ }
        } finally { Pop-Location }

        # Les temoins d'une installation aboutie, dans le dossier de travail.
        foreach ($t in @('vendor\composer\installed.json', 'vendor\symfony\symfony',
                         'vendor\doctrine\annotations', 'vendor\twig\twig')) {
            if (-not (Test-Path (Join-Path $Atelier $t))) {
                Tracer "   installation incomplete dans $Atelier : $t absent"
                return $false
            }
        }
        return $true
    }

    if (-not (Test-PaquetsInstalles)) {
        if (Test-Path 'app\vendor') {
            Info 'dossier vendor incomplet, il est efface avant reinstallation'
            Remove-Item 'app\vendor' -Recurse -Force -ErrorAction SilentlyContinue
        }
        Info 'installation des dependances, comptez plusieurs minutes'

        # Premiere tentative dans le projet lui-meme.
        $atelier = Join-Path $racine 'app'
        $ok = Install-Dependances $atelier

        if (-not $ok) {
            # Echec typique quand OneDrive synchronise Documents, ou qu'un
            # antivirus refuse l'ecriture des archives temporaires. On repart
            # d'un dossier local, hors de Documents.
            Souci "L'installation a echoue dans le projet."
            Souci "Cause frequente : synchronisation OneDrive du dossier Documents,"
            Souci "ou antivirus qui bloque l'ecriture des fichiers .zip."
            if (Test-Path 'app\vendor') { Remove-Item 'app\vendor' -Recurse -Force -ErrorAction SilentlyContinue }

            $atelier = Join-Path $env:LOCALAPPDATA 'gsb-atelier'
            if (Test-Path $atelier) { Remove-Item $atelier -Recurse -Force -ErrorAction SilentlyContinue }
            Info "seconde tentative depuis un dossier local : $atelier"
            $ok = Install-Dependances $atelier

            if (-not $ok) {
                Write-Host ''
                Souci "La seconde tentative a echoue aussi."
                Souci "Verifiez, dans cet ordre :"
                Souci "  1. le reseau, et le proxy si vous etes en salle ;"
                Souci "  2. l'antivirus, qui bloque peut-etre les fichiers .zip ;"
                Souci "  3. l'espace disque disponible."
                Echouer "Installation des dependances impossible. Detail : $script:Journal"
            }
        }

        # Rapatriement si Composer a du travailler ailleurs.
        if ($atelier -ne (Join-Path $racine 'app')) {
            Info 'rapatriement des dependances dans le projet'
            $cible = Join-Path $racine 'app\vendor'
            if (Test-Path $cible) { Remove-Item $cible -Recurse -Force }
            Move-Item (Join-Path $atelier 'vendor') $cible
            Remove-Item $atelier -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (-not (Test-PaquetsInstalles)) {
            Echouer "Des paquets manquent encore apres installation.
           Detail dans $script:Journal"
        }
        Info 'dependances installees'
    } else {
        Info 'paquets deja installes'
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
        # Symfony et Doctrine declenchent sur PHP 7.4 des avertissements dans
        # leur propre code. Invoke-Php les absorbe : sans cela, PowerShell en
        # ferait des exceptions fatales.
        Detail 'regeneration de l autoloader'
        $sortieAuto = Invoke-Php @('-c', $php_ini, $composer, 'dump-autoload')
        if ($script:PhpCode -ne 0) {
            Write-Host ''
            Souci "La generation de l autoloader a echoue :"
            $sortieAuto -split "`n" | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
            Echouer "Sans autoloader, l application ne peut pas demarrer."
        }

        # Verification reelle : l autoloader charge-t-il une classe du vendor ?
        # Sans ce controle, l erreur n apparaissait qu a l ouverture de la page,
        # sous la forme « Class AnnotationRegistry not found ».
        $essai = Invoke-Php @('-c', $php_ini, '-r',
            "require 'vendor/autoload.php'; echo class_exists('Doctrine\\Common\\Annotations\\AnnotationRegistry') ? 'oui' : 'non';")
        if ($essai -ne 'oui') {
            Write-Host ''
            Souci "L autoloader ne trouve pas les classes de Doctrine."
            Detail "reponse obtenue : '$essai'"
            if (-not (Test-Path 'vendor\autoload.php')) { Souci 'vendor\autoload.php est absent.' }
            if (-not (Test-Path 'vendor\doctrine\annotations')) { Souci 'vendor\doctrine\annotations est absent.' }
            Souci 'Le dossier vendor sera efface au prochain lancement, qui le refera.'
            Echouer "Dependances incompletes. Relancez simplement ce script."
        }
        Detail 'autoloader verifie, les classes de Doctrine se chargent'

        Detail 'generation du fichier d amorcage'
        Invoke-Php @('-c', $php_ini, 'vendor\sensio\distribution-bundle\Sensio\Bundle\DistributionBundle\Resources\bin\build_bootstrap.php', 'app') | Out-Null
        Detail 'publication des ressources'
        Invoke-Php @('-c', $php_ini, 'app\console', 'assets:install', 'web', '--env=prod', '--no-debug', '--quiet') | Out-Null
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

    # Meme precaution que pour la base : un port peut etre reserve par Windows
    # sans que rien ne l'ecoute.
    $portWebDemande = $PortWeb
    $PortWeb = Trouver-Port $PortWeb @(8089, 8091, 8095, 8100, 18080, 28080)
    if ($PortWeb -eq 0) {
        Echouer "Aucun port disponible pour le serveur web.
           Relancez en en choisissant un :
             .\sans-docker\demarrer-windows.ps1 -PortWeb 18080"
    }
    if ($PortWeb -ne $portWebDemande) {
        Souci "Le port $portWebDemande etait inutilisable, le serveur web ecoute sur $PortWeb."
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
