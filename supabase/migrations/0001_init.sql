-- ============================================================================
-- GSB — Gestion des frais de mission des visiteurs médicaux
-- Migration 0001 : schéma, règles de gestion en base, sécurité au niveau ligne.
--
-- Principe directeur (cahier des charges, section 7.3) : le mobile écrit en
-- direct dans la base, sans passer par Symfony. Toute règle de gestion qui
-- protège la cohérence des données vit donc ICI, sous forme de contraintes,
-- de déclencheurs et de politiques RLS. Symfony et Flutter valident pour
-- l'ergonomie ; la base valide pour la sûreté.
--
-- Les numéros RGn renvoient aux règles de gestion de docs/cahier-des-charges.md.
--
-- Conventions : snake_case, noms de tables AU SINGULIER (une table décrit ce
-- qu'est UNE ligne : « une fiche_frais »), montants en numeric(10,2), jamais
-- de float (RG8), horodatages en timestamptz.
-- ============================================================================

create extension if not exists pgcrypto;
create extension if not exists btree_gist;


-- ----------------------------------------------------------------------------
-- 1. Types énumérés
-- ----------------------------------------------------------------------------

-- Cycle de vie d'une fiche : cinq états, quatre transitions linéaires (RG5, RG6).
create type public.etat_fiche as enum (
    'creee', 'cloturee', 'validee', 'mise_en_paiement', 'remboursee'
);

create type public.role_utilisateur as enum ('visiteur', 'comptable');

create type public.carburant as enum ('diesel', 'essence');

-- Un frais hors forfait refusé n'est pas supprimé physiquement : il reste en
-- base avec ce statut, disparaît des totaux, et aucun motif n'est stocké
-- (RG38 à RG40, arbitrage client I).
create type public.statut_hors_forfait as enum ('saisi', 'refuse');


-- ----------------------------------------------------------------------------
-- 2. Profil : le complément métier d'un compte Supabase Auth
--
-- L'identité (courriel, mot de passe) appartient à auth.users. Cette table
-- porte ce que le métier ajoute : matricule, nom, rôle. Même identifiant.
-- ----------------------------------------------------------------------------

create table public.profil (
    id              uuid primary key references auth.users (id) on delete cascade,
    matricule       varchar(20)  not null unique,
    nom             varchar(60)  not null,
    prenom          varchar(60)  not null,
    role            public.role_utilisateur not null default 'visiteur',
    adresse         varchar(120),
    code_postal     varchar(10),
    ville           varchar(60),
    date_embauche   date,
    created_at      timestamptz  not null default now(),
    updated_at      timestamptz  not null default now()
);

comment on table public.profil is 'Visiteur médical ou comptable ; complète auth.users (RG56 à RG60).';


-- ----------------------------------------------------------------------------
-- 3. Référentiels
-- ----------------------------------------------------------------------------

-- Catégories de frais forfaitisés (RG10). Le kilométrage n'a pas de montant
-- fixe : il dépend du véhicule, via le barème ci-dessous.
create table public.categorie_frais (
    code              char(3)       primary key,
    libelle           varchar(40)   not null,
    montant_unitaire  numeric(10,2) check (montant_unitaire >= 0),
    ordre             smallint      not null default 0,
    est_kilometrique  boolean       not null default false,
    -- Seule la catégorie kilométrique peut se passer de montant fixe.
    check (est_kilometrique or montant_unitaire is not null)
);

-- Barème kilométrique indexé sur la puissance fiscale et le carburant (RG16).
-- Une tranche va de cv_min à cv_max inclus ; cv_max nul = « et plus ».
create table public.bareme_km (
    carburant        public.carburant not null,
    cv_min           smallint         not null check (cv_min > 0),
    cv_max           smallint         check (cv_max is null or cv_max >= cv_min),
    montant_par_km   numeric(10,2)    not null check (montant_par_km > 0),
    primary key (carburant, cv_min)
);


-- ----------------------------------------------------------------------------
-- 4. Véhicule, historisé (arbitrage client A, RG17 à RG20)
--
-- Un visiteur qui change de voiture en juin ne doit pas voir ses frais de
-- mars recalculés : chaque véhicule a une période de validité, et deux
-- périodes d'un même visiteur ne peuvent pas se chevaucher.
-- ----------------------------------------------------------------------------

create table public.vehicule (
    id                uuid primary key default gen_random_uuid(),
    visiteur_id       uuid not null references public.profil (id) on delete cascade,
    immatriculation   varchar(15),
    puissance_cv      smallint not null check (puissance_cv between 1 and 50),
    carburant         public.carburant not null,
    date_debut        date not null,
    date_fin          date,                      -- nulle : véhicule courant
    created_at        timestamptz not null default now(),
    check (date_fin is null or date_fin >= date_debut),
    -- Pas de chevauchement de périodes pour un même visiteur.
    exclude using gist (
        visiteur_id with =,
        daterange(date_debut, coalesce(date_fin, 'infinity'::date), '[]') with &&
    )
);


-- ----------------------------------------------------------------------------
-- 5. Fiche de frais mensuelle (RG1 à RG7)
-- ----------------------------------------------------------------------------

create table public.fiche_frais (
    id              uuid primary key default gen_random_uuid(),
    visiteur_id     uuid not null references public.profil (id) on delete restrict,
    -- Le mois est stocké comme le premier jour du mois : triable, comparable,
    -- et sans conversion de chaîne, contrairement au « aaaamm » de 2013.
    mois            date not null check (extract(day from mois) = 1),
    etat            public.etat_fiche not null default 'creee',
    -- Figé par le comptable au moment de la validation (RG42).
    montant_valide  numeric(10,2) check (montant_valide >= 0),
    date_modif      timestamptz not null default now(),
    created_at      timestamptz not null default now(),
    unique (visiteur_id, mois)                   -- RG1
);

create index fiche_frais_mois_etat_idx on public.fiche_frais (mois, etat);


-- Une ligne par catégorie forfaitisée et par fiche (RG3, RG12).
--
-- Historisation des montants : le montant unitaire est RECOPIÉ sur la ligne.
-- Tant que la fiche est à l'état « créée », il suit le référentiel et le
-- véhicule ; dès qu'elle quitte cet état, il est figé. Une fiche validée
-- l'an dernier garde donc ses montants, quel que soit le barème d'aujourd'hui.
create table public.ligne_forfait (
    id                uuid primary key default gen_random_uuid(),
    fiche_id          uuid not null references public.fiche_frais (id) on delete cascade,
    categorie_code    char(3) not null references public.categorie_frais (code),
    quantite          integer not null default 0 check (quantite >= 0),   -- RG11
    montant_unitaire  numeric(10,2) not null default 0 check (montant_unitaire >= 0),
    unique (fiche_id, categorie_code)
);


-- Frais hors forfait (RG23 à RG29).
--
-- L'identifiant est généré PAR LE CLIENT (le mobile, ou Symfony) : c'est lui
-- qui rend la synchronisation idempotente. Rejouer l'envoi d'une ligne déjà
-- reçue ne crée pas de doublon (RG24, RG52).
create table public.ligne_hors_forfait (
    id            uuid primary key,
    fiche_id      uuid not null references public.fiche_frais (id) on delete cascade,
    date_frais    date not null,
    libelle       varchar(150) not null check (length(trim(libelle)) > 0),
    montant       numeric(10,2) not null check (montant > 0),
    statut        public.statut_hors_forfait not null default 'saisi',
    -- Renseigné uniquement quand la ligne a été reportée sur une fiche
    -- postérieure : le comptable voit d'où elle vient (arbitrage client G).
    mois_origine  date check (mois_origine is null or extract(day from mois_origine) = 1),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index ligne_hors_forfait_fiche_idx on public.ligne_hors_forfait (fiche_id);


-- Justificatif déposé pour un frais hors forfait (RG25). Le fichier lui-même
-- est dans Supabase Storage ; la table en garde la trace.
create table public.justificatif (
    id                     uuid primary key default gen_random_uuid(),
    ligne_hors_forfait_id  uuid not null unique
                           references public.ligne_hors_forfait (id) on delete cascade,
    chemin                 text not null,          -- chemin dans le bucket
    nom_fichier            varchar(200) not null,
    type_mime              varchar(100) not null
                           check (type_mime in ('application/pdf', 'image/jpeg', 'image/png')),
    taille_octets          integer not null check (taille_octets between 1 and 5242880),
    created_at             timestamptz not null default now()
);


-- ----------------------------------------------------------------------------
-- 6. Fonctions utilitaires
-- ----------------------------------------------------------------------------

-- Rôle de l'utilisateur connecté. SECURITY DEFINER : la fonction lit profil
-- sans être soumise à ses propres politiques, ce qui évite une récursion.
create or replace function public.est_comptable()
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (select 1 from profil where id = auth.uid() and role = 'comptable');
$$;

-- Premier jour du mois d'une date.
create or replace function public.debut_mois(d date)
returns date language sql immutable
as $$ select date_trunc('month', d)::date $$;

-- Montant par kilomètre applicable à un visiteur pour un mois donné : celui
-- du véhicule en service ce mois-là (RG17, RG21). Nul si aucun véhicule.
create or replace function public.taux_km(p_visiteur uuid, p_mois date)
returns numeric
language sql stable security definer set search_path = public
as $$
    select b.montant_par_km
    from vehicule v
    join bareme_km b
      on b.carburant = v.carburant
     and v.puissance_cv >= b.cv_min
     and (b.cv_max is null or v.puissance_cv <= b.cv_max)
    where v.visiteur_id = p_visiteur
      and v.date_debut <= (p_mois + interval '1 month' - interval '1 day')::date
      and (v.date_fin is null or v.date_fin >= p_mois)
    order by v.date_debut desc
    limit 1;
$$;


-- ----------------------------------------------------------------------------
-- 7. Déclencheurs
-- ----------------------------------------------------------------------------

-- Horodatage de modification.
create or replace function public.tg_maj_horodatage()
returns trigger language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger profil_maj before update on public.profil
    for each row execute function public.tg_maj_horodatage();
create trigger ligne_hors_forfait_maj before update on public.ligne_hors_forfait
    for each row execute function public.tg_maj_horodatage();


-- Création d'une fiche : une ligne à zéro par catégorie (RG3), au montant du
-- référentiel. Le taux kilométrique est posé par le déclencheur de ligne.
create or replace function public.tg_fiche_creee()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
    insert into ligne_forfait (fiche_id, categorie_code, quantite, montant_unitaire)
    select new.id, c.code, 0, coalesce(c.montant_unitaire, 0)
    from categorie_frais c;
    return new;
end;
$$;

create trigger fiche_frais_lignes after insert on public.fiche_frais
    for each row execute function public.tg_fiche_creee();


-- Cycle de vie : transitions linéaires uniquement, aucun retour (RG6) ; une
-- fiche validée ou au-delà ne change plus que d'état (RG43).
create or replace function public.tg_fiche_transition()
returns trigger language plpgsql
as $$
declare
    ordre constant public.etat_fiche[] :=
        array['creee','cloturee','validee','mise_en_paiement','remboursee']::public.etat_fiche[];
begin
    if new.visiteur_id <> old.visiteur_id or new.mois <> old.mois then
        raise exception 'Le visiteur et le mois d''une fiche ne se modifient pas.';
    end if;

    if new.etat <> old.etat then
        if array_position(ordre, new.etat) <> array_position(ordre, old.etat) + 1 then
            raise exception 'Transition interdite : % vers % (RG6).', old.etat, new.etat;
        end if;
    elsif old.etat in ('validee', 'mise_en_paiement', 'remboursee')
          and new.montant_valide is distinct from old.montant_valide then
        raise exception 'Une fiche validée est immuable (RG43).';
    end if;

    new.date_modif := now();
    return new;
end;
$$;

create trigger fiche_frais_transition before update on public.fiche_frais
    for each row execute function public.tg_fiche_transition();


-- Écriture sur une ligne forfaitisée :
--   - le visiteur n'écrit que sur une fiche « créée » (RG13) ;
--   - le comptable corrige les quantités d'une fiche « clôturée » (RG36, RG37) ;
--   - kilométrage sans véhicule : refusé (RG20) ;
--   - le montant unitaire suit le référentiel tant que la fiche est créée,
--     puis reste figé.
create or replace function public.tg_ligne_forfait()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
    f        fiche_frais;
    cat      categorie_frais;
    taux     numeric;
begin
    select * into f from fiche_frais where id = new.fiche_id;
    select * into cat from categorie_frais where code = new.categorie_code;

    if tg_op = 'UPDATE' then
        if new.fiche_id <> old.fiche_id or new.categorie_code <> old.categorie_code then
            raise exception 'Une ligne forfaitisée ne change ni de fiche ni de catégorie.';
        end if;
        if f.etat = 'creee' then
            null;
        elsif f.etat = 'cloturee' and (auth.uid() is null or public.est_comptable()) then
            -- Correction comptable : la quantité change, le montant reste figé.
            new.montant_unitaire := old.montant_unitaire;
            return new;
        else
            raise exception 'Fiche %, état « % » : les frais ne sont plus modifiables (RG13, RG43).',
                to_char(f.mois, 'MM/YYYY'), f.etat;
        end if;
    end if;

    if cat.est_kilometrique then
        taux := public.taux_km(f.visiteur_id, f.mois);
        if taux is null and new.quantite > 0 then
            raise exception 'Aucun véhicule déclaré pour %/% : la saisie kilométrique est bloquée (RG20).',
                extract(month from f.mois), extract(year from f.mois)
                using hint = 'Déclarez votre véhicule dans votre profil.';
        end if;
        new.montant_unitaire := coalesce(taux, 0);
    else
        new.montant_unitaire := cat.montant_unitaire;
    end if;
    return new;
end;
$$;

create trigger ligne_forfait_controle before insert or update on public.ligne_forfait
    for each row execute function public.tg_ligne_forfait();


-- Frais hors forfait :
--   - date d'engagement dans l'année écoulée, jamais dans le futur (RG4, RG27) ;
--   - le visiteur ajoute, modifie, supprime sur une fiche « créée » (RG13) ;
--   - le comptable peut refuser ou reporter une ligne d'une fiche « clôturée ».
create or replace function public.tg_ligne_hors_forfait()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
    f fiche_frais;
begin
    if tg_op = 'DELETE' then
        select * into f from fiche_frais where id = old.fiche_id;
        if f.etat <> 'creee' then
            raise exception 'Une ligne d''une fiche « % » ne se supprime pas ; le comptable la refuse (RG39).', f.etat;
        end if;
        return old;
    end if;

    select * into f from fiche_frais where id = new.fiche_id;

    if tg_op = 'INSERT' or new.date_frais <> old.date_frais then
        if new.date_frais > current_date then
            raise exception 'La date d''un frais ne peut pas être dans le futur.';
        end if;
        if new.date_frais < (current_date - interval '1 year')::date then
            raise exception 'Frais engagé il y a plus d''un an : saisie refusée (RG4).';
        end if;
    end if;

    if f.etat = 'creee' then
        return new;
    end if;

    -- Hors de l'état « créée », seul le comptable intervient, et seulement pour
    -- refuser la ligne ou la déplacer sur une autre fiche (report, RG28).
    if f.etat = 'cloturee' and tg_op = 'UPDATE'
       and (auth.uid() is null or public.est_comptable())
       and new.libelle = old.libelle and new.montant = old.montant
       and new.date_frais = old.date_frais then
        return new;
    end if;

    raise exception 'Fiche %, état « % » : les frais ne sont plus modifiables (RG13, RG43).',
        to_char(f.mois, 'MM/YYYY'), f.etat;
end;
$$;

create trigger ligne_hors_forfait_controle
    before insert or update or delete on public.ligne_hors_forfait
    for each row execute function public.tg_ligne_hors_forfait();


-- ----------------------------------------------------------------------------
-- 8. Opérations métier exposées aux clients (web et mobile)
--
-- Ces fonctions portent les règles qui dépassent une seule ligne. Elles sont
-- SECURITY DEFINER et vérifient elles-mêmes qui les appelle.
-- ----------------------------------------------------------------------------

-- Fiche du mois courant du visiteur connecté, créée au besoin.
-- À la première saisie d'un mois, les fiches antérieures encore « créées »
-- sont clôturées (RG31).
create or replace function public.fiche_courante()
returns public.fiche_frais
language plpgsql security definer set search_path = public
as $$
declare
    uid   uuid := auth.uid();
    m     date := public.debut_mois(current_date);
    f     fiche_frais;
begin
    if uid is null then
        raise exception 'Utilisateur non authentifié.';
    end if;

    select * into f from fiche_frais where visiteur_id = uid and mois = m;
    if found then
        return f;
    end if;

    update fiche_frais set etat = 'cloturee'
     where visiteur_id = uid and etat = 'creee' and mois < m;          -- RG31

    insert into fiche_frais (visiteur_id, mois) values (uid, m)
    returning * into f;
    return f;
end;
$$;


-- Synchronisation mobile d'une quantité forfaitisée (RG51, RG53).
-- La quantité ÉCRASE la valeur serveur : le mobile fait foi. Si la fiche du
-- mois visé n'est plus « créée », l'écriture est refusée et la saisie reste
-- dans la file locale du mobile.
create or replace function public.maj_quantite_forfait(p_mois date, p_code char(3), p_quantite integer)
returns public.ligne_forfait
language plpgsql security definer set search_path = public
as $$
declare
    uid  uuid := auth.uid();
    m    date := public.debut_mois(p_mois);
    f    fiche_frais;
    l    ligne_forfait;
begin
    if uid is null then raise exception 'Utilisateur non authentifié.'; end if;

    if m = public.debut_mois(current_date) then
        f := public.fiche_courante();
    else
        select * into f from fiche_frais where visiteur_id = uid and mois = m;
        if not found then
            raise exception 'MOIS_VERROUILLE: aucune fiche ouverte pour %.', to_char(m, 'MM/YYYY');
        end if;
    end if;

    if f.etat <> 'creee' then
        raise exception 'MOIS_VERROUILLE: la fiche de % est « % ».', to_char(m, 'MM/YYYY'), f.etat;
    end if;

    update ligne_forfait set quantite = p_quantite
     where fiche_id = f.id and categorie_code = p_code
    returning * into l;
    return l;
end;
$$;


-- Ajout idempotent d'un frais hors forfait, depuis le web comme le mobile.
--   - l'identifiant vient du client : un second envoi est sans effet (RG52) ;
--   - la ligne va sur la fiche du mois de sa date ; si cette fiche n'est plus
--     « créée », elle bascule sur la fiche du mois courant, avec son mois
--     d'origine (RG54, arbitrage client F).
create or replace function public.ajouter_hors_forfait(
    p_id uuid, p_date date, p_libelle text, p_montant numeric)
returns public.ligne_hors_forfait
language plpgsql security definer set search_path = public
as $$
declare
    uid      uuid := auth.uid();
    m        date := public.debut_mois(p_date);
    f        fiche_frais;
    origine  date := null;
    l        ligne_hors_forfait;
begin
    if uid is null then raise exception 'Utilisateur non authentifié.'; end if;

    select * into l from ligne_hors_forfait where id = p_id;
    if found then
        return l;                                  -- déjà reçue : idempotence
    end if;

    select * into f from fiche_frais where visiteur_id = uid and mois = m;
    if not found or f.etat <> 'creee' then
        if found then origine := m; end if;
        f := public.fiche_courante();
        if f.mois = m then origine := null; end if;
    end if;

    insert into ligne_hors_forfait (id, fiche_id, date_frais, libelle, montant, mois_origine)
    values (p_id, f.id, p_date, trim(p_libelle), p_montant, origine)
    returning * into l;
    return l;
end;
$$;


-- Clôture de campagne : toutes les fiches encore « créées » d'un mois passé
-- sont clôturées (RG32). Réservé au comptable.
create or replace function public.cloturer_mois(p_mois date)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
    n integer;
begin
    if auth.uid() is not null and not public.est_comptable() then
        raise exception 'Réservé au comptable.';
    end if;
    if public.debut_mois(p_mois) >= public.debut_mois(current_date) then
        raise exception 'On ne clôture que des mois échus.';
    end if;
    update fiche_frais set etat = 'cloturee'
     where mois = public.debut_mois(p_mois) and etat = 'creee';
    get diagnostics n = row_count;
    return n;
end;
$$;


-- Report d'un frais hors forfait sur la fiche du mois suivant (RG28, RG29).
create or replace function public.reporter_hors_forfait(p_ligne uuid)
returns public.ligne_hors_forfait
language plpgsql security definer set search_path = public
as $$
declare
    l      ligne_hors_forfait;
    f      fiche_frais;
    cible  fiche_frais;
begin
    if auth.uid() is not null and not public.est_comptable() then
        raise exception 'Réservé au comptable.';
    end if;

    select * into l from ligne_hors_forfait where id = p_ligne;
    select * into f from fiche_frais where id = l.fiche_id;
    if f.etat <> 'cloturee' then
        raise exception 'Seule une ligne d''une fiche clôturée se reporte.';
    end if;

    select * into cible from fiche_frais
     where visiteur_id = f.visiteur_id and mois = (f.mois + interval '1 month')::date;
    if not found then
        insert into fiche_frais (visiteur_id, mois)
        values (f.visiteur_id, (f.mois + interval '1 month')::date)
        returning * into cible;
    end if;

    update ligne_hors_forfait
       set fiche_id = cible.id,
           mois_origine = coalesce(l.mois_origine, f.mois)
     where id = p_ligne
    returning * into l;
    return l;
end;
$$;


-- Validation par le comptable (UC 4.3, RG42) : le montant validé est figé.
create or replace function public.valider_fiche(p_fiche uuid)
returns public.fiche_frais
language plpgsql security definer set search_path = public
as $$
declare
    f fiche_frais;
begin
    if auth.uid() is not null and not public.est_comptable() then
        raise exception 'Réservé au comptable.';
    end if;
    update fiche_frais
       set etat = 'validee',
           montant_valide = (select total from v_fiche_total where fiche_id = p_fiche)
     where id = p_fiche and etat = 'cloturee'
    returning * into f;
    if not found then
        raise exception 'Seule une fiche clôturée peut être validée.';
    end if;
    return f;
end;
$$;


-- Mise en paiement puis remboursement (RG44, RG45).
create or replace function public.avancer_paiement(p_fiche uuid)
returns public.fiche_frais
language plpgsql security definer set search_path = public
as $$
declare
    f fiche_frais;
begin
    if auth.uid() is not null and not public.est_comptable() then
        raise exception 'Réservé au comptable.';
    end if;
    update fiche_frais
       set etat = case etat when 'validee' then 'mise_en_paiement'::etat_fiche
                            when 'mise_en_paiement' then 'remboursee'::etat_fiche end
     where id = p_fiche and etat in ('validee', 'mise_en_paiement')
    returning * into f;
    if not found then
        raise exception 'La fiche n''est ni validée ni mise en paiement.';
    end if;
    return f;
end;
$$;


-- Création d'un compte applicatif. Utilisé par le seed et par l'administration.
-- Le mot de passe est haché en bcrypt, comme le fait Supabase Auth.
create or replace function public.creer_utilisateur(
    p_email text, p_mdp text, p_matricule text, p_nom text, p_prenom text,
    p_role public.role_utilisateur default 'visiteur')
returns uuid
language plpgsql security definer set search_path = public, auth, extensions
as $$
declare
    uid uuid := gen_random_uuid();
begin
    insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change)
    values (
        '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
        lower(p_email), crypt(p_mdp, gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}', '{}', now(), now(),
        '', '', '', '');

    insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
            jsonb_build_object('sub', uid::text, 'email', lower(p_email)),
            'email', now(), now());

    insert into profil (id, matricule, nom, prenom, role)
    values (uid, p_matricule, p_nom, p_prenom, p_role);
    return uid;
