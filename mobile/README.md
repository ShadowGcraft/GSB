# Application mobile Flutter

Pour la présentation générale du projet GSB, l'architecture d'ensemble et les décisions
communes aux deux clients, se reporter au README à la racine du dépôt.

## Statut

Dossier vide. Le projet Flutter sera initialisé à la phase de développement, après la
création des tables et des politiques RLS. Seul un fichier `.gitkeep` occupe le dossier.

## À qui s'adresse cette application

Aux **visiteurs médicaux** uniquement, pour la saisie au fil de l'eau, sur le terrain,
entre deux rendez-vous. C'est un mémo de poche : on note un repas ou une nuitée au moment
où la dépense a lieu, sans attendre le retour au poste de travail. Les péages, eux, ne sont
jamais remboursés : chaque visiteur dispose d'un badge de télépéage.

Ce n'est **pas** un second client complet. Le comptable n'y a pas accès : la validation,
la mise en paiement et l'édition PDF restent l'affaire de l'application web. Ce choix
limite volontairement la surface à développer et à défendre.

## Écrans attendus

Déduits du document `_sources/GSB_Android.pdf` fourni par le client :

- Un menu d'accueil.
- La saisie du kilométrage.
- La saisie des repas de midi, des nuitées et des relais étape.
- La saisie d'un frais hors forfait au jour le jour, avec date, libellé, montant et photo du
  justificatif. Le fichier part vers Supabase Storage au moment de la synchronisation, pas au
  moment de la prise de vue : il rejoint la file d'attente locale comme le reste.
- Un récapitulatif mensuel des frais hors forfait, avec suppression d'une ligne.
- La consultation du véhicule déclaré, en lecture seule. La déclaration et l'historisation se
  font sur l'application web.
- Un écran de synchronisation.

**Sans véhicule déclaré, la saisie du kilométrage est bloquée**, sur le mobile comme sur le
web : le barème dépend de la puissance fiscale et du carburant, et il n'existe pas de taux par
défaut. L'écran affiche alors un message renvoyant vers la déclaration du véhicule. La règle
est portée par la base ; le mobile ne fait que l'anticiper pour éviter un rejet tardif à la
synchronisation.

## Stack technique

- Flutter et Dart.
- SDK `supabase_flutter`, en accès direct à la base, sans API intermédiaire.
- Un stockage local (base embarquée) pour la file d'attente hors ligne.

## Synchronisation

Le protocole est arrêté. Il conditionne l'essentiel de l'architecture du client mobile.

L'application **n'écrit jamais sur le serveur au fil de la saisie**. Toute action de
l'utilisateur alimente une **file d'attente locale** persistée sur l'appareil. La remontée
se fait sur **appui d'un bouton explicite** : l'utilisateur sait quand ses données partent,
et le comportement reste identique avec ou sans réseau. La contrepartie assumée est qu'une
saisie non synchronisée n'est visible ni du web ni du comptable.

La séquence est toujours **pull puis push** : on récupère d'abord l'état serveur, puis on
applique la file locale.

Deux traitements distincts selon la nature du frais :

- **Quantités forfaitisées** (repas, nuitées, relais étape, kilométrage) : les lignes
  existent déjà en base, créées à zéro à l'ouverture de la fiche. Le mobile fait donc
  toujours une mise à jour, jamais une insertion, et **écrase** la valeur serveur. En cas
  de saisie concurrente web et mobile, le mobile fait foi. Choix simple à expliquer, au
  prix d'une perte possible de la saisie web la plus récente.
- **Frais hors forfait** : insertion portant un **UUID généré côté client** et stocké dans
  la table. Une remontée rejouée deux fois n'insère donc pas deux lignes : l'idempotence
  est garantie par construction, sans compteur ni horodatage à comparer.

Cas d'un **mois verrouillé**, c'est-à-dire d'une fiche déjà clôturée :

- un frais forfaitisé est **rejeté** par le serveur et **reste dans la file locale**, il
  n'est pas perdu ;
- un frais hors forfait **bascule sur la fiche du mois courant**, en conservant sa date
  d'origine, ce qui permet de retrouver la dépense réelle.

## Initialisation prévue

Commandes à exécuter plus tard, à la phase de développement, depuis la racine du dépôt :

```bash
# À NE PAS EXÉCUTER POUR L'INSTANT
flutter create --org fr.gsb --project-name gsb_mobile mobile
cd mobile && flutter pub add supabase_flutter
```

En salle, penser au proxy HTTP `172.16.63.130:3128` avant tout téléchargement `pub`.
