# Module 08 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M08-E46 — Mini-projet : stockage MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des deux démonstrations, et la **grille de revue** avec laquelle Claire, Karim, Sophie, Nadia et Julien évaluent la livraison. Les fichiers de référence sont ceux des exercices du module ; les seuls nouveaux sont [`allocations.yaml`](fichiers/M08-E46/ceph/allocations.yaml) (état de livraison : équipes **et** identités des consommateurs), l'[extrait de `config/cluster.yaml`](fichiers/M08-E46/ceph/config-cluster-pools-extrait.yaml) (pools des consommateurs, capacité et surallocation) et le modèle de [`docs/stockage/architecture.md`](fichiers/M08-E46/medisphere/docs/stockage/architecture.md).

**Solution**

*Plan de travail recommandé* (dans cet ordre : chaque étape libère de la capacité ou de la redondance pour la suivante)

1. **État des lieux** (1 h) : `lab/bin/check 08 46`, puis les contrôles détaillés rouges (`08 24` à `08 34`) et `lab/bin/check 07 46` (MTU, bordure). Liste des restes : `ceph osd pool ls` (pools d'essai : `bench`, pools de démonstration des codes d'effacement de E15, restaurations), `rbd ls rbd-test`, `ceph auth ls` (identités d'essai de E13/E19/E39), `ceph orch host ls` (`ceph04`), `ceph health detail` (sourdines).
2. **Sauvegarde d'abord** (30 min) : un passage réussi de `wb-backup-ceph` et une restauration de test **avant** les opérations lourdes (étapes 3 et 4) ; c'est le filet si un redéploiement tourne mal.
3. **Retirer `ceph04`** (1 à 2 h, surtout de l'attente) : par la section « Retirer un nœud » de RB-081 (E18) :
   ```
   [admin@ceph01 ~]$ sudo ceph orch host drain ceph04            # vide les OSD (et les démons) de l'hôte
   [admin@ceph01 ~]$ sudo ceph orch osd rm status                # attendre la fin ; HEALTH_OK
   [admin@ceph01 ~]$ sudo ceph orch host rm ceph04
   [admin@ceph01 ~]$ sudo ceph osd crush rm ceph04               # si le seau d'hôte reste vide dans la carte
   ```
   puis la VM 2084 par OpenTofu (état `ceph`), les objets NetBox et l'enregistrement DNS par le même code. Vérifie qu'aucune spécification de `plateforme/ceph` ne cite encore `ceph04` (`hosts.yaml`, `config/cluster.yaml` : hiérarchie CRUSH), et passe `MS_CEPH_OSDS` de 12 à 9 dans la configuration de `ms-verif-ceph` (MR sur `plateforme/outils`) : sinon la sonde reste rouge, à raison.
4. **Chiffrer les OSD de `ceph01` et `ceph02`** (2 à 3 h d'attente) : procédure de E27, un OSD à la fois, `ok-to-stop`, HEALTH_OK entre deux ; vérifier `lsblk` après chaque. Ordre conseillé : les HDD en dernier (récupération plus lente).
5. **Consommateurs et équipes** (1 à 2 h) : les cinq pools dans `config/cluster.yaml` ([extrait](fichiers/M08-E46/ceph/config-cluster-pools-extrait.yaml)), créés un par un par `outils/pool-repliquee.sh <pool> rbd` sur `ceph01` (E05, fiche de changement) et réglés par `outils/config-cluster.sh --appliquer` ; [`allocations.yaml`](fichiers/M08-E46/ceph/allocations.yaml) de livraison (quatre identités de consommateurs, `client.sauvegarde`, trois équipes), `outils/ceph-allocations.sh appliquer --simuler` relu dans la MR, `appliquer`, `verifier`. Trousseaux des consommateurs en Vault (`ceph auth get client.glance | ansible-vault encrypt_string --stdin-name …`), **non distribués**. Registre des allocations à jour, avec la somme des quotas et l'écart à la capacité sûre (surallocation assumée dans le lab, écrite).
6. **Sécurité, finitions** (1 h) : sourdines restantes = seulement les contrôles « clients » de cephx, avec durée et ticket ; clé SSH de l'orchestrateur renouvelée (E27) ; tableau de bord TLS (certificats renouvelés) ; aucune identité `allow *` hors administration ; `mon_allow_pool_delete` à `false`.
7. **Réseau** (30 min) : `qm config 2081` à `2083` (`net0` et `net1` avec `mtu=9000`), `qm config 2085`, `ip link` dans les invités, `ping -M do -s 8972` dans les deux VLAN ; matrice des flux (`runner01` → VIP RGW et → nœuds pour la dérive, `cephcli01` → `pbs01`) dans `group_vars/role_routeur/pare_feu.yml` et `matrice-flux.md`.
8. **Documentation et livraison** (3 à 4 h) : `architecture.md`, politique, ADR-0080, registre des allocations, performances, runbooks RB-080 à RB-08x, inventaire NetBox exporté, registre des secrets ; MR, pipelines verts, étiquette `stockage-v1`.

*Démonstration de Nadia — arrêt d'un nœud entier* (à répéter **avant** la revue)

| Étape | Action | Attendu |
|---|---|---|
| 1 | Sur `cephcli01` : `boucles-temoins.sh start` (RBD, CephFS, S3 de MédiDoc) | lignes `ok` |
| 2 | `qm stop 2083` (`ceph03`, porte un MON, un MDS, un RGW, une instance de l'ingress) | — |
| 3 | `ceph -s` | `HEALTH_WARN` : 1 hôte et 3 OSD `down`, 1 MON hors quorum (2 sur 3), PG `undersized+degraded`, aucune reconstruction (3 hôtes, `size=3`) |
| 4 | Boucles | quelques secondes de latence (MDS de secours, VIP RGW si elle était sur `ceph03`), **aucun échec** |
| 5 | Sonde (≤ 5 min) | alerte `ms-alerte` : `quorum 2 sur 3`, `osd.N:down`, `HEALTH_WARN : …` |
| 6 | Julien dépose et relit un document S3 pendant la panne | succès |
| 7 | `qm start 2083`, attendre | OSD `up`, rattrapage des écritures manquées (*recovery* court), HEALTH_OK sans intervention |
| 8 | `boucles-temoins.sh stop ; bilan` | 0 échec, latences max commentées |

Points de discussion attendus : pourquoi pas de reconstruction (plus d'hôte disponible), ce qui se passerait avec un deuxième nœud (quorum perdu, PG sous `min_size` : tout se fige), pourquoi c'est la limite d'un cluster de 3 nœuds.

*Contenu attendu de `docs/stockage/architecture.md`*

Modèle : [`fichiers/M08-E46/medisphere/docs/stockage/architecture.md`](fichiers/M08-E46/medisphere/docs/stockage/architecture.md) — démons et réseaux, pools et règles, consommateurs, tableau « ce qui se passe quand… » (OSD, nœud, deux nœuds, MGR, MON, ingress, RGW, réseau de cluster, `pve01`), exploitation, points uniques de défaillance et module qui les traitera, ce que M09, M10 et M16 consomment.

**Explications**

Le mini-projet vérifie surtout la **cohérence** : chaque brique a été construite dans un exercice, mais la livraison exige qu'elles tiennent ensemble (sauvegarde qui découvre les volumes des équipes, sonde qui connaît le bon nombre d'OSD après le retrait de `ceph04`, identités calculées par un seul outil, politique qui décrit ce qui existe). Le contrôle global revérifie le MTU de M07 parce que c'est la dépendance réseau la plus fragile du stockage : une seule interface oubliée à 1500 produit des pannes intermittentes difficiles à diagnostiquer (M08-E42). Préparer les pools et identités d'OpenStack et de Kubernetes **maintenant**, dans le même registre que les équipes, évite qu'ils soient créés à la main sous la pression des modules 10 et 16.

**Alternatives**
- Garder `ceph04` comme quatrième nœud plutôt que le détruire : la perte d'un nœud se reconstruirait (4 hôtes pour `size=3`), au prix de 6 Gio de mémoire permanents ; écarté par le PLAN (budget du profil `infra`), à reconsidérer pour la production.
- Chiffrement côté client des volumes OpenStack (Cinder avec LUKS) plutôt que des OSD : la clé reste hors du cluster ; complémentaire, décidé au M10.
- Pools des consommateurs créés par Kolla-Ansible et Ceph-CSI eux-mêmes : possible, mais leurs droits et quotas échapperaient au registre.

**Pièges classiques**
- Redéployer les OSD avant d'avoir retiré `ceph04` (ou l'inverse sans attendre HEALTH_OK) : deux mouvements de données superposés, PG sous `min_size`.
- Oublier `ceph04` dans une spécification (placement des OSD) : cephadm tente de le recontacter, `CEPHADM_HOST_CHECK_FAILED`.
- Identités OpenStack calquées sur un tutoriel avec `allow *` ou `allow rwx pool=…`, ou sans les droits **mgr** (`profile rbd pool=…`) dont les clients RBD récents ont besoin (instantanés planifiés, statistiques).
- Sourdines `--sticky` pour obtenir HEALTH_OK.
- Dépôt de documentation avec des clés cephx ou S3 en clair (`key = AQ…`) : le contrôle global les cherche.
- Démonstration de Nadia jamais répétée : la VIP RGW n'était pas où on le croyait, la sonde n'alerte qu'au bout de 5 minutes, et Julien attend devant l'écran.

**En production chez MédiSphère**
Au moins 5 nœuds de stockage dédiés (reconstruction possible après la perte d'un nœud, codes d'effacement pour l'objet), réseau de stockage physique redondant en jumbo frames vérifié par la supervision, réplication ou sauvegarde des objets vers PAR2 (F5), rotation planifiée des clés, et recette de reprise semestrielle (arrêt d'un nœud, perte d'un disque, restauration) dont les résultats complètent `architecture.md`.

**Grille de revue (auto-évaluation si tu travailles seul)**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Contrôle global | `lab/bin/check 08 46` entièrement vert, sans contrôle ignoré |
| Claire | Rien de provisoire | `ceph04` absent (cluster, Proxmox, NetBox, DNS), pools et identités d'essai supprimés ou justifiés |
| Claire | Points uniques de défaillance | listés dans `architecture.md` avec l'impact et le module qui les traitera |
| Karim | Code | `plateforme/ceph` décrit tout (spécifications, allocations), pipeline vert, `outils/ceph-allocations.sh verifier` et `outils/config-cluster.sh --verifier` sans écart, MR relues |
| Karim | Consommateurs | 5 pools (application, règle de classe, quota), 4 identités aux droits de la documentation Ceph, trousseaux en Vault non distribués |
| Sophie | Chiffrement | msgr2 `secure`, 9 OSD chiffrés, TLS du S3 et du tableau de bord par la PKI interne |
| Sophie | Clés | démons et administration en `aes256k`, clés clientes : renouvelées ou listées avec une date ; clé SSH de l'orchestrateur renouvelée ; sourdines temporaires seulement |
| Sophie | Documents | politique de stockage, ADR-0080, registre des secrets (emplacements, jamais de valeurs), matrice des flux |
| Nadia | Panne d'un nœud | sonde qui alerte, clients sans échec, retour à HEALTH_OK sans intervention |
| Nadia | Restauration | test chronométré récent (RTO, RPO), runbooks RB-080 à RB-08x à jour |
| Julien | Stockage des équipes | espaces de noms, sous-volumes, comptes S3 utilisables en libre-service, plafonds connus |
| Tous | Présentation | 10 minutes : architecture, compromis, ce qui n'est pas redondant, ce que M09, M10 et M16 consommeront |

Une livraison est acceptée quand tous les critères sont remplis ; un critère manquant est noté comme action (responsable, échéance) dans le compte rendu de recette, jamais passé sous silence.