end;
$$;

-- Vérification d'identifiants pour l'application web (RG56, RG57).
-- Même base de comptes que Supabase Auth : le visiteur a UN seul mot de passe
-- pour le web et le mobile. Réservée au rôle de connexion de Symfony.
create or replace function public.verifier_identifiants(p_email text, p_mdp text)
returns uuid
language sql stable security definer set search_path = public, auth, extensions
as $$
    select u.id from auth.users u
    where u.email = lower(p_email)
      and u.encrypted_password = crypt(p_mdp, u.encrypted_password);
$$;


-- ----------------------------------------------------------------------------
-- 9. Vue des totaux (RG7, RG26, RG47)
--
-- Le total n'est PAS stocké : il est recalculé. Seul le montant validé est
-- figé, au moment de la validation.
-- ----------------------------------------------------------------------------

create view public.v_fiche_total with (security_invoker = true) as
select
    f.id as fiche_id,
    f.visiteur_id,
    f.mois,
    f.etat,
    coalesce((select sum(lf.quantite * lf.montant_unitaire)
                from ligne_forfait lf where lf.fiche_id = f.id), 0)
  + coalesce((select sum(h.montant) from ligne_hors_forfait h
               where h.fiche_id = f.id and h.statut = 'saisi'), 0)       as total,
    (select count(*) from justificatif j
       join ligne_hors_forfait h on h.id = j.ligne_hors_forfait_id
      where h.fiche_id = f.id and h.statut = 'saisi')::int               as nb_justificatifs,
    -- Nombre de prestations (RG47, hypothèse) : quantités forfaitisées hors
    -- kilométrage, plus lignes hors forfait retenues.
    coalesce((select sum(lf.quantite) from ligne_forfait lf
                join categorie_frais c on c.code = lf.categorie_code
               where lf.fiche_id = f.id and not c.est_kilometrique), 0)::int
  + (select count(*) from ligne_hors_forfait h
      where h.fiche_id = f.id and h.statut = 'saisi')::int               as nb_prestations
