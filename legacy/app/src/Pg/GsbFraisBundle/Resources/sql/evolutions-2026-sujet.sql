-- ---------------------------------------------------------------------------
-- Évolution 2026, troisième temps : les demandes du sujet (ap-gsb-web.pdf).
--
-- Barème kilométrique indexé sur le véhicule, report d'un frais hors forfait
-- sur le mois suivant, état « Mise en paiement » distinct de « Validée ».
-- Mêmes règles que evolutions-2026.sql : rejouable, sans point-virgule dans
-- les commentaires ni dans les chaînes. Le témoin est l'état MP, inséré en
-- dernier.
-- ---------------------------------------------------------------------------

-- Le barème qui remplace le taux unique de 0,62 € par km (RG16).
CREATE TABLE IF NOT EXISTS baremekm (
  id         CHAR(3)      NOT NULL,
  puissance  VARCHAR(20)  NOT NULL,
  carburant  VARCHAR(10)  NOT NULL,
  tarif      DECIMAL(4,2) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT IGNORE INTO baremekm (id, puissance, carburant, tarif) VALUES
  ('4D',  '4 CV',          'Diesel',  0.52),
  ('56D', '5 ou 6 CV',     'Diesel',  0.58),
  ('7D',  '7 CV et plus',  'Diesel',  0.65),
  ('4E',  '4 CV',          'Essence', 0.62),
  ('56E', '5 ou 6 CV',     'Essence', 0.67),
  ('7E',  '7 CV et plus',  'Essence', 0.72);

-- Les véhicules déclarés par chaque visiteur, historisés (RG17 à RG19).
-- dateFin nulle : le véhicule actuel, un seul par visiteur. Le taux d'un mois
-- est celui du dernier véhicule valide pendant ce mois.
CREATE TABLE IF NOT EXISTS vehicule (
  id          INT      NOT NULL AUTO_INCREMENT,
  idVisiteur  CHAR(4)  NOT NULL,
  idBaremeKm  CHAR(3)  NOT NULL,
  dateDebut   DATE     NOT NULL,
  dateFin     DATE     DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_vehicule_visiteur (idVisiteur, dateDebut),
  CONSTRAINT fk_vehicule_visiteur FOREIGN KEY (idVisiteur) REFERENCES visiteur (id),
  CONSTRAINT fk_vehicule_bareme   FOREIGN KEY (idBaremeKm) REFERENCES baremekm (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Démonstration : deux visiteurs du jeu d'essai ont déclaré leur véhicule
-- au début du mois dernier. Leurs fiches plus anciennes gardent l'ancien taux
-- unique. Pascal Bentot n'a rien déclaré : sa saisie de km est bloquée.
INSERT INTO vehicule (idVisiteur, idBaremeKm, dateDebut)
  SELECT id, '56E', DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') FROM visiteur
  WHERE id = 'a17' AND NOT EXISTS (SELECT 1 FROM vehicule WHERE idVisiteur = 'a17');
INSERT INTO vehicule (idVisiteur, idBaremeKm, dateDebut)
  SELECT id, '7D', DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') FROM visiteur
  WHERE id = 'b13' AND NOT EXISTS (SELECT 1 FROM vehicule WHERE idVisiteur = 'b13');

-- Un frais reporté garde le mois de sa fiche d'origine (RG28, RG29).
ALTER TABLE lignefraishorsforfait ADD COLUMN IF NOT EXISTS moisOrigine CHAR(6) DEFAULT NULL;

-- Cinq états (RG5) : la validation et la mise en paiement sont distinctes.
UPDATE etat SET libelle = 'Validée' WHERE id = 'VA';
INSERT IGNORE INTO etat (id, libelle) VALUES ('MP', 'Mise en paiement')
