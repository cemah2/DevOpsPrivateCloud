-- Schéma de Legacy-RDV (MariaDB 10.x / 11.x).
-- Création de la base et du compte (à faire une fois, en root MariaDB) :
--   CREATE DATABASE legacy_rdv CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
--   CREATE USER 'legacy_rdv'@'localhost' IDENTIFIED BY '<MOT-DE-PASSE>';
--   GRANT SELECT, INSERT, UPDATE, DELETE ON legacy_rdv.* TO 'legacy_rdv'@'localhost';
-- Puis : mariadb legacy_rdv < schema.sql
--
-- Pas de migrations versionnées : InfoGér modifiait ce fichier et le rejouait
-- à la main. Ce qui est en production peut donc différer de ce fichier.

CREATE TABLE IF NOT EXISTS rendez_vous (
    id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    patient       VARCHAR(200) NOT NULL,
    praticien     VARCHAR(100) NOT NULL,
    -- DATETIME sans fuseau : heure « de Paris » implicite.
    date_rdv      DATETIME     NOT NULL,
    motif         VARCHAR(500) NULL,
    -- Nom du fichier dans uploads/ sur le disque du serveur web.
    piece_jointe  VARCHAR(255) NULL,
    cree_le       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY rendez_vous_praticien_date (praticien, date_rdv),
    KEY rendez_vous_date (date_rdv)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Jeu de données fictif (aucune personne réelle).
INSERT IGNORE INTO rendez_vous (id, patient, praticien, date_rdv, motif, piece_jointe) VALUES
    (1, 'Jeanne Exemple', 'dr-morel', '2030-01-07 09:00:00', 'Consultation de suivi', NULL),
    (2, 'Paul Fictif', 'dr-morel', '2030-01-07 09:30:00', 'Renouvellement d''ordonnance', NULL),
    (3, 'Inès Témoin', 'dr-benali', '2030-01-08 14:00:00', 'Résultats d''analyses', NULL);
