<#
    Arrête l'application GSB lancée sans Docker, sous Windows.

    Les processus sont retrouvés par leur EMPLACEMENT, dans legacy\local\bin\,
    et non par leur port : celui-ci varie d'un lancement à l'autre quand Windows
    réserve le port habituel. Rien d'autre que les processus de ce dossier n'est
    arrêté : une installation PHP, WAMP, XAMPP ou MySQL du poste n'est pas touchée.

    Les données sont conservées dans legacy\local\mysql\data.
    Pour repartir d'une base vierge :
        .\sans-docker\demarrer-windows.ps1 -BaseNeuve
#>

#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$racine   = Split-Path -Parent $PSScriptRoot
$local    = Join-Path $racine 'local'
$binaires = Join-Path $local 'bin'

Write-Host ''
Write-Host '  Arrêt de l''application GSB (mode sans Docker)'
Write-Host ''

# Arrête les processus d'un exécutable donné, s'ils viennent de ce projet.
function Stopper-Processus([string]$Nom, [string]$Etiquette) {
    $tous = Get-Process -Name $Nom -ErrorAction SilentlyContinue
    if (-not $tous) {
        Write-Host "  $Etiquette : rien à arrêter"
        return
    }

    $nôtres = @($tous | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($binaires, 'OrdinalIgnoreCase') } catch { $false }
    })

    if (-not $nôtres) {
        Write-Host "  $Etiquette : $($tous.Count) processus trouvé(s), aucun de ce projet." -ForegroundColor Yellow
        $tous | ForEach-Object {
            $chemin = try { $_.Path } catch { '(chemin inaccessible)' }
            Write-Host "      pid $($_.Id)  $chemin" -ForegroundColor DarkGray
        }
        Write-Host "      Rien n'a été arrêté." -ForegroundColor Yellow
        return
    }

    foreach ($p in $nôtres) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Host "  $Etiquette arrêté (pid $($p.Id))"
        } catch {
            Write-Host "  $Etiquette : impossible d'arrêter le pid $($p.Id) — $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

<#
    Arrêt PROPRE du serveur de base.

    Tuer le processus laisse les journaux du moteur Aria dans un état
    incohérent, et le démarrage suivant échoue sur « Aria recovery failed ».
    On demande donc d'abord un arrêt en bonne et due forme, et on ne force
    qu'en dernier recours.
#>
function Stopper-BaseProprement {
    $mariadb = Get-ChildItem (Join-Path $binaires 'mariadb') -Filter 'mysqladmin.exe' `
                   -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $mariadb) { return $false }

    $processus = @(Get-Process -Name 'mysqld' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($binaires, 'OrdinalIgnoreCase') } catch { $false }
    })
    if (-not $processus) { return $true }

    # Le port réel se lit sur le processus : le fichier de configuration a pu
    # être réécrit depuis son démarrage.
    $port = 0
    $ecoute = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
              Where-Object { $_.OwningProcess -eq $processus[0].Id } | Select-Object -First 1
    if ($ecoute) { $port = $ecoute.LocalPort }

    $plugins = Join-Path (Split-Path -Parent $mariadb.DirectoryName) 'lib\plugin'
    foreach ($mdp in @('root', '')) {
        $parametres = @('--host=127.0.0.1', '--protocol=tcp', '--user=root', '--connect-timeout=5')
        if (Test-Path $plugins) { $parametres += "--plugin-dir=$plugins" }
        if ($port -gt 0) { $parametres += "--port=$port" }
        if ($mdp) { $parametres += "--password=$mdp" }
        $parametres += 'shutdown'

        & $mariadb.FullName @parametres 2>&1 | Out-Null
        Start-Sleep -Seconds 3

        $restant = @(Get-Process -Name 'mysqld' -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($binaires, 'OrdinalIgnoreCase') } catch { $false }
        })
        if (-not $restant) {
            Write-Host '  base de données arrêtée proprement'
            return $true
        }
    }
    return $false
}

# Le serveur de base est arrêté en premier : il doit relâcher ses fichiers.
if (-not (Stopper-BaseProprement)) {
    Write-Host '  arrêt propre impossible, le processus va être forcé' -ForegroundColor Yellow
    Stopper-Processus 'mysqld' 'base de données'
}
Stopper-Processus 'php' 'serveur web'

Start-Sleep -Seconds 2

# Reste-t-il quelque chose ?
$restants = @(
    @(Get-Process -Name 'mysqld', 'php' -ErrorAction SilentlyContinue) | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($binaires, 'OrdinalIgnoreCase') } catch { $false }
    }
)
if ($restants) {
    Write-Host ''
    Write-Host '  Certains processus résistent :' -ForegroundColor Yellow
    $restants | ForEach-Object { Write-Host "      pid $($_.Id)  $($_.ProcessName)" -ForegroundColor DarkGray }
    Write-Host '  Fermez-les depuis le Gestionnaire des tâches.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  Les données saisies sont conservées.'
Write-Host '  Pour repartir d''une base vierge :'
Write-Host '      .\sans-docker\demarrer-windows.ps1 -BaseNeuve'
Write-Host ''
