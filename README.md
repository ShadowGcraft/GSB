# GSB - Gestion des frais de mission

Application de suivi des frais de mission des visiteurs médicaux du laboratoire Galaxy Swiss Bourdin.
Le visiteur saisit ses frais au fil de ses déplacements, le comptable les contrôle et déclenche le
remboursement. Le projet réunit une application web Symfony, une application mobile Flutter et une
base de données Supabase partagée par les deux.

---

## Le contexte GSB

Galaxy Swiss Bourdin est un laboratoire pharmaceutique né du rapprochement d'un laboratoire américain
et d'un laboratoire suisse. Son réseau de visiteurs médicaux sillonne le terrain pour présenter les
produits aux praticiens : ces déplacements génèrent en permanence des repas, des nuitées, des étapes
et des kilomètres à rembourser. D'après le cahier des charges fourni (`_sources/ap-gsb-web.pdf`),
l'enveloppe annuelle de ce seul poste approche les 25 millions d'euros, ce qui justifie un suivi précis,
traçable et outillé plutôt qu'un traitement papier. La direction
souhaite donc dématérialiser la fiche de frais mensuelle, du remplissage par le visiteur jusqu'à la
mise en paiement par la comptabilité.

Galaxy Swiss Bourdin est un **contexte pédagogique du réseau CERTA**, utilisé en BTS SIO. Ce n'est pas
un client réel et aucune donnée de ce dépôt ne concerne une entreprise existante.

---

## Ce que fait l'application

- **Saisir ses frais au forfait** : le visiteur renseigne, mois par mois, le nombre de repas de midi,
  de nuitées, d'étapes et de kilomètres parcourus.
- **Saisir ses frais hors forfait** : les dépenses qui n'entrent dans aucune catégorie forfaitaire sont
  déclarées à l'unité, avec leur date, leur libellé, leur montant et leur justificatif.
- **Déclarer son véhicule** : la puissance fiscale et le carburant conditionnent le barème kilométrique
  applicable. Sans véhicule déclaré, la saisie des frais kilométriques est bloquée.
- **Clôturer la fiche du mois** : le visiteur ferme sa fiche et la transmet à la comptabilité.
- **Valider côté comptable** : le comptable consulte les fiches de tous les visiteurs, contrôle les
  montants et les justificatifs, refuse le cas échéant certains frais hors forfait, puis valide la fiche.
- **Suivre le remboursement** : la fiche parcourt cinq états et quatre transitions, sans retour en
  arrière : créée, clôturée, validée, mise en paiement, remboursée.
- **Consulter l'historique** : chaque visiteur retrouve ses fiches des mois précédents en lecture seule.

### Refus d'un frais hors forfait

Le refus d'une ligne par le comptable est une **suppression logique** : la ligne reste en base avec le
statut « refusé », disparaît de la vue du visiteur et n'entre plus dans les totaux. **Aucun motif n'est
enregistré**, conformément au cahier des charges, qui précise que la raison du refus n'est pas conservée.
La contrepartie assumée est que le visiteur constate le refus sans en connaître la raison par
l'application : l'échange se fait hors outil, comme aujourd'hui par téléphone. La ligne conservée garde
la trace du contrôle, ce qu'une suppression physique ferait perdre.

Le détail des règles de gestion, des états de la fiche et des cas limites est décrit dans
`docs/cahier-des-charges.md`. *Ce document n'est pas encore rédigé, il arrive à la phase suivante.*

---

## Montants applicables

| Catégorie | Code | Montant unitaire | Statut |
| --- | --- | --- | --- |
| Repas de midi | REP | 29,00 € | Hypothèse, à confirmer auprès du client |
| Nuitée, hôtel seul | NUI | 80,00 € | Hypothèse, à confirmer auprès du client |
| Relais étape, nuit et repas | ETP | 110,00 € | Hypothèse, à confirmer auprès du client |
| Kilométrage | KM | Voir le barème ci-dessous | Imposé par le cahier des charges |

Barème kilométrique, en euros par kilomètre, indexé sur la puissance fiscale et le carburant du véhicule
déclaré par le visiteur :

| Puissance fiscale | Diesel | Essence |
| --- | --- | --- |
| 4 CV | 0,52 | 0,62 |
| 5 à 6 CV | 0,58 | 0,67 |
| 7 CV et plus | 0,65 | 0,72 |

