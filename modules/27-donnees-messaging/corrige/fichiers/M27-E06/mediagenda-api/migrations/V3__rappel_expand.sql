-- V3 (EXPAND, M27-E06, DEV-2806) : canal et contact de rappel choisis par le patient.
-- Compatible avec la version N-1 de l'API, qui ne connaît pas ces colonnes :
--   - elle lit par une liste de colonnes explicite : les colonnes ajoutées ne la gênent pas ;
--   - elle écrit sans les nommer : canal_rappel prend son DÉFAUT « aucun », contact_rappel NULL,
--     ce qui respecte les deux contraintes ci-dessous.
-- Ne jamais modifier ce fichier une fois appliqué : ajouter une migration V suivante.

-- Un ALTER TABLE prend un verrou ACCESS EXCLUSIVE, bref… s'il l'obtient. Derrière une longue
-- transaction, il ATTEND, et toutes les requêtes sur rendez_vous attendent derrière lui : on
-- préfère échouer vite (le Job de migration réessaie) que geler l'API.
-- SET LOCAL : valable jusqu'à la fin de la transaction de la migration (Flyway en ouvre une par
-- fichier sur PostgreSQL).
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

-- PostgreSQL ≥ 11 : une colonne avec un défaut CONSTANT n'oblige pas à réécrire la table
-- (le défaut est stocké dans le catalogue) ; NOT NULL est alors vérifié sans parcours.
ALTER TABLE rendez_vous
    ADD COLUMN canal_rappel   text NOT NULL DEFAULT 'aucun',
    ADD COLUMN contact_rappel text;

-- Contraintes ajoutées NOT VALID : appliquées aux NOUVELLES lignes tout de suite, sans
-- parcourir les lignes existantes sous verrou exclusif. Elles sont validées en V4.
ALTER TABLE rendez_vous
    ADD CONSTRAINT rendez_vous_canal_rappel_ck
        CHECK (canal_rappel IN ('sms', 'mail', 'aucun')) NOT VALID,
    ADD CONSTRAINT rendez_vous_contact_rappel_ck
        CHECK ((canal_rappel = 'aucun') = (contact_rappel IS NULL)
               AND (contact_rappel IS NULL OR length(contact_rappel) <= 254)) NOT VALID;

COMMENT ON COLUMN rendez_vous.canal_rappel IS 'Canal de rappel choisi par le patient : sms, mail ou aucun (consentement explicite)';
COMMENT ON COLUMN rendez_vous.contact_rappel IS 'Téléphone ou courriel de rappel (donnée personnelle, RGPD) ; NULL si aucun rappel';
