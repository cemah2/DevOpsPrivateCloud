-- mediagenda/api — flyway/rappels/beforeBaseline.sql (M27-E05, DEV-2805)
-- Rappel (callback) SQL de Flyway, exécuté AVANT toute reprise (baseline), y compris celle que
-- déclenche baselineOnMigrate sur un schéma non vide sans flyway_schema_history.
-- Garde-fou : on ne déclare « V2 déjà appliquée » que si l'ancien outil (python -m
-- mediagenda.migrate) a bien noté V1 ET V2. Sinon la migration échoue, rien n'est écrit (la
-- transaction est annulée) et le Job du hook Argo CD est en échec : la synchronisation s'arrête
-- AVANT la nouvelle version de l'API. Vérifié sur PostgreSQL 18.6 + Flyway 13.11.1 : base à V1
-- seule → « garde : V1 et V2 absentes… », code de sortie 1, aucune table d'historique créée.
-- Sur une base VIDE (environnement reconstruit), Flyway ne fait pas de reprise : ce rappel ne
-- s'exécute pas, V1 et V2 sont appliquées normalement.
DO $$
BEGIN
  IF to_regclass('public.mediagenda_historique_schema') IS NULL THEN
    RAISE EXCEPTION 'garde (M27-E05) : schéma non vide sans mediagenda_historique_schema : reprise refusée';
  END IF;
  IF (SELECT count(*) FROM mediagenda_historique_schema WHERE version IN ('1', '2')) <> 2 THEN
    RAISE EXCEPTION 'garde (M27-E05) : V1 et V2 absentes de mediagenda_historique_schema : reprise refusée';
  END IF;
END $$;
