-- plateforme/k8s — espaces/mediagenda-recette/sql/preparer-lecture.sql (M27-E02, PLAT-2802)
-- Joué en superutilisateur APRÈS que CloudNativePG a créé le rôle géré « mediagenda_lecture »
-- (status.managedRolesStatus du Cluster). Idempotent : le rejouer ne change rien.
--   admin@adm01:~/src/k8s$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -v ON_ERROR_STOP=1 \
--       < espaces/mediagenda-recette/sql/preparer-lecture.sql
-- CloudNativePG gère les RÔLES, pas les DROITS sur les objets : ce fichier est le complément.

\set ON_ERROR_STOP 1

GRANT CONNECT ON DATABASE mediagenda TO mediagenda_lecture;
GRANT USAGE ON SCHEMA public TO mediagenda_lecture;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mediagenda_lecture;
-- … et sur les tables que les migrations créeront (créées PAR mediagenda : le migrateur dynamique
-- prend ce rôle à la connexion, M25-E14).
ALTER DEFAULT PRIVILEGES FOR ROLE mediagenda IN SCHEMA public
  GRANT SELECT ON TABLES TO mediagenda_lecture;
-- Lire pg_stat_statements pour TOUS les utilisateurs (sinon un rôle ne voit le texte que de ses
-- propres requêtes) : rôle prédéfini de PostgreSQL.
GRANT pg_read_all_stats TO mediagenda_lecture;

-- Contrôle (à lire) : droits effectifs de mediagenda_lecture sur les tables.
SELECT table_name, string_agg(privilege_type, ',' ORDER BY privilege_type) AS droits
  FROM information_schema.role_table_grants
 WHERE grantee = 'mediagenda_lecture'
 GROUP BY table_name ORDER BY table_name;