Le contexte historique appliquait un taux unique de 0,62 € par kilomètre, sans distinction de véhicule.
Les trois montants forfaitaires ci-dessus sont une **hypothèse de travail** reprise du jeu de données
historique du contexte GSB : le cahier des charges ne les donne pas. Ils seront confirmés auprès du
client avant tout développement du calcul.

---

## Stack technique

| Brique | Technologie | Rôle |
| --- | --- | --- |
| Application web | Symfony 7 (PHP 8.3+), Twig | Interface des visiteurs et des comptables, poste de travail |
| Application mobile | Flutter (Dart) | Saisie au fil de l'eau par le visiteur, sur le terrain |
| Base de données | PostgreSQL hébergé par Supabase | Base unique et partagée par les deux clients, siège des règles métier |
| Authentification | Supabase Auth | Comptes et jetons communs au web et au mobile |
| Stockage de fichiers | Supabase Storage | Justificatifs (photos et scans de factures) |
| Accès aux données côté web | Doctrine ORM | Mappage objet-relationnel au-dessus du même PostgreSQL |
| Accès aux données côté mobile | SDK `supabase_flutter` | Accès direct à Supabase, sans API intermédiaire |

---

## Pourquoi Supabase plutôt que Firebase

Le choix de la base est le choix structurant du projet. Il a été arbitré en faveur de Supabase, donc de
PostgreSQL, pour cinq raisons.

**1. Le modèle de données est fortement relationnel.** Une fiche mensuelle porte des lignes forfaitisées
rattachées à un référentiel de catégories, des lignes hors forfait, et un barème kilométrique indexé sur
le véhicule du visiteur. Firestore est un magasin de documents : ce modèle s'y traduit mal, soit par
duplication du référentiel dans chaque document, soit par une dénormalisation qu'il faudrait ensuite
maintenir à la main.

**2. Les contraintes d'intégrité sont vérifiées par le moteur.** Les clés étrangères, l'unicité d'une
fiche par visiteur et par mois, les types numériques exacts pour les montants s'expriment directement en
PostgreSQL et sont garantis quelle que soit l'application qui écrit. Firestore ne connaît pas ces
contraintes : il aurait fallu les réimplémenter dans chaque client, donc deux fois, avec le risque de
divergence que cela suppose.

**3. Les deux clients tapent la même base, sans couche de traduction.** Symfony passe par Doctrine, qui
parle SQL. Avec PostgreSQL, le web et le mobile lisent et écrivent les mêmes tables. Avec Firebase, il
aurait fallu soit une seconde base pour le web, soit une API intermédiaire chargée de faire le pont :
dans les deux cas, deux modèles de données à maintenir en cohérence.

**4. Le sujet est au programme du BTS SIO.** SQL, le modèle relationnel et la normalisation font partie
des compétences évaluées. Le projet doit pouvoir être défendu sur ce terrain à l'oral, ce qu'une base
documentaire rendrait plus difficile.

**5. Row Level Security.** Les règles d'accès (un visiteur ne voit que ses fiches, le comptable lit tout
et n'écrit que sur les fiches clôturées, une fiche validée est immuable) sont écrites une seule fois,
dans la base, et s'appliquent à l'identique au web et au mobile.

### Contrepartie assumée

Supabase est moins outillé que Firebase sur le fonctionnement hors ligne : Firestore fournit un cache
local et une synchronisation automatique, là où Supabase ne propose rien d'équivalent. La file d'attente
locale du mobile et son bouton de synchronisation explicite sont donc entièrement à notre charge, ce qui
représente une part non négligeable du développement Flutter. Par ailleurs, l'écosystème Flutter de
Firebase est plus mature et mieux documenté. Nous acceptons ce coût parce que la qualité du modèle de
données et l'unicité de la base pèsent davantage sur ce projet.

---

## Pourquoi Flutter attaque Supabase en direct

Aucune API intermédiaire n'est développée. L'application Flutter interroge Supabase directement via le
SDK `supabase_flutter`, exactement comme Symfony interroge PostgreSQL via Doctrine.

- **Pas de troisième application.** Une API maison serait un projet supplémentaire à écrire, à déployer,
  à sécuriser et à maintenir, pour une valeur ajoutée faible sur un périmètre de cette taille.
