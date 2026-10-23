# ECA-3611 — Alertes de sécurité réduites au silence pour 60 jours

> Trouvé en F6-S04 (audit à blanc, SEC-3604), le 2026-11-17. Exemple de fiche : un écart par candidat injecté, même forme.

## Constat
Un silence actif dans l'Alertmanager de `k8s-par1` (`alertmanager.apps.par1.medisphere.internal`) couvre `alertname=~"AlerteFalco|Audit.*"` du 2026-11-16 22:41 UTC au 2027-01-15 : aucune alerte de Falco ni des règles d'audit de l'API (exécution en production, lecture de Secret par une personne, liaison de rôle de cluster, bris de glace) n'est plus envoyée par courriel. Auteur déclaré : `lucas.martin` ; commentaire : « Trop de bruit pendant les essais de charge de la recette, je remets après. »

## Référence
- ISO/IEC 27001:2022 : **8.16** (activités de surveillance), **5.25** (évaluation des événements), 8.15 (journalisation).
- HDS : traçabilité et détection des accès aux données de santé (activité 5).

## Preuves
- `amtool silence query -o extended` (ou API `GET /api/v2/silences`) : identifiant du silence, filtres, auteur, dates.
- Preuve P-SUP-01 : absente du lot du 2026-11-16, présente dans celui du 2026-11-17 (`silences_actifs`).
- Mailpit : aucune alerte `AlerteFalco` depuis le 2026-11-16 22:41 alors que Falco en a émis 3 (journaux de `falcosidekick`, locataire `plateforme` de Loki).

## Gravité
**Mineure** (non-conformité ponctuelle : un processus de surveillance existe et fonctionne par ailleurs ; aucune alerte critique ne s'est produite pendant la période). Aurait été **majeure** si elle avait masqué un incident.

## Cause
Un silence peut être posé par toute personne qui joint l'API d'Alertmanager (MGMT), sans durée maximale ni revue. L'essai de charge générait des alertes `AuditExecProduction` faussement positives (exécutions dans les pods par le scénario) : la règle aurait dû être corrigée, pas réduite au silence.

## Correction
Silence expiré (`amtool silence expire <ID>`) le 2026-11-17 10:12 ; alertes de la nuit relues dans Loki (aucune action malveillante) ; règle `AuditExecProduction` corrigée pour exclure le compte de service de l'essai de charge (MR `plateforme/observabilite`).

## Action corrective (prévention)
- Alerte `SilenceLong` : tout silence actif de plus de 24 h ou visant `AlerteFalco|Audit.*` déclenche une alerte vers `securite@` (règle Prometheus sur `alertmanager_silences{state="active"}` complétée par la preuve quotidienne P-SUP-01).
- Règle écrite dans RB-360 : un silence sur une alerte de sécurité se pose par ticket `SEC-`, 24 h au plus, par l'astreinte.

## Responsable
Karim Benali.

## Échéance
2026-11-24.

## Statut
**clos** le 2026-11-17.

## Preuve de clôture
Lot `20261118T010507Z-quotidienne` : P-SUP-01 sans silence actif ; règle `SilenceLong` sur `main` de `plateforme/observabilite` (commit `<SHA>`) et son test `promtool`.
