-- V5 (EXPAND, F2-S07, DEV-3207) : vue pseudonymisée pour l'extraction nocturne vers l'équipe Data.
-- Projet mediagenda/api, dossier migrations/ (Flyway 13, M27-E05). Compatible avec les versions N et
-- N-1 de l'API : rien n'est modifié dans public, on AJOUTE un schéma « extraction ».
-- Propriétaire de tout ce qui est créé ici : « mediagenda » (le migrateur dynamique d'OpenBao prend ce
-- rôle à la connexion, M25-E14). Ne jamais modifier ce fichier une fois appliqué.
--
-- Principe (ADR-0327) : l'équipe Data ne lit JAMAIS public.rendez_vous. Elle reçoit, chaque nuit, le
-- contenu de extraction.rendez_vous_pseudo lu sur le réplica de secours par un rôle qui n'a QUE ce droit.
--   - Les identifiants (id, patient, praticien) sont remplacés par un HMAC-SHA-256 calculé avec une clé
--     propre à chaque environnement, générée DANS la base (jamais dans Git, jamais dans un Secret) et
--     lisible par « mediagenda » seul : la vue s'exécute avec les droits de son propriétaire (vue
--     classique, sans security_invoker), le lecteur de la vue ne voit jamais la clé.
--   - Le texte libre (motif) et les coordonnées (contact_rappel) ne sortent pas.
--   - Les horodatages sont tronqués (jour et heure du rendez-vous, jour de la prise) : un horodatage à la
--     seconde près ré-identifie une personne qui connaît son propre rendez-vous.
-- Un pseudonyme reste une donnée PERSONNELLE au sens du RGPD (considérant 26) : la base Data est traitée
-- comme telle (accès nominatifs, journaux, durée de conservation), seulement avec un risque réduit.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- pgcrypto (hmac, gen_random_bytes) est une extension « de confiance » depuis PostgreSQL 13 : le
-- propriétaire de la base peut la créer sans être superutilisateur.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS extraction;
COMMENT ON SCHEMA extraction IS 'Vues pseudonymisées exportées vers l''équipe Data (ADR-0327). Lecture : rôle extraction_data seulement.';
REVOKE ALL ON SCHEMA extraction FROM PUBLIC;

-- Clé de pseudonymisation : une ligne, 32 octets aléatoires tirés par la base elle-même. La faire
-- tourner (UPDATE) change TOUS les pseudonymes : à décider avec l'équipe Data (RB-327).
CREATE TABLE IF NOT EXISTS extraction.cle_pseudonyme (
    une_seule boolean PRIMARY KEY DEFAULT true CHECK (une_seule),
    cle       bytea   NOT NULL CHECK (length(cle) = 32),
    creee_le  timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON extraction.cle_pseudonyme FROM PUBLIC;
INSERT INTO extraction.cle_pseudonyme (cle)
SELECT gen_random_bytes(32)
WHERE NOT EXISTS (SELECT 1 FROM extraction.cle_pseudonyme);

-- La vue. Fenêtre glissante de 13 mois (comparaison d'une année sur l'autre) : rien de plus ancien ne sort.
CREATE OR REPLACE VIEW extraction.rendez_vous_pseudo AS
SELECT
    left(encode(hmac(convert_to('rdv:' || r.id::text, 'UTF8'), k.cle, 'sha256'), 'hex'), 32)               AS rdv_pseudo,
    left(encode(hmac(convert_to('patient:' || lower(btrim(r.patient)), 'UTF8'), k.cle, 'sha256'), 'hex'), 32) AS patient_pseudo,
    left(encode(hmac(convert_to('praticien:' || lower(btrim(r.praticien)), 'UTF8'), k.cle, 'sha256'), 'hex'), 32) AS praticien_pseudo,
    (r.debut AT TIME ZONE 'Europe/Paris')::date                                AS jour,
    extract(hour FROM r.debut AT TIME ZONE 'Europe/Paris')::smallint           AS heure,
    extract(isodow FROM r.debut AT TIME ZONE 'Europe/Paris')::smallint         AS jour_semaine,
    r.duree_minutes,
    r.canal_rappel,
    ((r.debut AT TIME ZONE 'Europe/Paris')::date
      - (r.cree_le AT TIME ZONE 'Europe/Paris')::date)::integer                AS delai_reservation_jours
FROM public.rendez_vous r
CROSS JOIN extraction.cle_pseudonyme k
WHERE r.debut >= now() - interval '13 months';

COMMENT ON VIEW extraction.rendez_vous_pseudo IS
  'Rendez-vous pseudonymisés (HMAC-SHA-256, clé interne), sans motif ni contact, horodatages tronqués — ADR-0327';

-- Droits : seulement si le rôle de lecture existe dans CET environnement (déclaré par CloudNativePG en
-- prod et en recette, managed.roles ; absent en dev, où la migration doit passer quand même).
-- Le GRANT est fait par le propriétaire de la vue : aucun superutilisateur n'est nécessaire.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'extraction_data') THEN
    GRANT USAGE ON SCHEMA extraction TO extraction_data;
    GRANT SELECT ON extraction.rendez_vous_pseudo TO extraction_data;
  ELSE
    RAISE NOTICE 'rôle extraction_data absent : droits de lecture non posés (environnement sans extraction)';
  END IF;
END
$$;
