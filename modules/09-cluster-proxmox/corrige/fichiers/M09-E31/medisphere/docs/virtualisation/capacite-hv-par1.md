# Capacité du cluster `hv-par1` (DEV-1057)

> Modèle (corrigé M09-E31). Mesures **indicatives** relevées sur le lab ; remplace-les par les tiennes. Mise à jour à chaque changement de matériel, de version de Ceph, ou à chaque revue mensuelle.

## 1. Mesures (par nœud, 12 Gio = 12 288 Mio)

| Poste | Mesure | Commande | Retenu (réserve) |
|---|---|---|---|
| Proxmox VE (pmxcfs, pveproxy, pvedaemon, pvestatd, HA, Corosync, FRR, keepalived) | ~1 150 Mio | `ps -eo rss,comm --sort=-rss \| head`, `systemd-cgtop` | 1 536 Mio |
| Ceph : 2 OSD | ~1 900 Mio (`osd_memory_target` 1 Gio : cible, pas plafond) | `ceph tell osd.N heap stats`, RSS des `ceph-osd` | |
| Ceph : MON + MGR | ~750 Mio | RSS de `ceph-mon`, `ceph-mgr` | 3 072 Mio pour Ceph |
| Cache ZFS (ARC) | `c_max` 1 024 Mio (plafond posé par `pve_noeud` depuis E03), `size` ~870 Mio après réplications | `arc_summary`, `/proc/spl/kstat/zfs/arcstats`, `zfs_arc_max` | **1 024 Mio** |
| Marge (pointes, cache de pages de l'hôte, récupération Ceph) | — | — | 10 % du reste |

Constat : sur une installation **ext4 + LVM-thin**, l'installateur de Proxmox VE ne limite pas l'ARC (il ne le fait que pour une installation sur ZFS) : sans le plafond posé par `pve_noeud` (E03), la valeur par défaut d'OpenZFS laisserait le cache prendre une large part de la RAM. L'ARC rend de la mémoire sous pression, mais **pas assez vite** pour une VM qui démarre (échec de démarrage, OOM). Le plafond de 1 Gio est confirmé (le pool `tank` ne sert qu'aux VMs répliquées) et contrôlé par `pve_noeud` (`memoire.yml`).

## 2. Calcul N+1

- Capacité d'un nœud : (12 288 − 1 536 − 3 072 − 1 024) × 0,9 = **5 990 Mio**.
- Trois nœuds : 17 970 Mio. On doit survivre à la perte d'un nœud : capacité N+1 = 17 970 − 5 990 = **11 980 Mio** (≈ 11,7 Gio).
- « Le cluster a 36 Go » : faux à double titre (réserves de l'hôte, de Ceph et de ZFS : 16,5 Gio ; réserve N+1 : 5,9 Gio).
- Engagé aujourd'hui (`ms-capacite-cluster`) : ~5 Gio (VMs de production et de test du module).

## 3. Politique de surallocation

| Classe | Mémoire | Processeur | Pourquoi |
|---|---|---|---|
| Production (pool `prod`), VMs HA, bases de données | **aucune** : comptée en entier, ballon désactivé ou plancher = mémoire | ≤ 2 vCPU par cœur physique | une VM relancée par la HA après une panne doit trouver sa mémoire ; une base qui perd son cache s'effondre |
| Recette (pool `recette`) | ballon avec plancher à 50 % ; comptée à son plancher | ≤ 4 vCPU par cœur | charge intermittente ; dégradation acceptable |
| KSM | actif (`ksmtuned`) sur tous les nœuds | — | gain réel sur des VMs identiques (mêmes images) ; ne compte pas dans la capacité (gain non garanti, et KSM a un coût CPU) |

Démonstration (VMs 123-126, 2 Gio, plancher 1 Gio, sur `hv02`) : en remplissant la mémoire de `hv02`, le ballon commence à reprendre de la mémoire aux invités quand l'occupation de l'hôte dépasse le seuil de `pvestatd` (≈ 80 %) ; l'invité voit sa mémoire totale **baisser** (`free -m`), sans erreur, jusqu'au plancher. KSM : `pages_sharing` monte de quelques centaines de Mio après quelques minutes. Au-delà du plancher, plus rien ne se rend : l'hôte échange (*swap*) ou l'OOM tue un processus. **Le ballon déplace la capacité dans le temps, il n'en crée pas.**

## 4. Règle d'acceptation d'une demande

Une demande de VMs est acceptée si `ms-capacite-cluster --demande <N>x<Mio>` répond `OUI` (mémoire engagée + demande ≤ capacité N+1, en comptant les VMs de recette à leur plancher de ballon). Sinon : refus motivé, et proposition alternative. La sonde (E25) signale tout dépassement déjà présent (revue mensuelle : rapport sans `--demande`).

## 5. Réponse à Julien

> Non, 20 VMs de 2 Go ne tiennent pas sur `hv-par1`. Sur 36 Go, environ 16,5 servent au fonctionnement du cluster (Proxmox, Ceph, cache disque), et on garde de quoi encaisser la perte d'un serveur : il reste environ 11,7 Go pour **toutes** les VMs, dont 5 déjà engagés. Avec un plancher de ballon à 1 Go, je peux te donner **6** VMs de 2 Go aujourd'hui (comptées 1 Go chacune), utilisables tant que le cluster n'est pas sous pression.
> Pour 20 VMs éphémères, la bonne plateforme est OpenStack (ADR-0090) : quotas par projet, libre-service, sur `ceph-par1`. En attendant le module 10 : 6 VMs ici, ou une douzaine de VMs de 512 Mo (comptées en entier).
