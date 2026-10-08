# Capacité et quotas du cloud OpenStack PAR1

> M10-E13 (PLAT-1123), mis à jour en M10-E16 (répartiteurs) et M10-E20 (réserve des calculs). Les valeurs exactes de ta mesure remplacent celles de ce modèle.

## 1. Capacité mesurée (Placement)

| Calcul | VCPU (total × ratio) | MEMORY_MB (total − réservé) × ratio | DISK_GB |
|---|---|---|---|
| `oscmp01` | 4 × 4.0 = 16 | (7 960 − 512) × 1.0 ≈ 7 450 | capacité du pool `vms`, annoncée par chaque calcul |
| `oscmp02` | 4 × 4.0 = 16 | (7 960 − 512) × 1.0 ≈ 7 450 | idem (comptée deux fois : ne pas l'additionner) |

Mesure réelle sur un calcul (`free -m` avec seulement les conteneurs de Kolla) : ≈ 1 300 Mio utilisés par le système et les conteneurs (`nova_compute`, `nova_libvirt`, `ovn_controller`, `neutron_ovn_metadata_agent`, `openvswitch_*`, `fluentd`, `cron`, `kolla_toolbox`). La réserve par défaut (512 Mio) est trop faible : passée à 2 048 Mio en M10-E20, soit ≈ 5 900 Mio utilisables par calcul, **≈ 11 800 Mio au total**.

Disque : les disques des instances et les volumes sont sur Ceph ; la limite réelle est la capacité du pool (`ceph df`), pas `DISK_GB`. Les quotas de Go de volumes sont dimensionnés sur l'espace **net** de `ceph-par1` (réplication 3).

## 2. Quotas

| Ressource | `plateforme` | `mediagenda-dev` | `mediagenda-prod` | Justification |
|---|---|---|---|---|
| Instances | 4 | 4 | 4 | prod : 2 applicatifs + 1 base + 1 bastion ; dev : idem, en plus petit |
| vCPU | 4 | 5 | 8 | prod prioritaire ; somme 17 ≤ 32 vCPU allouables (surallocation 4:1) |
| Mémoire (Mio) | 2 048 | 3 072 | 6 144 | somme 11 264 ≤ 11 800 utilisables ; prod ≥ dev (Claire) |
| Volumes | 10 | 10 | 10 | |
| Go de volumes | 100 | 100 | 200 | base de prod (40) + instantanés et marge |
| Instantanés | 10 | 10 | 20 | un avant chaque migration de schéma |
| Sauvegardes / Go | 10 / 100 | 10 / 100 | 20 / 400 | rétention 7 jours en prod |
| IP flottantes | 2 | 3 | 3 | 1 répartiteur + 1 bastion (+1 essai en dev) |
| Réseaux / sous-réseaux / routeurs | 2 / 2 / 1 | 2 / 2 / 1 | 2 / 2 / 1 | un réseau applicatif (+1 pour essais) |
| Groupes de sécurité / règles | 10 / 100 | 10 / 100 | 10 / 100 | |
| Ports | 30 | 30 | 30 | instances + répartiteur + DHCP/métadonnées |
| Répartiteurs (Octavia) | 1 | 2 | 2 | posé en M10-E16 |

Somme des mémoires : 11 264 Mio. Le reste (≈ 500 Mio) est la marge de l'ordonnanceur. Toute hausse passe par une MR sur ce document **et** sur `envs/openstack-projets` (M10-E15).

## 3. Qui peut faire quoi

| Qui | `plateforme` | `mediagenda-dev` | `mediagenda-prod` |
|---|---|---|---|
| Compte `admin` (domaine `Default`, cloud `medisphere-admin`) | administration du cloud : quotas, gabarits, réseau externe, projets | idem | idem |
| `equipe-plateforme` | `member` (essais, outillage) | `reader` | `reader` |
| `equipe-mediagenda` | — | `member` (tout dans le projet) | `reader` (lecture ; déploiements par la CI) |
| CI de MédiAgenda (application credential d'un compte de service de `Default`) | — | `member` | `member` |
| `equipe-securite` (M10-E23) | `reader` hérité du domaine | `reader` hérité | `reader` hérité |
| `equipe-support` (M10-E23) | — | `support` | `support` |

**Règle** : `admin` n'est **jamais** donné sur un projet d'équipe. Dans les politiques de Nova (`context_is_admin: role:admin`) comme de la plupart des services, le rôle `admin` ne regarde pas le projet : un `admin` de `mediagenda-dev` est administrateur de tout le cloud (démontré avec `essai-admin`, supprimé ensuite).
