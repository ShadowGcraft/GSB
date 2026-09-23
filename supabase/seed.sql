-- ============================================================================
-- GSB — jeu d'essai
--
-- Données construites pour la démonstration. L'annexe 1 du cahier des charges
-- n'est PAS reprise : elle contient une erreur arithmétique (A4).
-- Les montants forfaitaires sont une HYPOTHÈSE à confirmer (A1).
--
-- Tous les comptes ont le mot de passe « gsb2026 ».
-- Les mois sont calculés par rapport à la date du jour, pour que la démonstration
-- présente toujours une fiche en cours et un historique.
-- ============================================================================

-- Référentiel des frais forfaitisés (RG10, hypothèse A1).
insert into public.categorie_frais (code, libelle, montant_unitaire, ordre, est_kilometrique) values
    ('ETP', 'Relais étape',        110.00, 1, false),
    ('KM',  'Kilométrage',          null,  2, true),
    ('NUI', 'Nuitée hôtel',         80.00, 3, false),
    ('REP', 'Repas midi',           29.00, 4, false);

-- Barème kilométrique imposé par le cahier des charges (RG16).
insert into public.bareme_km (carburant, cv_min, cv_max, montant_par_km) values
    ('diesel',  1, 4,    0.52), ('diesel',  5, 6,    0.58), ('diesel',  7, null, 0.65),
    ('essence', 1, 4,    0.62), ('essence', 5, 6,    0.67), ('essence', 7, null, 0.72);

do $$
declare
    andre   uuid;
    bedos   uuid;
    bentot  uuid;
    m0 date := date_trunc('month', current_date)::date;
    m1 date := (m0 - interval '1 month')::date;
    m2 date := (m0 - interval '2 month')::date;
    m3 date := (m0 - interval '3 month')::date;
    f  uuid;
begin
    andre  := public.creer_utilisateur('david.andre@gsb.fr',   'gsb2026', 'a17', 'Andre',  'David');
    bedos  := public.creer_utilisateur('christian.bedos@gsb.fr','gsb2026', 'b13', 'Bedos',  'Christian');
    bentot := public.creer_utilisateur('pascal.bentot@gsb.fr', 'gsb2026', 'b19', 'Bentot', 'Pascal');
    perform public.creer_utilisateur('comptable@gsb.fr', 'gsb2026', 'c01', 'Villechalane', 'Louis', 'comptable');

    update public.profil set adresse = '8 rue des Charmes', code_postal = '46000', ville = 'Cahors',
           date_embauche = '2005-12-21' where id = andre;

    -- Véhicules. David André a changé de voiture il y a deux mois : ses fiches
    -- antérieures gardent le taux de l'ancien véhicule (historisation).
    -- Pascal Bentot n'a pas de véhicule : sa saisie kilométrique est bloquée (RG20).
    insert into public.vehicule (visiteur_id, immatriculation, puissance_cv, carburant, date_debut, date_fin) values
        (andre, 'AB-123-CD', 4, 'diesel',  (m0 - interval '2 year')::date, (m2 - interval '1 day')::date),
        (andre, 'EF-456-GH', 5, 'essence', m2, null),
        (bedos, 'IJ-789-KL', 7, 'diesel',  (m0 - interval '1 year')::date, null);

    -- David André : une fiche à chaque état.
    insert into public.fiche_frais (visiteur_id, mois) values (andre, m3) returning id into f;
    update public.ligne_forfait set quantite = case categorie_code
        when 'ETP' then 2 when 'KM' then 780 when 'NUI' then 5 when 'REP' then 14 end where fiche_id = f;
    insert into public.ligne_hors_forfait (id, fiche_id, date_frais, libelle, montant) values
        (gen_random_uuid(), f, m3 + 11, 'Repas de représentation, congrès de Dijon', 156.00),
        (gen_random_uuid(), f, m3 + 20, 'Location de salle, présentation produit', 320.00);
    update public.fiche_frais set etat = 'cloturee' where id = f;
    perform public.valider_fiche(f);
    perform public.avancer_paiement(f);
    perform public.avancer_paiement(f);                      -- remboursée

    insert into public.fiche_frais (visiteur_id, mois) values (andre, m2) returning id into f;
    update public.ligne_forfait set quantite = case categorie_code
        when 'ETP' then 1 when 'KM' then 520 when 'NUI' then 3 when 'REP' then 11 end where fiche_id = f;
    insert into public.ligne_hors_forfait (id, fiche_id, date_frais, libelle, montant) values
        (gen_random_uuid(), f, m2 + 8, 'Achat fleuriste, soirée partenaires', 120.30);
    update public.fiche_frais set etat = 'cloturee' where id = f;
    perform public.valider_fiche(f);                         -- validée

    insert into public.fiche_frais (visiteur_id, mois) values (andre, m1) returning id into f;
    update public.ligne_forfait set quantite = case categorie_code
        when 'ETP' then 3 when 'KM' then 910 when 'NUI' then 6 when 'REP' then 16 end where fiche_id = f;
    insert into public.ligne_hors_forfait (id, fiche_id, date_frais, libelle, montant) values
        (gen_random_uuid(), f, m1 + 5,  'Fournitures pour animation en pharmacie', 87.90),
        (gen_random_uuid(), f, m1 + 17, 'Repas avec un spécialiste, hôpital Nord',  64.50),
        (gen_random_uuid(), f, m1 + 22, 'Cadeau non professionnel',               45.00);
    update public.fiche_frais set etat = 'cloturee' where id = f;   -- à valider

    insert into public.fiche_frais (visiteur_id, mois) values (andre, m0) returning id into f;
    update public.ligne_forfait set quantite = case categorie_code
        when 'KM' then 140 when 'REP' then 2 else 0 end where fiche_id = f;

    -- Christian Bedos : une fiche clôturée à valider, et le mois courant.
    insert into public.fiche_frais (visiteur_id, mois) values (bedos, m1) returning id into f;
    update public.ligne_forfait set quantite = case categorie_code
        when 'ETP' then 1 when 'KM' then 615 when 'NUI' then 4 when 'REP' then 12 end where fiche_id = f;
    insert into public.ligne_hors_forfait (id, fiche_id, date_frais, libelle, montant) values
        (gen_random_uuid(), f, m1 + 11, 'Impression de documentation produit', 142.75);
    update public.fiche_frais set etat = 'cloturee' where id = f;

    -- Pascal Bentot : un mois écoulé encore « créé », pour la clôture de campagne.
    insert into public.fiche_frais (visiteur_id, mois) values (bentot, m1) returning id into f;
    update public.ligne_forfait set quantite = case categorie_code
        when 'NUI' then 1 when 'REP' then 4 else 0 end where fiche_id = f;
end;
$$;
