# RB-351 — Retour à PAR1 après un PRA

| | |
|---|---|
| Version | 1.0 (exercice 2026-1, rédigé avant le retour, annoté après : CHG-3512) |
| Déclenchement | décision de Claire Morel (fin de PRA), fiche CHG-3512 validée |
| Rôles | pilote : Nadia Roussel ; exécution : équipe Plateforme (deux personnes : une à PAR1 depuis `pve01`, une à PAR2 depuis `adm02`) ; validation métier : Julien Petit ; preuves : Sophie Laurent |
| Durée de référence | phase A 45 min ; phase B 2 à 3 h (rattrapage de la base) ; phase C (coupure) ≤ 15 min ; phase D 1 h |
| Entrées | RB-350, main courante INC-6109, `mode-degrade.md`, enveloppe de reprise |

> Principe : **PAR2 est la vérité** depuis la promotion de `mediagenda-db-par2`. Tout ce que PAR1 a écrit depuis la divergence est une copie à examiner, jamais une source. Rien ne coule de PAR1 vers PAR2 avant d'avoir été neutralisé.

## 0. Préalables (go / no-go)

| # | Condition | Comment la vérifier | Si non |
|---|---|---|---|
| 0.1 | PAR2 sert les trois noms, mode dégradé stable depuis ≥ 2 h | sonde, `lab/bin/check F5 11` | attendre |
| 0.2 | Sauvegarde de base de `mediagenda-db-par2` < 24 h, archivage OK | `kubectl cnpg status` | en faire une |
| 0.3 | PAR1 matériellement disponible (exercice : isolé, intact) | équipe sur place / `pve01` | rester à PAR2 |
| 0.4 | Fenêtre de coupure annoncée aux cabinets la veille (≤ 15 min, hors 8 h-10 h) | message d'état | reporter |
| 0.5 | Deux personnes, les deux accès (`pve01` et VPN de secours de `hp01`) | appel | reporter |
| 0.6 | Flux de retour ouverts : `k8s-par1` (VLAN 40) → `s3-02:8333` à travers `wg0` (bordure et `hp01`), identité S3 en **lecture** `cnpg-par1-lecture` sur `cnpg-k8s-par2` de `s3-02` | matrice des flux, MR | phase B bloquée |

## Phase A — Neutraliser PAR1 (isolement en place, depuis `pve01`)

