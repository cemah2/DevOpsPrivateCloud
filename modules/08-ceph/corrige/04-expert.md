# Module 08 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Avec Ceph, « j'ai redémarré et ça remarche » est doublement faux : un redémarrage efface la preuve (état de l'unité, journal du démon, règle posée à chaud) et peut aggraver la situation (une récupération qui démarre pendant qu'un second démon tombe).

Les scripts d'injection sont dans `corrige/pannes/` (`_m08-commun.sh` contient les fonctions partagées : exécution par SSH sur les nœuds et le client, commandes `ceph` par la CLI du nœud admin ou `cephadm shell`, arrêt et relance d'un démon cephadm, contrôle de santé avant injection, création des **témoins**). Chaque modification est journalisée sur l'hôte touché dans `/var/lib/workbook/pannes.log`, et les valeurs d'origine sont gardées sur `adm01` dans `~/.local/state/workbook/M08-EXX/`.

Les sorties reproduites sont **représentatives** : identifiants, époques, nombres de PG et formulations exactes varient selon ton cluster et la version. Elles suivent la documentation de Ceph Tentacle 20.2 (cephadm, Podman, Rocky Linux 10) et du client `ceph-common` de Debian 13.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- E35 v2 : la mise hors ligne d'un disque SCSI de l'invité (`/sys/block/sdX/device/state`) fait échouer BlueStore sur la première écriture (déclenchée par `ceph tell osd.N bench`) ; le libellé exact du journal de l'OSD (`unexpected aio error`, `ceph_abort`) peut différer. Si tes disques OSD sont en virtio-blk (`/dev/vdX`), la variante est sautée.
- E36 v3 : état exact des PG dont la règle ne trouve **aucun** OSD (`unknown` ou `stale`, selon le moment) ; dans tous les cas `PG_AVAILABILITY` est levé.
- E37 v1 : comportement de la commande `ceph osd set-full-ratio` avec des valeurs très basses (< 1 %) ; seuil de rafraîchissement du drapeau de pool plein (quelques secondes).
- E38 v1 : selon l'écart, un moniteur dont l'horloge avance de 150 s reste dans le quorum avec `MON_CLOCK_SKEW`, ou provoque des élections répétées ; les deux cas sont traités.
- E40 v1 : selon le contrôle de keepalived de l'ingress, la VIP est retirée (délai dépassé côté client) ou reste portée (connexion refusée).
- E42 v2 : en Tentacle, `osd_mclock_scheduler_client_lim` est une **proportion** de la capacité en IOPS de l'OSD (0 à 1,0 ; 0 = pas de limite) ; si ta version l'interprète autrement, l'injection passe à une autre variante.
- E44 : `cephadm shell --name osd.<id>` avec l'OSD arrêté, puis `ceph-objectstore-tool --data-path /var/lib/ceph/osd/ceph-<id>` ; selon la version, il peut falloir ajouter `--no-mon-config`.
- `curl --aws-sigv4` (curl 8.14 de Debian 13) contre RGW pour la sonde S3 : ajout automatique de l'en-tête `x-amz-content-sha256` pour le service `s3`.

---

## Méthode commune aux pannes de Ceph

1. **Lire la santé en entier.** `ceph health detail` donne les codes et les objets (OSD, PG, pools, démons). Chaque code est décrit dans la page *Health checks* : lis-la, elle donne souvent la démarche.
2. **Situer l'étage.** Pour un démon : orchestrateur (`ceph orch ps`) → unité (`systemctl status ceph-<fsid>@…`) → conteneur (`podman ps -a`) → démon (`cephadm logs --name …`) → ressource (disque, réseau, horloge). Pour un placement : pool (`size`, `min_size`, règle, quota) → règle CRUSH (racine, classe, domaine) → OSD disponibles. Pour un client : configuration et trousseau → authentification → droits → service (MDS, RGW) → fonctionnalités du client.
3. **Chercher ce qui a bougé.** Le journal d'audit du cluster (`ceph log last <n> debug audit`) trace chaque commande d'administration avec l'entité qui l'a passée ; `ceph config log` trace les changements de la base de configuration ; sur les nœuds, `nft list ruleset`, `tc qdisc show`, `journalctl --since`.
4. **Protéger avant d'agir.** `ceph osd ok-to-stop`, `noout` pour une intervention courte, jamais de commande qui efface ou renonce à des données sans avoir la preuve qu'il n'y a pas d'autre copie.
5. **Corriger à la racine, puis faire converger le code.** Une règle CRUSH, un réglage de pool ou une spécification cephadm modifiés à la main doivent être reportés dans `plateforme/ceph` (MR), sinon la dérive revient.
6. **Prévenir** : quelle sonde de `ms-verif-ceph`, quelle alerte (module `prometheus` du mgr), quelle étape de pipeline aurait vu la panne avant l'utilisateur ?

---

### M08-E35 — Panne : un OSD a disparu

**Démarche de diagnostic**

*Symptômes* : variantes 1 et 2, `HEALTH_WARN` avec `OSD_DOWN` et des PG dégradés ; variante 3, pas d'alerte (ou une alerte passagère de récupération), mais un OSD sans PG et une capacité utile en baisse.

*Hypothèses* : démon arrêté (par quelqu'un, par l'orchestrateur, par un plantage) ; unité qui ne peut plus démarrer ; disque disparu ou en erreur ; OSD sorti du placement par une décision (`out`, poids nul) ; réseau du nœud (traité en E42).

**Étape 1 — Constater sans toucher.**

```
[root@ceph01 ~]# ceph health detail
HEALTH_WARN 1 osds down; Degraded data redundancy: 214/1890 objects degraded (11.323%), 31 pgs degraded
[WRN] OSD_DOWN: 1 osds down
    osd.5 (root=default,host=ceph02) is down
…
[root@ceph01 ~]# ceph osd tree
ID  CLASS  WEIGHT   TYPE NAME        STATUS  REWEIGHT  PRI-AFF
-1         0.56238  root default
-5         0.18746      host ceph02
 3    ssd  0.06249          osd.3        up   1.00000  1.00000
 4    ssd  0.06249          osd.4        up   1.00000  1.00000
 5    hdd  0.06249          osd.5      down   1.00000  1.00000
…
[root@ceph01 ~]# ceph log last 30 info cluster | grep -i osd.5
… osd.5 marked itself down and dead …           # arrêt propre (variante 1)
… osd.5 reported failed by osd.1 …               # plantage (variante 2)
```

Un OSD `down` mais encore `in` (REWEIGHT 1) : Ceph attend `mon_osd_down_out_interval` (600 s par défaut) avant de le passer `out` et de recopier ses données ailleurs. Si tu sais que l'intervention sera courte, `ceph osd set noout` évite ce déplacement ; si l'OSD est perdu, au contraire, le passage à `out` est ce qu'on veut. Note ta décision.

**Étape 2 — Descendre les étages sur l'hôte.**

```
[root@ceph01 ~]# ceph orch ps --daemon-type osd | grep osd.5
osd.5   ceph02   stopped   …                     # ou « error »
[admin@ceph02 ~]$ sudo cephadm ls | grep -A3 '"osd.5"'
[admin@ceph02 ~]$ systemctl status 'ceph-*@osd.5.service' --no-pager
```

**Variante 1 — démon arrêté et unité masquée.**

```
[admin@ceph02 ~]$ systemctl status ceph-<FSID>@osd.5.service --no-pager
○ ceph-<FSID>@osd.5.service
     Loaded: masked (Reason: Unit ceph-<FSID>@osd.5.service is masked.)
     Active: inactive (dead) since …
[root@ceph01 ~]# ceph orch daemon start osd.5
… Failed to start ceph-<FSID>@osd.5.service: Unit ceph-<FSID>@osd.5.service is masked.
[admin@ceph02 ~]$ ls -l /etc/systemd/system/ceph-<FSID>@osd.5.service
lrwxrwxrwx 1 root root 9 … /etc/systemd/system/ceph-<FSID>@osd.5.service -> /dev/null
```

`<FSID>` est l'identifiant du cluster (`ceph fsid`). Le journal du démon (`cephadm logs --name osd.5`) montre un arrêt propre (`received signal: Terminated`), pas un plantage. Un masque empêche tout démarrage, par systemd comme par l'orchestrateur : c'est un geste délibéré (souvent « pour qu'il ne redémarre pas pendant que je change le disque », puis oublié). La date du lien (`ls -l --time-style=full-iso`) et `journalctl _COMM=systemctl --since …` sur le nœud racontent qui et quand. Correctif :

```
[admin@ceph02 ~]$ sudo systemctl unmask ceph-<FSID>@osd.5.service
[root@ceph01 ~]# ceph orch daemon start osd.5
[root@ceph01 ~]# ceph -w          # osd.5 boot, récupération, HEALTH_OK
```

**Variante 2 — disque hors ligne côté invité.**

```
[admin@ceph02 ~]$ sudo cephadm logs --name osd.5 | tail -n 20
… bdev(…/block) _aio_thread got r=-5 ((5) Input/output error)
… unexpected aio error
… *** Caught signal (Aborted) **
[admin@ceph02 ~]$ systemctl status ceph-<FSID>@osd.5.service --no-pager
     Active: failed (Result: exit-code) … (start limit hit)
[admin@ceph02 ~]$ sudo dmesg -T | tail
… sd 2:0:0:3: rejecting I/O to offline device
… Buffer I/O error on dev dm-5, logical block …
[admin@ceph02 ~]$ cat /sys/block/sdd/device/state
offline
[root@ceph01 ~]# ceph osd metadata 5 | grep -E '"devices"|bluestore_bdev_dev_node'
    "devices": "sdd",
```

Le démon a planté sur une erreur d'E/S (`-5`, `EIO`), systemd a tenté de le relancer puis a abandonné (`start limit hit`). Le noyau de l'invité refuse les E/S vers un périphérique SCSI en état `offline` : c'est l'état que prend un disque après des erreurs répétées ou un retrait à chaud, ou qu'un administrateur pose à la main (`echo offline > …/state`, ici le « test de retrait à chaud » d'InfoGér). Avant de relancer, la question est : **le disque est-il sain ?** Sur un vrai serveur : `smartctl -a`, journal du contrôleur, compteurs d'erreurs ; si le disque est défaillant, on ne le remet pas en service, on applique RB-080 (M08-E22). Ici, le disque virtuel est sain (`ssd-lab`/`hdd-bulk` de `pve01`, aucune erreur côté hôte) :

```
[admin@ceph02 ~]$ echo running | sudo tee /sys/block/sdd/device/state
[admin@ceph02 ~]$ sudo systemctl reset-failed ceph-<FSID>@osd.5.service
[root@ceph01 ~]# ceph orch daemon restart osd.5
```

BlueStore rejoue son journal (WAL de RocksDB) au démarrage : l'arrêt brutal équivaut à une coupure de courant, pour laquelle il est conçu. Le *peering* compare ensuite les journaux de PG et ne recopie que ce qui a changé pendant l'absence (récupération par journal, pas un remplissage complet), d'où un retour rapide si l'OSD revient avant d'être `out`.

**Variante 3 — OSD sorti du placement.**

