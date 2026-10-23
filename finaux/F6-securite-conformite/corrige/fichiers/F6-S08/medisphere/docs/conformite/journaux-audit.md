# Journaux d'audit : traçabilité inaltérable

> `plateforme/medisphere` — `docs/conformite/journaux-audit.md` (F6-S08, SEC-3608, ferme ECA-3601).
> Propriétaire : RSSI (Sophie Laurent). Référentiels : ISO/IEC 27001:2022 A.8.15 (journalisation),
> A.8.16 (surveillance), HDS v2 (traçabilité des accès et des actions d'administration), RGPD art. 33.5
> (registre). Ce document est la description de la chaîne que l'on montre à l'auditeur.

## 1. Principe

Un journal d'audit n'a de valeur de preuve que s'il est **complet** (toutes les sources), **cohérent dans
le temps** (même référence d'horloge), **centralisé** (consultable), **inaltérable** (personne ne peut le
retoucher) et **conservé** le temps requis. « Centralisé » et « inaltérable » sont deux propriétés
distinctes : Loki centralise, l'archive en verrouillage d'objets rend inaltérable.

## 2. Sources couvertes

| Source | Ce qui est tracé | Mécanisme natif | Étiquette `job` |
|---|---|---|---|
| Kubernetes | Appels à l'API (qui, quoi, quand, sur quel objet) | Politique d'audit de l'API (M14), `/var/log/kubernetes/audit/audit.log` | `kubernetes-audit` |
| OpenBao | Lectures/écritures de secrets, authentifications, politiques | Moteur d'audit `file` (HMAC des valeurs sensibles) | `openbao-audit` |
| Keycloak | Connexions, échecs, actions d'administration | Écouteur d'événements `jboss-logging` (events + admin events) | `keycloak-audit` |
| GitLab | Événements d'audit (accès, changements de droits, poussées protégées) | `audit_json.log` (gitlab-rails) | `gitlab-audit` |
| Proxmox | Tâches (`pve01`, `pbs01`) et authentifications | `/var/log/pve/tasks/`, `journald` | `proxmox-audit` |
| FreeIPA | Modifications d'annuaire, connexions Kerberos | 389-ds `nsslapd-auditlog`, `/var/log/krb5kdc.log` | `freeipa-audit` |

Toutes vont dans le **locataire `audit`** de Loki (`X-Scope-OrgID: audit`). La politique d'audit de
Kubernetes et le HMAC d'OpenBao garantissent qu'**aucune valeur de secret** n'entre dans ce locataire.

## 3. Horodatage

Référence unique : `gw01` (chrony, M00), sur laquelle toutes les VMs se synchronisent. Chaque source
émet un horodatage que l'étape `stage.timestamp` d'Alloy utilise (sinon Loki date à la réception, ce
qui décale une chronologie d'incident). Un décalage d'horloge sur une source est lui-même une alerte.

## 4. Archive inaltérable

- Compartiment RGW **`archive-audit`** (`ceph-par1`), créé **avec** verrouillage d'objets activé dès le
  départ (versionnage obligatoire). Mode **`COMPLIANCE`** : un objet ne peut être ni supprimé ni
  remplacé avant son échéance, même par l'administrateur du RGW.
- Dépôt quotidien par le CronJob `audit-archive` (espace `observabilite`) : un fichier compressé par
  source pour la journée, un **manifeste** (période, objets, SHA-256, nombre de lignes), la **signature**
  du manifeste (`transit` d'OpenBao). `put-object --object-lock-mode COMPLIANCE
  --object-lock-retain-until-date <jour + 1 an>`.
- Éprouver d'abord en `GOVERNANCE` (verrou levable avec le bon droit, pour corriger une erreur de date),
  basculer en `COMPLIANCE` une fois la rétention validée.

## 5. Intégrité

`observabilite/outils/verifier-archive-audit.sh` (pipeline planifié et à la demande de l'auditeur) :
télécharge le manifeste et les objets d'une période, **vérifie la signature**, recalcule les condensats,
les compare. Écart → sortie ≠ 0 → alerte. C'est ce contrôle, et non Loki, qui prouve l'inaltérabilité.

## 6. Conservation et minimisation

- Locataire `audit` : **1 an** dans Loki (rétention par locataire, M22-E13) et 1 an sur l'archive
  (échéance du verrouillage).
- Journaux **applicatifs** (diagnostic) : rétention courte, inchangée. On ne les confond pas avec l'audit.
- Pourquoi pas plus d'un an : coût de stockage, requêtes plus lentes, et surtout **minimisation** (RGPD) —
  plus on garde, plus une fuite est grave et un effacement difficile. Un an couvre l'exigence et la durée
  utile d'une enquête.

## 7. Revue

À chaque revue de conformité : vérifier que les six sources émettent (alerte « trou de journalisation »),
relancer `verifier-archive-audit.sh` sur une période au hasard, contrôler l'échéance de verrouillage.