- **La sécurité repose sur les politiques RLS.** Elles sont évaluées par la base pour tout appelant, quel
  qu'il soit. Un client mobile compromis ne peut pas lire ou écrire ce que la politique lui interdit.
- **L'authentification est déjà commune.** Supabase Auth délivre un jeton exploité indifféremment par le
  web et par le mobile : il n'y a pas de session à réinventer côté API.

### Contrepartie assumée

Puisque le mobile parle à la base sans passer par Symfony, **les règles métier ne peuvent pas vivre
uniquement dans un contrôleur Symfony** : le mobile les contournerait purement et simplement. Tout ce qui
constitue un invariant métier doit descendre dans la base, sous forme de contraintes, de déclencheurs
(triggers) et de politiques RLS. L'immuabilité d'une fiche validée, le blocage des frais kilométriques en
l'absence de véhicule ou le calcul des montants à partir du barème appartiennent au schéma, pas au code
applicatif. C'est une contrainte de conception permanente, pas un détail d'implémentation : le code
Symfony et le code Flutter ne font que présenter et confirmer des règles que la base impose déjà.

---

## Organisation du dépôt

```text
GSB/
├── web/          Application Symfony 7 : interface visiteur et comptable (à venir)
├── mobile/       Application Flutter : saisie au fil de l'eau (à venir)
├── supabase/     Schéma de la base : migrations SQL, politiques RLS, jeu de données de test
│   └── migrations/
├── docs/         Documentation du projet : cahier des charges, modèle de données, livrables
│   └── assets/   Images et diagrammes utilisés par la documentation
├── _sources/     Sujet et documents fournis par l'enseignant (lecture seule)
├── .gitignore    Règles d'exclusion commentées, communes aux trois briques
├── CONTRIBUTING.md  Conventions de travail à deux
└── README.md
```

Le dépôt est un **monorepo** : les trois briques vivent dans un seul historique Git. La raison est que le
contrat entre elles n'est pas une API, c'est le schéma de la base. Une migration qui casse le mobile doit
être visible dans le même commit que la correction du mobile, sinon la régression n'apparaît qu'à
l'exécution, chez l'autre étudiant. À deux, avec un seul historique et une seule liste d'issues, la
coordination est immédiate et l'état du projet reste lisible d'un seul coup d'œil.

*Contrepartie :* l'outillage est hétérogène dans un même dépôt. Composer pour le web, Flutter et pub pour
le mobile, la CLI Supabase pour la base : trois gestionnaires de dépendances, un `.gitignore` unique qui
doit couvrir les trois écosystèmes, et pas d'outil de build commun. Sur un projet de cette taille, la
friction reste inférieure au coût de synchronisation de trois dépôts séparés.

Le dossier `_sources/` reste versionné, malgré ses quelque 16 Mo. C'est le dossier de sujet : cahier des
charges, annexes, supports fournis par l'enseignant. Un projet évalué gagne à embarquer ses sources, pour
rester lisible et vérifiable plusieurs mois après sa réalisation, sans dépendre d'un lien ou d'un espace
de cours qui aura disparu.

---

## Prérequis

Les versions ci-dessous sont des ordres de grandeur, pas des exigences testées. Elles seront figées ici
une fois l'environnement de chacun installé et relevé sur nos deux postes.

| Outil | Version | Vérification |
| --- | --- | --- |
| PHP | 8.3 minimum, exigé par Symfony 7 | `php -v` |
| Composer | 2.x | `composer --version` |
| Symfony CLI | dernière version | `symfony version` |
| Flutter SDK | canal `stable` | `flutter --version` |
| Dart SDK | fourni avec Flutter | `dart --version` |
| CLI Supabase | 2.x | `supabase --version` |
| Docker Desktop | requis par Supabase en local | `docker --version` |
| Git | 2.x | `git --version` |

Un diagnostic complet de l'installation Flutter est disponible avec `flutter doctor`.

---

## Démarrage

> À ce stade du projet, seul le schéma de la base est en cours de construction. Les répertoires `web/` et
> `mobile/` ne contiennent pas encore de code : ils seront initialisés à la phase suivante et cette
> section sera complétée à ce moment-là.

### Base de données

Supabase peut tourner en local, dans des conteneurs Docker, ce qui évite de travailler directement sur
l'instance partagée. Les commandes ci-dessous sont celles de la CLI Supabase.