from public.fiche_frais f;


-- ----------------------------------------------------------------------------
-- 10. Sécurité au niveau ligne (RLS)
--
-- Un visiteur ne lit et n'écrit que ses propres données ; un comptable lit
-- tout et n'écrit que sur les fiches clôturées. L'immuabilité d'une fiche
-- validée est assurée par les déclencheurs ci-dessus, pour tout le monde.
-- ----------------------------------------------------------------------------

alter table public.profil             enable row level security;
alter table public.categorie_frais    enable row level security;
alter table public.bareme_km          enable row level security;
alter table public.vehicule           enable row level security;
alter table public.fiche_frais        enable row level security;
alter table public.ligne_forfait      enable row level security;
alter table public.ligne_hors_forfait enable row level security;
alter table public.justificatif       enable row level security;

-- Référentiels : lecture pour tout utilisateur connecté.
create policy lecture_referentiel on public.categorie_frais for select to authenticated using (true);
create policy lecture_bareme      on public.bareme_km       for select to authenticated using (true);

-- Profil : chacun le sien ; le comptable voit tout le monde (RG35).
create policy profil_lecture on public.profil for select to authenticated
    using (id = auth.uid() or public.est_comptable());
create policy profil_maj on public.profil for update to authenticated
    using (id = auth.uid())
    with check (id = auth.uid() and role = (select p.role from public.profil p where p.id = auth.uid()));

