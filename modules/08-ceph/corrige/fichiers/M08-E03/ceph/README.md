# plateforme/ceph — le cluster ceph-par1 décrit par le code

Projet créé en M08-E03. Il contient ce qui décrit le cluster **dans Ceph** (spécifications de
cephadm, configuration d'amorçage) ; les VMs sont dans `plateforme/infra` (`envs/ceph`), la
préparation des hôtes dans `plateforme/ansible` (rôle `ceph_noeud`).

| Chemin | Contenu | Exercice |
|---|---|---|
| `bootstrap/initial-ceph.conf` | options posées dès l'amorçage | M08-E03 |
| `bootstrap/amorcer.sh` | contrôles et commande d'amorçage (une seule fois, sur `ceph01`) | M08-E03 |
| `specs/hosts.yaml`, `mon.yaml`, `mgr.yaml` | hôtes, moniteurs, gestionnaires | M08-E03 |
| `specs/osd.yaml` | OSD par classe de disque | M08-E04 |
| `outils/` | scripts d'exploitation (pools…) | M08-E05 et suivants |

Appliquer une spécification (depuis un nœud `_admin`) : `ceph orch apply -i specs/<fichier> --dry-run`,
lire, puis sans `--dry-run`. Ce qui est dans `main` doit être ce qui tourne : `ceph orch ls --export`
doit redonner les mêmes services.

Version de Ceph : **20.2.3** (image `quay.io/ceph/ceph:v20.2.3`), montée en 20.2.4 en M08-E26.
