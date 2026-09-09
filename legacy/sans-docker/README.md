# Lancer l'application sans Docker

Docker n'est pas toujours disponible : droits administrateur refusés en salle, poste peu puissant,
virtualisation désactivée dans le BIOS. Ce dossier fait tourner la même application sans lui.

Le principe est identique sur les deux systèmes : PHP 7.4, une instance MariaDB dédiée, et le
serveur web intégré de PHP à la place d'Apache. Tout ce qui est produit vit dans `legacy/local/`,
un dossier ignoré par Git et supprimable à tout moment.

## macOS

```bash
./legacy/sans-docker/demarrer-mac.sh      # ou double-clic sur Lancer-GSB-sans-Docker-mac.command
./legacy/sans-docker/arreter-mac.sh
```

PHP 7.4 et MariaDB sont installés par Homebrew au premier lancement. PHP 7.4 ayant quitté Homebrew
officiel, il vient du dépôt communautaire `shivammathur/php`, qui fournit des versions compilées
pour les Mac ARM.

## Windows

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\legacy\sans-docker\demarrer-windows.ps1     # ou double-clic sur Lancer-GSB-sans-Docker-windows.bat
.\legacy\sans-docker\arreter-windows.ps1
```

Rien n'est installé sur le poste : PHP 7.4 et MariaDB sont téléchargés en archive dans
`legacy\local\bin\`. **Aucun droit administrateur n'est nécessaire**, ce qui en fait la solution
adaptée aux salles de cours. Comptez une dizaine de minutes au premier lancement, le temps de
récupérer environ 400 Mo.

Options :

```powershell
.\legacy\sans-docker\demarrer-windows.ps1 -PortWeb 8091   # si 8089 est pris
.\legacy\sans-docker\demarrer-windows.ps1 -BaseNeuve      # repart d'une base vierge
```

## Comparaison des deux modes

| | Avec Docker | Sans Docker |
| --- | --- | --- |
| Adresse | <http://localhost:8088> | <http://127.0.0.1:8089> |
| Serveur web | Apache, dans le conteneur | serveur intégré de PHP |
| Base | MariaDB 10.6, conteneur | MariaDB locale, port 3307 |
| Droits administrateur | oui, pour installer Docker | non sous Windows |
| Poids | environ 800 Mo d'images | environ 400 Mo dans `legacy/local/` |
| Premier lancement | quelques minutes | dix minutes environ |

Les deux modes partagent le même code, le même schéma et le même jeu d'essai. Ils utilisent des
ports différents et peuvent donc tourner en même temps, sur deux bases distinctes.

Le fichier de configuration `services.yml` du bundle porte l'adresse de la base. Chaque script y
écrit la valeur de son mode au démarrage : passer de l'un à l'autre ne demande rien de plus que de
lancer le script voulu. Git signalera ce fichier comme modifié selon le dernier mode utilisé, c'est
normal.

## Ce qui remplace Apache

Le serveur intégré de PHP ne lit pas les fichiers `.htaccess`. Le fichier `routeur.php` en tient
lieu : il sert directement les fichiers qui existent, feuilles de style et images comprises, et
confie tout le reste au contrôleur frontal de Symfony. Il refuse les chemins contenant `..`.

Par défaut il utilise `app_dev.php`, avec les messages d'erreur détaillés. La variable
d'environnement `GSB_ENV=prod` bascule sur `app.php`.

## Les mêmes réglages d'époque

L'instance MariaDB reprend les deux réglages indispensables, décrits dans le README de `legacy/` :
le mode SQL non strict, sans lequel l'ajout d'un frais hors forfait échoue en silence, et
l'insensibilité à la casse des noms de tables, sans laquelle la consultation d'une fiche plante.

Elle est isolée : port 3307, données dans `legacy/local/mysql/data`, aucun service système
enregistré. Une installation MariaDB, MySQL, WAMP ou XAMPP déjà présente sur le poste n'est pas
touchée. Le script d'arrêt sous Windows vérifie d'ailleurs que le processus qu'il s'apprête à
arrêter vient bien de `legacy\local\bin\`, et ne touche à rien d'autre.

## Repartir de zéro

Supprimez `legacy/local/` : binaires, base et journaux disparaissent. Le prochain lancement
reconstruit tout. Pour ne réinitialiser que les données, supprimez `legacy/local/mysql/data`, ou
utilisez `-BaseNeuve` sous Windows.

## Trois particularités de Windows

Ces trois points ont été découverts au premier essai sur un vrai poste, et corrigés.

**PHP 7.4 pour Windows ne fournit pas l'extension `zip`.** Ce n'est pas une omission de notre part :
l'archive officielle `php-7.4.33-Win32-vc15-x64.zip` ne contient aucun `php_zip.dll`, sur les
quarante extensions qu'elle livre. Or Composer en a besoin pour extraire les dépendances, et il
refuse de démarrer sans elle, y compris avec `--prefer-source`. Le script télécharge donc 7-Zip
autonome, 385 Ko sous licence LGPL, et l'ajoute au chemin de recherche : Composer le détecte et
s'en sert. Le fonctionnement de ce contournement a été vérifié.

**Les accents.** PowerShell 5.1, celui livré avec Windows, lit un script sans marque d'ordre
d'octets comme du texte ANSI : « téléchargement » s'affichait « tÃ©lÃ©chargement ». Les quatre
scripts sont désormais enregistrés en UTF-8 avec cette marque.

**Un avertissement suffisait à tout arrêter.** Quand PHP écrit sur la sortie d'erreur, PowerShell
en fait une exception fatale si `ErrorActionPreference` vaut `Stop`. Le script abaisse maintenant ce
réglage autour des appels à PHP et ne juge que sur la valeur renvoyée. Il n'active en outre que les
extensions réellement présentes dans le dossier `ext\`, au lieu d'une liste écrite à l'avance.

## Ce qui a été vérifié

Le mode macOS a été **exécuté et testé** de bout en bout : installation, initialisation de la base,
chargement du schéma, connexion, saisie forfaitisée, ajout d'un frais hors forfait, consultation
d'une fiche clôturée, feuilles de style et logo. La bascule entre les deux modes a été testée dans
les deux sens.

Le mode Windows a été **essayé sur un vrai poste**, ce qui a révélé les trois problèmes décrits
plus haut. Ils sont corrigés, et chaque correctif a été vérifié à part : contenu réel de l'archive
PHP, fonctionnement de Composer avec un extracteur externe, lecture des accents, filtrage des
avertissements. La **suite du parcours reste à confirmer** : initialisation de MariaDB, installation
des dépendances, démarrage du serveur.

Deux points méritent encore l'attention : les liens symboliques n'existant pas de la même façon,
`assets:install` copie les fichiers au lieu de les lier, et le script duplique ensuite le dossier
sous le nom attendu par les gabarits de 2013 ; par ailleurs, si un antivirus bloque l'exécution de
`mysqld.exe` téléchargé, il faut l'autoriser.