-- Véhicule : saisi par le visiteur, consulté par le comptable (RG18, RG19).
create policy vehicule_lecture on public.vehicule for select to authenticated
    using (visiteur_id = auth.uid() or public.est_comptable());
create policy vehicule_ecriture on public.vehicule for all to authenticated
    using (visiteur_id = auth.uid()) with check (visiteur_id = auth.uid());

-- Fiche : lecture de ses fiches ; le comptable lit tout et ne modifie que
-- les fiches clôturées. La création passe par fiche_courante().
create policy fiche_lecture on public.fiche_frais for select to authenticated
    using (visiteur_id = auth.uid() or public.est_comptable());
create policy fiche_maj_comptable on public.fiche_frais for update to authenticated
    using (public.est_comptable() and etat = 'cloturee');

-- Lignes forfaitisées.
create policy lf_lecture on public.ligne_forfait for select to authenticated
    using (exists (select 1 from public.fiche_frais f where f.id = fiche_id
                   and (f.visiteur_id = auth.uid() or public.est_comptable())));
create policy lf_maj_visiteur on public.ligne_forfait for update to authenticated
    using (exists (select 1 from public.fiche_frais f where f.id = fiche_id
                   and f.visiteur_id = auth.uid() and f.etat = 'creee'));
create policy lf_maj_comptable on public.ligne_forfait for update to authenticated
    using (public.est_comptable() and exists (select 1 from public.fiche_frais f
                   where f.id = fiche_id and f.etat = 'cloturee'));

