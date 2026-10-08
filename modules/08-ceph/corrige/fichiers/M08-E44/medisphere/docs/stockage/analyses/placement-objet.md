# Où est rangé un objet dans ceph-par1 ?

> Compte rendu de M08-E44 (PLAT-980). Toutes les commandes ont été lancées dans `sudo cephadm shell`
> sur `ceph01` (dossier temporaire `/tmp/analyse`), sauf l'étape « Dans l'OSD », dans
> `cephadm shell --name osd.7` sur `ceph03`. Les identifiants (pool 2, PG 2.1e, OSD 5, 1, 7) sont
> ceux du lab au moment de l'analyse : refais le calcul, ils changent avec la carte.

## Du nom à l'OSD

```
# rados -p rbd-test put analyse-placement /etc/os-release
# ceph osd map rbd-test analyse-placement
osdmap e431 pool 'rbd-test' (2) object 'analyse-placement' -> pg 2.7d1c5a3e (2.1e) -> up ([5,1,7], p5) acting ([5,1,7], p5)
```

| Élément | Valeur | Origine |
|---|---|---|
| Époque de la carte | 431 | carte des OSD courante |
| Pool | 2 (`rbd-test`) | `ceph osd pool ls detail` |
| Hachage du nom | `0x7d1c5a3e` | rjenkins du nom de l'objet |
| PG réel | **2.1e** | `ceph_stable_mod(0x7d1c5a3e, pg_num = 32, masque 31)` = `0x1e` |
| Ensembles *up* / *acting* | `[5,1,7]` / `[5,1,7]` | CRUSH (règle `ssd-baie`, domaine `rack`), aucun *pg_temp* ni *upmap* |
| Primaire | `osd.5` (`ceph02`) | premier de l'ensemble *acting* |

Hors ligne, avec la carte des OSD seule :

```
# ceph osd getmap -o osdmap.bin
# osdmaptool osdmap.bin --test-map-object analyse-placement --pool 2
 object 'analyse-placement' -> 2.1e -> [5,1,7]
# osdmaptool osdmap.bin --test-map-pgs --pool 2      # répartition : 9 à 12 PG par OSD, écart type ≈ 1,2
```

Même résultat que le cluster : le client n'a besoin que de la carte pour calculer où écrire.

## Simulations CRUSH