```bash
# Créer supabase/config.toml, une seule fois pour le dépôt
supabase init

# Démarrer l'instance locale (PostgreSQL, Auth, Storage, Studio)
supabase start

# Appliquer les migrations en attente sur l'instance LOCALE
supabase migration up

# Recréer la base LOCALE à vide, rejouer toutes les migrations puis seed.sql
supabase db reset

# Afficher l'état des services et les URL locales
supabase status

# Arrêter l'instance
supabase stop
```

> **`supabase db push` n'est pas une commande locale.** Elle pousse les migrations vers le projet
> Supabase distant lié par `supabase link`, c'est-à-dire la base partagée. Ne l'utiliser que
> délibérément, jamais pour tester.

> **À vérifier au premier usage.** Ces commandes n'ont pas encore été exécutées sur le projet. Elles
> correspondent à l'usage courant de la CLI Supabase mais peuvent différer selon la version installée, et
> `supabase db reset` recrée la base à vide : ne jamais l'utiliser sur autre chose qu'une instance locale.
> La procédure définitive sera écrite ici une fois la première migration appliquée pour de bon.

### Application web (Symfony)

Le projet Symfony n'est pas encore initialisé. La procédure d'installation (`composer install`,
configuration de `DATABASE_URL` vers PostgreSQL, `symfony serve`) sera documentée ici à la création du
squelette.

### Application mobile (Flutter)

Le projet Flutter n'est pas encore initialisé. La procédure (`flutter pub get`, renseignement de l'URL et
de la clé publique Supabase, `flutter run`) sera documentée ici à la création du squelette.

---

## Travailler derrière le proxy de la salle

En salle, l'accès à Internet passe par un proxy HTTP : **172.16.63.130**, port **3128**. Sans
configuration, les téléchargements de Composer, de pub et de Git n'aboutissent pas : selon l'outil, la
commande expire au bout de plusieurs dizaines de secondes ou renvoie une erreur réseau peu explicite.

Variables d'environnement, à poser dans la session du terminal :

```bash
export http_proxy="http://172.16.63.130:3128"
export https_proxy="http://172.16.63.130:3128"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export no_proxy="localhost,127.0.0.1"
```

Git :

```bash
git config --global http.proxy http://172.16.63.130:3128
git config --global https.proxy http://172.16.63.130:3128
```

Composer (Composer lit les variables `http_proxy` et `https_proxy` ci-dessus, aucun réglage
supplémentaire n'est nécessaire) :

```bash
# Vérifier que Composer atteint bien le réseau
composer diagnose
```

npm (utilisé par Symfony pour les assets, le cas échéant) :

```bash
npm config set proxy http://172.16.63.130:3128
npm config set https-proxy http://172.16.63.130:3128
```

Dart et Flutter (les outils Dart s'appuient sur les mêmes variables d'environnement) :

```bash
# À poser avant flutter pub get / flutter run
export http_proxy="http://172.16.63.130:3128"
export https_proxy="http://172.16.63.130:3128"
export no_proxy="localhost,127.0.0.1"
```

**Ces réglages ne valent qu'en salle.** À la maison ou en connexion personnelle, ils empêchent tout accès
réseau et doivent être retirés :

```bash
git config --global --unset http.proxy
git config --global --unset https.proxy
npm config delete proxy
npm config delete https-proxy
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy
```

---

## Documentation

| Document | Emplacement | État |
| --- | --- | --- |
| Cahier des charges | `docs/cahier-des-charges.md` | À venir |
| Modèle de données | `docs/modele-donnees.md` | À venir |
| Diagramme de Gantt | `docs/gantt.md` | À venir |
| Notice utilisateur | `docs/notice-utilisateur.md` | À venir |
| Charte graphique | `docs/charte-graphique.md` | À venir |
| Maquettage | `docs/maquettage.md` | À venir |
| Sujet et annexes fournis | `_sources/` | Fourni par l'enseignant |

---

## Équipe

Projet réalisé par **Louis** et **Romain**, étudiants en deuxième année de BTS SIO, option SLAM, dans le
cadre de l'atelier de professionnalisation.

Les conventions de travail (branches, messages de commit, revue croisée, répartition des tâches) sont
décrites dans [`CONTRIBUTING.md`](CONTRIBUTING.md).