-- Lignes hors forfait. L'insertion passe par ajouter_hors_forfait().
create policy lhf_lecture on public.ligne_hors_forfait for select to authenticated
    using (exists (select 1 from public.fiche_frais f where f.id = fiche_id
                   and ((f.visiteur_id = auth.uid() and statut = 'saisi') or public.est_comptable())));
create policy lhf_suppr_visiteur on public.ligne_hors_forfait for delete to authenticated
    using (exists (select 1 from public.fiche_frais f where f.id = fiche_id
                   and f.visiteur_id = auth.uid() and f.etat = 'creee'));
create policy lhf_maj_comptable on public.ligne_hors_forfait for update to authenticated
    using (public.est_comptable() and exists (select 1 from public.fiche_frais f
                   where f.id = fiche_id and f.etat = 'cloturee'));

-- Justificatifs : déposés par le visiteur sur ses lignes d'une fiche créée.
create policy justif_lecture on public.justificatif for select to authenticated
    using (exists (select 1 from public.ligne_hors_forfait h join public.fiche_frais f on f.id = h.fiche_id
                   where h.id = ligne_hors_forfait_id
                     and (f.visiteur_id = auth.uid() or public.est_comptable())));
create policy justif_ecriture on public.justificatif for insert to authenticated
    with check (exists (select 1 from public.ligne_hors_forfait h join public.fiche_frais f on f.id = h.fiche_id
                   where h.id = ligne_hors_forfait_id and f.visiteur_id = auth.uid() and f.etat = 'creee'));
create policy justif_suppr on public.justificatif for delete to authenticated
    using (exists (select 1 from public.ligne_hors_forfait h join public.fiche_frais f on f.id = h.fiche_id
                   where h.id = ligne_hors_forfait_id and f.visiteur_id = auth.uid() and f.etat = 'creee'));


-- ----------------------------------------------------------------------------
-- 11. Droits
-- ----------------------------------------------------------------------------

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on public.v_fiche_total to authenticated;

-- Les fonctions sensibles ne sont PAS appelables depuis l'API publique :
-- la vérification d'identifiants et la création de comptes restent côté
-- serveur, sans quoi elles offriraient un point d'attaque par force brute.
revoke execute on function public.verifier_identifiants(text, text) from public, anon, authenticated;
revoke execute on function public.creer_utilisateur(text, text, text, text, text, public.role_utilisateur)
    from public, anon, authenticated;
