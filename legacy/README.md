# Application GSB de 2013, remise en marche

Ce dossier fait tourner l'application historique fournie par l'enseignant, celle qui sert de
**référence fonctionnelle** au projet. Ce n'est pas notre code : c'est l'existant, remis en état pour
qu'on puisse le manipuler plutôt que le deviner en lisant les sources.

Rien de ce dossier n'a vocation à finir dans l'application Symfony 7. Le nouveau projet est dans
`/web`, `/mobile` et `/supabase`.

## Démarrer

Deux modes au choix, qui font tourner exactement la même application.

**Avec Docker**, sur <http://localhost:8088>. Double-cliquez sur `Lancer-GSB-mac.command` ou
`Lancer-GSB-windows.bat`, à la racine du dépôt.

**Sans Docker**, sur <http://127.0.0.1:8089>. Double-cliquez sur
`Lancer-GSB-sans-Docker-mac.command` ou `Lancer-GSB-sans-Docker-windows.bat`. Ce mode n'exige
aucun droit administrateur sous Windows : PHP et MariaDB y sont téléchargés en version portable.
Voir `sans-docker/README.md`.

Les fichiers `Arreter-GSB-...` font l'inverse.

En ligne de commande :

```bash
./mise-en-route.sh                      # macOS et Linux
.\windows\mise-en-route.ps1             # Windows, dans PowerShell
```

Sous Windows, les prérequis s'installent une fois pour toutes avec
`.\windows\installer-prerequis.ps1`. Voir `windows/README.md`.

Puis ouvrir <http://localhost:8088>.

| Visiteur | Identifiant | Mot de passe |
| --- | --- | --- |
| David André | `dandre` | `oppg5` |
| Christian Bedos | `cbedos` | `gvide` |
| Pascal Bentot | `pbentot` | `doypa` |
| Comptable | `comptable` | `gsbcompta` |
| Administrateur | `admin` | `gsbadmin` |

Les deux derniers comptes, ajoutés en 2026, ont chacun leurs couleurs. Le
comptable, en vert sapin et or, valide les fiches clôturées. L'administrateur,
en bordeaux et champagne, fait de même et gère en plus les comptes.

David André et Christian Bedos ont déclaré leur véhicule au début du mois
dernier. Pascal Bentot n'en a déclaré aucun : sa saisie de kilomètres est
bloquée, ce qui permet de montrer la règle.

Le mode développement, avec la barre de débogage Symfony, est sur
<http://localhost:8088/app_dev.php/accueil>.

Pour arrêter : `docker compose down`. Pour repartir d'une base vierge : `docker compose down -v`,
qui supprime le volume et rejoue le jeu d'essai au démarrage suivant.

## Ce que contenait l'archive, et ce qui manquait

L'archive `codeGsbSymfony.zip` ne contient **que le bundle** `GsbFraisBundle` : 24 fichiers, des
contrôleurs, des gabarits Twig et une classe d'accès aux données. Il manquait tout le reste.

| Élément | Dans l'archive | Reconstitué ici |
| --- | --- | --- |
| Bundle applicatif | oui | — |
| Squelette Symfony | non | Symfony 2.8, installé par le script |
| Schéma de la base | non | `sql/01-schema.sql`, déduit des requêtes du code |
| Jeu de données | non | `sql/02-donnees.sql` |
| Feuille de style | non | `Resources/public/styles/styles.css` |
| Logo | non | extrait du PDF du cahier des charges |
| Procédure d'installation | non | `mise-en-route.sh` |

Le schéma mérite une précision : **aucune source ne le donne**. Chaque table et chaque colonne de
`sql/01-schema.sql` est déduite d'une requête précise de `PdoGsb.php` ou d'un champ lu dans un
gabarit. Le fichier est commenté ligne à ligne sur ce point. Il reproduit le modèle de 2013 tel
qu'il était, défauts compris : mot de passe en clair, mois stocké en chaîne, clés composites.

## L'environnement, et pourquoi il est daté

| Brique | Version | Raison |
| --- | --- | --- |
| PHP | 7.4 | Dernier PHP qui fait tourner Symfony 2, et dernier disponible en image officielle pour les Mac ARM |
| Symfony | 2.8 | Dernière version de la branche 2, celle du support de 2013 |
| MariaDB | 10.6 | Compatible MySQL, avec des images ARM natives |

Le code de 2013 ne fonctionne pas sur PHP 8 : c'est la raison d'être de ce conteneur.

## Ce qu'il a fallu corriger

Sept obstacles séparaient l'archive d'une application qui démarre. Les quatre premiers relèvent de
l'environnement, les trois derniers sont des défauts du code lui-même.

**Configuration de la base, dans `docker-compose.yml`.**

1. *Mode SQL strict.* Le code insère une chaîne vide dans la colonne entière auto-incrémentée de
   `lignefraishorsforfait`. MySQL le tolérait en 2013 ; MariaDB en mode strict refuse la ligne, et
   PDO, configuré en mode silencieux, ne signale rien. L'ajout d'un frais échouait sans message.
   La base tourne donc en mode non strict, plutôt que de corriger la requête.
2. *Casse des noms de tables.* Le code écrit tantôt `etat`, tantôt `Etat`. Sous Windows, où
   l'application a été développée, MySQL ignore la casse ; sous Linux il la respecte et la
   consultation d'une fiche échouait. Le serveur est réglé pour ignorer la casse.

**Configuration du serveur web, dans le `Dockerfile`.**

3. *Dépôts Debian en HTTPS.* Sur le réseau utilisé pour ce projet, le port 80 sortant est
   intercepté et `apt` reçoit une erreur 400. La construction de l'image échouait.
