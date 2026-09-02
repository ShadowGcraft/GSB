# Application web Symfony

Pour la présentation générale du projet GSB, l'architecture d'ensemble et les décisions
communes aux deux clients, se reporter au README à la racine du dépôt.

## Statut

Dossier vide. L'application n'est pas encore initialisée : le squelette Symfony sera créé
à la phase de développement, une fois le modèle de données figé et les migrations écrites.
Seul un fichier `.gitkeep` occupe le dossier pour le conserver dans Git.

## À qui s'adresse cette application

Deux profils d'utilisateurs, avec des usages nettement différents :

- Les **visiteurs médicaux**, pour saisir leurs frais au poste de travail et consulter
  l'historique de leurs fiches mensuelles.
- Les **comptables**, pour contrôler les fiches clôturées, les valider, les mettre en
  paiement et éditer le document PDF de remboursement.

Le module comptable n'existe pas dans le contexte historique de GSB : c'est une demande
nouvelle du client. Il n'a donc aucun équivalent fonctionnel à reprendre, et ses écrans
sont à concevoir intégralement.

## Périmètre fonctionnel attendu

- Authentification commune aux deux clients, adossée à Supabase Auth.
- Saisie et modification des quantités forfaitisées (repas, nuitées, relais étape, kilométrage).
- Saisie, consultation et retrait de ses propres frais hors forfait par le visiteur, avec
  dépôt du justificatif. Ce retrait par le visiteur est une suppression réelle, à distinguer
  du refus par le comptable, qui est une suppression logique.
- Déclaration et historisation des véhicules du visiteur (puissance fiscale, carburant, dates).
- Consultation des fiches mensuelles et de leurs totaux.
- Côté comptable : liste de toutes les fiches, contrôle ligne à ligne, refus d'un frais hors
  forfait, suivi des transitions d'état et édition du PDF de remboursement.

## Stack technique

Symfony 7, PHP 8.3 ou supérieur, Twig, Doctrine ORM sur la base PostgreSQL de Supabase,
Supabase Auth pour l'authentification et Supabase Storage pour les justificatifs. Le détail
et la justification de ces choix sont dans le README à la racine, section « Stack technique ».

Le support Symfony 2 de 2013 fourni dans `/_sources` exclut Doctrine. Ce document ne sert
que de référence fonctionnelle et n'a aucune autorité sur nos choix techniques.

## Points d'attention

L'application mobile écrit **directement** dans la base, via le SDK `supabase_flutter`,
sans passer par Symfony. Il en découle une contrainte structurante :

> Aucune règle métier ne doit reposer uniquement sur un contrôleur Symfony.

Tout invariant qui protège la cohérence des données descend dans la base : contraintes
d'intégrité, contraintes de vérification, déclencheurs et politiques RLS. Une règle écrite
seulement en PHP serait contournée par le mobile sans que personne s'en aperçoive.

La répartition assumée est la suivante : **Symfony valide pour l'ergonomie**, afin d'afficher
un message d'erreur clair et immédiat à l'utilisateur ; **la base valide pour la sûreté**,
comme dernier rempart. La double validation est une redondance volontaire, pas un oubli.

### États de la fiche

Cinq états, quatre transitions linéaires, aucun retour en arrière : créée, clôturée, validée,
mise en paiement, remboursée. Le comptable n'écrit que sur les fiches à l'état « clôturée ».
Dès qu'une fiche est validée, elle est **immuable pour tout le monde**, comptable compris :
l'interface n'affiche plus de formulaire, et la base refuse l'écriture même si l'interface se
trompait. Le cahier des charges ne prévoit aucune correction après validation ; ce point est
à confirmer auprès du client.

## Initialisation prévue

Commandes à exécuter plus tard, à la phase de développement. Le dossier `web/` contient déjà
un `.gitkeep` et le Symfony CLI refuse de créer un projet dans un dossier non vide : on crée
donc le squelette à côté, puis on rapatrie son contenu.

```bash
# À NE PAS EXÉCUTER POUR L'INSTANT
symfony new web-tmp --webapp        # --webapp installe Twig, Doctrine et le reste
rsync -a web-tmp/ web/ && rm -rf web-tmp
```

En salle, penser au proxy HTTP `172.16.63.130:3128` avant tout téléchargement Composer.
