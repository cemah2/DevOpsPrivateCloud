---
id: ECA-3611
titre: "Alertes de sécurité réduites au silence pour 60 jours"
origine: audit-2026, F6-S04 (auditeur interne)
mesures: [8.16, 5.25, 8.15, HDS activité 5]
gravite: mineur
statut: clos
ouvert-le: 2026-11-17
echeance: 2026-11-24
responsable: karim.benali
remediation: SEC-3604
clos-le: 2026-11-18
preuve: lots/2026/11/18/20261118T010507Z-quotidienne/
valideur: sophie.laurent
---

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
Un silence peut être posé par toute personne qui joint l'API d'Alertmanager (MGMT), sans durée maximale ni revue. L'essai de charge de la recette générait des alertes `AlerteFalco` faussement positives (le scénario lançait un shell dans les pods de recette pour préparer ses données) : la règle ou le scénario auraient dû être corrigés, pas les alertes réduites au silence — et le silence, posé large, a aussi tu les alertes d'audit.

## Correction
Silence expiré (`amtool silence expire <ID>`) le 2026-11-17 10:12 ; alertes de la nuit relues dans Loki (aucune action malveillante) ; scénario de l'essai de charge corrigé (données préparées par un Job, plus de shell dans les pods) et exception Falco étroite, datée, pour la période de l'essai (MR `plateforme/gitops`, valeurs de Falco).

## Action corrective (prévention)
- Alerte `SilenceLong` : tout silence actif de plus de 24 h ou visant `AlerteFalco|Audit.*` déclenche une alerte vers `securite@` (règle Prometheus sur `alertmanager_silences{state="active"}` complétée par la preuve quotidienne P-SUP-01).
- Règle écrite dans RB-360 : un silence sur une alerte de sécurité se pose par ticket `SEC-`, 24 h au plus, par l'astreinte.

## Responsable
Karim Benali.

## Échéance
2026-11-24.

## Statut
**clos** le 2026-11-18 (corrigé le 17 à 10:12, confirmé par le lot quotidien du 18).

## Preuve de clôture
Lot `20261118T010507Z-quotidienne` : P-SUP-01 sans silence actif ; règle `SilenceLong` sur `main` de `plateforme/observabilite` (commit `<SHA>`) et son test `promtool`.
