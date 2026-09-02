-- ---------------------------------------------------------------------------
-- Jeu d'essai de l'application de 2013.
--
-- L'archive ne fournit aucune donnée : le cahier des charges mentionne bien un
-- « script de génération de données aléatoires » parmi les travaux du
-- prédécesseur, mais ce script n'est pas dans l'archive. Les données ci-dessous
-- sont donc construites pour la démonstration.
--
-- Les montants forfaitaires reprennent les valeurs de travail du projet, qui
-- sont une hypothèse : le cahier des charges ne donne aucun barème. Voir A1
-- dans docs/cahier-des-charges.md.
-- ---------------------------------------------------------------------------

-- Les quatre états du cycle de vie décrit par le cahier des charges.
-- Le code de 2013 n'en pose que deux, CR et CL, et sait lire VA.
INSERT INTO etat (id, libelle) VALUES
  ('CR', 'Fiche créée, saisie en cours'),
  ('CL', 'Saisie clôturée'),
  ('VA', 'Validée et mise en paiement'),
  ('RB', 'Remboursée');

-- Les quatre catégories de frais forfaitisés.
-- Le libellé du kilométrage est « Frais Kilométrique » dans le contexte
-- historique ; la fiche papier de l'annexe 1 l'appelle « Véhicule ».
INSERT INTO fraisforfait (id, libelle, montant) VALUES
  ('ETP', 'Forfait Étape',      110.00),
  ('KM',  'Frais Kilométrique',   0.62),
  ('NUI', 'Nuitée Hôtel',        80.00),
  ('REP', 'Repas Restaurant',    29.00);

-- Trois visiteurs. Le mot de passe est en clair, comme dans le modèle d'origine.
INSERT INTO visiteur (id, nom, prenom, login, mdp, adresse, cp, ville, dateEmbauche) VALUES
  ('a17', 'Andre',   'David',   'dandre',   'oppg5', '1 rue Petit',         '25000', 'Besançon',  '2000-11-13'),
  ('b13', 'Bedos',   'Christian','cbedos',  'gvide', '3 rue des Lilas',     '69000', 'Lyon',      '1998-05-05'),
  ('b19', 'Bentot',  'Pascal',  'pbentot',  'doypa', '5 avenue de la Gare', '75011', 'Paris',     '2001-03-25');

-- ---------------------------------------------------------------------------
-- Les fiches de frais.
-- Le mois est une chaîne aaaamm. Les mois sont calculés à partir de la date du
-- jour pour que l'application, qui ne travaille que sur le mois courant, trouve
-- toujours des données à afficher.
-- ---------------------------------------------------------------------------

SET @m0 = DATE_FORMAT(CURDATE(), '%Y%m');                              -- mois courant
SET @m1 = DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y%m');           -- mois précédent
SET @m2 = DATE_FORMAT(CURDATE() - INTERVAL 2 MONTH, '%Y%m');
SET @m3 = DATE_FORMAT(CURDATE() - INTERVAL 3 MONTH, '%Y%m');

-- David André : trois fiches closes ou validées, plus le mois courant ouvert.
INSERT INTO fichefrais (idVisiteur, mois, nbJustificatifs, montantValide, dateModif, idEtat) VALUES
  ('a17', @m3, 4, 1256.30, CURDATE() - INTERVAL 80 DAY, 'RB'),
  ('a17', @m2, 2,  874.50, CURDATE() - INTERVAL 50 DAY, 'VA'),
  ('a17', @m1, 3,    0.00, CURDATE() - INTERVAL 20 DAY, 'CL'),
  ('a17', @m0, 0,    0.00, CURDATE(),                   'CR');

INSERT INTO fichefrais (idVisiteur, mois, nbJustificatifs, montantValide, dateModif, idEtat) VALUES
  ('b13', @m2, 1,  642.00, CURDATE() - INTERVAL 45 DAY, 'VA'),
  ('b13', @m1, 2,    0.00, CURDATE() - INTERVAL 18 DAY, 'CL'),
  ('b13', @m0, 0,    0.00, CURDATE(),                   'CR');

INSERT INTO fichefrais (idVisiteur, mois, nbJustificatifs, montantValide, dateModif, idEtat) VALUES
  ('b19', @m1, 0,    0.00, CURDATE() - INTERVAL 15 DAY, 'CL');

-- Les lignes forfaitisées. L'application en crée une par catégorie à
-- l'ouverture d'une fiche : le jeu d'essai fait de même, y compris à zéro.
INSERT INTO lignefraisforfait (idVisiteur, mois, idFraisForfait, quantite) VALUES
  ('a17', @m3, 'ETP', 2), ('a17', @m3, 'KM', 780), ('a17', @m3, 'NUI', 5), ('a17', @m3, 'REP', 14),
  ('a17', @m2, 'ETP', 1), ('a17', @m2, 'KM', 520), ('a17', @m2, 'NUI', 3), ('a17', @m2, 'REP', 11),
  ('a17', @m1, 'ETP', 3), ('a17', @m1, 'KM', 910), ('a17', @m1, 'NUI', 6), ('a17', @m1, 'REP', 16),
  ('a17', @m0, 'ETP', 0), ('a17', @m0, 'KM',   0), ('a17', @m0, 'NUI', 0), ('a17', @m0, 'REP',  0),
  ('b13', @m2, 'ETP', 0), ('b13', @m2, 'KM', 340), ('b13', @m2, 'NUI', 2), ('b13', @m2, 'REP',  9),
  ('b13', @m1, 'ETP', 1), ('b13', @m1, 'KM', 615), ('b13', @m1, 'NUI', 4), ('b13', @m1, 'REP', 12),
  ('b13', @m0, 'ETP', 0), ('b13', @m0, 'KM',   0), ('b13', @m0, 'NUI', 0), ('b13', @m0, 'REP',  0),
  ('b19', @m1, 'ETP', 0), ('b19', @m1, 'KM', 155), ('b19', @m1, 'NUI', 1), ('b19', @m1, 'REP',  4);

-- Les lignes hors forfait, avec une date d'engagement dans le mois de la fiche.
INSERT INTO lignefraishorsforfait (idVisiteur, mois, libelle, date, montant) VALUES
  ('a17', @m3, 'Repas de représentation, congrès de Dijon', LAST_DAY(CURDATE() - INTERVAL 3 MONTH) - INTERVAL 12 DAY, 156.00),
  ('a17', @m3, 'Location de salle, présentation MediLog',   LAST_DAY(CURDATE() - INTERVAL 3 MONTH) - INTERVAL 5 DAY,  320.00),
  ('a17', @m2, 'Achat fleuriste, soirée partenaires',       LAST_DAY(CURDATE() - INTERVAL 2 MONTH) - INTERVAL 9 DAY,  120.30),
  ('a17', @m1, 'Fournitures pour animation en pharmacie',   LAST_DAY(CURDATE() - INTERVAL 1 MONTH) - INTERVAL 14 DAY,  87.90),
  ('a17', @m1, 'Repas avec un spécialiste, hôpital Nord',   LAST_DAY(CURDATE() - INTERVAL 1 MONTH) - INTERVAL 3 DAY,   64.50),
  ('b13', @m2, 'Parking, colloque de cardiologie',          LAST_DAY(CURDATE() - INTERVAL 2 MONTH) - INTERVAL 7 DAY,   28.00),
  ('b13', @m1, 'Impression de documentation produit',       LAST_DAY(CURDATE() - INTERVAL 1 MONTH) - INTERVAL 11 DAY, 142.75);
