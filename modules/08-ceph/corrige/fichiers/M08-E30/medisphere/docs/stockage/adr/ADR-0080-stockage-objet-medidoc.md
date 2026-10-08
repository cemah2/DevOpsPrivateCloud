# ADR-0080 — Stockage objet des documents de MédiDoc

- **Statut** : accepté
- **Date** : 2026-10-XX
- **Décideurs** : Claire Morel (décision), Sophie Laurent (sécurité), Julien Petit (MédiDoc), équipe Plateforme
- **Ticket** : PLAT-956

## Contexte et problème

MédiDoc stocke des **données de santé** (comptes rendus, ordonnances numérisées, imagerie légère) : environ 2 To la première année, objets de 50 Kio à 20 Mio, accès par l'API S3 depuis le SDK Go (URL présignées, versionnage). Exigences de Sophie : chiffrement en transit et au repos, cloisonnement par application, traçabilité des accès, sauvegarde hors site, conservation réglementaire. Deux solutions existent déjà : **SeaweedFS** sur `s3-01` (socle, porte l'état OpenTofu et les artefacts) et **RGW** sur `ceph-par1`.

## Critères (pondération sur 5)

| Critère | Poids |
|---|---|
| C1 Redondance, domaines de panne | 5 |
| C2 Chiffrement en transit et au repos | 5 |
| C3 Cloisonnement (comptes, politiques, quotas) | 4 |
| C4 Versionnage, verrouillage d'objets (rétention) | 3 |
| C5 Journalisation des accès | 4 |
| C6 Sauvegarde hors site | 4 |
| C7 Indépendance : ce qui tombe avec quoi | 5 |
| C8 Compatibilité S3 (SDK Go, présignage) | 3 |
| C9 Exploitation (supervision, mises à jour, compétences) | 3 |
| C10 Coût (mémoire, disque) dans le lab et en cible | 2 |

## Options

| | O1 SeaweedFS de `s3-01` | O2 RGW de `ceph-par1` | O3 instance dédiée (SeaweedFS ou RGW séparé) |
|---|---|---|---|
| C1 | une VM, un disque (`hdd-bulk`) : aucune redondance (M05) — **1** | 3 copies sur 3 hôtes, 2 démons RGW + VIP (E11) — **4** | selon la conception ; un SeaweedFS mono-VM n'apporte rien — **2** |
| C2 | TLS (M05) ; au repos : non (pas de chiffrement mis en place) — **2** | TLS step-ca (E11), msgr2 `secure` (E27), OSD LUKS (E27, E46) — **4** | à construire — **2** |
| C3 | identités et politiques simples, pas de comptes multi-tenants — **2** | comptes RGW, utilisateurs IAM, politiques, quotas par compte (E12) — **5** | instance par application : cloisonnement par construction, coût élevé — **4** |
| C4 | versionnage selon la version de SeaweedFS : **à vérifier**, non exercé — **2** | versionnage et *Object Lock* S3 disponibles (à mettre en œuvre) — **4** | idem selon le produit — **3** |
| C5 | journaux d'accès limités — **2** | journal des opérations RGW (`rgw_enable_ops_log`) et journaux d'accès HTTP de l'ingress — **3** | — **3** |
| C6 | non sauvegardé hors site aujourd'hui — **1** | v1 : non (E25 couvre RBD et configuration) ; action ci-dessous — **2** | à construire — **2** |
| C7 | partage `s3-01` avec l'état OpenTofu : une saturation par MédiDoc empêche de réparer l'infrastructure — **1** | indépendant du socle ; partage `ceph-par1` avec OpenStack et Kubernetes (quotas, supervision) — **3** | indépendant — **5** |
| C8 | S3 compatible (état OpenTofu, `use_lockfile`) — **4** | S3 compatible, SigV4 corrigé en 20.2.4 (CVE-2026-54330) — **4** | — **4** |
| C9 | connu de l'équipe (M05), une VM — **4** | exercé dans tout M08, supervisé (E24), RB-082 — **4** | une brique de plus à exploiter — **2** |
| C10 | faible — **5** | marginal (cluster existant) — **4** | une VM ou un cluster de plus — **2** |
| **Score pondéré** (max. 190) | **80** | **139** | **112** |

(Score = somme des notes × poids ; les notes s'appuient sur les exercices cités, aucune sur une possibilité non testée.)

## Décision

**O2 : MédiDoc stocke ses documents dans le RGW de `ceph-par1`**, compte RGW `medidoc` (E12), point d'entrée `https://rgw.par1.medisphere.internal`. **`s3-01` reste le stockage de la plateforme** (état OpenTofu, artefacts, sauvegardes du socle), sans donnée métier : la plateforme doit pouvoir se reconstruire sans dépendre de ce qu'elle héberge, et inversement une saturation par une application ne doit jamais bloquer `tofu apply`.

## Conséquences

**Positives** : redondance et chiffrement déjà en place et vérifiés ; cloisonnement par compte, extensible aux autres applications (MédiNotif, E34) ; un seul stockage métier à exploiter.

**Négatives et actions**

| Conséquence | Action | Où |
|---|---|---|
| Les objets ne sont pas sauvegardés hors du cluster | sauvegarde des compartiments vers PAR2 (rclone ou réplication multisite vers un RGW de PAR2) | final F5 (PRA), ticket SEC à ouvrir |
| `ceph-par1` devient critique pour une application patient | supervision RGW (E24) puis SLO (M21) ; astreinte ; RB-083+ (palier 4) | M08, M21 |
| Rétention réglementaire non appliquée techniquement | versionnage puis *Object Lock* en mode gouvernance, à concilier avec le droit à l'effacement (RGPD) — avis du DPO | M27 ou F6 |
| Clés d'accès S3 longues durées | rotation semestrielle, puis identités par OIDC/STS | M24, M25 |
| Journalisation d'accès incomplète pour l'audit | journal des opérations RGW vers la pile de journaux | M22 |
| Un seul site | PRA à PAR2 | F5 |
