-- V1 : schéma initial de MédiAgenda.
-- Ne jamais modifier ce fichier une fois appliqué : ajouter une migration V suivante.

CREATE TABLE rendez_vous (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient        text        NOT NULL CHECK (length(patient) BETWEEN 1 AND 200),
    praticien      text        NOT NULL CHECK (length(praticien) BETWEEN 1 AND 100),
    debut          timestamptz NOT NULL,
    duree_minutes  integer     NOT NULL DEFAULT 30 CHECK (duree_minutes BETWEEN 5 AND 240),
    motif          text        CHECK (length(motif) <= 500),
    cree_le        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE rendez_vous IS 'Rendez-vous pris en ligne (données de santé : HDS)';
