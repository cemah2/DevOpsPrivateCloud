# RB-082 — Mettre à jour Ceph (cephadm)

> Propriétaire : équipe Plateforme · Créé : M08-E26 (CHG-952, 20.2.3 → 20.2.4) · Durée : 1 h à 2 h pour une version mineure · Fenêtre : heures ouvrées, hors sauvegardes (01:00-03:00)

## 0. Quand utiliser ce runbook

Toute montée de version de `ceph-par1` dans une même série (20.2.x → 20.2.y). Une **version majeure** (Tentacle → série suivante) exige en plus : lecture complète des notes de la série, vérification de la compatibilité des clients (`ceph features`), des hôtes (OS supportés) et des modules mgr supprimés, et un essai sur un cluster jetable.

## 1. Lire avant de décider (J-7 à J-1)

- [ ] Notes de version de la version cible (`docs.ceph.com/en/latest/releases/<série>/`) : sections *Notable changes*, *Upgrade notes*, liens « Critical upgrade steps ».
- [ ] Chaque avis de sécurité lié (`docs.ceph.com/en/latest/security/`) : condition d'exploitation, étapes **avant** / **après**. Exemple 20.2.4 : CVE-2026-54330 demande `rgw_sigv4_insecure=true` **avant** la mise à jour en multisite seulement (non applicable : un seul site RGW) ; CVE-2025-30156 introduit le type de clé `aes256k` et six contrôles `AUTH_INSECURE_*` attendus après la mise à jour (traitement : ticket SEC, voir E27) ; CVE-2026-50152 recommande de renouveler la clé SSH de l'orchestrateur.
- [ ] Version des clients (`cephcli01`, futurs OpenStack et Kubernetes) : un client plus ancien reste compatible dans une même série ; noter qui ne pourra pas suivre une évolution (types de clés).
- [ ] Ticket CHG ouvert, MR `plateforme/ansible` (`ceph_image`, `ceph_noeud_version`) prête, pipeline vert, **non fusionnée** (elle décrira l'état d'après).

## 2. Préalables (J, avant la fenêtre)

```
[admin@ceph01 ~]$ sudo ceph -s                       # HEALTH_OK, tous les PG active+clean
[admin@ceph01 ~]$ sudo ceph mgr stat                 # un actif ET au moins un en attente
[admin@ceph01 ~]$ sudo ceph orch host ls             # aucun hôte hors ligne
[admin@ceph01 ~]$ sudo ceph orch upgrade check --image quay.io/ceph/ceph:v<VERSION>
```
- [ ] Sauvegarde E25 de moins de 24 h (volumes et configuration) : `systemctl status wb-backup-ceph` sur `cephcli01`.
- [ ] Aucune panne d'exercice active, aucune récupération en cours, aucun drapeau (`ceph osd dump | grep flags`).
- [ ] Charges témoins lancées 10 min avant (`boucles-temoins.sh start` sur `cephcli01`) : ligne de base relevée.
- [ ] Prévenir : canal d'exploitation, Julien (MédiDoc, MédiAgenda).

`upgrade check` vérifie que l'image est récupérable et indique les démons concernés, **sans rien démarrer**.

## 3. Mise à jour

```
[admin@ceph01 ~]$ sudo ceph osd pool set noautoscale                 # pas de division/fusion de PG pendant les redémarrages
[admin@ceph01 ~]$ sudo ceph orch upgrade start --image quay.io/ceph/ceph:v<VERSION> --daemon-types mgr
[admin@ceph01 ~]$ sudo ceph orch upgrade status ; sudo ceph versions   # les mgr sont à jour, un actif a basculé
[admin@ceph01 ~]$ sudo ceph orch upgrade start --image quay.io/ceph/ceph:v<VERSION>
[admin@ceph01 ~]$ sudo ceph -W cephadm                               # suivre (Ctrl-C n'interrompt pas la mise à jour)
```
Ordre imposé par l'orchestrateur : mgr, mon, crash, osd, mds, rgw, rbd-mirror, cephfs-mirror, iscsi, nfs. Les démons qui n'utilisent pas l'image Ceph (haproxy et keepalived de l'ingress) gardent leur propre image : elle se change à part, dans la spécification du service, et se vérifie dans `ceph orch ps` (colonne VERSION). Pour chaque OSD, cephadm attend que l'arrêt soit sans danger (`ok-to-stop`). Pendant les OSD, `HEALTH_WARN` passager (`OSD_DOWN`, PG `degraded`) : normal tant qu'il se résorbe à chaque étape.

