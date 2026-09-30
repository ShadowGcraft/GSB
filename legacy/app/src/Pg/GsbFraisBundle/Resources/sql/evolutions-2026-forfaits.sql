-- ---------------------------------------------------------------------------
-- Évolution 2026, quatrième temps : un référentiel des forfaits plus lisible.
--
-- Les quatre forfaits reprennent les termes exacts du sujet : repas midi,
-- relais étape (nuit plus repas), nuitée (hôtel seul), kilométrage. Ils sont
-- rangés par thème pour la saisie. Leur montant reste fixé par le laboratoire :
-- une dépense au prix variable, comme un repas du soir ou un parking, se
-- déclare hors forfait avec sa facture.
--
-- Mêmes règles que evolutions-2026.sql : rejouable, sans point-virgule dans
-- les commentaires ni dans les chaînes. Le témoin est le libellé du
-- kilométrage, mis à jour en dernier.
-- ---------------------------------------------------------------------------

ALTER TABLE fraisforfait MODIFY libelle VARCHAR(40) NOT NULL;
ALTER TABLE fraisforfait ADD COLUMN IF NOT EXISTS groupe VARCHAR(20) NOT NULL DEFAULT 'Autres';
ALTER TABLE fraisforfait ADD COLUMN IF NOT EXISTS ordre  TINYINT     NOT NULL DEFAULT 99;

UPDATE fraisforfait SET libelle = 'Repas de midi', groupe = 'Repas', ordre = 1, unite = 'repas',
  description = 'Le déjeuner pris au restaurant pendant une journée de tournée. Un repas par midi.'
  WHERE id = 'REP';
UPDATE fraisforfait SET libelle = 'Nuitée (hôtel seul)', groupe = 'Hébergement', ordre = 2, unite = 'nuitée(s)',
  description = 'Une nuit d''hôtel sans repas, pendant un déplacement. Une nuitée par nuit.'
  WHERE id = 'NUI';
UPDATE fraisforfait SET libelle = 'Relais étape', groupe = 'Hébergement', ordre = 3, unite = 'étape(s)',
  description = 'La nuit d''hôtel avec le repas du soir, en un seul forfait. Une étape par nuit.'
  WHERE id = 'ETP';
UPDATE fraisforfait SET libelle = 'Kilométrage', groupe = 'Déplacements', ordre = 4, unite = 'km',
  description = 'Les kilomètres parcourus avec votre véhicule personnel pour un déplacement professionnel. Le tarif dépend du véhicule déclaré.'
  WHERE id = 'KM'