```
[root@ceph01 ~]# ceph osd tree | grep osd.7
 7    ssd  0.06249          osd.7        up         0  1.00000
[root@ceph01 ~]# ceph osd df | awk 'NR==1 || $1==7'
ID  CLASS  WEIGHT   REWEIGHT  SIZE  RAW USE  …  PGS  STATUS
 7    ssd  0.06249         0   0 B      0 B  …    0    up
[root@ceph01 ~]# ceph log last 200 debug audit | grep -E 'osd (out|reweight)'
… from='client.admin' … cmd=[{"prefix": "osd out", "ids": ["7"]}]: finished
```

L'OSD tourne (`up`) mais n'est plus `in` : CRUSH ne lui attribue plus rien, ses PG ont été recopiés ailleurs (la récupération de la nuit), la santé est redevenue `HEALTH_OK` et la capacité utile a baissé d'un disque. Le journal d'audit donne la commande, l'heure et l'entité (`client.admin`, donc une personne avec le trousseau admin : d'où la nécessité de comptes nominatifs pour l'administration, M08-E27). Correctif : `ceph osd in 7`, puis la récupération inverse. Ce n'était ni une panne matérielle, ni une raison de commander un disque.

**Clôture commune** : `ceph osd unset noout` si tu l'avais posé, `ceph -s` jusqu'à `HEALTH_OK`, temps de récupération noté, `lab/bin/check 08 35` puis `lab/bin/break 08 35 --annuler`.

**Explications**

Les deux dimensions d'un OSD sont indépendantes : `up/down` est l'avis des moniteurs sur la vie du démon (battements de cœur entre OSD, rapports de panne, `mon_osd_min_down_reporters`), `in/out` est son poids dans le placement (le *reweight* de 0 à 1). Un OSD `down`+`in` garde ses PG, qui tournent en mode dégradé sur les autres copies ; au bout de `mon_osd_down_out_interval`, les moniteurs le passent `out` (sauf `noout`) et CRUSH recalcule. Un OSD sorti automatiquement est remis `in` quand il revient (`mon_osd_auto_mark_auto_out_in`) ; un OSD sorti à la main ne l'est pas. Avec cephadm, le démon est un conteneur lancé par une unité systemd ; l'orchestrateur ne relance pas de lui-même un démon arrêté (il signale `stopped`), systemd relance un démon planté jusqu'à sa limite de démarrages.

**Alternatives**
- Pour une maintenance planifiée d'un nœud : `ceph orch host maintenance enter <hôte>` (pose `noout` sur l'hôte et arrête ses démons proprement), puis `exit`.
- `ceph osd set-group noout <hôte>` : `noout` limité à un hôte ou une classe plutôt qu'au cluster entier.

**Pièges classiques**
- Purger et recréer un OSD qui pouvait revenir : déplacement complet de ses données (deux fois : vidage puis remplissage), et risque réel si un autre OSD tombe pendant ce temps.
- Oublier `noout` après l'intervention : la prochaine vraie panne ne déclenchera aucune récupération.
- Remettre en ligne un disque qui a vraiment produit des erreurs : il retombera, peut-être pendant une récupération.
- Ne regarder que `ceph -s` : un OSD `out` et un cluster `HEALTH_OK` peuvent cacher une capacité amputée.

**En production chez MédiSphère**
Alerte sur `OSD_DOWN` (immédiate) et sur tout OSD `up` mais `out` depuis plus de 24 h ; tableau de bord de la capacité utile ; `noout` posé par la procédure de maintenance et retiré par elle (avec alerte si posé depuis plus de 4 h) ; comptes d'administration nominatifs pour que l'audit dise **qui**. RB-083 : `corrige/fichiers/M08-E35/medisphere/docs/stockage/runbooks/RB-083-osd-hors-service.md`.

---

### M08-E36 — Panne : des PG restent inactifs

**Démarche de diagnostic**

*Symptômes* : les écritures sur `/mnt/sonde` attendent sans erreur ; `ceph -s` : `Reduced data availability: N pgs inactive`, tous les PG d'un seul pool.

*Hypothèses* : OSD manquants (exclu : tous `up`) ; `min_size` non atteint ; règle CRUSH qui ne trouve pas assez d'OSD (classe, racine, domaine de panne) ; PG qui ne parviennent pas au *peering* (journaux divergents, exclu ici).

**Étape 1 — Les PG et leurs ensembles.**

```
[root@ceph01 ~]# ceph health detail | head
[WRN] PG_AVAILABILITY: Reduced data availability: 32 pgs inactive
    pg 2.0 is stuck inactive for 412s, current state undersized+peered, last acting [4,1,8]
…
[root@ceph01 ~]# ceph pg map 2.0
osdmap e412 pg 2.0 (2.0) -> up [4,1,8] acting [4,1,8]
[root@ceph01 ~]# ceph pg map 3.0          # PG sain d'un autre pool, pour comparer
osdmap e412 pg 3.0 (3.0) -> up [2,6,3] acting [2,6,3]
```

**Étape 2 — Trois nombres : copies voulues, copies exigées, copies plaçables.**

```
[root@ceph01 ~]# ceph osd pool get rbd-test all | grep -E '^(size|min_size|crush_rule):'
[root@ceph01 ~]# ceph osd crush rule dump <règle>
[root@ceph01 ~]# ceph osd getcrushmap -o /tmp/crush.bin
[root@ceph01 ~]# crushtool -i /tmp/crush.bin --test --rule <id> --num-rep <size> --show-bad-mappings | head
```

**Variante 1 — `size 4`, `min_size 4`.** Le pool veut 4 copies et en exige 4 pour servir ; la règle (domaine `host`) ne peut en placer que 3 sur 3 hôtes : ensemble de 3 OSD, `undersized` (moins que `size`) et `peered` (moins que `min_size`). `crushtool --num-rep 4 --show-bad-mappings` affiche une mauvaise correspondance pour **chaque** entrée (`bad mapping rule 0 x 0 num_rep 4 result [4,1,8]`). Le journal d'audit montre `osd pool set … size 4` puis `min_size 4`. Correctif immédiat, sans déplacement de données (les trois copies sont déjà en place) :

```
[root@ceph01 ~]# ceph osd pool set rbd-test min_size 2
[root@ceph01 ~]# ceph osd pool set rbd-test size 3
```

`min_size` d'abord : c'est lui qui rend les PG actifs. Selon la version, changer `size` recalcule `min_size` ; vérifie-le ensuite (`ceph osd pool get rbd-test min_size`).

**Variante 2 — règle sur une classe portée par un seul OSD.**

```
[root@ceph01 ~]# ceph osd pool get rbd-test crush_rule
crush_rule: regle-nvme
[root@ceph01 ~]# ceph osd crush class ls
[ "hdd", "nvme", "ssd" ]
[root@ceph01 ~]# ceph osd crush class ls-osd nvme
4
[root@ceph01 ~]# ceph osd crush tree --show-shadow | grep -B2 -A2 'default~nvme'
```

Lucas a changé la classe d'un OSD en `nvme` et basculé le pool sur une règle `host` + classe `nvme` : l'arbre fantôme `default~nvme` ne contient qu'un hôte et un OSD, donc une seule copie plaçable (`crushtool --num-rep 3 --show-bad-mappings` le prouve), moins que `min_size`. Correctif, dans cet ordre :

```
[root@ceph01 ~]# ceph osd pool set rbd-test crush_rule <règle d'origine>     # PG actifs à nouveau
[root@ceph01 ~]# ceph osd crush rm-device-class osd.4
[root@ceph01 ~]# ceph osd crush set-device-class ssd osd.4                 # sa vraie classe
[root@ceph01 ~]# ceph osd pool ls detail | grep -c "crush_rule <id de regle-nvme>"   # 0 : plus aucun pool
[root@ceph01 ~]# ceph osd crush rule rm regle-nvme
```

La règle d'origine est dans l'audit, dans `plateforme/ceph` (M08-E23) ou dans ton journal de M08-E14. Rendre sa classe à l'OSD déplace un peu de données (ses PG des pools « ssd » reviennent) : c'est attendu.

**Variante 3 — règle sur une racine vide.**

```
[root@ceph01 ~]# ceph pg map 2.0
osdmap e420 pg 2.0 (2.0) -> up [] acting []
[root@ceph01 ~]# ceph osd crush rule dump regle-par2 | grep -A2 '"take"'
            "op": "take", "item": -9, "item_name": "par2"
[root@ceph01 ~]# ceph osd crush tree | grep -A1 par2
-9  0  root par2
```

La règle part d'une racine `par2` créée « pour préparer PAR2 », sans aucun hôte : CRUSH ne renvoie rien, les PG n'ont plus aucun OSD (`unknown`/`stale`, inactifs). Les données n'ont pas bougé : les OSD d'origine les gardent tant que les PG ne sont pas actifs ailleurs. Correctif : remettre la règle d'origine au pool, puis supprimer `regle-par2` (plus utilisée) et la racine vide (`ceph osd crush rm par2`). PAR2 sera un autre cluster (ou un *stretch cluster*, en connaissance de cause), pas une racine vide dans `ceph-par1`.

**Étape finale** : `sudo wb-sonde-stockage` vert (les E/S en attente reprennent seules dès que les PG sont actifs), `lab/bin/check 08 36`, `--annuler`.

**Réponse à Julien (modèle)** : « La politique voulue (4 copies, ou des données sur NVMe, ou une copie à PAR2) n'est pas applicable telle quelle à `ceph-par1` : 3 hôtes ne portent pas 4 copies avec un domaine `host`, nous n'avons pas de NVMe, et PAR2 n'a pas d'OSD. Toute modification de règle ou de réplication passe désormais par une MR sur `plateforme/ceph`, avec la sortie de `crushtool --test --show-bad-mappings` pour la `size` du pool et une estimation du volume déplacé (`--compare` ou `osdmaptool --test-map-pgs` avant/après), appliquée dans une fenêtre. Pour les données de santé, l'exigence de Sophie est mieux servie par la sauvegarde hors cluster (M08-E25) et par la réplication vers PAR2 au module de PRA que par une 4ᵉ copie locale. »

**Explications**

