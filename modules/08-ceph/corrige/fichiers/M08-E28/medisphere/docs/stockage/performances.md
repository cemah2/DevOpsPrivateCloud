# Performances de ceph-par1

> Propriétaire : équipe Plateforme · Tickets : PLAT-954 (mesures, M08-E28), PLAT-955 (réglages, M08-E29) · À refaire : après chaque changement de matériel, de version majeure ou de réglage du messager, avec **la même méthode**.
>
> Les valeurs entre chevrons sont **à remplacer par tes mesures** : ce modèle ne contient aucun chiffre mesuré.

## 1. Méthode

**Conditions** (vérifiées et notées avant chaque série) : `ceph -s` HEALTH_OK, tous les PG `active+clean`, aucune récupération (`ceph -s` sans ligne *recovery*), aucune sauvegarde en cours (hors 01:00-03:00), aucune autre charge sur `pve01` (`pvesh get /nodes/pve01/status`), version de Ceph et mode du messager (`ceph config get osd ms_cluster_mode`) notés.

**Répétitions** : chaque mesure 3 fois ; on garde la **médiane** et on note l'écart. Une mesure dont l'écart dépasse 20 % est refaite après avoir cherché pourquoi (autre charge, récupération).

**Couche par couche**, du bas vers le haut, pour savoir **où** se perd la performance :

| Couche | Outil | Paramètres | Ce qu'on lit |
|---|---|---|---|
| Réseau | `iperf3 -c <IP> -t 30` puis `-P 4` ; `ping -M do -s 8972` | public (10.10.30.x) et cluster (10.10.31.x), entre `ceph01` et `ceph02` | débit, MTU effectif |
| OSD seul | `ceph tell osd.<N> bench` | défaut (1 Gio en blocs de 4 Mio) ; un OSD `ssd`, un `hdd` | débit et IOPS d'un OSD sans réseau ni réplication |
| RADOS | `rados bench -p bench 60 write -b 4M -t 16 --no-cleanup`, puis `seq`, `rand` ; idem `-b 4K` | pool `bench` (classe `ssd`, réplication 3) | débit, IOPS, latence moyenne et max |
| RBD | `rbd bench --io-type write --io-size 4K --io-threads 16 --io-total 2G --io-pattern rand bench/fio01` ; `--io-size 4M --io-pattern seq` | image `bench/fio01` | IOPS et débit vus par librbd |
| Client | `fio` (profils `plateforme/ceph/bench/`) sur `/dev/rbd0` depuis `cephcli01` | `base-de-donnees`, `sequentiel`, `latence` | IOPS, débit, **p95/p99** de latence |

**Lecture** : la moyenne cache les pics ; une base de données souffre du p99. En réplication 3, une écriture est acquittée quand les **trois** copies sont écrites : la latence d'écriture est celle de la plus lente des trois, plus deux traversées réseau.

## 2. Réserves (à lire avant tout chiffre)

Les « disques » des OSD sont des fichiers sur **deux disques physiques** de `pve01` (tous les SSD virtuels sur un seul SSD, tous les HDD virtuels sur un seul HDD ; 12 OSD tant que `ceph04` est là), les « réseaux » sont un pont Linux en mémoire, et les VMs ont 2 vCPU. Les chiffres absolus ne disent **rien** d'un cluster réel : un vrai cluster a des disques indépendants, et le réseau est souvent la limite. Ils servent à **comparer** (avant/après un réglage, MTU, mode du messager) et à donner à Julien un ordre de grandeur **dans ce lab**.

## 3. Résultats du <DATE> (Ceph 20.2.4, msgr2 `secure`)

| Mesure | Résultat (médiane de 3) | Écart |
|---|---|---|
| `iperf3` public, 1 flux / 4 flux | <Gbit/s> / <Gbit/s> | |
| `iperf3` cluster, 1 flux / 4 flux | <Gbit/s> / <Gbit/s> | |
| `ceph tell osd.<ssd> bench` | <Mio/s>, <IOPS> | |
| `ceph tell osd.<hdd> bench` | <Mio/s>, <IOPS> | |
| capacité mClock mesurée (`osd_mclock_max_capacity_iops_ssd` / `_hdd`) | <IOPS> / <IOPS> | |
| `rados bench` écriture 4 Mio | <Mio/s>, latence moy. <ms> | |
| `rados bench` lecture seq 4 Mio | <Mio/s> | |
| `rados bench` lecture rand 4 Mio | <Mio/s> | |
| `rados bench` écriture 4 Kio | <IOPS>, latence moy. <ms> | |
| `rbd bench` écriture aléatoire 4 Kio | <IOPS> | |
| `rbd bench` écriture séquentielle 4 Mio | <Mio/s> | |
| `fio` base-de-donnees (lecture / écriture) | <IOPS> / <IOPS>, p99 <ms> / <ms> | |
| `fio` sequentiel (écriture / lecture) | <Mio/s> / <Mio/s> | |
| `fio` latence (écriture synchrone) | moy. <ms>, p99 <ms> | |

