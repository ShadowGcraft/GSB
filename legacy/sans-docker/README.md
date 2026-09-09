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
.\legacy\sans-docker\demarrer-windows.ps1 -PortWeb 8091    # si 8089 est pris
.\legacy\sans-docker\demarrer-windows.ps1 -PortBase 3309   # si 3307 est pris
.\legacy\sans-docker\demarrer-windows.ps1 -BaseNeuve       # repart d'une base vierge
.\legacy\sans-docker\demarrer-windows.ps1 -Verbeux         # détaille chaque étape
```

### En cas de blocage

Le script écrit tout ce qu'il fait dans `legacy\local\log\demarrage.log`, horodaté : commandes
lancées, requêtes envoyées à la base, codes de retour. C'est le premier fichier à ouvrir.

Trois autres journaux complètent le tableau, dans le même dossier :

| Fichier | Contenu |
| --- | --- |
| `mariadb-sortie.log` et `.err` | Ce que le serveur de base écrit au démarrage |
| `init-db.log` | L'initialisation des données, au tout premier lancement |
| `php-server.log` | Le serveur web |

Le serveur de base est surveillé pendant son démarrage : s'il s'arrête, le script le détecte tout
de suite, affiche ses journaux et celui de MariaDB, et s'arrête au lieu d'attendre. Les appels au
client ont un délai d'attente de cinq secondes, ce qui évite qu'une connexion sans réponse fige la
fenêtre.

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

## Sept particularités de Windows

Ces sept points ont été découverts en essayant sur un vrai poste, et corrigés.

**Composer ne pouvait écrire aucune archive.** Il téléchargeait chaque dépendance dans un fichier
`.zip` temporaire, et Windows refusait l'écriture, pour les trente-sept paquets. Deux causes se
combinent souvent : le dossier `Documents` est synchronisé par OneDrive, qui verrouille les fichiers,
et les antivirus refusent l'écriture d'archives dans un dossier surveillé.

Le script teste maintenant l'écriture d'une archive avant de lancer Composer. Si elle est refusée, il
bascule sur un dossier local hors de `Documents`, y installe les dépendances, puis les rapatrie dans
le projet. Si même ce dossier refuse, il le dit et pointe l'antivirus.

**Une extension déclarée de travers.** `opcache` n'est pas une extension ordinaire mais une extension
Zend : elle se déclare avec `zend_extension`. Écrite comme les autres, elle provoquait un
avertissement à chaque appel de PHP, et donc l'arrêt du script. Elle est retirée : elle n'apporte
rien à un serveur de démonstration.

**Windows réserve des plages entières de ports.** C'est la plus déroutante. MariaDB refusait de
démarrer avec l'erreur 10013 et le message « Do you already have another server running on port
3307 ? », alors que rien n'écoutait ce port. Hyper-V et WSL, installés avec Docker, réservent des
blocs de ports souvent situés autour de 3300 : rien ne les occupe, mais Windows interdit de s'y
mettre à l'écoute.

Le script essaie désormais réellement d'écouter le port avant de lancer quoi que ce soit, ce qui est
le seul test fiable. S'il est refusé, il en essaie d'autres et annonce celui qu'il retient. En
dernier recours, il affiche les plages réservées du poste et indique quoi faire. Le port du serveur
web est protégé de la même façon.

Au passage, le fichier de configuration de MariaDB n'était écrit qu'au premier lancement : demander
un autre port avec `-PortBase` changeait les appels du client, mais le serveur continuait d'écouter
l'ancien. Il est maintenant réécrit à chaque démarrage.

**PHP 7.4 pour Windows ne fournit pas l'extension `zip`.** Ce n'est pas une omission de notre part :
l'archive officielle `php-7.4.33-Win32-vc15-x64.zip` ne contient aucun `php_zip.dll`, sur les
quarante extensions qu'elle livre. Or Composer en a besoin pour extraire les dépendances, et il
refuse de démarrer sans elle, y compris avec `--prefer-source`. Le script télécharge donc 7-Zip
autonome, 385 Ko sous licence LGPL, et l'ajoute au chemin de recherche : Composer le détecte et
s'en sert. Le fonctionnement de ce contournement a été vérifié.

**Les accents.** PowerShell 5.1, celui livré avec Windows, lit un script sans marque d'ordre
d'octets comme du texte ANSI : « téléchargement » s'affichait « tÃ©lÃ©chargement ». Les quatre
scripts sont désormais enregistrés en UTF-8 avec cette marque.

**Le client MariaDB ne trouvait pas ses greffons.** L'erreur était trompeuse :
`Plugin caching_sha2_password could not be loaded`, un nom qui évoque MySQL 8 et laisse croire à un
serveur étranger sur le port. En réalité MariaDB fournit bien ce greffon, dans `lib\plugin\`, mais
le client le cherche à côté de lui : lancé depuis un autre dossier, il ne le trouve pas. Les appels
au client passent maintenant `--plugin-dir` et demandent l'authentification classique par mot de
passe. Le script crée par ailleurs explicitement les comptes `root` pour `localhost` et pour
`127.0.0.1`, sans quoi la connexion réseau de PHP est refusée.

**Un avertissement suffisait à tout arrêter.** Quand PHP écrit sur la sortie d'erreur, PowerShell
en fait une exception fatale si `ErrorActionPreference` vaut `Stop`. Le script abaisse maintenant ce
réglage autour des appels à PHP et ne juge que sur la valeur renvoyée. Il n'active en outre que les
extensions réellement présentes dans le dossier `ext\`, au lieu d'une liste écrite à l'avance.

## Ce qui a été vérifié

Le mode macOS a été **exécuté et testé** de bout en bout : installation, initialisation de la base,
chargement du schéma, connexion, saisie forfaitisée, ajout d'un frais hors forfait, consultation
d'une fiche clôturée, feuilles de style et logo. La bascule entre les deux modes a été testée dans
les deux sens.

Le mode Windows a été **essayé sur un vrai poste**, en quatre passes, ce qui a révélé les sept
problèmes décrits plus haut. Le téléchargement des outils, la configuration de PHP, le démarrage de
MariaDB, le chargement du schéma et du jeu d'essai sont désormais confirmés sur Windows. Le téléchargement des outils, la configuration de PHP et le démarrage
de MariaDB sont désormais confirmés sur Windows. Chaque correctif a été vérifié à part : contenu
réel des archives PHP et MariaDB, fonctionnement de Composer avec un extracteur externe, lecture
des accents, filtrage des avertissements, comportement du client MariaDB. La **fin du parcours
reste à confirmer** : chargement du schéma, installation des dépendances, démarrage du serveur web.

Deux points méritent encore l'attention : les liens symboliques n'existant pas de la même façon,
`assets:install` copie les fichiers au lieu de les lier, et le script duplique ensuite le dossier
sous le nom attendu par les gabarits de 2013 ; par ailleurs, si un antivirus bloque l'exécution de
`mysqld.exe` téléchargé, il faut l'autoriser.
