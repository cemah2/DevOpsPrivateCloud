# Essai de réversibilité — <AAAA-MM-JJ> (modèle de compte rendu)

> F7-S07 (PLAT-3707), procédure RB-371. Fichier à nommer `docs/capstone/reversibilite/<AAAA-MM-JJ>.md`. Aucune donnée (même fictive) dans ce compte rendu : des nombres, des empreintes, des durées.

| | |
|---|---|
| Client, environnement | GHSV, `ghsv-prod` (données fictives) |
| Export | `s3://ghsv-reversibilite/<DOSSIER>/` |
| Empreinte de l'archive chiffrée (SHA-256) | `<EMPREINTE>` |
| Clé de l'enveloppe | `transit/ghsv-exports`, version `<N>` |
| Signature du manifeste | `transit/ghsv-signature`, version `<N>`, vérifiée : oui |
| Réalisé par / relu par | `<MOI>` / Julien Petit |
| Déchiffrement par | `<MEMBRE DE plateforme-admins>` (entrée du journal d'audit d'OpenBao : `<HORODATAGE>`) |

## Contenu

| Table | Lignes exportées | Lignes relues (CSV) | Lignes rechargées (base vierge) |
|---|---|---|---|
| `rendez_vous` | `<N>` | `<N>` | `<N>` |
| `flyway_schema_history` | `<N>` | `<N>` | `<N>` |

Base de relecture : PostgreSQL `<VERSION>` (VMID 3701, `vsandbox`, détruite le `<DATE>`), chargée par `schema.sql` puis `\copy` de chaque CSV.

## Durées

| Étape | Durée |
|---|---|
| Export (lecture, signature, chiffrement, dépôt) | `<MIN>` |
| Relecture (téléchargement, déchiffrement, vérifications) | `<MIN>` |
| Rechargement dans la base vierge | `<MIN>` |

Extrapolation au volume réel du GHSV (≈ 1,8 M de rendez-vous par an, 5 ans, pièces jointes ≈ 2 To/an conservées 12 mois — R-06) : `<CALCUL>` ; conforme au délai de 30 jours (ERV-02) : `<OUI/NON, avec la marge>`.

## Écarts constatés

1. `<ÉCART>` — action : `<ACTION, RESPONSABLE, ÉCHÉANCE>`.

## Ce que l'essai ne prouve pas

- Les pièces jointes, les comptes des patients et les consentements hors rappel (absents de la preuve de concept).
- La relecture **par un tiers** : à refaire avec le GHSV (ERV-03).
