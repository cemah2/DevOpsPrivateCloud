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

| Source | Ce qui est tracé | Mécanisme natif | Sélecteur (locataire `audit`) | Depuis |
|---|---|---|---|---|
| Kubernetes | Appels à l'API (qui, quoi, quand, sur quel objet) | Politique d'audit de l'API, `/var/log/kubernetes/audit/audit.log` | `{job="kubernetes-audit"}` | M14, M22-E07 |
| OpenBao | Requêtes et réponses (valeurs sensibles en HMAC) | Dispositif d'audit **déclaré** dans `openbao.hcl` (`fichier`, `/var/log/openbao/audit.log`) : l'API `sys/audit` refuse d'en activer un depuis OpenBao 2.4 | `{service="openbao"}` | M25-E21 |
| Keycloak | Connexions, échecs, actions d'administration | Événements et événements d'administration, journal de `keycloak.service` | `{service="keycloak"}` | M24-E26 |
| FreeIPA | Liaisons et recherches LDAP, tickets Kerberos, erreurs de l'API | 389-ds `access`, `krb5kdc.log`, `httpd/error_log` | `{service="freeipa"}` | M24-E26 |
| GitLab | Événements d'audit (connexions, droits, jetons, comptes bloqués/débloqués) | `/var/log/gitlab/gitlab-rails/audit_json.log` (partiel en édition Free) | `{service="gitlab"}` | **F6-S08** |
| Proxmox | Connexions, tâches et leur auteur, ACL (`pve01`, PBS de `hp01`) | journal de `pvedaemon`, `pveproxy`, `proxmox-backup(-proxy)` | `{service="proxmox"}` | **F6-S08** |

Toutes vont dans le **locataire `audit`** de Loki (`X-Scope-OrgID: audit`), par le rôle `alloy` de
`plateforme/ansible` (variables `alloy_audit_unites`, `alloy_audit_fichiers`) ; étiquettes de la liste
fermée du M22 (`job`, `host`, `site`, `service`). La politique d'audit de Kubernetes (niveau `Metadata`
pour les Secrets) et le HMAC d'OpenBao garantissent qu'**aucune valeur de secret** n'entre dans ce locataire.

## 3. Horodatage

Référence unique : `gw01`/`gw02` (chrony, M00), sur laquelle toutes les VMs et les deux hôtes physiques se
synchronisent. Les sources lues dans journald gardent l'heure de journald ; les fichiers JSON sont datés
par leur propre champ (`requestReceivedTimestamp` pour Kubernetes, `time` pour GitLab et OpenBao) par
l'étape `stage.timestamp` d'Alloy, sinon Loki daterait à la lecture. Une ligne sans heure lisible garde
l'heure de lecture (jamais une heure inventée). Un décalage d'horloge sur une source est lui-même alerté.

## 4. Archive inaltérable

- Compartiment RGW **`archive-audit`** (`ceph-par1`), créé **avec** verrouillage d'objets
  (`plateforme/ceph`, `rgw-preuves.sh` avec `COMPARTIMENT=archive-audit`) : utilisateurs `archive-audit`
  (écriture, clés dans `kv/plateforme/archive-audit/rgw-ecriture`) et `archive-audit-lecture` (lecture
  par politique de compartiment). Rétention par défaut **`COMPLIANCE` 365 jours** : un objet ne peut être
  ni supprimé ni remplacé avant son échéance, même par le propriétaire du compartiment.
- Dépôt quotidien par le CronJob `journaux/audit-archive` (`plateforme/k8s`, image
  `plateforme/audit-archive`, outil `archiver-audit` de `plateforme/observabilite`) : pour la veille, un
  `<source>.jsonl.gz` par source, `manifeste.json` (période, objets, SHA-256, nombre de lignes) et
  `manifeste.sig` (signature du SHA-256 du manifeste par `transit/audit-archive`), sous le préfixe
  `AAAA-MM-JJ/`. Une période déjà archivée n'est jamais réécrite.
- Éprouvé d'abord en `GOVERNANCE` 1 jour sur des périodes d'essai, puis bascule en `COMPLIANCE` le
  2026-12-07 ; essai de suppression d'une version sous `COMPLIANCE` : `AccessDenied` (SEC-3608).

## 5. Intégrité

`outils/verifier-archive-audit.sh` de `plateforme/observabilite` (pipeline planifié `archive:verifier`
chaque matin sur la veille, et à la demande de l'auditrice sur une période au hasard) : télécharge le
manifeste et les objets d'une période, **vérifie la signature** (`transit/verify/audit-archive`),
recalcule les condensats, vérifie qu'aucun objet ne manque. Écart → sortie ≠ 0 → pipeline rouge → alerte.
C'est ce contrôle, et non Loki, qui prouve que rien n'a bougé.

**Limites** (écrites, pas cachées) : l'archive prouve ce que Loki a **reçu** ; une source qui n'a rien
émis (collecteur arrêté) laisse un trou, couvert par l'alerte « source d'audit muette » et la preuve
P-AUD-01 ; l'administrateur de Ceph peut détruire le pool sous le RGW (même limite que
`preuves-conformite`, `preuves.md`) ; GitLab Free ne journalise pas tous les événements d'audit.

## 6. Conservation et minimisation

- Locataire `audit` : **1 an** dans Loki (rétention par locataire, M22-E13) et 1 an sur l'archive
  (échéance du verrouillage).
- Journaux **applicatifs** (diagnostic) : rétention courte, inchangée. On ne les confond pas avec l'audit.
- Pourquoi pas plus d'un an : coût de stockage, requêtes plus lentes, et surtout **minimisation** (RGPD) —
  plus on garde, plus une fuite est grave et un effacement difficile. Un an couvre l'exigence et la durée
  utile d'une enquête.

## 7. Revue

À chaque revue de conformité : vérifier que les six sources émettent (alerte « trou de journalisation »),
relancer `verifier-archive-audit.sh` sur une période au hasard, contrôler l'échéance de verrouillage
(P-AUD-02 dans les lots quotidiens).