Règle du pool `rbd-test` : `ssd-baie` (identifiant numérique donné par `ceph osd crush rule dump ssd-baie`, ici `<ID>` ; les sorties l'affichent).

```
# ceph osd getcrushmap -o crush.bin && crushtool -d crush.bin -o crush.txt
# crushtool -i crush.bin --test --rule <ID> --num-rep 3 --min-x 0 --max-x 9 --show-mappings
CRUSH rule <ID> x 0 [5,1,7]
CRUSH rule <ID> x 1 [2,6,4]
…
# crushtool -i crush.bin --test --rule <ID> --num-rep 3 --min-x 0 --max-x 1023 --show-utilization
  device 0:  stored : 337  expected : 341.333
  …
# crushtool -i crush.bin --test --rule <ID> --num-rep 4 --show-bad-mappings | head -n 2
bad mapping rule <ID> x 0 num_rep 4 result [5,1,7]
bad mapping rule <ID> x 1 num_rep 4 result [2,6,4]
```

- 4 copies sur 3 baies avec un domaine `rack` : **toutes** les entrées sont de mauvaises correspondances. C'est exactement la variante « size 4 » de M08-E36 : la règle ne peut pas placer ce que le pool demande.
- Perte simulée de `ceph02` (`--weight 3 0 --weight 4 0 --weight 5 0`) : 1024 entrées sur 1024 changent d'ensemble (chaque PG a une copie sur chaque hôte) et toutes restent à 2 copies : les PG seraient `undersized+degraded` jusqu'au retour de l'hôte.

## Une image RBD en objets

```
# rbd info rbd-test/sonde
        size 1 GiB in 256 objects
        order 22 (4 MiB objects)
        block_name_prefix: rbd_data.1a2b3c4d5e6f
        features: layering, exclusive-lock, object-map, fast-diff, deep-flatten
# rados -p rbd-test ls | grep -E '^rbd_(id|header|object_map)\..*|^rbd_directory$'
rbd_directory
rbd_id.sonde
rbd_header.1a2b3c4d5e6f
rbd_object_map.1a2b3c4d5e6f
# rados -p rbd-test ls | grep -c '^rbd_data.1a2b3c4d5e6f'
19
# ceph osd map rbd-test rbd_data.1a2b3c4d5e6f.0000000000000000
… -> pg 2.4b0c93f1 (2.11) -> up ([3,8,0], p3) acting ([3,8,0], p3)
```

| Objet | Rôle |
|---|---|
| `rbd_directory` | correspondance nom ↔ identifiant de toutes les images du pool (omap) |
| `rbd_id.sonde` | identifiant interne de l'image `sonde` |
| `rbd_header.<id>` | taille, ordre, fonctionnalités, instantanés, verrou exclusif (omap) |
| `rbd_object_map.<id>` | carte des objets existants (fonctionnalité `object-map`) |
| `rbd_data.<id>.<n°>` | données, tranches de 4 Mio, numéro en hexadécimal sur 16 chiffres |

19 objets de données sur 256 possibles : seules les tranches écrites existent (métadonnées d'ext4, fichier témoin). Deux objets voisins d'une même image sont dans des PG différents : les E/S d'une image se répartissent sur tout le cluster.

## Dans l'OSD (BlueStore)

```
[root@ceph01 ~]# ceph osd ok-to-stop 7 && ceph osd set noout && ceph orch daemon stop osd.7
[ceph: root@ceph03 /]# ceph-objectstore-tool --data-path /var/lib/ceph/osd/ceph-7 --op list-pgs | wc -l
33
[ceph: root@ceph03 /]# ceph-objectstore-tool --data-path /var/lib/ceph/osd/ceph-7 --pgid 2.1e --op list analyse-placement
["2.1e",{"oid":"analyse-placement","key":"","snapid":-2,"hash":2098207294,"max":0,"pool":2,"namespace":"","max":0}]
[ceph: root@ceph03 /]# ceph-objectstore-tool --data-path /var/lib/ceph/osd/ceph-7 --pgid 2.1e '["2.1e",{"oid":"analyse-placement","key":"","snapid":-2,"hash":2098207294,"max":0,"pool":2,"namespace":"","max":0}]' get-bytes | sha256sum
9f2c…e41  -
[ceph: root@ceph01 /]# sha256sum /etc/os-release      # relevé au moment du put, dans le même conteneur
9f2c…e41  /etc/os-release
[root@ceph01 ~]# ceph orch daemon start osd.7 ; ceph -s ; ceph osd unset noout
```

- `osd.7` porte 33 PG (tous pools confondus), dont 2.1e : il est bien dans l'ensemble *acting*.
- `hash` = 2098207294 = `0x7d1c5a3e`, le hachage calculé par `ceph osd map` : le placement est cohérent de bout en bout.
- Le contenu lu directement dans BlueStore a la même empreinte que le fichier écrit : une réplique est une copie complète de l'objet.
- Seules des opérations de lecture ont été utilisées ; l'OSD a été relancé, `noout` retiré, `HEALTH_OK` constaté à 14 h 52.

## Réponses aux questions

1. **PG plutôt qu'objets** : suivre l'état, le journal et la récupération de milliards d'objets est impossible ; le PG agrège (quelques centaines par OSD), et un changement de carte ne recalcule que des PG.
2. **Pas d'annuaire** : le placement est une fonction de la carte ; le client la tient des moniteurs et calcule. Carte en retard : l'OSD contacté répond avec une carte plus récente, le client recalcule et renvoie.
3. **up / acting** : *up* = calcul CRUSH, *acting* = qui sert. Ils diffèrent avec *pg_temp* (pendant un remplissage, les anciens OSD complets continuent de servir) ou *upmap*.
4. **upmap** : exceptions ciblées par PG posées par l'équilibreur, sans modifier les poids CRUSH ni provoquer de déplacements en cascade.
5. **Objet inexistant** : `ceph osd map` ne fait qu'appliquer le calcul au nom ; il n'interroge aucun OSD.
6. **Allocation à la demande** : l'image n'est qu'un en-tête ; une tranche n'existe qu'après sa première écriture. Une écriture de 4 Kio touche un objet de données, l'unité d'allocation minimale de BlueStore (4 Kio), ses métadonnées RocksDB et, avec `object-map`, l'objet de carte.
7. **OSD arrêté** : BlueStore et RocksDB n'admettent qu'un ouvreur. Usage réel : exporter un PG d'un OSD mourant (`--op export`) pour l'importer ailleurs quand c'est la dernière copie ; précautions : `noout`, export vérifié avant toute suppression, jamais d'`export-remove` en première intention.
