---
id: ECA-3601
titre: "Journaux d'audit centralisés mais non inaltérables"
origine: audit-2026 (Auditia Santé, Hélène Mercier)
mesures: [8.15, 5.33, 5.28, 8.17, HDS activités 4-5]
gravite: majeur
statut: clos
ouvert-le: 2026-11-18
echeance: 2026-12-11
responsable: karim.benali
remediation: SEC-3608
clos-le: 2026-12-09
preuve: lots/2026/12/09/20261209T013004Z-quotidienne/
valideur: sophie.laurent
---

# ECA-3601 — Journaux d'audit centralisés mais non inaltérables

> Audit à blanc HDS v2 / ISO 27001 (Auditia Santé), constat d'Hélène Mercier du 2026-11-18, formalisé en F6-S07 (SEC-3607).

## Constat
Les journaux d'audit de l'API Kubernetes (M22), d'OpenBao (M25), de Keycloak et de FreeIPA (M24) sont centralisés dans Loki (locataire `audit`, rétention un an). Rien ne permet de démontrer qu'ils n'ont pas été modifiés ou supprimés : le compartiment `loki-k8s-par1` du RGW n'est pas verrouillé et appartient à l'utilisateur RGW `loki`, administré par la Plateforme — les personnes dont l'activité est tracée. Les événements d'audit de GitLab et les tâches et connexions de Proxmox (`pve01`, PBS de `hp01`) restent sur leurs hôtes, avec leurs propres durées (de quelques jours à quelques semaines).

## Référence
- ISO/IEC 27001:2022 : **8.15** (journalisation : protection des journaux), **5.33** (protection des enregistrements), 5.28 (recueil des preuves), 8.17 (synchronisation des horloges).
- HDS : traçabilité des accès aux données de santé (activités 4 et 5) ; valeur probante des traces.

## Preuves
- Configuration du compartiment `loki-k8s-par1` : `get-object-lock-configuration` → absente.
- `values.yaml` de Loki (`plateforme/observabilite`) : rétention `audit` 8760 h, aucune copie ailleurs.
- Entretien du 2026-11-19 (question 6) : la lecture d'un Secret de `mediagenda-prod` se retrouve dans Loki, mais l'équipe ne peut pas prouver l'intégrité de la réponse.
- Inventaire des sources : 4 sources centralisées sur 6 (GitLab et Proxmox absents du locataire `audit`).

## Gravité
**Majeure** : l'exigence de protection des journaux n'est satisfaite pour aucune source ; une enquête (ou un litige) ne pourrait pas s'appuyer sur ces traces.

## Cause
La journalisation a été construite module par module (M14, M22, M25) avec un objectif d'exploitation (chercher, alerter), jamais avec un objectif probatoire ; aucune exigence d'intégrité n'avait été écrite.

## Correction
Aucune correction immédiate possible sans conception ; mesure conservatoire : exports quotidiens du locataire `audit` déposés par `ms-preuves` dans `preuves-conformite` (verrouillé) en attendant l'archive dédiée.

## Action corrective
F6-S08 : GitLab et Proxmox ajoutés au locataire `audit` (six sources), archive dans un compartiment verrouillé en `COMPLIANCE` d'un an, manifeste signé par période et contrôle d'intégrité automatisé, politique de conservation écrite (`docs/conformite/journaux-audit.md`).

## Responsable
Karim Benali (Plateforme), validation Sophie Laurent.

## Échéance
2026-12-11.

## Statut
clos le 2026-12-09 (SEC-3608, F6-S08), validé par Sophie Laurent.

## Preuve de clôture
Le lot `lots/2026/12/09/20261209T013004Z-quotidienne/` de `preuves-conformite` (signé, verrouillé, antérieur à la clôture) contient :
- **P-AUD-01** — lignes des dernières 24 h pour chacun des six sélecteurs du locataire `audit` (`{job="kubernetes-audit"}`, `{service="openbao"}`, `{service="keycloak"}`, `{service="freeipa"}`, `{service="gitlab"}`, `{service="proxmox"}`), aucune source muette ;
- **P-AUD-02** — verrouillage (`COMPLIANCE`, 365 jours) et versionnage du compartiment `archive-audit`, manifeste et signature de la veille présents ;
- **P-CTL-01** — dernier pipeline planifié de `plateforme/observabilite` (job `archive:verifier`, `outils/verifier-archive-audit.sh` sur la veille) : réussi.

Pièces versionnées citées : `docs/conformite/journaux-audit.md` (politique), MR de `plateforme/ansible` (GitLab et Proxmox vers le locataire `audit`) et de `plateforme/k8s` (CronJob `audit-archive`). L'essai de suppression d'une version d'objet sous `COMPLIANCE` (refusé, `AccessDenied`) est consigné dans le ticket SEC-3608.
