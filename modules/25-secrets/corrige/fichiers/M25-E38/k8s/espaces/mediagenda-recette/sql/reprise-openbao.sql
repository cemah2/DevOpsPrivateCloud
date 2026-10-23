-- plateforme/k8s — espaces/mediagenda-recette/sql/reprise-openbao.sql (M25-E38, INC-5238)
-- Bris de glace : OpenBao ne s'authentifie plus auprès de la base (mot de passe du rôle « openbao »
-- changé hors d'OpenBao). Donne au rôle un mot de passe PROVISOIRE tiré DANS PostgreSQL et l'écrit sur
-- la sortie standard, une seule ligne, pour qu'un tube le passe à OpenBao, qui le remplace aussitôt
-- (rotate-root). Personne ne le lit : jamais de terminal en bout de tube.
--   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -X -qAt -d mediagenda -f - \
--       < ~/src/k8s/espaces/mediagenda-recette/sql/reprise-openbao.sql | tr -d '\r\n' \
--       | bao write db-mediagenda/config/mediagenda-recette password=-
--   admin@adm01:~$ bao write -f db-mediagenda/rotate-root/mediagenda-recette
-- Le mot de passe ne figure dans AUCUNE instruction de premier niveau (seul le texte du bloc DO serait
-- journalisé si log_statement le demandait) ; « bao write … password=- » ne retire pas le saut de
-- ligne final : d'où le « tr ». Même fichier pour la prod (nom du Cluster et de l'espace à adapter).

\set ON_ERROR_STOP 1

SELECT set_config('medisphere.mdp_openbao',
                  encode(sha256((gen_random_uuid()::text || gen_random_uuid()::text)::bytea), 'hex'),
                  false) \g /dev/null

DO $$
BEGIN
  EXECUTE format('ALTER ROLE openbao PASSWORD %L', current_setting('medisphere.mdp_openbao'));
END
$$;

SELECT current_setting('medisphere.mdp_openbao');