Accès : `root@pve01:~# ssh adm01`, puis kubeconfig de **bris de glace** de `k8s-par1` (RB-240 ; l'OIDC demande un navigateur). GitLab, OpenBao et Keycloak de PAR1 sont joignables depuis `adm01`.

| # | Geste | Condition de passage | Retour arrière |
|---|---|---|---|
| A1 | Suspendre l'auto-synchronisation d'Argo CD de PAR1 pour les Applications de production (`argocd app set <APP> --sync-policy none`), noté dans la main courante | `argocd app get` : *Sync Policy: Manual* | réactiver |
| A2 | Arrêter les écrivains internes de PAR1 : `temoin-rpo` suspendu, API de MédiAgenda de prod à 0 (Rollout) | aucun pod d'API, CronJob `suspend: true` | remettre |
| A3 | Forcer l'archivage du dernier segment : `SELECT pg_switch_wal()` sur le primaire de PAR1 | `Last Archived WAL` récent | — |
| A4 | **Exporter la divergence** (voir §A4 ci-dessous) : vrai RPO, témoins de PAR1, liste des écritures de PAR1 postérieures au dernier témoin vu à PAR2 | fichiers exportés, sommes de contrôle | — |
| A5 | Copie de sécurité : `VolumeSnapshot` (classe `ceph-rbd`) de chaque PVC de `mediagenda-db` | `readyToUse: true` | — |
| A6 | Clôturer (*fencing*) toutes les instances : `kubectl cnpg fencing on mediagenda-db "*" -n mediagenda-prod` | `kubectl cnpg status` : instances clôturées, PostgreSQL arrêté | `fencing off` |
| A7 | Désactiver les *push mirrors* de GitLab vers `adm02` (API `PUT /projects/:id/remote_mirrors/:id` `enabled=false`) pour chaque projet miroité | liste des miroirs : `enabled: false` | réactiver |
| A8 | Côté PAR2 (depuis `adm02`) : arrêter et désactiver les unités `filer.sync` (`seaweedfs-filer-sync@*`) et la minuterie `rclone` de `s3-02` | `systemctl is-active` : inactive | réactiver |
| A9 | Constat de Sophie (A1 à A8), ligne `[décision]` du pilote : « levée autorisée » | main courante | — |
| A10 | Lever l'isolement : `root@pve01:~/DevOpsPrivateCloud# lab/bin/break F5 9 --annuler` | `wg show wg0` : poignée de main ; `adm02` joint `git01` | aucun : l'isolement ne se repose pas (refaire A1-A9 si besoin) |

### A4 — Export de la divergence (avant A6)

T0 est dans `/var/lib/workbook/f5-t0` de `gw01` et de `adm02` (`T0_EPOCH`). `D` = horodatage du dernier témoin vu à PAR2 (relevé de RB-350, main courante).

```sql
-- Vrai RPO : dernier témoin écrit à PAR1 AVANT T0
SELECT max(cree_le) FROM rendez_vous WHERE praticien = 'PRA-TEMOIN' AND cree_le < to_timestamp(<T0_EPOCH>);
-- Témoins de PAR1 après D (preuve versée dans Git : aucune donnée de patient)
\copy (SELECT id, cree_le, motif FROM rendez_vous WHERE praticien = 'PRA-TEMOIN' AND cree_le > '<D>' ORDER BY cree_le) TO 'temoins-par1-divergence.csv' CSV HEADER
-- Écritures réelles de PAR1 après D (DONNÉES DE PATIENTS : jamais dans Git ; chiffré, remis à Julien)
\copy (SELECT * FROM rendez_vous WHERE praticien <> 'PRA-TEMOIN' AND cree_le > '<D>' ORDER BY cree_le) TO 'rdv-par1-divergence.csv' CSV HEADER
```
Limites écrites dans CHG-3512 : une **annulation** (DELETE) faite à PAR1 après D ne se voit pas par `cree_le` ; les **identifiants** des deux côtés se recouvrent après la divergence (chaque site a continué sa séquence) : une réintégration éventuelle passe par l'API de MédiAgenda (nouvel identifiant), jamais par une copie SQL.

## Phase B — Resynchroniser PAR2 → PAR1 (PAR2 sert les patients)

| # | Geste | Condition de passage |
|---|---|---|
| B1 | **Code et documentation** : pour chaque projet miroité modifié pendant le PRA, récupérer la branche `main` du miroir dans un clone de GitLab (branche `pra/inc-6109`), MR vers `main` (avance rapide si GitLab n'a pas bougé), fusion | `main` de GitLab = `main` du miroir pour chaque projet |
| B2 | **Réplications de temps normal, sens PAR1 → PAR2** : réactiver et relancer les unités `seaweedfs-filer-sync@*` sur `s3-02` (`filer.sync` rattrape les événements de `s3-01` depuis T0 : archives de l'ancien PAR1 sous `mediagenda-db-prod-day0`, sans effet sur les compartiments propres à PAR2) | unité active, retard en baisse |
| B3 | **Base, reconstruction de PAR1 en réplique de PAR2** : `ObjectStore` `cnpg-s3-par2` déclaré en S06 (lecture de `cnpg-k8s-par2` sur `s3-02`, identité `cnpg-par1-lecture`) ; MR dans `mediagenda/deploiement` (overlay de prod) : `bootstrap.recovery` depuis `mediagenda-db-par2`, `replica.primary: mediagenda-db-par2`, `replica.source: mediagenda-db-par2`, archivage sous un **nouveau** `serverName` `mediagenda-db-prod-pra1` ; suppression du `Cluster` clôturé (les instantanés de A5 restent) ; synchronisation de la seule base (`argocd app sync … --resource postgresql.cnpg.io:Cluster:mediagenda-db`) | `kubectl cnpg status` : réplique, *designated primary* qui rejoue ; retard < 1 min |
| B4 | **Autorité de la nouvelle base pour OpenBao de PAR1** (F1-S11) : la nouvelle `mediagenda-db-ca` copiée dans `plateforme/ansible` (`files/openbao/postgresql/`), rôle `coffre` rejoué | `bao read db-mediagenda/creds/…` par l'ExternalSecret : `Ready` |
| B5 | **MédiDoc** : copie (jamais synchronisation) des objets écrits à PAR2 : `rclone copy s3-02:medidoc-documents/documents rgw:medidoc-documents/documents --max-age <depuis T0>` puis `rclone check --one-way` ; liste des identifiants (clés `documents/<id>` modifiées après T0 sur `s3-02`) → `docs/pra/mesures/<exercice>/medidoc-par2.csv` | `rclone check` sans différence |
| B6 | **Legacy-RDV** : préparer le transfert de sa base (sauvegarde mariadb-operator de PAR2 vers un compartiment de `s3-02`, `Restore` à PAR1 qui le lit) et de ses pièces jointes (copie depuis le volume local de PAR2) ; répétition sur la recette de PAR1 | répétition < 5 min |
| B7 | **Témoins** : `outils/pra/mesures-pra.sh temoins-depuis <T0_EPOCH>` à PAR2 → `temoins-par2.csv` (mis à jour en C3) | fichier dans le clone de travail |

## Phase C — Coupure et bascule par jetons (fenêtre annoncée)

Heure de début de coupure notée (`[action]`) ; la sonde mesure. Ordre impératif.

| # | Geste | Condition de passage | Retour arrière (rester à PAR2) |
|---|---|---|---|
| C1 | Geler les écritures à PAR2 : API de MédiAgenda, MédiDoc, Legacy-RDV à 0 ; `temoin-rpo` de PAR2 suspendu ; file `notifications` de PAR2 vide | aucun pod applicatif, file à 0 message | remettre les réplicas |
| C2 | Derniers deltas : `rclone copy` MédiDoc (B5) ; base de Legacy-RDV (B6) ; `temoins-par2.csv` final (B7) | contrôles B5/B6 verts | — |
| C3 | **Rétrograder PAR2** (fichier de site `sites/par2/mediagenda-prod/50-mediagenda-db-par2.yaml`, commité dans le miroir de `plateforme/k8s`, puis `kubectl apply --server-side` depuis `adm02`) : `spec.replica.primary: mediagenda-db` ; dans `externalClusters`, `mediagenda-db` lit désormais `serverName: mediagenda-db-prod-pra1` (la nouvelle archive de PAR1, copiée par `filer.sync`) | `kubectl get cluster mediagenda-db-par2 -n mediagenda-prod -o jsonpath='{.status.demotionToken}'` non vide | `spec.replica.primary: mediagenda-db-par2` (PAR2 n'a pas perdu sa ligne temporelle) |
| C4 | **Promouvoir PAR1** (MR dans `mediagenda/deploiement`, une seule modification) : `replica.primary: mediagenda-db` **et** `replica.promotionToken: <JETON>` ; réactiver l'auto-synchronisation de l'Application de prod | `kubectl cnpg status mediagenda-db` : primaire ; nouvelle ligne temporelle | aucun simple : une fois PAR1 promu, revenir à PAR2 = recommencer B3 dans l'autre sens |
| C5 | Applications de PAR1 : API (réplicas de prod), `temoin-rpo` réactivé ; contrôle de Julien (création d'un rendez-vous par `mediagenda.apps.par1…`) | `/pret` 200, création 201 | — |
| C6 | **DNS** : sur dns01, incrémenter la série de `medisphere.internal` (et de `par1.medisphere.internal`, `par2.medisphere.internal`) au-delà de celle de dns03 ; sur dns03, `pdnsutil zone set-kind <zone> secondary` puis `pdns_control retrieve <zone>` ; vider les caches des récurseurs | dns01 et dns03 : même série, CNAME vers `*.apps.par1` ; sonde : 2xx `par1` | sur dns03, repasser la zone en `native` et remettre les CNAME vers PAR2 |
| C7 | Fin de coupure notée quand la sonde voit `par1` sur les trois noms ; message d'état | `mesures-pra.sh coupure mediagenda.medisphere.internal <LEVEE>` | — |

## Phase D — Retour en veille et clôture

| # | Geste | Condition de passage |
|---|---|---|
| D1 | Retirer le jeton de la spécification de PAR1 (MR de nettoyage, sans effet sur un cluster déjà promu) | Application `Synced` |
| D2 | `mediagenda-db-par2` suit PAR1 (`replica.primary: mediagenda-db`) ; retard < 15 min | `kubectl cnpg status` ; âge du témoin à PAR2 |
| D3 | Fichiers de site de PAR2 revenus à la veille (applications à 0, témoin suspendu), commit dans le miroir **puis** dans GitLab | aucun pod applicatif à PAR2 |
| D4 | Miroirs : `main` du miroir = `main` de GitLab (B1 rejoué pour les commits de C), puis *push mirrors* réactivés | dernière mise à jour des miroirs « réussie » |
| D5 | Minuterie `rclone` RGW → `s3-02` réactivée (le RGW contient tout ce qui a été écrit à PAR2 ; un document supprimé à PAR2 pendant le PRA réapparaîtrait à `s3-02` : liste en main courante) | une exécution réussie |
| D6 | Coffre : 3501 détruite, `bao-par2` arrêté ; secrets créés dans `bao-par2` pendant le PRA recréés à PAR1 (liste), baux dynamiques de `bao-par2` révoqués avant l'arrêt | `controle-preparation` vert |
| D7 | Sauvegardes de PAR1 : sauvegarde complète PBS lancée (aucune n'est passée pendant l'isolement) ; sauvegarde de base CNPG de `mediagenda-db` (première sous `mediagenda-db-prod-pra1`) | tâches OK |
| D8 | Instantanés de A5 et exports de divergence : conservés jusqu'à la clôture du rapport (S13), puis supprimés (décision écrite) | ticket PLAT-35xx |
| D9 | INC-6109 `[clôture]` ; main courante versée dans GitLab ; `lab/bin/check F5 12` | vert |

## Ce qui rend ce runbook dangereux

- Lever l'isolement avant A6-A8 : PAR1 se croit primaire, `filer.sync` et les miroirs coulent vers PAR2, la minuterie `rclone` **efface** à `s3-02` les documents écrits pendant le PRA.
- Promouvoir PAR1 sans jeton : second basculement, PAR2 à reconstruire, et les écritures entre le gel et la promotion perdues.
- Réutiliser `mediagenda-db-prod-day0` pour la nouvelle base de PAR1 : deux lignées dans la même archive (le plugin le refuse, et il a raison).
- Oublier que le secondaire PowerDNS refuse une série inférieure à la sienne : dns03 servirait encore PAR2, sans erreur visible.
