-- plateforme/k8s — espaces/mediagenda-recette/sql/preparer-openbao.sql (M25-E14, DEV-2614)
-- Joué UNE fois par environnement, en superutilisateur, APRÈS que CloudNativePG a créé les rôles
-- gérés « openbao » et « mediagenda_api » (status.managedRolesStatus du Cluster) :
--   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -v ON_ERROR_STOP=1 \
--       < ~/src/k8s/espaces/mediagenda-recette/sql/preparer-openbao.sql
-- Idempotent : le rejouer ne change rien. Ce que CloudNativePG ne sait pas déclarer : les droits sur
-- les tables, les droits par défaut, l'option ADMIN d'une appartenance (PostgreSQL ≥ 16 : un rôle
-- CREATEROLE ne donne l'appartenance à un rôle que s'il a l'option ADMIN sur lui).

\set ON_ERROR_STOP 1

-- 1. Droits de l'API : lire et écrire des LIGNES, jamais le schéma.
GRANT CONNECT ON DATABASE mediagenda TO mediagenda_api;
GRANT USAGE ON SCHEMA public TO mediagenda_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mediagenda_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mediagenda_api;
-- … et sur ce que les migrations créeront (objets créés PAR mediagenda : voir le rôle migrateur).
ALTER DEFAULT PRIVILEGES FOR ROLE mediagenda IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mediagenda_api;
ALTER DEFAULT PRIVILEGES FOR ROLE mediagenda IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO mediagenda_api;

-- 2. OpenBao peut DONNER l'appartenance à mediagenda_api et à mediagenda (ADMIN), sans en recevoir
--    les droits (INHERIT FALSE) ni pouvoir « SET ROLE » vers eux (SET FALSE). Un nouveau GRANT sur
--    une appartenance existante (créée par CloudNativePG via inRoles) en met les options à jour.
GRANT mediagenda_api TO openbao WITH ADMIN TRUE, INHERIT FALSE, SET FALSE;
GRANT mediagenda TO openbao WITH ADMIN TRUE, INHERIT FALSE, SET FALSE;

-- 3. Contrôle (à lire, pas à copier ailleurs).
SELECT r.rolname AS role, m.rolname AS membre, a.admin_option, a.inherit_option, a.set_option
  FROM pg_auth_members a
  JOIN pg_roles r ON r.oid = a.roleid
  JOIN pg_roles m ON m.oid = a.member
 WHERE m.rolname = 'openbao';
