-- ---------------------------------------------------------------------------
-- Évolution 2026, second temps : le rôle comptable.
--
-- Le comptable traite les fiches clôturées, l'administrateur garde en plus la
-- gestion des comptes. Joué par PdoGsb tant que le compte « cpt » n'existe pas.
-- Mêmes règles que evolutions-2026.sql : rejouable, sans point-virgule dans
-- les commentaires ni dans les chaînes.
-- ---------------------------------------------------------------------------

INSERT IGNORE INTO visiteur (id, nom, prenom, login, mdp, role, actif)
VALUES ('cpt', 'Comptable', 'Service', 'comptable', 'gsbcompta', 'comptable', 1)
