# RB-080 — Remplacer un disque défaillant d'un nœud Ceph

| | |
|---|---|
| Service | Stockage distribué `ceph-par1` |
| Public | Astreinte de niveau 1 (support), avec accès `sudo ceph` sur `ceph01` (nœud `_admin`) et Proxmox `wb-admin` (lab) |
| Escalade | Astreinte niveau 2 Plateforme (`<NUMÉRO>`), puis Claire Morel |
| Durée | 30 min de gestes + attente de la récupération (minutes à heures selon le volume) |
| Version | 1.0 — `<DATE>` — `<MOI>` (PLAT-932) — joué en exercice sur `ceph04` (M08-E22) |

## 0. Tableau d'entrée

| Ce que tu vois | Aller à |
|---|---|
| Alerte `OSD_DOWN` (un seul OSD), aucun PG `inactive` | §1 puis §2 |
| `OSD_DOWN` + `PG_DEGRADED` | §1 puis §2 (attendre la fin de la récupération) |
| PG `inactive`, `incomplete`, `down`, `stale`, ou `HEALTH_ERR` autre que l'OSD | **STOP** — §6 Escalade immédiate |
| Plusieurs OSD `down` dans **des baies différentes** | **STOP** — §6 |
| Disque signalé (SMART, erreurs de lecture) mais OSD `up` | §1 puis §3 (remplacement préventif) |

> **Interdits — à ne JAMAIS faire sans l'astreinte de niveau 2 :**
> `ceph osd purge`, `ceph osd lost`, `ceph osd destroy`, toute option `--force` ou `--yes-i-really-mean-it`,
> `ceph orch device zap` sur un disque non identifié deux fois, baisser `min_size`, redémarrer un autre
> nœud pendant une récupération, `ceph osd set noout` « pour faire taire l'alerte ».

## 1. Qualifier (lecture seule)

En root sur `ceph01` (nœud `_admin`, invite `[root@ceph01 ~]#`) :

| Commande | Ce que tu dois lire |
|---|---|
| `ceph -s` | `health`, nombre d'OSD `up`/`in`, ligne `pgs:` (que des `active+…` ?) |
| `ceph health detail` | les identifiants exacts : `osd.N`, PG concernés |
| `ceph osd tree down` | l'OSD `down`, son **hôte** et sa **baie** (`par1-baie-…`) |
| `ceph pg ls inactive` | **doit être vide**. Sinon : §6 |
| `ceph osd find <ID>` | hôte et adresse de l'OSD |
| `ceph device ls-by-daemon osd.<ID>` | identifiant du disque (fabricant_modèle_série) |
| `ceph crash ls-new` | un plantage récent de cet OSD ? (note l'identifiant) |

Note dans le ticket : OSD, hôte, baie, disque (numéro de série), heure de la panne, état des PG.

**Point d'arrêt** : un seul OSD perdu, ou plusieurs dans la **même** baie, et aucun PG inactif → continuer.
Sinon → §6.

## 2. Panne réelle : laisser la récupération finir

Un OSD `down` est marqué `out` seul après 10 minutes (`mon_osd_down_out_interval`) ; ses données sont
alors recopiées ailleurs. **Ne rien faire** tant que `ceph -s` montre des PG `degraded` ou `backfilling`.

- Suivre : `ceph -s` toutes les 10 minutes ; `ceph progress`.
- La récupération ne progresse plus et des PG restent `undersized` : normal si la baie n'a pas d'autre
  disque de la même classe (baie B ou C, HDD). Passer au §3 : c'est le remplacement qui rétablira.
- Fin : plus aucun PG `degraded` lié à cet OSD, puis :
  `ceph osd safe-to-destroy <ID>` → doit répondre que l'OSD est sûr. **Sinon : §6.**

## 3. Retirer l'OSD en conservant son identifiant

1. Empêcher la recréation automatique sur le disque neuf avant l'heure : dans `plateforme/ceph`, passer
   la spécification OSD de la classe concernée en `unmanaged: true` (MR express relue par le niveau 2 ;
   au lab : application directe par `outils/appliquer.sh specs/osd.yaml`).
2. Retrait : `ceph orch osd rm <ID> --replace`
   - disque **mort** : sans `--zap` (rien à effacer) ;
   - disque **qui faiblit** (OSD encore `up`) : sans `--zap` aussi ; l'OSD est vidé avant destruction.
3. Suivre : `ceph orch osd rm status` jusqu'à disparition de la ligne ; `ceph osd tree | grep osd.<ID>` →
   état `destroyed`.
   - Retour arrière **avant** la destruction : `ceph orch osd rm stop <ID>`.

## 4. Remplacer le disque

1. Allumer le voyant : `ceph device light on <DEVID> ident` (vérifier sur place que c'est **ce** voyant).
2. Remplacement par le technicien de salle (disque de même classe et de taille ≥).
3. Éteindre : `ceph device light off <DEVID> ident`.

**Au lab** (disque virtuel de la VM du nœud, sur `pve01`) :
1. Identifier la ligne : `qm config <VMID> | grep -E '^scsi'` ; le numéro de série vu dans le nœud
   (`lsblk -o NAME,SERIAL`) vaut `drive-scsiN`. **Vérifier deux fois** VMID et `scsiN`.
2. `qm set <VMID> --delete scsiN`, puis `qm disk unlink <VMID> --idlist unusedK --force`.
3. `qm set <VMID> --scsiN <stockage>:64,ssd=1,discard=on,iothread=1` (`ssd=1` pour un disque `ssd-lab`
   seulement ; sinon la classe change).

## 5. Recréer et contrôler

1. `ceph orch device ls <hôte> --refresh` : le disque neuf est `Available: Yes`.
2. Remettre la spécification en gérée (`unmanaged` retiré) et l'appliquer.
3. Contrôles :
   - `ceph osd tree` : `osd.<ID>` **même identifiant**, `up`, sous le bon hôte ;
   - `ceph osd crush get-device-class osd.<ID>` : la classe attendue ;
   - `ceph -s` : récupération en cours puis `HEALTH_OK`.
4. Clôture : `ceph crash info <ID-CRASH>` lu et joint au ticket, puis `ceph crash archive <ID-CRASH>` ;
   ticket fournisseur (retour du disque) ; mise à jour de l'inventaire NetBox (numéro de série).

## 6. Escalade

Appeler l'astreinte de niveau 2 **sans rien changer**, avec : sortie de `ceph -s`, `ceph health detail`,
`ceph osd tree down`, `ceph pg ls inactive`, heure de début. Situations : PG inactifs ou incomplets ;
plusieurs OSD perdus dans des baies différentes ; `safe-to-destroy` qui refuse après la récupération ;
doute sur le disque physique ; toute commande de ce runbook qui ne donne pas le résultat attendu.

## Historique

| Version | Date | Auteur | Changement |
|---|---|---|---|
| 1.0 | `<DATE>` | `<MOI>` | Création (PLAT-932), joué sur `ceph04` : `<écarts constatés>` |
