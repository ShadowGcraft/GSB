-- ---------------------------------------------------------------------------
-- Base de l'application GSB de 2013.
--
-- ATTENTION : ce schéma ne figure PAS dans l'archive fournie par l'enseignant.
-- Il est reconstitué à partir des seules requêtes SQL du fichier
-- GsbFraisBundle/services/PdoGsb.php et des champs lus dans les gabarits Twig.
-- Chaque colonne ci-dessous est justifiée par au moins une requête du code.
--
-- Il reproduit le modèle de 2013 tel qu'il était, défauts compris : mot de passe
-- en clair, mois stocké en chaîne, clés primaires composites. Le modèle du
-- nouveau projet est décrit dans docs/modele-donnees.md et n'a rien à voir.
-- ---------------------------------------------------------------------------

SET NAMES utf8;

-- Le visiteur médical.
-- Colonnes prouvées par getInfosVisiteur() : id, nom, prenom, login, mdp.
-- Les autres viennent du jeu de données historique du contexte GSB.
CREATE TABLE visiteur (
  id            CHAR(4)      NOT NULL,
  nom           VARCHAR(30)  NOT NULL,
  prenom        VARCHAR(30)  NOT NULL,
  login         VARCHAR(45)  NOT NULL,
  mdp           VARCHAR(45)  NOT NULL,   -- en clair : comparé tel quel en SQL
  adresse       VARCHAR(30)  DEFAULT NULL,
  cp            CHAR(5)      DEFAULT NULL,
  ville         VARCHAR(30)  DEFAULT NULL,
  dateEmbauche  DATE         DEFAULT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Les états d'une fiche de frais.
-- Prouvée par la jointure de getLesInfosFicheFrais() et le filtre idetat = 'VA'.
CREATE TABLE etat (
  id       CHAR(2)     NOT NULL,
  libelle  VARCHAR(30) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Le référentiel des frais forfaitisés.
-- getLesFraisForfait() lit id et libelle. La colonne montant n'est jamais lue
-- par le code de 2013, mais la fiche papier de l'annexe 1 la suppose : elle est
-- donc présente ici, alimentée, et simplement inexploitée par l'application.
CREATE TABLE fraisforfait (
  id       CHAR(3)       NOT NULL,
  libelle  VARCHAR(20)   NOT NULL,
  montant  DECIMAL(5,2)  NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- La fiche mensuelle.
-- Les six colonnes viennent de l'INSERT de creeNouvellesLignesFrais() :
--   insert into fichefrais(idvisiteur,mois,nbJustificatifs,montantValide,dateModif,idEtat)
-- Le mois est une chaîne aaaamm : le code en extrait l'année et le mois par substr.
CREATE TABLE fichefrais (
  idVisiteur       CHAR(4)         NOT NULL,
  mois             CHAR(6)         NOT NULL,
  nbJustificatifs  INT             DEFAULT 0,
  montantValide    DECIMAL(10,2)   DEFAULT 0.00,
  dateModif        DATE            DEFAULT NULL,
  idEtat           CHAR(2)         NOT NULL DEFAULT 'CR',
  PRIMARY KEY (idVisiteur, mois),
  CONSTRAINT fk_fichefrais_visiteur FOREIGN KEY (idVisiteur) REFERENCES visiteur (id),
  CONSTRAINT fk_fichefrais_etat     FOREIGN KEY (idEtat)     REFERENCES etat (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Une ligne forfaitisée : une quantité par catégorie et par fiche.
-- Le triplet (idVisiteur, mois, idFraisForfait) suffit à désigner une ligne dans
-- le UPDATE de majFraisForfait() : c'est donc la clé primaire.
CREATE TABLE lignefraisforfait (
  idVisiteur      CHAR(4)  NOT NULL,
  mois            CHAR(6)  NOT NULL,
  idFraisForfait  CHAR(3)  NOT NULL,
  quantite        INT      DEFAULT 0,
  PRIMARY KEY (idVisiteur, mois, idFraisForfait),
  CONSTRAINT fk_lff_fiche FOREIGN KEY (idVisiteur, mois)
      REFERENCES fichefrais (idVisiteur, mois) ON DELETE CASCADE,
  CONSTRAINT fk_lff_frais FOREIGN KEY (idFraisForfait) REFERENCES fraisforfait (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Une ligne hors forfait.
-- L'ordre des colonnes est imposé par l'INSERT sans liste de colonnes de
-- creeNouveauFraisHorsForfait() :
--   insert into lignefraishorsforfait values('',:idVisiteur,:mois,:libelle,'date',:montant)
-- L'identifiant technique vient donc en premier, et il est auto-incrémenté.
CREATE TABLE lignefraishorsforfait (
  id          INT           NOT NULL AUTO_INCREMENT,
  idVisiteur  CHAR(4)       NOT NULL,
  mois        CHAR(6)       NOT NULL,
  libelle     VARCHAR(100)  NOT NULL,
  date        DATE          DEFAULT NULL,
  montant     DECIMAL(10,2) DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_lhf_fiche (idVisiteur, mois),
  CONSTRAINT fk_lhf_fiche FOREIGN KEY (idVisiteur, mois)
      REFERENCES fichefrais (idVisiteur, mois) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