**Pause / reprise** : `ceph orch upgrade pause` puis `ceph orch upgrade resume`. **Arrêt** : `ceph orch upgrade stop` (les démons déjà mis à jour le restent).

## 4. Si quelque chose bloque

| Symptôme | Lecture | Action |
|---|---|---|
| `UPGRADE_NO_STANDBY_MGR` | pas de mgr en attente | `ceph orch ps --daemon-type mgr`, redémarrer le mgr arrêté (`ceph orch daemon restart <nom>`) ; reprendre |
| `UPGRADE_FAILED_PULL` | un hôte n'a pas pu tirer l'image | réseau ou registre depuis l'hôte (`podman pull` sur l'hôte) ; `upgrade stop` puis `start` |
| mise à jour en pause avec un message d'erreur | un démon n'a pas redémarré | `ceph orch upgrade status`, `ceph orch ps --refresh`, `cephadm logs --name <démon>` sur l'hôte ; corriger, puis `upgrade resume` |
| OSD qui ne redémarre pas | journal du démon | ne **pas** le supprimer ; laisser le cluster dégradé (3 copies, 1 absente), diagnostiquer ; RB-080 si le disque est en cause |
| boucles témoins en échec | interruption de service | `upgrade pause` immédiat, diagnostic, décision CHG |

**Pas de retour arrière par l'image précédente** une fois les moniteurs mis à jour (formats et fonctionnalités des moniteurs) : le « retour arrière » est la pause, le diagnostic et la reprise. Une mise à jour mineure ne change pas `require_osd_release`, mais rien ne garantit l'inverse : ne jamais redéployer une image plus ancienne sans l'avis d'une source officielle.

## 5. Après

```
[admin@ceph01 ~]$ sudo ceph versions                                  # une seule version
[admin@ceph01 ~]$ sudo ceph orch ps --format json | jq -r '.[].version' | sort | uniq -c
[admin@ceph01 ~]$ sudo ceph osd pool unset noautoscale
[admin@ceph01 ~]$ sudo ceph health detail
```
- [ ] Code à jour : MR sur `group_vars/env_m08/ceph.yml` (`ceph_image`) et `group_vars/role_ceph/ceph_noeud.yml` (`ceph_noeud_version`), fusionnée **maintenant** ; pipeline de `plateforme/ansible`, rôle `ceph_noeud` sur les nœuds (paquets `cephadm` et `ceph-common`) ; `sudo cephadm version` sur chaque hôte.
- [ ] Client de `cephcli01` : version notée ; mise à jour si une étape de sécurité l'exige.
- [ ] Contrôles de santé nouveaux **attendus** (ex. `AUTH_INSECURE_*` en 20.2.4) : ticket SEC, jamais de sourdine sans durée.
- [ ] Boucles témoins : `boucles-temoins.sh stop`, puis `bilan` ; consigner échecs (attendu : 0) et latences max dans le CHG.
- [ ] Mettre à jour le `README` de `plateforme/ceph` (version) et l'inventaire des versions ; clore le CHG.

## 6. Historique

| Date | De → vers | Durée | Incidents | Opérateur |
|---|---|---|---|---|
| 2026-10-XX | 20.2.3 → 20.2.4 | 1 h 10 | aucun échec client ; latence S3 max 4,8 s (bascule de l'ingress) | <MOI> |