4. *Réécriture d'URL.* Sans `AllowOverride`, Apache ignore le `.htaccess` de Symfony : la racine du
   site listait le répertoire au lieu de servir l'application.

**Défauts du code de 2013.** Ce sont les seules modifications apportées au bundle.

5. *Marqueurs d'ordre d'octets.* Les deux fichiers de `Controller/include/` commençaient par un BOM
   UTF-8, émis avant les en-têtes HTTP. Symfony ne pouvait plus démarrer la session.
6. *Résidus de débogage.* Un `var_dump` dans `PdoGsb.php` et un couple `echo`/`var_dump` dans
   `fct.inc.php` produisaient la même erreur. L'application n'était pas exécutable en l'état.
7. *Chemin des assets.* Les gabarits demandent `bundles/gsbfrais/`, alors que le bundle s'appelle
   `PgGsbFraisBundle` et publie sous `bundles/pggsbfrais/`. Un lien supplémentaire répond au chemin
   attendu, sans toucher aux gabarits.

Deux ajouts de confort, hors du bundle : la racine du site redirige vers l'accueil, et le
contrôleur de développement accepte les requêtes venant de l'extérieur du conteneur.

## Ce qui a été vérifié

Huit parcours, tous passants : page de connexion, authentification, écran de saisie, enregistrement
des quantités forfaitisées, ajout d'un frais hors forfait, suppression d'une ligne, liste des mois,
consultation d'une fiche clôturée, déconnexion. Les écritures ont été contrôlées en base, pas
seulement à l'écran.

## L'archive telle qu'elle était

Défauts constatés dans le code de 2013, documentés dans le cahier des charges, section 1.3 :

- **Le module comptable n'existait pas.** L'entrée « Valider les frais » du menu pointait vers une
  URL d'avant Symfony, `index.php?uc=validerFrais`, qui renvoyait une erreur.
- **La saisie ne porte que sur le mois courant.** Le contrôleur force le mois du jour.
- **Aucun montant n'était calculé.** Ni le montant d'une ligne, ni le total d'une fiche.
- **Le contrôle d'accès était inopérant.** `estConnecte` lit le sac de messages flash alors que la
  connexion écrit dans la session, et aucune route ne l'appelait.
- **Les mots de passe sont en clair**, comparés tels quels dans la requête SQL.

## Les évolutions de 2026

Les scripts de `Resources/sql/evolutions-2026*.sql` mettent à niveau une base existante au premier
accès, sans la recréer. Ils ajoutent :

- les rôles comptable et administrateur, le contrôle d'accès par rôle et la gestion des comptes ;
- les pièces jointes des frais hors forfait (PDF, JPEG, PNG, 5 Mo au plus) ;
- le **barème kilométrique** du sujet, indexé sur la puissance fiscale et le carburant. Le visiteur
  déclare son véhicule dans « Mon véhicule », sans pouvoir saisir de km avant. Le taux d'un mois est
  celui du dernier véhicule valide ce mois-là. Un mois sans véhicule déclaré date d'avant le barème et
  garde l'ancien taux unique de 0,62 € ;
- la **validation par le comptable** (annexe 2) : choix du visiteur et du mois, correction des
  quantités forfaitisées, refus d'un frais hors forfait, report d'un frais sur la fiche du mois
  suivant, créée au besoin, puis validation ;
- la **clôture de campagne** : un bouton clôture d'un coup les fiches des mois écoulés restées en
  cours de saisie ;
- les **cinq états** du diagramme : Créée, Clôturée, Validée, Mise en paiement, Remboursée ;
- l'**édition PDF** au format de l'annexe 1 (bibliothèque dompdf), fiche par fiche ou en un clic pour
  toutes les fiches du mois précédent dont la saisie est terminée ;
- un **référentiel des forfaits plus lisible** : les quatre forfaits reprennent les termes du sujet
  (repas de midi, nuitée hôtel seul, relais étape, kilométrage), rangés par thème, tarif affiché. Leur
  montant reste fixé par le laboratoire, le visiteur ne saisit qu'une quantité ;
- des **dépenses hors forfait classées**, comme dans les applications de notes de frais : 27
  catégories en six thèmes (transport, repas, animations et congrès, bureau, formation, divers),
  choisies dans une grille d'icônes avec recherche. Le visiteur saisit le prix payé et joint sa
  facture. Les dépenses s'affichent en liste, avec leur catégorie et l'état de leur facture. Les
  péages ne figurent pas dans les catégories : le badge télépéage les couvre.

Restent en l'état : les mots de passe en clair, et la saisie des forfaits limitée au mois courant.

## Structure

```text
legacy/
├── docker-compose.yml   Les deux services, et les réglages de base d'époque
├── Dockerfile           PHP 7.4, Apache, extensions
├── mise-en-route.sh     Installation et démarrage sous macOS et Linux
├── windows/             Les mêmes opérations en PowerShell, plus l'installation
│   ├── installer-prerequis.ps1
│   └── mise-en-route.ps1
├── sans-docker/         Le même service sans conteneur, macOS et Windows
│   ├── demarrer-mac.sh      arreter-mac.sh
│   ├── demarrer-windows.ps1 arreter-windows.ps1
│   └── routeur.php          tient lieu d'Apache
├── local/               Binaires, base et journaux du mode sans Docker (ignoré par Git)
├── sql/
│   ├── 01-schema.sql    Schéma reconstitué, commenté requête par requête
│   └── 02-donnees.sql   Jeu d'essai
└── app/                 Projet Symfony 2.8 ; le bundle d'origine est dans src/Pg/
```

Le dossier `app/vendor/` n'est pas versionné : `mise-en-route.sh` le réinstalle.
