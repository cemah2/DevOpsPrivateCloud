-- Legacy-RDV 2.4.0 — table des sessions partagées entre réplicas (F4-S12, CHG-3412).
-- Appliqué par le compte de migration legacy_rdv_migrateur (SqlJob « legacy-rdv-schema-v2 » de
-- legacy/deploiement). Rejouable.
CREATE TABLE IF NOT EXISTS sessions (
    id         VARCHAR(128)  NOT NULL,
    donnees    MEDIUMBLOB    NOT NULL,
    expire_le  INT UNSIGNED  NOT NULL,
    PRIMARY KEY (id),
    KEY sessions_expire_le (expire_le)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
