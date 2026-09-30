-- ---------------------------------------------------------------------------
-- Évolution 2026, cinquième temps : les catégories des frais hors forfait.
--
-- Comme dans les applications de notes de frais, le visiteur choisit la
-- catégorie de sa dépense dans une liste rangée par thème, puis saisit le prix
-- payé et joint sa facture. Les forfaits du sujet n'y figurent pas (repas de
-- midi, nuitée, relais étape, kilométrage), ni les péages, couverts par le
-- badge télépéage (RG22).
--
-- Mêmes règles que evolutions-2026.sql : rejouable, sans point-virgule dans
-- les commentaires ni dans les chaînes. Le témoin est la clé étrangère, posée
-- en dernier.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS categoriehorsforfait (
  id       CHAR(3)      NOT NULL,
  libelle  VARCHAR(40)  NOT NULL,
  groupe   VARCHAR(30)  NOT NULL,
  ordre    TINYINT      NOT NULL,
  exemple  VARCHAR(80)  DEFAULT NULL,
  motscles VARCHAR(120) DEFAULT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- motscles : les mots qu'un visiteur taperait dans la recherche de la grille.
INSERT IGNORE INTO categoriehorsforfait (id, libelle, groupe, ordre, exemple, motscles) VALUES
  ('TRA', 'Train',                        'Transport',              1, 'Ex. : Paris - Lyon, aller-retour',              'sncf tgv ter billet gare'),
  ('AVI', 'Avion',                        'Transport',              2, 'Ex. : Lyon - Nice',                             'vol aeroport billet'),
  ('TAX', 'Taxi, VTC',                    'Transport',              3, 'Ex. : gare - hôpital Nord',                     'uber course chauffeur'),
  ('TEC', 'Transport en commun',          'Transport',              4, 'Ex. : carnet de tickets de métro',              'metro bus tram rer ticket'),
  ('LOC', 'Location de véhicule',         'Transport',              5, 'Ex. : 2 jours, agence de la gare',              'voiture auto loueur'),
  ('CAR', 'Carburant (véhicule loué)',    'Transport',              6, 'Ex. : plein avant restitution',                 'essence gazole gasoil plein station'),
  ('PAR', 'Parking',                      'Transport',              7, 'Ex. : parking du CHU, journée',                 'stationnement horodateur garer'),
  ('VEL', 'Vélo, trottinette',            'Transport',              8, 'Ex. : vélo en libre-service',                   'velib velo trottinette'),
  ('DIN', 'Repas du soir',                'Repas',                  9, 'Ex. : dîner sans nuit d''hôtel',                'diner restaurant soir'),
  ('PDJ', 'Petit-déjeuner',               'Repas',                 10, 'Ex. : petit-déjeuner non compris à l''hôtel',   'cafe croissant matin'),
  ('INV', 'Repas avec un praticien',      'Repas',                 11, 'Ex. : présentation du produit au Dr Martin',    'medecin docteur client invitation restaurant'),
  ('COL', 'Collation, boissons',          'Repas',                 12, 'Ex. : pause café pendant l''animation',         'cafe boisson eau snack'),
  ('SAL', 'Location de salle',            'Animations et congrès', 13, 'Ex. : salle de conférence, soirée partenaires', 'conference seminaire reunion'),
  ('TRT', 'Traiteur, buffet',             'Animations et congrès', 14, 'Ex. : buffet pour 20 personnes',                'repas groupe cocktail'),
  ('FAN', 'Fournitures d''animation',     'Animations et congrès', 15, 'Ex. : kakémono, supports de présentation',      'kakemono stand materiel'),
  ('FLE', 'Fleurs, décoration',           'Animations et congrès', 16, 'Ex. : fleuriste, soirée partenaires',           'fleuriste bouquet'),
  ('CON', 'Congrès, salon',               'Animations et congrès', 17, 'Ex. : inscription au congrès de cardiologie',   'colloque symposium inscription'),
  ('FOU', 'Fournitures de bureau',        'Bureau',                18, 'Ex. : cahiers, stylos',                         'stylo cahier papeterie'),
  ('IMP', 'Impression, reprographie',     'Bureau',                19, 'Ex. : 200 plaquettes produit',                  'photocopie plaquette flyer'),
  ('POS', 'Envoi postal',                 'Bureau',                20, 'Ex. : envoi de documentation à un cabinet',     'courrier colis timbre poste'),
  ('TEL', 'Téléphone, internet',          'Bureau',                21, 'Ex. : connexion wifi à l''hôtel',               'mobile wifi forfait'),
  ('INF', 'Petit matériel informatique',  'Bureau',                22, 'Ex. : câble, souris, clé USB',                  'usb cable souris chargeur ordinateur'),
  ('FOR', 'Formation',                    'Formation',             23, 'Ex. : formation produit, frais d''inscription', 'cours stage'),
  ('DOC', 'Livres, abonnements',          'Formation',             24, 'Ex. : revue médicale',                          'livre revue journal abonnement'),
  ('PRE', 'Pressing',                     'Divers',                25, 'Ex. : déplacement de plus de trois jours',      'blanchisserie linge'),
  ('BAN', 'Frais bancaires, change',      'Divers',                26, 'Ex. : commission de change',                    'commission devise retrait'),
  ('AUT', 'Autre',                        'Divers',                27, 'Précisez la dépense',                           'divers');

ALTER TABLE lignefraishorsforfait ADD COLUMN IF NOT EXISTS idCategorie CHAR(3) DEFAULT NULL AFTER mois;

-- Les frais déjà saisis sont classés d'après leur libellé. Les autres
-- restent sans catégorie et s'affichent « Non classé ».
UPDATE lignefraishorsforfait SET idCategorie = 'INV' WHERE idCategorie IS NULL AND (libelle LIKE 'Repas avec%' OR libelle LIKE 'Repas de repr%');
UPDATE lignefraishorsforfait SET idCategorie = 'SAL' WHERE idCategorie IS NULL AND libelle LIKE 'Location de salle%';
UPDATE lignefraishorsforfait SET idCategorie = 'FLE' WHERE idCategorie IS NULL AND libelle LIKE '%fleuriste%';
UPDATE lignefraishorsforfait SET idCategorie = 'FAN' WHERE idCategorie IS NULL AND libelle LIKE 'Fournitures pour anim%';
UPDATE lignefraishorsforfait SET idCategorie = 'PAR' WHERE idCategorie IS NULL AND libelle LIKE 'Parking%';
UPDATE lignefraishorsforfait SET idCategorie = 'IMP' WHERE idCategorie IS NULL AND libelle LIKE 'Impression%';

ALTER TABLE lignefraishorsforfait
  ADD CONSTRAINT fk_lhf_categorie FOREIGN KEY IF NOT EXISTS (idCategorie) REFERENCES categoriehorsforfait (id)