Un PG sert les E/S quand il est `active` : son primaire a fait le *peering* avec au moins `min_size` OSD. `undersized` signifie « moins de copies que `size` », `degraded` « des objets ont moins de copies que voulu », `peered` « le *peering* est fait mais `min_size` n'est pas atteint ». Les clients librados et krbd ne renvoient pas d'erreur : ils attendent que le PG redevienne actif (d'où le « rien ne bouge »). CRUSH ne connaît que la carte : il placera exactement ce que la règle sait choisir, sans avertissement à la création de la règle ni au changement de pool.

**Alternatives**
- `crushtool --compare` (entre deux cartes) ou `osdmaptool --test-map-pgs-dump` avant/après pour chiffrer le déplacement.
- L'équilibreur en mode `upmap` pour corriger un déséquilibre sans toucher aux règles.

**Pièges classiques**
- `ceph osd force-create-pg` ou `mark_unfound_lost` pour « débloquer » : perte de données certaine, alors que les copies sont intactes.
- Supprimer la classe ou la règle **avant** d'avoir rebasculé le pool : des PG sans règle, ou une commande refusée.
- `min_size 1` « pour débloquer » : les PG deviennent actifs avec une seule copie (voir M08-E45, question 3).

**En production chez MédiSphère**
Test de pipeline de `plateforme/ceph` : `crushtool --test --show-bad-mappings` pour chaque pool avec sa `size`, et refus de toute règle dont la racine ou la classe est vide ; alerte immédiate sur `PG_AVAILABILITY` (c'est une indisponibilité, pas un avertissement).

---

### M08-E37 — Panne : plus aucune écriture

**Démarche de diagnostic**

*Symptômes* : les écritures attendent sur le stockage de test, sans erreur côté client ; selon la variante, les lectures aussi.

*Hypothèses* : OSD ou pool réellement plein ; seuil abaissé ; quota ; drapeau de la carte des OSD ; PG inactifs (E36, exclu par `ceph health detail`).

**Étape 1 — Ce que dit Ceph.**

```
[root@ceph01 ~]# ceph health detail
[root@ceph01 ~]# ceph osd dump | grep -E '^flags|ratio'
[root@ceph01 ~]# ceph osd pool get-quota rbd-test
[root@ceph01 ~]# ceph df detail
```

**Variante 1 — seuils abaissés.**

```
HEALTH_ERR 9 full osd(s); 6 pool(s) full
[ERR] OSD_FULL: 9 full osd(s)
    osd.0 is full
…
full_ratio 0.0066
backfillfull_ratio 0.0059
nearfull_ratio 0.0053
[root@ceph01 ~]# ceph osd df | awk '{print $1, $(NF-3)}'      # %USE autour de 1-2 %
```

L'espace ne manque pas : les OSD sont à 1 ou 2 %, mais le seuil « plein » a été posé sous ce niveau. Tous les pools sont marqués pleins, toutes les écritures attendent (lectures et suppressions passent). L'audit montre `osd set-full-ratio`, `set-backfillfull-ratio`, `set-nearfull-ratio`. Correctif, avec les valeurs justes (celles du cluster, sinon les valeurs par défaut) et dans l'ordre qui garde les seuils ordonnés :

```
[root@ceph01 ~]# ceph osd set-full-ratio 0.95
[root@ceph01 ~]# ceph osd set-backfillfull-ratio 0.90
[root@ceph01 ~]# ceph osd set-nearfull-ratio 0.85
```

Justification : à 0,95, il reste 5 % pour que BlueStore et RocksDB travaillent (compactage, journaux) ; `backfillfull` à 0,90 empêche une récupération de remplir un OSD jusqu'au blocage ; `nearfull` à 0,85 laisse le temps d'agir. Sur un petit cluster (9 OSD de 64 Go), la perte d'un hôte fait monter tous les autres d'un tiers : la vraie limite d'exploitation est plus basse (M08-E20, politique de stockage M08-E33).

**Variante 2 — quota de pool.**

```
[ERR] POOL_FULL: 1 pool(s) full
    pool 'rbd-test' is full (running out of quota)
[root@ceph01 ~]# ceph osd pool get-quota rbd-test
quotas for pool 'rbd-test':
  max objects: N/A
  max bytes  : 24 MiB  (current num bytes: 49512448 bytes)
```

Un quota de 24 Mio sur un pool qui en contient 47 : le pool est plein par décision, pas par manque de place. Seul `rbd-test` est touché (CephFS et S3 écrivent). Correctif : la valeur décidée dans la politique de stockage (M08-E33), ou `max_bytes 0` (pas de quota) si aucune n'est fixée pour ce pool de test ; jamais « 10 fois l'occupation » sans raison. Rappel : un quota de pool est vérifié avec un léger retard, il protège contre l'emballement, pas au octet près.

**Variante 3 — drapeaux de maintenance oubliés.**

```
HEALTH_WARN pauserd,pausewr,noout flag(s) set
[root@ceph01 ~]# ceph osd dump | grep flags
flags pauserd,pausewr,noout,sortbitwise,recovery_deletes,purged_snapdirs,pglog_hardlimit
```

`ceph osd set pause` suspend **toutes** les E/S clientes (lectures et écritures) ; `noout` empêche la sortie automatique des OSD morts. Karim les a posés pour sa maintenance et n'a retiré ni l'un ni l'autre. Correctif : `ceph osd unset pause` et `ceph osd unset noout`. Le second est le plus dangereux à oublier : il ne bloque rien aujourd'hui, mais la prochaine panne de disque ne déclenchera aucune réparation.

**Clôture** : la sonde est verte, `lab/bin/check 08 37`, `--annuler`. RB-084 : `corrige/fichiers/M08-E37/medisphere/docs/stockage/runbooks/RB-084-ecritures-bloquees.md`.

**Explications**

Ceph préfère suspendre que corrompre : un OSD plein ne peut plus garantir l'écriture des métadonnées de BlueStore, donc le cluster arrête d'accepter des écritures **avant** (`full_ratio`) et refuse les remplissages qui y mèneraient (`backfillfull_ratio`). Les seuils vivent dans la carte des OSD (`ceph osd dump`), pas dans `ceph config` : `ceph config get mon mon_osd_full_ratio` ne sert qu'à la création du cluster. Les quotas sont par pool (`max_bytes`, `max_objects`), et le drapeau `pause` (= `pauserd` + `pausewr`) est un interrupteur global.

**Alternatives**
- En cas de vrai remplissage : supprimer des instantanés RBD, des objets de test (`rados bench` oubliés), ajouter des OSD ; remonter `full_ratio` à 0,97 **le temps** de supprimer, puis le redescendre.
- Quotas par client : quotas RBD par espace de noms (*namespace*) ou quotas CephFS par répertoire (`ceph.quota.max_bytes`) plutôt qu'un quota de pool partagé.

**Pièges classiques**
- Remonter `full_ratio` à 0,99 « pour débloquer » : l'OSD finit réellement plein, et un OSD BlueStore à 100 % peut refuser de démarrer.
- Supprimer un quota décidé pour une raison (facturation, isolement) sans demander.
- Ne retirer que `pause` et laisser `noout`.

**En production chez MédiSphère**
Les seuils et quotas sont décrits dans `plateforme/ceph` et comparés à l'état réel par la sonde ; alerte `nearfull` à 75 % d'occupation **prévue** (en tenant compte de la perte d'un hôte) ; procédure de maintenance qui pose et retire elle-même ses drapeaux.

---

### M08-E38 — Panne : les moniteurs perdent le quorum

**Démarche de diagnostic**

*Symptômes* : un moniteur hors quorum et des commandes lentes (variantes 1, 2), ou plus aucune réponse (variante 3).

*Hypothèses* : démon arrêté ; réseau entre moniteurs (ports 3300/6789, pare-feu, MTU du public) ; horloge ; disque du moniteur plein (`MON_DISK_CRIT`) ; *monmap* incohérente (exclu sans manipulation).

**Étape 1 — Interroger les moniteurs.**

```
[root@ceph01 ~]# timeout 20 ceph -s
[root@ceph01 ~]# ceph quorum_status -f json-pretty | grep -A4 quorum_names
[root@ceph01 ~]# ceph time-sync-status
[admin@ceph0X ~]$ sudo cephadm shell --name mon.ceph0X -- ceph daemon mon.ceph0X mon_status
```

`mon_status` répond toujours (socket local) : `state` (`leader`, `peon`, `probing`, `electing`, `synchronizing`), `quorum` (rangs), `outside_quorum`, `extra_probe_peers`, et la `monmap` connue du moniteur.

**Variante 1 — horloge décalée.**

```
[root@ceph01 ~]# ceph health detail
[WRN] MON_CLOCK_SKEW: clock skew detected on mon.ceph03
    mon.ceph03 clock skew 150.12s > max 0.05s (latency 0.0012s)
[admin@ceph03 ~]$ timedatectl
      System clock synchronized: no
              NTP service: inactive
[admin@ceph03 ~]$ systemctl status chronyd --no-pager
     Active: inactive (dead) since …
```

Le moniteur de `ceph03` a 150 s d'avance : il voit expirer avant l'heure les baux que le chef lui accorde, provoque des élections, et selon les moments il est dans le quorum (avec `MON_CLOCK_SKEW`) ou en sort. chronyd est arrêté (et l'horloge a été réglée à la main) : c'est la cause racine ; le décalage en est la conséquence. Correctif :

```
[admin@ceph03 ~]$ sudo systemctl enable --now chronyd
[admin@ceph03 ~]$ chronyc sources -v ; chronyc tracking
[admin@ceph03 ~]$ sudo chronyc makestep
```

`makestep` corrige l'écart d'un coup (sans lui, chrony ne fait un saut qu'aux premières mesures, selon la directive `makestep 1.0 3` de Rocky, puis ralentit ou accélère l'horloge, ce qui prendrait des heures pour 150 s). Le contrôle d'horloge des moniteurs se refait à l'élection suivante ou toutes les 300 s (`mon_timecheck_interval`) : l'alerte peut rester quelques minutes.

**Variante 2 — ports des moniteurs filtrés sur un nœud.**

```
[root@ceph01 ~]# ceph health detail
[WRN] MON_DOWN: 1/3 mons down, quorum ceph01,ceph02
    mon.ceph03 (rank 2) addr [v2:10.10.30.53:3300/0,v1:10.10.30.53:6789/0] is down (out of quorum)
[admin@ceph03 ~]$ systemctl is-active ceph-<FSID>@mon.ceph03.service
active
[admin@ceph01 ~]$ timeout 3 bash -c '</dev/tcp/10.10.30.53/3300' || echo fermé
fermé
[admin@ceph03 ~]$ sudo nft list ruleset | grep -B3 -A3 3300
table inet durcissement {
        comment "Durcissement InfoGer - ports d'administration"
        chain entree {
                type filter hook input priority -50; policy accept;
                ip saddr != 10.10.30.53 tcp dport { 3300, 6789 } counter packets 418 bytes 25080 drop comment "filtrage ports Ceph"
…
```

Le moniteur tourne mais personne ne le joint, et il ne joint personne (chaîne `sortie`) : il reste en `probing`/`electing`. La table a été posée à chaud à côté de `firewalld` (absente de `firewall-cmd --list-all`, qui ne montre que la zone de firewalld). Effet secondaire si on tarde : les OSD de `ceph03` ne joignent plus aucun moniteur ; après `mon_osd_report_timeout` (900 s), les moniteurs les déclarent `down`. Correctif ciblé :

```
[admin@ceph03 ~]$ sudo nft delete table inet durcissement
```

Puis vérifier que les OSD de `ceph03` sont `up` (sinon `ceph orch daemon restart osd.N`). Prévention : le pare-feu des nœuds Ceph se gère par `firewalld` (services `ceph` et `ceph-mon`, que cephadm ouvre lui-même), dans le rôle Ansible des nœuds ; un contrôle de dérive compare `nft list tables` à la liste attendue.

**Variante 3 — deux moniteurs arrêtés.**

```
[root@ceph01 ~]# timeout 20 ceph -s
… monclient(hunting): authenticate timed out after 300
[root@ceph01 ~]# timeout 20 ceph -s ; echo $?
124
[admin@ceph01 ~]$ sudo cephadm shell --name mon.ceph01 -- ceph daemon mon.ceph01 mon_status | grep -E '"state"|outside_quorum'
    "state": "probing",
[admin@ceph02 ~]$ systemctl status ceph-<FSID>@mon.ceph02.service --no-pager
     Active: inactive (dead) since … 
[admin@ceph02 ~]$ sudo journalctl -u ceph-<FSID>@mon.ceph02.service --since -12h | grep -E 'Stopping|Stopped'
```

Un seul moniteur sur trois ne fait pas de majorité : il reste en `probing`, aucune commande `ceph` (ni l'orchestrateur, qui passe par le mgr, qui a besoin des moniteurs) ne répond. Les deux autres ont été arrêtés proprement (« mises à jour » d'InfoGér, sans relance). Correctif, **par systemd** puisque l'orchestrateur est inaccessible :

```
[admin@ceph02 ~]$ sudo systemctl start ceph-<FSID>@mon.ceph02.service
[admin@ceph03 ~]$ sudo systemctl start ceph-<FSID>@mon.ceph03.service
[root@ceph01 ~]# ceph -s       # quorum ceph01,ceph02,ceph03
```

Les clients (krbd, CephFS, RGW) ont attendu pendant la panne : les E/S en cours reprennent seules (les OSD continuaient de servir les PG actifs tant que leurs cartes et leurs tickets étaient valides, mais toute nouvelle connexion ou tout changement de carte était impossible).

**Clôture** : `lab/bin/check 08 38`, `--annuler`. RB-085 : `corrige/fichiers/M08-E38/medisphere/docs/stockage/runbooks/RB-085-perte-quorum-mon.md`.

**Explications**

Les moniteurs maintiennent les cartes du cluster par Paxos : une décision exige une majorité stricte de la *monmap* (2 sur 3). Le chef accorde des baux de lecture aux autres (*leases*, quelques secondes) ; des horloges qui divergent font expirer ces baux à tort, d'où l'exigence d'un écart inférieur à `mon_clock_drift_allowed` (0,05 s). Sans quorum, plus rien ne change dans le cluster : pas de nouvelle carte, pas d'authentification nouvelle, pas d'orchestrateur ; les E/S déjà établies continuent un temps.

**Alternatives**
- Cinq moniteurs (sur cinq hôtes) tolèrent deux pertes ; inutile tant qu'il n'y a que trois nœuds.
- Mode *stretch* (deux sites + arbitre) pour PAR1/PAR2 : moniteur arbitre (*tiebreaker*) sur un troisième site.

**Pièges classiques**
- `nft flush ruleset` pour « nettoyer » : `firewalld` perd ses règles, le nœud n'est plus filtré du tout (ou plus joignable selon la politique).
- Retirer le moniteur muet de la *monmap* (`ceph mon remove`) : on passe de 3 à 2 moniteurs, et la prochaine panne fait perdre le quorum.
- Relancer un moniteur sur un nœud dont l'horloge est fausse : il ressortira du quorum.

**En production chez MédiSphère**
Alerte sur `MON_DOWN` et `MON_CLOCK_SKEW` ; sonde chrony sur tous les nœuds (décalage, `Leap status`) ; pare-feu des nœuds uniquement par `firewalld` et le rôle Ansible ; deux sources de temps (les deux passerelles, M07).

---

### M08-E39 — Panne : le client RBD est refusé

**Démarche de diagnostic**

*Symptôme* : `rbd device map --id sonde rbd-test/sonde` échoue après un redémarrage du client.

*Hypothèses* : configuration (`ceph.conf`, adresses des moniteurs) ; trousseau (absent, illisible, mauvaise clé) ; droits du compte ; image (absente, verrouillée, fonctionnalités) ; module noyau.

**Étape 1 — Les deux messages.**

```
admin@cephcli01:~$ sudo rbd device map --id sonde rbd-test/sonde
admin@cephcli01:~$ sudo dmesg -T | tail -n 10
```

**Étape 2 — Le compte sans le noyau.**

```
admin@cephcli01:~$ sudo rbd --id sonde ls rbd-test
admin@cephcli01:~$ sudo rbd --id sonde info rbd-test/sonde
```

**Variante 1 — droits avec une faute de pool.**

```
rbd: sysfs write failed
rbd: map failed: (1) Operation not permitted
admin@cephcli01:~$ sudo rbd --id sonde ls rbd-test
rbd: error opening pool 'rbd-test': (1) Operation not permitted     # ou une liste vide selon l'opération
[root@ceph01 ~]# ceph auth get client.sonde | grep caps
        caps mon = "profile rbd"
        caps osd = "profile rbd pool=rbd-tests"
```

L'authentification passe (pas d'erreur `auth`), mais les droits OSD visent `rbd-tests`, qui n'existe pas : aucun accès à `rbd-test`. Correctif au plus juste (ne jamais « élargir pour voir ») :

```
[root@ceph01 ~]# ceph auth caps client.sonde mon 'profile rbd' osd 'profile rbd pool=rbd-test'
```

`ceph auth caps` remplace **tous** les droits du compte : redonne aussi ceux des moniteurs.

**Variante 2 — trousseau restauré depuis une vieille sauvegarde.**

```
rbd: couldn't connect to the cluster!
… monclient(hunting): handle_auth_bad_method server allowed_methods [2] but i only support [2]
admin@cephcli01:~$ sudo dmesg -T | tail -n 3
… libceph: auth protocol 'cephx' msgr authentication failed: -13     # selon le chemin, noyau ou espace utilisateur
admin@cephcli01:~$ sudo ls -l --time-style=long-iso /etc/ceph/ceph.client.sonde.keyring
-rw------- 1 root root 64 2025-11-04 03:12 /etc/ceph/ceph.client.sonde.keyring
admin@cephcli01:~$ sudo awk '/key/ {print $3}' /etc/ceph/ceph.client.sonde.keyring | sha256sum
[root@ceph01 ~]# ceph auth get-key client.sonde | sha256sum        # empreintes différentes
```

Les deux empreintes diffèrent : le client présente une clé que le cluster ne connaît pas (la date du fichier, antérieure à la création du compte, trahit une restauration). `rbd --id sonde ls` échoue de la même façon : le noyau n'y est pour rien. Correctif côté client, sans afficher la clé :

```
[root@ceph01 ~]# ceph auth get client.sonde -o /tmp/sonde.keyring     # 600, puis copie par scp vers cephcli01
admin@cephcli01:~$ sudo install -m 600 -o root -g root /tmp/sonde.keyring /etc/ceph/ceph.client.sonde.keyring && rm -f /tmp/sonde.keyring
```

(Supprime aussi la copie de `ceph01`.) La bonne pratique est de ne pas garder de trousseaux dans des sauvegardes non chiffrées ; le registre des secrets dit où vit la source (Vault `lab`, M08-E27).

**Variante 3 — fonctionnalité refusée par krbd.**

```
rbd: sysfs write failed
RBD image feature set mismatch. You can disable features unsupported by the kernel with "rbd feature disable rbd-test/sonde journaling".
In some cases useful info is found in syslog - try "dmesg | tail".
admin@cephcli01:~$ sudo dmesg -T | tail -n 1
… rbd: image sonde: image uses unsupported features: 0x40
admin@cephcli01:~$ sudo rbd --id sonde info rbd-test/sonde | grep features
        features: layering, exclusive-lock, object-map, fast-diff, deep-flatten, journaling
```

`0x40` est le bit `journaling` (nécessaire au miroir RBD par journal, non pris en charge par le pilote noyau). Le message propose la solution ; la vraie question est **pourquoi** la fonctionnalité a été activée (essai de miroir par journal de M08-E25 « pour aller plus loin » ?) et ce qu'on perd en la retirant. Ici, rien : pas de miroir configuré (`rbd mirror pool info rbd-test`). Correctif : `rbd feature disable rbd-test/sonde journaling`. Si le miroir était voulu, on choisirait le miroir par **instantanés** (compatible krbd) plutôt que par journal.

**Remontage et preuve** (toutes variantes) :

```
admin@cephcli01:~$ sudo rbd device map --id sonde rbd-test/sonde
/dev/rbd0
admin@cephcli01:~$ sudo mount /dev/rbd0 /mnt/sonde && cat /mnt/sonde/temoin
admin@cephcli01:~$ sudo wb-sonde-stockage
```

**Explications**

`rbd device map` se fait en deux temps : l'outil `rbd` (espace utilisateur) lit la configuration et le trousseau, puis demande au module noyau `rbd` (via sysfs) d'ouvrir l'image ; le noyau s'authentifie lui-même auprès des moniteurs avec la clé transmise, lit l'en-tête de l'image et compare ses fonctionnalités à celles qu'il sait gérer. D'où deux sources de messages, et l'intérêt de tester le compte avec une commande `rbd` purement en espace utilisateur (`ls`, `info`) pour séparer « authentification et droits » de « pilote noyau ».

**Alternatives**
- `rbd-nbd` (client en espace utilisateur exposé comme périphérique bloc) : toutes les fonctionnalités de librbd, au prix d'un processus à surveiller.
- Fixer `rbd_default_features` côté clients qui créent des images destinées à krbd.

**Pièges classiques**
- Donner `allow *` au compte pour « voir si c'est les droits » : la faille reste après le test.
- Afficher la clé (`cat` du trousseau) dans un ticket ou un journal.
- Recréer l'image ou le compte : perte des données de l'image dans le premier cas, rupture de tous les clients dans le second.

**En production chez MédiSphère**
Les droits des comptes clients sont décrits dans le code (`plateforme/ceph`, M08-E23) et comparés à `ceph auth ls` par la sonde ; les trousseaux sont déposés par le rôle Ansible depuis Vault ; un test de montage (`rbd --id … info`) fait partie du contrôle de dérive des clients.

---

### M08-E40 — Panne : le S3 de Ceph répond en erreur

**Démarche de diagnostic**

*Symptômes* : la sonde est rouge sur S3 ; le message varie selon la variante.

*Hypothèses*, dans l'ordre du chemin : nom → VIP (keepalived) → haproxy → RGW → authentification (signature, horloge, utilisateur) → RADOS (pool plein, PG inactifs : E36/E37).

**Étape 1 — Classer le symptôme.**

```
admin@cephcli01:~$ sudo wb-sonde-stockage
admin@cephcli01:~$ curl -sv https://rgw.par1.medisphere.internal/ -o /dev/null 2>&1 | grep -E 'Trying|Connected|HTTP/|SSL'
admin@cephcli01:~$ sudo curl -s -K /etc/workbook/sonde-s3.curl https://rgw.par1.medisphere.internal/sonde/temoin
admin@adm01:~$ curl -sI https://rgw.par1.medisphere.internal/
```

**Variante 1 — haproxy de l'ingress arrêté.**

```
[KO] S3     lecture … : curl: (7) Failed to connect to rgw.par1.medisphere.internal port 443 … Connection refused
   (ou : curl: (28) Connection timed out after 15001 milliseconds)
[root@ceph01 ~]# ceph orch ls ingress
NAME              PORTS                  RUNNING  REFRESHED  AGE  PLACEMENT
ingress.rgw.par1  10.10.30.200:443,1967  2/4      …
[root@ceph01 ~]# ceph orch ps --daemon-type haproxy
haproxy.rgw.par1.ceph02.xxxx  ceph02  *:443,1967  stopped …
haproxy.rgw.par1.ceph03.yyyy  ceph03  *:443,1967  stopped …
```

Rien n'écoute sur 443 : soit la VIP est toujours portée par un keepalived (refus immédiat), soit keepalived, dont le contrôle interroge haproxy, l'a retirée (délai dépassé, `ip -br addr` ne la montre plus nulle part). Les deux haproxy ont été arrêtés par systemd (journal : `Stopped …`), et l'orchestrateur ne relance pas un démon arrêté : il constate `stopped`. Correctif : `ceph orch daemon start haproxy.rgw.par1.ceph02.xxxx` (et l'autre), puis vérifier que la VIP revient (`ip -br addr` sur le maître VRRP).

**Variante 2 — RGW arrêtés et masqués.**

```
[KO] S3     lecture … : <html><body><h1>503 Service Unavailable</h1> No server is available to handle this request. </body></html>
[root@ceph01 ~]# ceph orch ps --daemon-type rgw
rgw.par1.ceph02.aaaa  ceph02  *:8080  stopped …
rgw.par1.ceph03.bbbb  ceph03  *:8080  stopped …
[root@ceph01 ~]# ceph orch daemon start rgw.par1.ceph02.aaaa
… Unit … is masked.
```

Le `503` vient de haproxy (page HTML, pas de XML S3) : la connexion TLS et haproxy vont bien, ce sont ses serveurs qui sont tous hors service. Correctif : `sudo systemctl unmask ceph-<FSID>@rgw.par1.ceph02.aaaa.service` sur chaque hôte, puis `ceph orch daemon start …`. L'orchestrateur sait qu'un démon devrait tourner parce qu'il figure dans la spécification du service (`ceph orch ls rgw --export`) ; mais il ne « soigne » pas un démon arrêté, il ne redéploie que les démons **absents**.

**Variante 3 — horloge du client.**

```
[KO] S3     lecture … : <?xml version="1.0" encoding="UTF-8"?><Error><Code>RequestTimeTooSkewed</Code>…
admin@cephcli01:~$ timedatectl ; chronyc tracking
System clock synchronized: no
NTP service: inactive
```

La requête arrive, TLS est valide (20 minutes d'écart ne sortent pas de la validité du certificat), RGW répond lui-même en XML : la signature SigV4 inclut l'horodatage du client, et RGW refuse un écart de plus de 15 minutes avec sa propre horloge (protection contre le rejeu d'une requête interceptée). Le S3 du socle fonctionnait-il depuis `cephcli01` ? Oui si on l'essaie sans signature, non avec. Correctif : `sudo systemctl enable --now chrony` puis `sudo chronyc makestep` sur `cephcli01` (le service s'appelle `chrony` sur Debian). Cause contributive : chrony arrêté sans alerte.

**Variante 4 — utilisateur suspendu.**

```
[KO] S3     lecture … : <Error><Code>UserSuspended</Code>…
[root@ceph01 ~]# radosgw-admin user info --uid=sonde-s3 | grep suspended
    "suspended": 1,
```

L'utilisateur existe, ses clés sont bonnes, mais il est suspendu (« audit des comptes inactifs »). Correctif : `radosgw-admin user enable --uid=sonde-s3`, après avoir vérifié **avec le propriétaire** que le compte doit bien être actif (une suspension peut être volontaire, par exemple après une fuite de clé : on fait alors tourner la clé avant de réactiver).

**Preuve commune** : sonde verte, `curl -sI https://rgw.par1.medisphere.internal/` depuis `adm01` en 200 avec certificat vérifié, `lab/bin/check 08 40`, `--annuler`.

**Explications**

Chaque étage a sa signature d'échec : pas de réponse (VIP absente, filtrage), refus TCP (rien n'écoute), erreur TLS (certificat, nom), `503` HTML (haproxy sans serveur), `403`/`400` XML (RGW : authentification, droits, horloge), `500`/`503` XML (RGW malade ou RADOS indisponible), attente sans fin (PG inactifs, pool plein). Lire le **corps** d'une erreur S3 donne souvent le diagnostic en un mot.

**Alternatives**
- Publier RGW par les répartiteurs `lb01`/`lb02` (M07) plutôt que par l'ingress de cephadm : une seule technique de publication pour toute la plateforme, au prix d'une configuration en dehors de cephadm (choix discuté en M08-E30).

**Pièges classiques**
- Redémarrer « tout RGW » sans regarder l'état des démons : un masque reste, et le redémarrage d'un démon arrêté ne dit pas pourquoi il l'était.
- Corriger l'horloge d'un client par `date -s` : elle repartira à la dérive.
- Réactiver un utilisateur suspendu sans savoir pourquoi il l'a été.

**En production chez MédiSphère**
Sondes par étage : VIP joignable, haproxy « UP » pour chaque RGW (statistiques sur le port de supervision de l'ingress), requête **signée** de bout en bout ; alerte sur un démon `stopped` dans `ceph orch ps` ; supervision de chrony sur les clients.

---

### M08-E41 — Panne : le montage CephFS est figé

**Démarche de diagnostic**

*Symptômes* : `ls /mnt/sonde-fs` bloqué ou en erreur ; RBD et S3 fonctionnent.

*Hypothèses* : plus de MDS actif ; client évincé ou bloqué ; droits du client ; PG des pools du CephFS inactifs (E36) ; réseau entre client et MDS.

**Étape 1 — Sans se bloquer.**

```
admin@cephcli01:~$ timeout 10 ls /mnt/sonde-fs; echo $?
admin@cephcli01:~$ sudo dmesg -T | grep -iE 'ceph|libceph' | tail
admin@cephcli01:~$ sudo cat /sys/kernel/debug/ceph/*/mdsc         # requêtes en attente vers le MDS
[root@ceph01 ~]# ceph fs status cephfs ; ceph health detail
```

**Variante 1 — plus aucun MDS.**

```
[ERR] MDS_ALL_DOWN: 1 filesystem is offline
    fs cephfs is offline because no MDS is active for it.
[WRN] FS_DEGRADED: 1 filesystem is degraded
[root@ceph01 ~]# ceph fs get cephfs | grep standby_count_wanted
standby_count_wanted    0
[root@ceph01 ~]# ceph orch ps --daemon-type mds
mds.cephfs.ceph01.xxxx  ceph01  stopped …
mds.cephfs.ceph02.yyyy  ceph02  stopped …
```

Tous les MDS sont arrêtés (et leurs unités masquées), et `standby_count_wanted 0` a fait taire l'avertissement « pas assez de standby » qui aurait alerté plus tôt. Le client noyau attend (requêtes en file dans `mdsc`). Correctif : démasquer et démarrer les MDS (`systemctl unmask …` sur chaque hôte, `ceph orch daemon start …`), remettre `ceph fs set cephfs standby_count_wanted 1`. Le premier MDS reprend le rang 0 (rejeu de son journal, états `up:replay` → `up:reconnect` → `up:rejoin` → `up:active`), le client se reconnecte dans la fenêtre de reconnexion et ses requêtes en attente aboutissent : pas de remontage nécessaire.

**Variante 2 — client évincé.**

```
admin@cephcli01:~$ sudo dmesg -T | grep -i ceph | tail -n 3
… libceph: mds0 (2)10.10.30.51:6801 socket closed (con state OPEN)
… ceph: mds0 rejected session
… ceph: … evicted (blocklisted?)              # libellé représentatif
[root@ceph01 ~]# ceph osd blocklist ls
10.10.30.20:0/3381229043 2026-… (expire dans une heure)
[root@ceph01 ~]# ceph tell mds.cephfs:0 session ls | grep -c sonde-fs
0
[root@ceph01 ~]# ceph log last 50 debug audit | grep -i evict
```

Le MDS a fermé la session du client et mis son adresse (avec son *nonce*) en liste de blocage dans la carte des OSD : même si le client tentait d'écrire avec ses anciennes *capabilities*, les OSD le refuseraient. Par défaut, le client noyau ne se reconnecte pas seul (`recover_session=no`) : le montage est inutilisable. Attendre l'expiration de la liste de blocage ne suffit donc pas. Correctif :

```
admin@cephcli01:~$ sudo umount -f /mnt/sonde-fs || sudo umount -l /mnt/sonde-fs
admin@cephcli01:~$ sudo mount -t ceph sonde-fs@<FSID>.cephfs=/ /mnt/sonde-fs -o secretfile=/etc/ceph/sonde-fs.secret,ms_mode=prefer-crc
admin@cephcli01:~$ cat /mnt/sonde-fs/temoin
```

Le nouveau montage a un nouveau *nonce*, donc une adresse différente de celle bloquée ; retirer l'entrée (`ceph osd blocklist rm <adresse>`) est permis mais pas nécessaire. Ce que protège l'éviction : un client injoignable qui garde des *capabilities* bloquerait les autres clients ; la liste de blocage garantit qu'il ne pourra pas écrire « en retard » des données périmées. Ce qu'elle coûte : les écritures non encore vidées par ce client sont perdues (ici le `sync` de l'injection les avait vidées). L'administrateur évince lui-même un client qui ne répond plus et bloque les autres (`ceph tell mds.cephfs:0 client evict id=…`), après avoir vérifié qu'il est vraiment hors service.

**Variante 3 — droits MDS restreints à un chemin.**

```
admin@cephcli01:~$ sudo mount -t ceph sonde-fs@<FSID>.cephfs=/ /mnt/sonde-fs -o secretfile=/etc/ceph/sonde-fs.secret
mount error: no mds server is up or the cluster is laggy     # ou : mount error 13 = Permission denied
[root@ceph01 ~]# ceph auth get client.sonde-fs | grep caps
        caps mds = "allow rw fsname=cephfs path=/medidoc"
```

Le compte n'a plus de droits MDS que sur `/medidoc` (préparation du cloisonnement de M08-E31 appliquée au mauvais compte) : le montage de `/` est refusé. Le montage existant aurait continué (les droits sont vérifiés à l'ouverture de session), le « redémarrage » l'a révélé. Correctif, en redonnant **tous** les droits d'origine :

```
[root@ceph01 ~]# ceph auth caps client.sonde-fs mds 'allow rw fsname=cephfs' mon 'allow r fsname=cephfs' osd 'allow rw tag cephfs data=cephfs'
```

(ou les droits produits par `ceph fs authorize cephfs client.sonde-fs / rw`, la forme recommandée.) Puis remontage.

**Explications**

Le MDS ne stocke rien lui-même : il tient les métadonnées (arborescence, droits, tailles) dans le pool de métadonnées et accorde aux clients des *capabilities* (droit de mettre en cache, de lire, d'écrire, de modifier la taille d'un fichier). Sans MDS actif, aucune opération de métadonnées ne peut aboutir : tout le système de fichiers attend. Un client qui ne rend pas ses *capabilities* bloque les autres ; d'où l'éviction et la liste de blocage, qui protègent la cohérence au prix des écritures non vidées du client évincé.

**Alternatives**
- Option de montage `recover_session=clean` : le client noyau se reconnecte seul après une éviction, en jetant ses données en cache non vidées (à réserver aux usages qui le tolèrent).
- `allow_standby_replay` : un MDS en attente suit le journal du MDS actif et reprend en quelques secondes.

**Pièges classiques**
- `ls` sans délai sur un montage figé : le terminal est perdu (processus en état `D`, non tuable).
- Redémarrer le client : on perd l'information (`dmesg`, `mdsc`) et on n'a pas corrigé la cause côté cluster.
- `standby_count_wanted 0` pour faire taire une alerte au lieu de déployer un MDS en attente.

**En production chez MédiSphère**
Alerte sur `MDS_ALL_DOWN`, `FS_DEGRADED`, `MDS_INSUFFICIENT_STANDBY` et sur les sessions évincées (journal d'audit) ; MDS en *standby-replay* pour le CephFS des équipes ; droits générés par `ceph fs authorize` dans le code, jamais écrits à la main.

---

### M08-E42 — Panne : le cluster est lent

**Démarche de diagnostic**

*Symptômes* : latences élevées, `SLOW_OPS` passagers, rien de « cassé ».

*Hypothèses* : un OSD ou un disque lent ; un nœud ou un réseau dégradé (MTU, limitation, erreurs) ; un réglage de l'ordonnanceur ; une récupération ou un *scrub* qui consomment la capacité.

**Étape 1 — Mesurer avec le protocole de M08-E28.**

```
[root@ceph01 ~]# rados bench -p rbd-test 30 write -b 4M -t 16 --no-cleanup
[root@ceph01 ~]# rados bench -p rbd-test 30 seq -t 16
[root@ceph01 ~]# rados -p rbd-test cleanup
admin@cephcli01:~$ sudo rbd --id sonde bench --io-type write --io-size 4K --io-threads 16 --io-total 64M rbd-test/sonde
```

⚠️ `rbd bench --io-type write` écrit **dans l'image** : sur l'image témoin (sans données utiles) c'est acceptable ; sur une vraie image, crée une image de test. Compare les débits, IOPS et latences moyennes à ta référence.

**Étape 2 — Localiser.**

```
[root@ceph01 ~]# ceph health detail
[root@ceph01 ~]# ceph osd perf                       # latences de validation/application par OSD
[root@ceph01 ~]# ceph daemon osd.4 dump_historic_ops | grep -E '"description"|"duration"|event' | head -40   # dans cephadm shell --name osd.4
[root@ceph01 ~]# ceph config dump | grep -i mclock
```

**Variante 1 — trames de plus de 1500 octets jetées sur le réseau cluster d'un nœud.**

```
[WRN] OSD_SLOW_PING_TIME_BACK: Slow OSD heartbeats on back (longest 9832.511ms)
    Slow OSD heartbeats on back from osd.2 [ceph01] to osd.5 [ceph03] 9832.511 msec possibly improving
[admin@ceph01 ~]$ ping -c 3 -M do -s 1472 10.10.31.53   # passe
[admin@ceph01 ~]$ ping -c 3 -M do -s 8972 10.10.31.53   # 100 % de perte, aucun message « Frag needed »
[admin@ceph03 ~]$ ip -d link show ens19 | grep -o 'mtu [0-9]*'
mtu 9000
[admin@ceph03 ~]$ ethtool -k ens19 | grep -E 'generic-(receive|segmentation)-offload|tcp-segmentation'
generic-receive-offload: off
…
[admin@ceph03 ~]$ sudo nft list table inet medisphere_qos
table inet medisphere_qos {
        chain entree { … iifname "ens19" meta length > 1500 drop }
        chain sortie { … oifname "ens19" meta length > 1500 drop }
}
```

Un « trou noir de PMTU » : les interfaces annoncent 9000, TCP négocie de gros segments, mais tout paquet de plus de 1500 octets disparaît sans ICMP. Les connexions s'établissent (petits paquets), puis les transferts de réplication calent et sont retransmis ; les battements de cœur entre OSD, volontairement gonflés à 2000 octets (`osd_heartbeat_min_size`), se perdent sur le réseau cluster : Ceph le signale (`OSD_SLOW_PING_TIME_BACK`) et peut même déclarer des OSD `down` à tort (oscillations). Dans un vrai centre de données, c'est un port de commutateur ou une liaison restés à 1500 ; le lab ne pouvant pas toucher `vmbr1`, la panne simule cet équipement sur le nœud visé (ici `ceph03`) (« profil réseau » d'InfoGér : table nftables et délestages coupés pour que le filtrage voie les vraies tailles). Correctif :

```
[admin@ceph03 ~]$ sudo nft delete table inet medisphere_qos
[admin@ceph03 ~]$ sudo ethtool -K ens19 gro on gso on tso on
[admin@ceph01 ~]$ ping -c 3 -M do -s 8972 10.10.31.53     # passe
```

**Variante 2 — limite client de mClock.**

```
[root@ceph01 ~]# ceph config dump | grep -i mclock
osd   advanced  osd_mclock_profile                 custom
osd   advanced  osd_mclock_scheduler_client_lim    0.010000
[root@ceph01 ~]# ceph config log 10 | grep mclock          # quand, par qui
```

Le profil `custom` désactive les profils intégrés et laisse les valeurs manuelles : la limite des opérations clientes à 1 % de la capacité estimée de chaque OSD écrase le débit (quelques IOPS sur les OSD `hdd`), sans aucune alerte de santé autre que des opérations lentes. Les mesures montrent un plafond net et régulier (pas d'erreurs, pas de pics), indice d'une limitation volontaire plutôt que d'une panne. Correctif : revenir au profil intégré décidé en M08-E29 :

```
[root@ceph01 ~]# ceph config rm osd osd_mclock_scheduler_client_lim
[root@ceph01 ~]# ceph config rm osd osd_mclock_profile          # retour au défaut (balanced), ou ta valeur de M08-E29
[root@ceph01 ~]# ceph config show osd.0 osd_mclock_profile
```

**Variante 3 — débit limité sur le réseau cluster d'un nœud.**

```
[admin@ceph02 ~]$ tc qdisc show dev ens19
qdisc tbf 8001: root refcnt 2 rate 4Mbit burst 64Kb lat 400ms
```

(Si `tc` ou le module `sch_tbf` manquent, la panne pose une règle nftables `limit rate over 512 kbytes/second drop` dans `inet medisphere_qos`.) Toute réplication qui passe par `ceph02` est bridée à 4 Mbit/s : les écritures dont un réplica est sur `ceph02` attendent leurs sous-opérations (`waiting for sub ops` dans `dump_historic_ops`, côté primaire), `ceph osd perf` montre des latences élevées partout sauf… quand aucun réplica n'est sur `ceph02`. `iperf3` entre `ceph01` et `ceph02` sur 10.10.31.0/24 le chiffre. Correctif : `sudo tc qdisc del dev ens19 root` (ou suppression de la table nftables).

**Étape finale** : mêmes mesures qu'à l'étape 1, rangées dans le journal (avant/après), objets de `rados bench` nettoyés, `lab/bin/check 08 42`, `--annuler`.

**Pourquoi aucune alerte franche** : la santé reste `HEALTH_OK` ou passe brièvement en `WARN` (`SLOW_OPS`, ping lent) ; les sondes de disponibilité réussissent (lentement). Il faut des alertes sur la **latence** : `ceph_osd_op_w_latency` / `ceph_osd_op_r_latency` du module `prometheus` (moyenne glissante par OSD), le temps de réponse de la sonde, et `OSD_SLOW_PING_TIME_*` en alerte et non en simple avertissement.

**Explications**

Une écriture répliquée n'est acquittée que lorsque toutes les copies de l'ensemble *acting* l'ont écrite : la latence du cluster est celle du **plus lent** réplica, et le réseau cluster est sur le chemin de chaque écriture. mClock répartit la capacité de chaque OSD entre clients, récupération et tâches de fond selon des réservations, poids et limites ; un profil intégré règle ces trois valeurs de façon cohérente, `custom` les laisse à la main.

**Alternatives**
- Mesurer le réseau seul avec `iperf3` (paquet `iperf3`, à installer temporairement) avant de soupçonner Ceph.
- `ceph tell osd.* bench` pour la performance brute des disques, indépendante du réseau.

**Pièges classiques**
- Régler mClock pour compenser un problème réseau.
- Tester la MTU avec `ping` sans `-M do` : le noyau fragmente et tout « passe ».
- Laisser les objets de `rados bench` (`benchmark_data_*`) dans le pool.

**En production chez MédiSphère**
Test de MTU de bout en bout dans le rôle Ansible des nœuds (ping `-M do -s 8972` vers chaque pair) ; alerte de latence par OSD ; réglages mClock dans `plateforme/ceph` et contrôle de dérive de `ceph config dump` ; aucun « profil » livré par un prestataire sans MR.

---

### M08-E43 — Astreinte : le stockage en détresse

**Démarche**

1. **Triage** : symptômes affichés, puis instruments dans l'ordre des dépendances : SSH par IP vers `ceph01-03` et `cephcli01`, console de secours, `timeout 20 ceph -s` sur `ceph01`, `ceph health detail`, `sudo wb-sonde-stockage`. Puis `lab/bin/check 08 35` à `08 42` pour la carte.
2. **Priorisation** par dépendances : quorum et horloges (E38) → réseau des OSD (E42 v1/v3) → OSD (E35) → placement et seuils (E36, E37) → MDS, RGW, ingress (E41, E40) → clients (E39, E41 v2/v3, E40 v3/v4). Exemples : avec E38 v3 et E39, rien n'est diagnosticable côté client tant que le quorum n'est pas revenu ; avec E42 v1 et E35, l'OSD `down` « à cause du réseau » et l'OSD `down` « à cause de son disque » se ressemblent : `cephadm logs` (plantage sur `EIO` ou arrêt) et `OSD_SLOW_PING_TIME_BACK` les séparent ; avec E37 v3 et E40, une requête S3 qui attend n'est pas un problème de RGW.
3. **Communication** (modèle) : « 02 h 55 — INC-3550 — Statut : en cours. Impact : écritures bloquées sur le stockage de test, S3 de MédiDoc indisponible. Cause : deux anomalies distinctes identifiées (drapeau de maintenance oublié, démons RGW arrêtés) ; correction de la première en cours. Risque pour la sauvegarde de 5 h : faible si la seconde est corrigée avant 4 h. Prochaine communication : 03 h 25. »
4. **Post-mortem** : chronologie horodatée (détection, hypothèses, fausses pistes, corrections), extraits de `ceph health detail` à chaque étape, deux causes racines et leurs causes contributives (interventions hors procédure, absence de sonde de latence, `standby_count_wanted` à 0…), détection (qu'est-ce qui aurait dû alerter avant Nadia ?), actions avec responsable et échéance (alertes `MON_DOWN`/`OSD_DOWN`/`PG_AVAILABILITY` en page immédiate, contrôle de dérive des drapeaux, des seuils, des tables nftables et de mClock, comptes d'administration nominatifs). Exemple : `corrige/fichiers/M08-E43/medisphere/docs/socle/post-mortems/2026-10-20-INC-3550.md`.

**Grille d'auto-évaluation**
- [ ] Les instruments ont été vérifiés avant le diagnostic (aucune conclusion tirée d'une commande qui attendait un quorum absent).
- [ ] Aucune commande destructive ni d'abandon de données n'a été lancée, même « pour essayer ».
- [ ] L'ordre de traitement est justifié par les dépendances ; chaque correction est suivie d'une reprise de **tous** les tests de départ.
- [ ] Trois communications au moins, avec statut, impact, prochaine étape, prochaine heure.
- [ ] Post-mortem sans coupable, causes racines distinctes des déclencheurs, actions vérifiables.

---

### M08-E44 — Sous le capot : où est rangé cet objet ?

**Solution**

Compte rendu modèle : `corrige/fichiers/M08-E44/medisphere/docs/stockage/analyses/placement-objet.md`. Déroulé (dans `sudo cephadm shell` sur `ceph01`, dossier `/tmp/analyse`) :

**1. Du nom au PG.**

```
[ceph: root@ceph01 /]# rados -p rbd-test put analyse-placement /etc/os-release
[ceph: root@ceph01 /]# ceph osd map rbd-test analyse-placement
osdmap e431 pool 'rbd-test' (2) object 'analyse-placement' -> pg 2.7d1c5a3e (2.1e) -> up ([5,1,7], p5) acting ([5,1,7], p5)
[ceph: root@ceph01 /]# ceph osd pool get rbd-test pg_num
pg_num: 32
```

`2.7d1c5a3e` : identifiant du pool et hachage (rjenkins) du nom ; `(2.1e)` : le PG réel, obtenu par `ceph_stable_mod(hachage, pg_num, masque)` — avec `pg_num` = 32, c'est le hachage modulo 32 (0x3e mod 0x20 = 0x1e). Si `pg_num` n'est pas une puissance de 2, `ceph_stable_mod` utilise le masque de la puissance supérieure et replie les valeurs trop grandes : certains PG reçoivent deux fois plus de hachages que d'autres (déséquilibre), d'où les puissances de 2 recommandées. *up* et *acting* identiques, primaire `osd.5`.

**2. Hors ligne avec la carte des OSD.**

```
[ceph: root@ceph01 analyse]# ceph osd getmap -o osdmap.bin
[ceph: root@ceph01 analyse]# osdmaptool osdmap.bin --test-map-object analyse-placement --pool 2
osdmaptool: osdmap file 'osdmap.bin'
 object 'analyse-placement' -> 2.1e -> [5,1,7]
[ceph: root@ceph01 analyse]# osdmaptool osdmap.bin --test-map-pgs --pool 2
pool 2 pg_num 32
#osd    count   first   primary c wt    wt
osd.0   11      4       4       …
…
 avg 10.6667 stddev 1.2472 (0.1169x) (expected 3.0912 0.289796x))
```

Le même calcul, sans interroger le cluster : un client n'a besoin que de la carte. La répartition par OSD (et l'écart type) dit si le pool est équilibré.

**3. Simulations CRUSH.**

```
[ceph: root@ceph01 analyse]# ceph osd getcrushmap -o crush.bin && crushtool -d crush.bin -o crush.txt
[ceph: root@ceph01 analyse]# crushtool -i crush.bin --test --rule 0 --num-rep 3 --min-x 0 --max-x 9 --show-mappings
CRUSH rule 0 x 0 [5,1,7]
…
[ceph: root@ceph01 analyse]# crushtool -i crush.bin --test --rule 0 --num-rep 3 --min-x 0 --max-x 1023 --show-utilization
[ceph: root@ceph01 analyse]# crushtool -i crush.bin --test --rule 0 --num-rep 4 --show-bad-mappings | head -3
bad mapping rule 0 x 0 num_rep 4 result [5,1,7]
[ceph: root@ceph01 analyse]# crushtool -i crush.bin --test --rule 0 --num-rep 3 --min-x 0 --max-x 1023 --show-mappings --weight 3 0 --weight 4 0 --weight 5 0 > sans-ceph02.txt
[ceph: root@ceph01 analyse]# crushtool -i crush.bin --test --rule 0 --num-rep 3 --min-x 0 --max-x 1023 --show-mappings > normal.txt
[ceph: root@ceph01 analyse]# diff normal.txt sans-ceph02.txt | grep -c '^>'
```

Avec 4 copies et 3 hôtes, chaque entrée est une mauvaise correspondance (c'est la variante 1 de M08-E36). En donnant un poids nul aux OSD de `ceph02` : avec trois hôtes et trois copies, **chaque** PG a une copie sur `ceph02`, donc tous changent d'ensemble, et aucun ne peut retrouver trois copies (deux hôtes restants, domaine `host`) : les PG restent `undersized` jusqu'au retour de l'hôte. Sur un cluster plus large, la même simulation chiffre la part de PG déplacés avant une maintenance ou une modification de carte. Les numéros d'OSD de `--weight` sont à adapter à ton arbre (`ceph osd tree`).

**4. Une image RBD en objets.**

```
[ceph: root@ceph01 /]# rbd info rbd-test/sonde | grep -E 'size|order|block_name_prefix|id:'
        size 1 GiB in 256 objects
        order 22 (4 MiB objects)
        id: 1a2b3c4d5e6f
        block_name_prefix: rbd_data.1a2b3c4d5e6f
[ceph: root@ceph01 /]# rados -p rbd-test stat rbd_id.sonde ; rados -p rbd-test listomapvals rbd_header.1a2b3c4d5e6f | head
[ceph: root@ceph01 /]# rados -p rbd-test ls | grep -c rbd_data.1a2b3c4d5e6f
19
[ceph: root@ceph01 /]# ceph osd map rbd-test rbd_data.1a2b3c4d5e6f.0000000000000000
```

`rbd_id.sonde` contient l'identifiant de l'image ; `rbd_header.<id>` ses métadonnées (taille, fonctionnalités, instantanés) en omap ; `rbd_directory` relie noms et identifiants pour tout le pool ; les données sont découpées en objets de 4 Mio (`order 22`) nommés `rbd_data.<id>.<numéro en hexadécimal sur 16 chiffres>`. Seuls les objets écrits existent (ici quelques dizaines : métadonnées d'ext4 et fichiers témoins), pas 256 : allocation à la demande.

**5. Dans l'OSD.** Pour `analyse-placement` (acting `[5,1,7]`, primaire 5), on prend `osd.7` (sur `ceph03`) :

```
[root@ceph01 ~]# ceph osd ok-to-stop 7
[root@ceph01 ~]# ceph osd set noout
[root@ceph01 ~]# ceph orch daemon stop osd.7
[admin@ceph03 ~]$ sudo cephadm shell --name osd.7
[ceph: root@ceph03 /]# ceph-objectstore-tool --data-path /var/lib/ceph/osd/ceph-7 --op list-pgs | grep '^2\.1e$'
2.1e
[ceph: root@ceph03 /]# ceph-objectstore-tool --data-path /var/lib/ceph/osd/ceph-7 --pgid 2.1e --op list analyse-placement
["2.1e",{"oid":"analyse-placement","key":"","snapid":-2,"hash":2098207294,"max":0,"pool":2,"namespace":"","max":0}]
[ceph: root@ceph03 /]# ceph-objectstore-tool --data-path /var/lib/ceph/osd/ceph-7 --pgid 2.1e '<JSON ci-dessus>' get-bytes | sha256sum
[ceph: root@ceph03 /]# exit
[root@ceph01 ~]# ceph orch daemon start osd.7
[root@ceph01 ~]# ceph -s            # attendre active+clean
[root@ceph01 ~]# ceph osd unset noout
```

Le `hash` du JSON (2098207294 = 0x7d1c5a3e) est celui de l'étape 1 : la boucle est bouclée. (Selon la version, ajoute `--no-mon-config` si l'outil cherche à joindre les moniteurs. Le fichier envoyé par `rados put` est le `/etc/os-release` **du conteneur** `cephadm shell` de `ceph01`, pas celui de Rocky : compare avec l'empreinte relevée dans ce conteneur au moment du `put`.)

**Réponses aux questions d'analyse**

1. **PG plutôt qu'objets** : des milliards d'objets ne peuvent pas avoir chacun un état suivi (*peering*, journal, récupération) ni être recalculés à chaque changement de carte. Le PG est l'unité d'agrégation : quelques centaines par OSD, chacun avec son journal et son état ; un changement de carte ne recalcule que des PG, et la récupération se fait par PG.
2. **Pas d'annuaire** : le placement est une **fonction** (hachage puis CRUSH) de la carte des OSD ; le client a la carte (fournie par les moniteurs) et calcule lui-même. Avec une carte en retard, il s'adresse au mauvais primaire, qui lui répond avec une carte plus récente (ou le client la redemande) : il recalcule et réessaie.
3. **up / acting** : *up* = ce que CRUSH calcule ; *acting* = qui sert réellement. Ils diffèrent quand une entrée *pg_temp* (posée pendant un remplissage pour garder les anciens OSD qui ont les données) ou *upmap* (exception explicite) s'applique : les clients continuent d'être servis par des OSD complets pendant que les nouveaux se remplissent.
4. **upmap** : l'équilibreur pose des exceptions individuelles (« ce PG va sur tel OSD plutôt que tel autre ») sans changer les poids CRUSH, donc sans déplacer d'autres PG en cascade ; une modification de poids déplace des PG de façon moins prévisible.
5. **Objet inexistant** : `ceph osd map` ne consulte aucun OSD ; il applique le calcul au nom. Le placement ne dépend que du nom, du pool et de la carte, jamais de l'existence de l'objet.
6. **Allocation à la demande** : une image n'est qu'un en-tête ; un objet de données n'existe qu'après la première écriture dans sa tranche de 4 Mio. Une écriture aléatoire de 4 Kio crée (ou modifie) un seul objet, mais BlueStore écrit au minimum une unité d'allocation (`bluestore_min_alloc_size`, 4 Kio par défaut sur SSD et HDD depuis Pacific) et met à jour ses métadonnées (et, si `object-map` est activé, l'objet de carte de l'image).
7. **OSD arrêté** : l'outil ouvre directement BlueStore et RocksDB, qui ne supportent qu'un seul ouvreur ; deux processus corrompraient les métadonnées. Usage réel : exporter un PG d'un OSD mourant (`--op export`) pour l'importer dans un OSD sain quand c'était la dernière copie ; précautions : OSD arrêté et `noout`, export vers un disque sûr, jamais `export-remove` avant d'avoir vérifié l'import, et ticket de support si les données sont précieuses.

**Pièges classiques**
- Oublier de relancer l'OSD ou de retirer `noout` (le check le vérifie).
- Utiliser `get-bytes` avec un JSON tronqué ou modifié : l'outil ne trouve pas l'objet.
- Garder `osdmap.bin` ou `crush.bin` dans le dépôt (inutile, et ils décrivent ton infrastructure).

---

### M08-E45 — Questions expert : Ceph

**Réponses**

1. **Pas de table centrale** : le placement est calculé (CRUSH) par chaque client et chaque OSD à partir d'une carte compacte. Aucun annuaire à interroger ni à répliquer, donc pas de goulot d'étranglement ni de point unique de défaillance, et une extension linéaire. Après une panne, chaque OSD calcule lui-même quels PG il doit maintenant porter et le *peering* les reconstruit entre pairs, en parallèle : la récupération est distribuée, sans coordinateur.
2. **QCM — réponse b.** Avec `min_size 2`, deux copies sur trois suffisent pour rester actif : les PG sont `active+undersized+degraded`. Domaine `host` et deux hôtes restants : CRUSH ne peut pas placer de troisième copie (c ferait deux copies sur un hôte, ce que la règle interdit). a est faux (deux copies ≥ `min_size`) ; d est faux (rien n'est en lecture seule).
3. **`min_size 1`** : le PG accepte des écritures avec une seule copie disponible. Scénario : OSD A et B tombent, C (seul) accepte des écritures ; C tombe à son tour, A et B reviennent avec des données anciennes. Les écritures acquittées pendant que C était seul n'existent que sur C : si son disque est perdu, elles le sont aussi (et le PG peut rester `incomplete` ou `down` en attendant C). `min_size 2` garantit qu'une écriture acquittée existe sur au moins deux OSD.
4. **Peering** : à chaque changement de l'ensemble *acting* (et au démarrage d'un OSD), le primaire collecte les informations de PG (journaux, `last_update`, `last_epoch_started`, historique des intervalles) des OSD actuels et passés susceptibles d'avoir écrit, choisit le journal faisant autorité et décide qui doit être récupéré. Un PG reste `peering` s'il attend un OSD qui a pu écrire dans un intervalle passé (`down`) ; `incomplete` s'il ne trouve pas de journal faisant autorité complet. On regarde `ceph pg <pgid> query` (`recovery_state`, `blocked_by`).
5. **Réplication / EC** : 3 copies = 200 % de surcoût, écriture simple, récupération par copie ; EC `k=4, m=2` = 50 % de surcoût, tolère 2 pertes, mais une petite écriture ou une réécriture partielle impose une lecture-modification-écriture de la bande (latence, amplification), et une récupération lit `k` fragments. Avec domaine `host`, il faut au moins `k+m` = 6 hôtes. `allow_ec_optimizations` (FastEC, Tentacle) active des optimisations de petites écritures et de lectures partielles pour un pool EC, pour en rapprocher les performances de la réplication (une fois activée, ne se désactive pas : à tester d'abord).
6. **QCM — réponse b.** `osd_memory_target` est une cible : BlueStore ajuste ses caches pour rester autour, mais la mémoire réelle peut dépasser (récupération, *peering* de nombreux PG). a est faux (pas de plafond dur, pas de tueur interne ; c'est le noyau qui tue si la VM manque de mémoire) ; c est faux (cephadm peut ajuster la cible automatiquement avec `osd_memory_target_autotune`, il ne réserve rien au conteneur) ; d est faux (concerne l'ensemble des caches de BlueStore, pas seulement RocksDB).
7. **BlueStore** : données directement sur le périphérique bloc (sans système de fichiers), métadonnées dans RocksDB (périphérique `block.db`), journal d'écriture anticipée de RocksDB (`block.wal`). Les placer sur SSD accélère les métadonnées et les petites écritures (différées dans le WAL) de disques durs lents. Si `block.db` est trop petit, RocksDB déborde sur le disque lent (`BLUEFS_SPILLOVER`) : performances dégradées, pas de perte.
8. **Nombre impair** : le quorum est une majorité stricte ; 4 moniteurs tolèrent 1 perte comme 3, et avec 2 pertes sur 4 il n'y a plus de majorité (2 n'est pas > 4/2). 7 moniteurs tolèrent 3 pertes mais chaque décision Paxos doit être acceptée par 4 : plus de latence, de trafic, de mémoire et de disque. 5 suffisent pour les gros clusters.
9. **cephx** : authentification mutuelle par secret partagé et tickets à durée limitée, et autorisation par droits (*caps*) ; ne chiffre pas les données (c'est le rôle de msgr2 `secure`) et ne protège pas contre qui a le trousseau. `profile rbd` = les droits exacts nécessaires à un client RBD (y compris la liste de blocage d'un ancien détenteur de verrou exclusif) ; `allow rwx pool=…` = lecture, écriture, exécution de classes d'objets sur le pool, sans les droits moniteurs adaptés ; `allow *` = tout, à réserver à l'administration. CVE-2025-30156 est une faiblesse de cephx corrigée en 20.2.4 ; la mise à jour comporte des étapes particulières décrites dans les notes de version (voir M08-E26 et son corrigé : c'est la référence pour le détail, à relire sur [docs.ceph.com](https://docs.ceph.com/en/latest/releases/tentacle/)).
10. **msgr2** : port 3300 (msgr2), 6789 (msgr1, ancien protocole) ; `crc` = intégrité par somme de contrôle, sans chiffrement ; `secure` = chiffrement AES-GCM. Avant d'imposer `secure` (`ms_cluster_mode`, `ms_service_mode`, `ms_client_mode`) : les clients noyau doivent le supporter (noyau ≥ 5.11, option `ms_mode=secure` ou `prefer-secure` au montage et au map) et joindre le port 3300 ; les vieux clients en msgr1 seront refusés. Mesurer aussi le coût CPU.
11. **QCM — réponse b.** Un PG `active` sert les écritures ; le primaire les envoie à tous les membres de l'ensemble *acting* et n'acquitte que quand tous ont écrit. `undersized` veut dire que l'ensemble est plus court que `size`, pas qu'on attend. a et c sont faux (le PG est actif) ; d est faux (Ceph n'acquitte jamais une écriture portée par le seul primaire quand d'autres membres sont dans l'ensemble).
12. **Écriture répliquée** : le client calcule le PG et envoie au primaire (réseau public) ; le primaire écrit localement (BlueStore : données, puis métadonnées dans RocksDB via le WAL) et envoie en parallèle aux répliques (réseau cluster) ; chaque réplique écrit et répond ; le primaire acquitte au client. Latence = réseau public + max(écriture locale, aller-retour cluster + écriture de la réplique la plus lente). Le réseau cluster est donc sur le chemin critique de chaque écriture (M08-E42), et il porte aussi la récupération.
13. **Drapeaux** : `noout` empêche le passage automatique à `out` ; `norebalance` empêche le rééquilibrage des PG non dégradés ; `nobackfill` les remplissages ; `norecover` les récupérations ; `pause` toutes les E/S clientes. Pour redémarrer un nœud 10 minutes : `noout` (éventuellement par hôte avec `ceph osd set-group noout <hôte>`, ou `ceph orch host maintenance enter`). Celui qu'il ne faut jamais oublier : `noout` (silencieux, il désactive la réparation automatique) — et `pause`, qui arrête tout.
14. **mClock** : les profils répartissent la capacité de chaque OSD : `high_client_ops` favorise les clients, `high_recovery_ops` la récupération (plus rapide, clients pénalisés), `balanced` (défaut) partage. Les réglages anciens de récupération (`osd_max_backfills`, `osd_recovery_max_active`) sont ignorés pour ne pas contredire l'ordonnanceur ; `osd_mclock_override_recovery_settings true` permet de les reprendre en main si nécessaire, en connaissance de cause.
15. **CephFS** : le MDS gère l'espace de noms et les *capabilities* (cache et accès accordés aux clients) ; un rang est une part de l'espace de noms servie par un MDS actif (`max_mds` rangs) ; un *standby-replay* suit le journal d'un rang pour reprendre vite. Toute opération de métadonnées (ouvrir, créer, `stat`, lister) passe par le MDS : s'il est lent (cache trop petit, `mds_cache_memory_limit`, client qui ne rend pas ses *capabilities*, journal lent sur le pool de métadonnées), tout le système de fichiers l'est. Remèdes : cache dimensionné, pool de métadonnées sur SSD, plusieurs rangs et épinglage de sous-arborescences, évincer les clients défaillants.
16. **QCM — réponse b.** L'éviction met l'adresse du client en liste de blocage dans la carte des OSD : ses écritures en retard sont refusées. a est faux (le client noyau ne se reconnecte pas seul par défaut) ; c est faux (les écritures non vidées sont perdues, le MDS ne les a jamais reçues) ; d est faux (la liste de blocage agit sur les OSD, donc sur les données).
17. **RGW** : une *zone* = un ensemble de pools et de passerelles ; un *zonegroup* regroupe des zones qui se répliquent ; un *realm* porte la configuration globale et l'historique (*period*) pour le multisite. Les *accounts* de Tentacle regroupent utilisateurs, rôles et politiques IAM sous un compte administrable comme un compte AWS, et remplacent l'IAM au niveau *tenant*, déprécié. `RequestTimeTooSkewed` : la signature SigV4 inclut l'horodatage ; un écart de plus de 15 minutes est refusé pour limiter le rejeu d'une requête capturée.
18. **cephadm** : `systemctl stop` arrête le conteneur sans prévenir l'orchestrateur, qui le voit `stopped` et ne le relance pas ; `ceph orch daemon stop` fait la même chose en le sachant. Un fichier de configuration modifié à la main dans `/var/lib/ceph/<fsid>/<démon>/` sera écrasé au prochain `redeploy`/`reconfig`. La spécification (et la base de configuration `ceph config`) fait foi pour ce qui doit exister ; l'état des hôtes n'est qu'un constat.
19. **`ceph orch upgrade`** : mgr d'abord (l'orchestrateur lui-même), puis moniteurs, crash, OSD (hôte par hôte, en respectant `ok-to-stop`), MDS, RGW et autres passerelles, puis les services annexes ; ordre qui garde la compatibilité (les démons de contrôle connaissent le nouveau protocole avant les autres). Avant : `HEALTH_OK`, notes de version lues (étapes particulières de 20.2.4), `ceph orch upgrade check --image …`, sauvegarde de la configuration. Pendant : `ceph orch upgrade status`, `ceph orch upgrade pause`/`resume`/`stop`.
20. **OSD `down`** : `ceph health detail`, `ceph osd tree` (down/out, hôte), journal du cluster (depuis quand, signalé par qui) ; `ceph orch ps` ; sur l'hôte : `systemctl status` de l'unité, `cephadm logs --name osd.N`, `dmesg`, état du disque (`lsblk`, SMART) ; décider : démon arrêté ou masqué → le relancer ; plantage logiciel → logs, relance, ticket ; disque en erreur → RB-080 (le laisser `out`, remplacement). Interdits tant que la réponse n'est pas connue : `ceph osd purge`, `destroy`, `zap`, `ceph osd lost`, `mark_unfound_lost`, et tout redémarrage en boucle qui efface le journal.

**Grille d'auto-évaluation** : une réponse est juste si elle explique le **mécanisme** (pas seulement la commande) ; pour les QCM, si elle justifie l'élimination de chaque mauvaise option. Les points faibles typiques : *peering* (4), états de PG (2, 11), éviction (16) : refais M08-E36 et M08-E41 en lisant `ceph pg query` à chaque étape.
