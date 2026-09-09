# Installation et démarrage sous Windows

Deux scripts, à exécuter dans cet ordre. Le premier une seule fois par poste, le second à chaque
fois qu'on veut travailler.

## 1. Installer les prérequis

À faire une fois. Ouvrez PowerShell **en administrateur** : clic droit sur le menu Démarrer, puis
« Terminal (administrateur) ». Placez-vous dans le dossier du dépôt et lancez :

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\legacy\windows\installer-prerequis.ps1
```

Le script vérifie avant d'installer, et n'installe que ce qui manque :

| Vérification | Ce qui se passe |
| --- | --- |
| Droits administrateur | Arrêt immédiat si la fenêtre n'est pas élevée |
| Version de Windows | Build 19041 minimum, sinon WSL 2 n'existe pas |
| Virtualisation matérielle | Avertissement si elle est désactivée dans le BIOS |
| winget | Arrêt avec le lien du Microsoft Store s'il est absent |
| Git | Installé via winget |
| Docker Desktop | Installé via winget |
| WSL 2 | Activé, noyau mis à jour |

Pour voir ce qui manque sans rien installer :

```powershell
.\legacy\windows\installer-prerequis.ps1 -Verification
```

Si WSL vient d'être activé, **redémarrez le poste**. Lancez ensuite Docker Desktop et attendez que
l'icône en forme de baleine cesse de bouger.

## 2. Démarrer l'application

Dans une fenêtre PowerShell ordinaire, sans droits particuliers :

```powershell
.\legacy\windows\mise-en-route.ps1
```

Le script démarre Docker s'il dort, vérifie que le port est libre, construit l'image, attend la
base, installe Symfony au premier passage, puis vérifie que la page d'accueil répond. Il est
réexécutable sans risque.

Deux options :

```powershell
.\legacy\windows\mise-en-route.ps1 -Port 8090    # si 8088 est déjà pris
.\legacy\windows\mise-en-route.ps1 -BaseNeuve    # repart d'une base vierge
```

Avec `-Port`, pensez à modifier aussi la ligne `ports` de `legacy/docker-compose.yml`, sinon le
conteneur continue de publier sur 8088.

Plus simple encore : double-cliquez sur `Lancer-GSB-windows.bat`, à la racine du dépôt. Il appelle
ce script et ouvre le navigateur.

## Ce qui a été vérifié, et ce qui ne l'a pas été

Ces scripts ont été écrits sur un Mac. Leur **syntaxe** est validée, ainsi que les cmdlets
employées et la conversion des fins de ligne, en exécutant PowerShell dans un conteneur. Leur
**exécution sur un vrai poste Windows ne l'a pas été**, faute de machine. Signalez ce qui coince,
la correction sera rapide.

Les deux cmdlets propres à Windows, `Get-CimInstance` et `Get-NetTCPConnection`, existent depuis
Windows 8 et PowerShell 3.0 : elles ne poseront pas de problème sur un poste récent.

## Pièges connus

**Fins de ligne.** Le fichier `.gitattributes` du dépôt force les fins de ligne Unix sur les
fichiers lus par les conteneurs Linux : scripts shell, SQL, YAML, `Dockerfile`. Sans cela, Git les
convertirait au format Windows et le conteneur échouerait avec un message obscur du type
`$'\r': command not found`. Ne modifiez pas cette règle.

Le script PowerShell applique la même précaution aux commandes qu'il envoie dans le conteneur : la
fonction `Invoke-DansConteneur` convertit les fins de ligne avant transmission.

**Politique d'exécution.** Windows refuse par défaut d'exécuter un script PowerShell téléchargé.
La ligne `Set-ExecutionPolicy -Scope Process` lève l'interdiction pour la seule fenêtre en cours,
sans rien changer aux réglages du poste. Le fichier `.bat` s'en charge tout seul.

**Docker Desktop et le proxy de la salle.** Docker ne lit pas les variables d'environnement du
terminal. Le proxy se règle dans ses préférences, à la rubrique des ressources. Voir le README à
la racine du dépôt, section « Travailler derrière le proxy de la salle ».
