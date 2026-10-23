---
id: ECA-3603
titre: "Sauvegardes Velero et exports non chiffrés côté serveur"
origine: audit-2026 (Auditia Santé, Hélène Mercier)
mesures: [8.13, 8.24, 5.33, 7.10, HDS activité 6]
gravite: majeur
statut: ouvert
ouvert-le: 2026-11-18
echeance: 2026-12-18
responsable: karim.benali
remediation: SEC-3609
clos-le:
preuve:
valideur:
---

# ECA-3603 — Sauvegardes Velero et exports non chiffrés côté serveur

> Audit à blanc (Auditia Santé), constat du 2026-11-18, formalisé en F6-S07 (SEC-3607).

## Constat
Les sauvegardes Velero (compartiment `velero-k8s-par1` de `s3-01`) contiennent deux choses : les **manifestes** des objets de chaque espace sauvegardé — Secrets compris, encodés en base64, dans une archive compressée **non chiffrée** — et les **données des volumes**, copiées par Kopia dans un dépôt chiffré avec la **phrase de passe par défaut** que Velero crée dans le Secret `velero-repo-credentials` (valeur publique dans la documentation : équivalent à un chiffrement absent). Les exports déposés sur `s3-01` (extractions, définitions RabbitMQ) sont en clair. Tout est répliqué tel quel vers `s3-02` (PAR2, si le F5 est fait). Les sauvegardes PBS et les instantanés d'OpenBao, eux, sont chiffrés (clé PBS, `age`).

## Référence
- ISO/IEC 27001:2022 : **8.13** (sauvegarde), **8.24** (cryptographie), 5.33, 7.10.
- HDS : activité 6 (sauvegarde externalisée des données de santé) ; confidentialité des copies.

## Preuves
- Démonstration du 2026-11-18 (identité de lecture du compartiment, accord de Sophie) : archive de la sauvegarde de `mediagenda-recette` ouverte, Secret de l'espace lisible (données de recette).
- `velero-repo-credentials` (espace `velero`) : valeur inchangée depuis l'installation (M16).
- Configuration du `BackupStorageLocation` `s3-01` et du dépôt Kopia (M16).
- Matrice des chiffrements : PBS oui, instantanés OpenBao oui, Velero non, exports non.

## Gravité
**Majeure** : des copies de données de santé (production) sont stockées et répliquées sans protection de confidentialité au repos indépendante du stockage.

## Cause
Velero a été installé au M16 pour la restauration (objectif : savoir restaurer), le chiffrement n'a pas été une exigence ; l'hypothèse implicite « `s3-01` est interne, donc sûr » n'a jamais été écrite ni revue.

## Correction
Accès en lecture aux compartiments de sauvegarde réduits à Velero et au compte de restauration (revue des identités de `s3-01`).

## Action corrective
F6-S09 : chiffrement des sauvegardes Velero et des exports, clé dans OpenBao, procédure de restauration éprouvée par une restauration d'essai.

## Responsable
Karim Benali.

## Échéance
2026-12-18.

## Statut
ouvert

## Preuve de clôture
_(à la clôture : lot `ms-preuves` cité dans l'en-tête, et ce qu'il contient)_
