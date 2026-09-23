-- ---------------------------------------------------------------------------
-- Évolutions 2026 du schéma de 2013.
--
-- Ce fichier est joué par PdoGsb au premier accès, tant que la table
-- justificatif n'existe pas : une base déjà installée est ainsi mise à niveau
-- sans être recréée. Chaque instruction est rejouable sans dommage.
--
-- Il est découpé sur les points-virgules : pas de point-virgule dans les
-- commentaires ni dans les chaînes.
-- ---------------------------------------------------------------------------

-- Rôle et activation des comptes. Un compte désactivé ne peut plus se
-- connecter ; il n'est pas supprimé, ses fiches y restent rattachées.
ALTER TABLE visiteur ADD COLUMN IF NOT EXISTS role  VARCHAR(15) NOT NULL DEFAULT 'visiteur';
ALTER TABLE visiteur ADD COLUMN IF NOT EXISTS actif TINYINT(1)  NOT NULL DEFAULT 1;

-- Le compte administrateur de démonstration.
INSERT IGNORE INTO visiteur (id, nom, prenom, login, mdp, role, actif)
VALUES ('adm', 'Administrateur', 'GSB', 'admin', 'gsbadmin', 'admin', 1);

-- L'aide affichée sous le « ? » de la saisie, et l'unité de la quantité.
ALTER TABLE fraisforfait ADD COLUMN IF NOT EXISTS description VARCHAR(255) DEFAULT NULL;
ALTER TABLE fraisforfait ADD COLUMN IF NOT EXISTS unite       VARCHAR(20)  DEFAULT NULL;
UPDATE fraisforfait SET unite = 'étape(s)',
  description = 'Une journée de déplacement complète loin de votre secteur habituel. Une étape par journée concernée.'
  WHERE id = 'ETP';
UPDATE fraisforfait SET unite = 'km',
  description = 'Les kilomètres parcourus avec votre véhicule personnel pour un déplacement professionnel.'
  WHERE id = 'KM';
UPDATE fraisforfait SET unite = 'nuitée(s)',
  description = 'Une nuit passée à l''hôtel pendant un déplacement. Une nuitée par nuit.'
  WHERE id = 'NUI';
UPDATE fraisforfait SET unite = 'repas',
  description = 'Un repas pris au restaurant pendant un déplacement. Un repas par service.'
  WHERE id = 'REP';

-- Un frais hors forfait peut être refusé par l'administrateur : il reste
-- visible mais sort du montant validé.
ALTER TABLE lignefraishorsforfait ADD COLUMN IF NOT EXISTS refuse TINYINT(1) NOT NULL DEFAULT 0;

-- Les pièces jointes d'un frais hors forfait. Le fichier est rangé sous un nom
-- aléatoire, hors du dossier web : seul le contrôleur le sert, après contrôle.
CREATE TABLE IF NOT EXISTS justificatif (
  id                   INT          NOT NULL AUTO_INCREMENT,
  idFraisHorsForfait   INT          NOT NULL,
  nomOriginal          VARCHAR(255) NOT NULL,
  nomStocke            VARCHAR(64)  NOT NULL,
  typeMime             VARCHAR(100) NOT NULL,
  taille               INT          NOT NULL,
  dateAjout            DATETIME     NOT NULL,
  PRIMARY KEY (id),
  KEY idx_justificatif_frais (idFraisHorsForfait),
  CONSTRAINT fk_justificatif_frais FOREIGN KEY (idFraisHorsForfait)
      REFERENCES lignefraishorsforfait (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8
