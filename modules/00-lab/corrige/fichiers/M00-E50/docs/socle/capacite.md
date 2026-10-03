# Plan de capacité — socle v0

> Exemple de corrigé M00-E50. Les valeurs **mesurées** sont des exemples plausibles : remplace-les
> par tes mesures (commande indiquée pour chacune) et date-les. Les profils viennent de PLAN §3.3.

Mesures du AAAA-MM-JJ.

## 1. Mémoire de `pve01`

| Poste | Valeur | Source |
|---|---|---|
| RAM physique | 128 Gio | `free -g` |
| Hôte (PVE, pmxcfs, pveproxy, services) hors VMs | 3,5 Gio | `free -m` avec les VMs arrêtées, ou somme hors processus `kvm` |
| Cache ZFS (ARC) maximal | 12,8 Gio (si ZFS ; 0 sinon) | `cat /sys/module/zfs/parameters/zfs_arc_max`, `arc_summary` |
| VMs personnelles préexistantes | <X> Gio | `qm list` hors pool `lab` (M00-E03) |
| Marge de sécurité (≈ 5 %) | 6,4 Gio | choix d'exploitation |
| **Disponible pour le lab** | **≈ 105 Gio − <X>** | 128 − 3,5 − 12,8 − 6,4 − <X> |

## 2. Consommation actuelle du socle v0

| VM | Configurée | Utilisée (mesure) | Ballooning (min) | Source |
|---|---|---|---|---|
| `gw01` 1000 | 2 Gio | 0,4 Gio | 1 Gio | `pvesh get /nodes/pve01/qemu/1000/status/current` (`mem`, `maxmem`) |
| `adm01` 1001 | 2 Gio | 0,9 Gio | 1 Gio | idem |
| `dns01` 1002 | 1 Gio | 0,2 Gio | — | idem |
| **Total** | **5 Gio** | **1,5 Gio** | | |

## 3. Projection : socle complet + profils

Socle complet (PLAN §3.3 et §4.5) : `gw01` 2, `adm01` 2, `dns01` 1, `ca01` 1, `git01` 8 (GitLab),
`nbx01` 4, `s3-01` 4 → 22 Gio configurés, **24 Gio** avec marge de croissance.

| Profil actif | Profil (PLAN) | Socle | Total | Disponible (≈ 105) | Marge | Verdict |
|---|---|---|---|---|---|---|
| aucun | 0 | 24 | 24 | 105 | 81 | confortable |
| `infra` (Proxmox imbriqué + Ceph) | 40 | 24 | 64 | 105 | 41 | confortable |
| `k8s` | 36 | 24 | 60 | 105 | 45 | confortable |
| `openstack` | 48 | 24 | 72 | 105 | 33 | correct |
| `plateforme` (finaux) | 80 | 24 | **104** | 105 | **≈ 1** | **limite** |
| `infra` + `k8s` (interdit) | 76 | 24 | 100 | 105 | 5 | refusé par la règle |

## 4. Mécanismes de récupération

| Mécanisme | Gain estimé | Coût / risque | Usage retenu |
|---|---|---|---|
| Ballooning | jusqu'à la différence configurée − minimum des VMs qui l'activent | inefficace si les VMs utilisent leur mémoire ; latence | activé sur les VMs non critiques (sandbox, nœuds de profils) ; pas sur `gw01`, `dns01` |
| KSM | 10 à 25 % sur des VMs Debian identiques (à mesurer : `/sys/kernel/mm/ksm/pages_sharing`) | CPU ; canal auxiliaire théorique entre VMs | actif (défaut), seuil par défaut |
| Réduction de l'ARC ZFS | jusqu'à 8 Gio | lectures plus lentes sur ZFS | `zfs_arc_max` abaissé pendant le profil `plateforme` uniquement |
| Swap de l'hôte | — | effondrement des performances | dernier recours, surveillé |

## 5. Règles d'exploitation qui en découlent

1. Un seul profil lourd actif à la fois en plus du socle (PLAN §3.3) ; vérification avant tout lancement : `pvesh get /nodes/pve01/status` (mémoire utilisée) + somme des mémoires configurées des VMs démarrées.
2. Profil `plateforme` : aucune VM sandbox ni VM personnelle démarrée en parallèle ; ARC abaissé ; ballooning activé sur les nœuds Kubernetes ; alerte mémoire hôte à 90 %.
3. Les VMs du socle ne sont jamais ballonnées sous leur minimum ; `gw01` et `dns01` sans ballooning.
4. Revue de ce plan à chaque nouveau profil ou nouvelle VM permanente (mise à jour de PLAN §4.5).

## 6. `hp01` / `pbs01` (16 Gio)

| Poste | Valeur | Source |
|---|---|---|
| RAM physique | 16 Gio | `free -g` |
| PBS (proxy, démon, tâches de vérification et GC) | 1 à 2 Gio, pics pendant *verify* | `free -m` pendant une tâche |
| Cache de pages (lecture des morceaux) | variable, récupérable | |
| Futur QDevice (module 09) | < 0,1 Gio | |
| Futur « petit site de repli » (F5) | 8 à 10 Gio max pour des VMs restaurées | à arbitrer : PBS bare-metal ne fait pas tourner de VMs ; il faudra un hyperviseur |

## 7. Disque du datastore `ds-lab`

| Donnée | Valeur | Source |
|---|---|---|
| Capacité du datastore | 1,8 Tio | `proxmox-backup-manager datastore list`, interface PBS |
| Occupé aujourd'hui | 9 Gio | interface PBS (*Usage*) |
| Facteur de déduplication | 6,5 | interface PBS (*Deduplication Factor*) |
| Taux de changement quotidien estimé | 2 % des données utilisées | écart entre deux sauvegardes successives |
| Rétention | 7 quotidiennes, 4 hebdomadaires, 6 mensuelles (M00-E22) | prune job |

Projection socle complet (≈ 120 Gio de données utiles, dont `git01` et `s3-01`) : ≈ 120 + 17 instantanés × 2,4 Gio de
changements ≈ 160 Gio, plus la configuration de `pve01`. Les profils lourds sont **recréés par IaC** et ne sont
pas sauvegardés (décision à confirmer dans un ADR). Seuil d'alerte : 70 % d'occupation ; le GC libère l'espace avec
24 h de décalage (voir M00-E49, question 12).