## 4. Jumbo frames : MTU 9000 contre 1500 (réseau de cluster)

Passage temporaire (non persistant) de `ens19` en 1500 sur les **trois** nœuds en même temps, mesure, retour à 9000, vérification `ping -M do -s 8972`.

| Mesure | MTU 9000 | MTU 1500 | Écart |
|---|---|---|---|
| `iperf3` cluster, 4 flux | <Gbit/s> | <Gbit/s> | <%> |
| `rados bench` écriture 4 Mio | <Mio/s> | <Mio/s> | <%> |
| charge CPU des nœuds pendant l'écriture (`top`, `%si`) | <%> | <%> | |

**Interprétation attendue** : sur un pont Linux en mémoire, le gain des jumbo frames vient surtout de la **charge CPU par octet** (moins de paquets, moins d'interruptions logicielles), pas du débit brut ; il est visible sur `iperf3` et sur les grosses écritures (réplication), presque nul sur les petites E/S où la latence domine. Sur un vrai réseau 10/25 Gbit/s, l'écart se voit d'abord dans le CPU des nœuds. Conclusion à écrire avec **tes** chiffres : garder 9000 si le gain est mesurable et le MTU vérifié de bout en bout ; le risque principal d'un MTU 9000 est l'incohérence (M08-E42), d'où la vérification automatique au mini-projet.

## 5. Réponse à Julien (PLAT-954)

« Dans le lab, un volume RBD de la classe `ssd` tient environ <N> IOPS en 4 Kio aléatoire mixte, avec une latence p99 de <x> ms, et <y> ms par écriture synchrone. Ces chiffres sont ceux d'un lab dont tous les disques sont sur un seul SSD : ils ne préjugent pas de la production. Pour PostgreSQL, la latence d'écriture synchrone est la valeur à surveiller ; on la mesurera à nouveau sur le matériel cible. »

## 6. Mémoire (M08-E29)

Budget d'un nœud de 6 Gio (mesures `ceph orch ps` MEM USE, `free -m`) :

| Consommateur | Réservé (Gio) | Commentaire |
|---|---|---|
| Système, Podman, agent, journal | 0,5 | mesuré à vide |
| MON | 0,7 | `mon_memory_target` vise 2 Gio par défaut mais un petit cluster en consomme bien moins : mesuré |
| MGR (2 nœuds sur 3) | 0,5 | modules actifs : prometheus, dashboard, cephadm |
| MDS | 0,6 | `mds_cache_memory_limit` ramené de 4 Gio (défaut) à 512 Mio : sinon le MDS seul peut prendre les deux tiers du nœud |
| RGW ou haproxy/keepalived | 0,3 | |
| 3 OSD × (1 Gio de cible + ~20 % de dépassement) | 3,6 | `osd_memory_target` est une **cible** de cache, pas une limite dure |
| **Total** | **6,2** | à la limite : aucun autre démon sur ces nœuds |

Décision : `osd_memory_target` = 1 Gio (`ceph config set osd osd_memory_target 1073741824`), au-dessus du minimum de l'option (`ceph config help osd_memory_target` : <valeur min relevée>), réglage automatique de cephadm désactivé (`osd_memory_target_autotune false`) car il calcule 70 % de la mémoire de l'hôte **moins** les autres démons et donnait <valeur relevée> par OSD ; les valeurs qu'il avait écrites par hôte (`osd/host:cephNN`) sont retirées. Contrôle : `ceph config show osd.N osd_memory_target` sur les neuf OSD.

## 7. Récupération et mClock (M08-E29)

Scénario : charge `fio` base-de-donnees sur `cephcli01`, arrêt de `osd.<N>` (SSD, `ceph02`), `ceph osd out <N>` ; mesure jusqu'au retour de tous les PG `active+clean`. OSD remis en service et HEALTH_OK entre deux essais.

| Profil | Durée de récupération | Débit de récupération (`ceph -s`) | p99 client pendant la récupération | p99 client hors récupération |
|---|---|---|---|---|
| `balanced` (défaut) | <min> | <Mio/s> | <ms> | <ms> |
| `high_client_ops` | <min> | <Mio/s> | <ms> | <ms> |
| `high_recovery_ops` | <min> | <Mio/s> | <ms> | <ms> |

Lecture attendue : `high_client_ops` protège la latence au prix d'une récupération plus longue (période de redondance réduite plus longue) ; `high_recovery_ops` raccourcit la fenêtre de risque et dégrade les clients. Profil nominal retenu : <balanced ou high_client_ops, justifié>. Fiche réflexe : `runbooks/fiche-recuperation.md`.
