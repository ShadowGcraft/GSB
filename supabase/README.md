# Base de données et sécurité

Pour la présentation générale du projet GSB et les décisions communes aux deux clients,
se reporter au README à la racine du dépôt.

## Contenu prévu du dossier

Aucun de ces fichiers n'est encore écrit. Le dossier ne contient pour l'instant que
`migrations/` et son `.gitkeep`.

- `migrations/` : les migrations SQL numérotées (tables, contraintes, déclencheurs,
  politiques RLS, buckets de stockage). *Dossier créé, vide.*
- `seed.sql` : le jeu de données de démonstration (visiteurs, véhicules, fiches d'exemple).
  *À venir.*
- `config.toml` : la configuration de la CLI Supabase pour l'instance locale, généré par
  `supabase init`. *À venir.*

## Pourquoi le schéma est le contrat du projet

Les deux applications, web Symfony et mobile Flutter, attaquent **la même base**. Le mobile
y écrit même en direct, sans API intermédiaire. Le schéma n'est donc pas un détail
d'implémentation : c'est le **contrat partagé** entre les deux clients. Une colonne renommée
ici casse les deux applications en même temps.

Règle de travail, sans exception :

> Toute évolution du schéma passe par une migration versionnée dans ce dossier.
> Jamais par une modification manuelle depuis l'interface Supabase.

Une modification faite à la souris dans l'interface n'est écrite nulle part : elle n'est pas
dans Git, l'autre développeur ne l'a pas, et elle sera perdue à la prochaine réinitialisation.
Si une manipulation a été faite dans l'interface pour essayer quelque chose, elle doit être
réécrite en migration avant d'être considérée comme acquise.

## Convention de nommage des migrations

Un numéro sur quatre chiffres, un tiret bas, un intitulé court en `snake_case` :

```
0001_init.sql
0002_vehicules.sql
0003_lignes_frais.sql
0004_rls_visiteur.sql
```

Le numéro donne l'ordre d'application, qui est aussi l'ordre de lecture. Une migration
**n'est jamais modifiée** une fois appliquée et poussée sur le dépôt : la base de l'autre
développeur l'a déjà exécutée et ne la rejouera pas. Pour corriger, on ajoute une nouvelle
migration.

La commande `supabase migration new` préfixe les fichiers d'un horodatage complet, du type
`20260902141530_init.sql`. Nous lui préférons la numérotation courte, plus lisible dans un
dossier de documentation destiné à être lu par un correcteur. La CLI applique les fichiers
dans l'ordre alphabétique du nom : les deux conventions fonctionnent, mais **il ne faut pas
les mélanger** dans un même dossier, sous peine d'un ordre d'application imprévisible.
Les migrations de ce projet sont donc créées à la main, pas par `supabase migration new`.

## Row Level Security

Le modèle de sécurité arrêté repose sur le RLS PostgreSQL, activé sur toutes les tables
métier. Il s'applique aux deux clients, puisque le mobile parle directement à la base.

- **Visiteur** : ne lit et n'écrit que ses propres fiches et ses propres lignes de frais.
- **Comptable** : lit toutes les fiches de tous les visiteurs, mais n'écrit que sur les
  fiches à l'état « clôturée ».
- **Immuabilité** : une fiche validée, mise en paiement ou remboursée n'est modifiable par
  personne, ni visiteur, ni comptable.

Le cycle de vie compte cinq états et quatre transitions linéaires, sans retour arrière :
créée, clôturée, validée, mise en paiement, remboursée.

## Commandes utiles

Commandes de la CLI Supabase, **à vérifier au premier usage** : la syntaxe dépend de la
version installée.

```bash
supabase init          # créer config.toml, une seule fois pour le dépôt
supabase start         # démarrer l'instance locale (Docker)
supabase migration up  # appliquer les migrations en attente sur l'instance LOCALE
supabase db reset      # recréer la base LOCALE à vide, rejouer les migrations puis seed.sql
supabase status        # afficher les URL et les clés de l'instance locale
supabase stop          # arrêter l'instance locale
```

> **Attention à `supabase db push`.** Malgré son nom, ce n'est pas une commande locale : elle
> pousse les migrations vers le projet Supabase **distant** lié par `supabase link`, donc vers
> la base partagée. Pour travailler en local, `supabase migration up` ou `supabase db reset`.

En salle, penser au proxy HTTP `172.16.63.130:3128` avant `supabase start` : la commande
télécharge plusieurs images Docker. Docker Desktop ne lit pas les variables `http_proxy` du
terminal, le proxy se règle dans ses préférences, section Resources puis Proxies. Voir le
README à la racine, section « Travailler derrière le proxy de la salle ».

## État

Aucune migration n'est encore écrite. Elles seront produites avec le modèle de données, une
fois celui-ci validé et figé dans `docs/modele-donnees.md`.
