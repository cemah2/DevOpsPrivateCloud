# Performances des volumes de `k8s-par1` — campagne M16-E28

| | |
|---|---|
| Date | <AAAA-MM-JJ HH:MM> |
| Banc | `plateforme/k8s/outils/banc-volumes/` (profils `profils.fio`), image `plateforme/outils-stockage:1.0.0@sha256:<…>` |
| Nœud de mesure | `k8s-w01` (4 vCPU, 8 Go) |
| Versions | Kubernetes 1.36.x, ceph-csi 3.18.x, Ceph Tentacle 20.2.4, noyau 6.12 |
| État du cluster | `ceph -s` HEALTH_OK, aucune récupération ; `ms-verif-k8s-stockage` vert ; aucune autre mesure en cours ; OpenStack <arrêté/actif> |

## Résultats (médiane de 3 répétitions ; entre crochets : écart min-max en %)

| Cible | `wal` IOPS / p99 | `oltp` IOPS lect.+écr. / p99 | `iops` IOPS / p99 | `debit` Mio/s |
|---|---|---|---|---|
| Client noyau nu (M08-E28, `cephcli01`) | | | | |
| `ceph-rbd` | | | | |
| `ceph-rbd-chiffre` | | | | |
| `cephfs` | | | | |
| `emptyDir` (disque local, `local-nvme`) | | | | |
| Longhorn (M16-E15, <mesuré/repris>) | | | | |

Processeur du nœud pendant `debit` : `ceph-rbd` <N> %, `ceph-rbd-chiffre` <N> % (dont `kcryptd` <N> %).

## Contrôle du banc

- Écart entre répétitions : <N> % au plus (seuil 15 %).
- Sans `--direct=1`, `debit` sur `ceph-rbd` monte à <N> Mio/s : le cache de pages du nœud (8 Go) sert les lectures, on mesure la mémoire, pas le volume.

## Interprétation

1. **Surcoût de Kubernetes** par rapport au client noyau nu : attendu **nul ou négligeable** (quelques %) : le chemin des données est le même (`rbdN` du noyau du nœud, msgr2 vers les OSD) ; ceph-csi n'intervient qu'au montage. Un écart notable vient d'ailleurs : autre nœud ou autre charge, limites de processeur du pod (`requests`/`limits`), système de fichiers (`ext4` dans le volume, contre un périphérique brut en M08), ou chiffrement en transit (`ms_mode=secure`) s'il n'était pas actif en M08-E28.
2. **Coût de LUKS** : se paie en **processeur du nœud** (AES-XTS, accéléré par AES-NI si le processeur virtuel l'expose : `grep -c aes /proc/cpuinfo` sur le nœud) et un peu en latence ; il est surtout visible sur `debit` et `iops` (beaucoup d'octets ou d'opérations par seconde), peu sur `wal` dominé par le réseau.
3. **`wal` est le plus lent** : chaque écriture attend l'acquittement des trois copies (nœud → OSD primaire → deux réplicas → acquittement), à profondeur 1 : aucune parallélisation ne le masque. Sa latence est une borne basse du temps de validation (`COMMIT`) d'une transaction PostgreSQL en `synchronous_commit = on` : <N> ms ici, soit au plus ~<1000/N> validations par seconde et par connexion. C'est le chiffre à donner à Julien, pas les IOPS de `iops`.
4. **`emptyDir` est plus rapide** : disque local du nœud, pas de réseau, pas de réplication. Il ne convient pas à la base : il disparaît avec le pod (expulsion, drain, panne de nœud), il partage le disque système du nœud, et sa « réplication » par PostgreSQL ne protège pas d'une perte simultanée (un drain de plusieurs nœuds, une mise à jour). Les volumes locaux persistants (`local`, TopoLVM) sont l'option à évaluer si un jour la latence prime (ADR-0160).
5. **Ce que le lab ne permet pas de conclure** : tous les OSD SSD de `ceph-par1` sont sur un seul SSD physique (`ssd-lab`), tous les nœuds sur un seul hyperviseur, le « réseau » est un pont virtuel : les chiffres absolus ne valent ni pour la production, ni pour la tenue en charge simultanée de plusieurs clients ; les comparaisons **relatives** (Kubernetes vs nu, chiffré vs clair, RBD vs CephFS) restent valables, sous réserve de mesures au même moment.

## Réserves

- Mesures faites un à un : la contention entre volumes n'est pas mesurée.
- Longhorn : chiffres de E15 (autre date, autre état du cluster) : comparaison indicative.
