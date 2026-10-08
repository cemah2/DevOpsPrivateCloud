# RB-091 — Reconstruire un nœud de `hv-par1` (perte ou remplacement)

| | |
|---|---|
| Version | 1.0 (M09-E29), section « remplacement planifié » ajoutée après M09-E34 |
| Propriétaire | Équipe Plateforme |
| Déclencheur | nœud perdu (matériel, disques) ou à remplacer ; décision de l'astreinte (perte) ou du comité de changement (remplacement) |
| Durée | 1 h 30 à 2 h dans le lab, dont 20 à 40 min d'attente de la récupération Ceph |
| Prérequis | accès à `adm01`, console de `pve01`, Vault `critique` (clé PBS, jetons), pipelines de `plateforme/infra` et `plateforme/ansible` |

Dans ce runbook, `<NŒUD>` est le nœud à reconstruire (ex. `hv03`), `<VMID>` sa VM sur `pve01` (2091-2093), `<AUTRE>` un nœud sain (ex. `hv01`). **Chaque commande destructive est précédée de son contrôle : ne saute jamais le contrôle.**

## 0. Décider

- Le nœud est-il **vraiment** perdu ? Console sur `pve01`, `qm status <VMID>`, journal. Un nœud qui redémarre en boucle n'est pas perdu : voir RB-093 et suivants (palier 4).
- Ne **jamais** retirer du cluster un nœud qui pourrait revenir tel quel : un ancien nœud qui revient après `pvecm delnode` casse le cluster (documentation, *Remove a Cluster Node*).
- Perte : prévenir (canal d'astreinte), ouvrir un incident `INC-36xx`. Remplacement : fiche de changement.

## 1. État de départ (5 min)

```
root@<AUTRE>:~# pvecm status                      # quorate, 2 votes sur 3
root@<AUTRE>:~# ha-manager status                 # ressources du nœud perdu : relancées ailleurs (fence → started)
root@<AUTRE>:~# ceph -s                           # HEALTH_WARN attendu : OSD down, PG undersized/degraded
root@<AUTRE>:~# ceph osd tree                     # identifiants des OSD de <NŒUD>
root@<AUTRE>:~# pvesh get /cluster/replication --output-format json   # tâches dont <NŒUD> est source ou cible
```

Avec `size 3` sur trois hôtes et `min_size 2`, la perte d'un hôte laisse 2 copies : les écritures continuent ; **une seconde panne** (un OSD d'un autre nœud) rendrait des PG inactifs. Priorité : retrouver trois hôtes.

Note les VMs qui n'existaient **que** sur le stockage local de `<NŒUD>` (ni HA, ni réplication) : elles se restaureront depuis PBS (§ 6).

## 2. Remplacement planifié seulement : vider le nœud **avant** (pas de coupure)

1. `ha-manager crm-command node-maintenance enable <NŒUD>` ; attendre que ses ressources HA soient ailleurs.
2. Migrer à chaud les VMs non HA restantes ; pour les VMs à disque local répliqué, migrer (réplication à jour d'abord : `pvesr run --id <ID>`).
3. Supprimer ou réorienter les tâches de réplication dont `<NŒUD>` est **source** (elles suivent la VM migrée) ; celles dont il est **cible** : supprimer (`pvesr delete <ID>`) puis recréer après la reconstruction.
4. Ceph : `ceph osd out <ID>` pour les OSD du nœud ; avec trois hôtes et `size 3`, les PG restent `undersized` (pas de troisième hôte pour recopier) : c'est attendu. Puis arrêter les OSD (`systemctl stop ceph-osd@<ID>`).
5. Continuer au § 3 (sans arrêt brutal : `qm shutdown <VMID>` sur `pve01`).

## 3. Retirer l'ancien nœud (15 min)

**Contrôle** : le nœud est arrêté et ne redémarrera pas (`qm status <VMID>` sur `pve01` : `stopped`, ou VM détruite).

Ceph (depuis `<AUTRE>`), pour chaque OSD `<ID>` de `<NŒUD>` :

```
root@<AUTRE>:~# ceph osd safe-to-destroy osd.<ID>    # attendu : NON sûr si les PG sont dégradés ; on purge
                                                      # quand même un OSD DONT LE DISQUE N'EXISTE PLUS
root@<AUTRE>:~# ceph osd purge <ID> --yes-i-really-mean-it   # carte CRUSH, clé, carte des OSD
```

Moniteur et gestionnaire :

```
root@<AUTRE>:~# ceph mon dump                         # le MON de <NŒUD> y figure-t-il encore ?
root@<AUTRE>:~# ceph mon remove <NŒUD>
root@<AUTRE>:~# ceph osd crush remove <NŒUD>          # l'hôte vide dans la carte CRUSH
```

Puis, dans `/etc/pve/ceph.conf`, retirer `<NŒUD>` de `mon_host` et la section `[mon.<NŒUD>]` s'il y en a une (le fichier est commun : une seule modification). `ceph -s` : 2 MON en quorum.

HA : les ressources ont été relancées ailleurs ; les règles qui citent `<NŒUD>` restent valides (non strictes) ; une règle **stricte** limitée à `<NŒUD>` laisse sa ressource en `error` : l'élargir.

Cluster :

```
root@<AUTRE>:~# pvecm nodes                           # nom exact
root@<AUTRE>:~# pvecm delnode <NŒUD>
root@<AUTRE>:~# pvecm status                          # 2 nœuds, Expected votes: 2
```

Restes à nettoyer (le nœud reviendra sous le même nom, avec de nouvelles clés) :

```
root@<AUTRE>:~# ls /etc/pve/nodes/                    # <NŒUD> peut y rester : déplacer son répertoire hors de /etc/pve
root@<AUTRE>:~# mv /etc/pve/nodes/<NŒUD> /root/ancien-<NŒUD>-$(date +%F)   # fichiers de VM orphelins : à examiner
root@<AUTRE>:~# ssh-keygen -f /etc/pve/priv/known_hosts -R <NŒUD>
root@<AUTRE>:~# ssh-keygen -f /etc/pve/priv/known_hosts -R <IP-MGMT-DU-NŒUD>
root@<AUTRE>:~# grep -n '<NŒUD>' /etc/pve/priv/authorized_keys     # ancienne clé root du nœud : supprimer la ligne
admin@adm01:~$ ssh-keygen -R <NŒUD>.par1.medisphere.internal          # clés d'hôte connues de adm01
```

## 4. Reconstruire la machine (20 à 30 min)

1. **Code** (`plateforme/infra`, état `hv`) : `tofu plan -replace=<ADRESSE-DE-LA-RESSOURCE-DU-NŒUD>` doit annoncer la destruction et la recréation de la **seule** VM `<VMID>` (disques neufs, même MAC si elle est fixée dans le code, même chien de garde). Appliquer par le pipeline.
2. L'ISO préparée (fichier de réponse en HTTP depuis `adm01`, M09-E03) installe Proxmox VE seul ; suivre la console sur `pve01`.
3. Contrôles : `ssh root@<NŒUD>.par1.medisphere.internal true` (clé de `adm01` posée par le fichier de réponse ; certificat d'hôte à signer par le rôle du M06) ; `pveversion` ; les cinq cartes et leurs adresses (`ip -br a`) ; MTU 9000 sur VLAN 30/31 (`ping -M do -s 8972 10.10.30.7x`).

## 5. Réintégrer (30 à 60 min)

1. **Rôles de base** (pipeline Ansible, `--limit <NŒUD>`) : `pve_noeud` (dépôts, NTP, chien de garde, SSH, cache ZFS), certificat d'hôte SSH. Le nœud n'est pas encore dans le cluster : ne pas lancer `pve_cluster` ni `pve_pare_feu`.
2. **Mise à niveau** : même version de paquets que les autres nœuds (`pveversion -v` comparé) **avant** de rejoindre.
3. **Rejoindre** :
   ```
   root@<NŒUD>:~# pvecm add <IP-MGMT-DE-AUTRE> --link0 <IP-COROSYNC-DU-NŒUD> --link1 <IP-MGMT-DU-NŒUD> --fingerprint <EMPREINTE-DE-AUTRE>
   root@<NŒUD>:~# pvecm status                           # 3 nœuds, quorate
   ```
   (empreinte : `pvenode cert info` sur `<AUTRE>`, certificat `pve-ssl.pem` ; mot de passe root de `<AUTRE>` demandé une fois.)
4. **Ceph** :
   ```
   root@<NŒUD>:~# pveceph install --repository no-subscription --version tentacle   # même version que les autres
   root@<NŒUD>:~# pveceph mon create
   root@<NŒUD>:~# pveceph mgr create
   root@<NŒUD>:~# pveceph osd create /dev/<DISQUE-OSD-1>
   root@<NŒUD>:~# pveceph osd create /dev/<DISQUE-OSD-2>
   root@<NŒUD>:~# ceph -s                                # récupération (backfill) en cours, puis HEALTH_OK
   ```
   Vérifier que `osd_memory_target` (1 Gio) s'applique aux nouveaux OSD (`ceph config get osd.<ID> osd_memory_target`).
5. **ZFS** : pool `tank` sur le disque de 32 Go (même nom que sur les autres nœuds), stockage `zfs-local` disponible sur `<NŒUD>` (`pvesm status`).
6. **Rôles de cluster** (pipeline, tous les nœuds) : `pve_cluster` (VIP keepalived, options, supervision), `pve_pare_feu` (le `host.fw` de `<NŒUD>` a disparu avec son répertoire : il est recréé ici), `hv-certificats.yml` (certificat 8006 de la PKI), SDN : `pvesh set /cluster/sdn` (application de la configuration SDN au nouveau nœud), FRR/EVPN actif.
7. **Réplication** : recréer les tâches vers `<NŒUD>` (code ou `pvesr create-local-job`) ; la première synchronisation est **complète**.
8. **HA** : `ha-manager crm-command node-maintenance disable <NŒUD>` si posé ; les ressources qui préfèrent `<NŒUD>` y reviennent (règles non strictes, `failback`).

## 6. Restaurer ce qui n'existait que sur l'ancien nœud

- **VM à disque local, sauvegardée par PBS** :
  ```
  root@<NŒUD>:~# pvesm list pbs-par2 --vmid <VMID-INVITÉ>          # dernier instantané
  root@<NŒUD>:~# qmrestore pbs-par2:backup/vm/<VMID-INVITÉ>/<DATE> <VMID-INVITÉ> --storage local-lvm --unique 0
  ```
  Le fichier de configuration de l'ancienne VM a pu rester dans `/root/ancien-<NŒUD>-…/qemu-server/` : ne pas le recopier tel quel (il désigne des disques qui n'existent plus).
- **Fichier de configuration supprimé par erreur** (sans restaurer la VM) : depuis la sauvegarde de configuration d'un nœud (`host/<nœud>`, archive `socle.pxar`, dossier `pve/etc-pve/`) :
  ```
  root@<AUTRE>:~# set -a; . /etc/wb-backup/pbs-<AUTRE>.env; set +a
  root@<AUTRE>:~# proxmox-backup-client snapshot list --ns par1/hv
  root@<AUTRE>:~# proxmox-backup-client restore --ns par1/hv host/<AUTRE>/<DATE> socle.pxar /root/restau-config \
                    --keyfile /etc/wb-backup/pbs-<AUTRE>.key
  root@<AUTRE>:~# cp /root/restau-config/pve/etc-pve/nodes/<NŒUD-DE-LA-VM>/qemu-server/<VMID>.conf \
                    /etc/pve/nodes/<NŒUD-DE-LA-VM>/qemu-server/        # puis : qm config <VMID>
  root@<AUTRE>:~# rm -rf /root/restau-config
  ```
  Vérifier que les disques désignés par le fichier existent (`pvesm list`) avant de démarrer.

## 7. Vérifier et clore

```
admin@adm01:~$ ms-verif-cluster                  # tout au vert
admin@adm01:~$ lab/bin/check 09 29               # (exercice) ou 09 34
root@<AUTRE>:~# ceph osd tree                     # 6 OSD up/in, aucun OSD « DNE » ou orphelin
root@<AUTRE>:~# ha-manager status                 # aucune ressource en error
root@<AUTRE>:~# pvesr status                      # dernières synchronisations OK
```

Compte rendu horodaté dans `docs/virtualisation/tests/reprise-hv-par1.md` ; incident ou changement clos.

## 8. Perte totale du cluster (les trois nœuds)

Ce que la sauvegarde de configuration **permet** : retrouver `config.db` (toute la configuration de `/etc/pve` : invités, stockages, HA, pare-feu, utilisateurs, secrets de `priv/`) et les fichiers propres à chaque nœud ; la documentation (*pmxcfs — Recovery*) décrit la remise en place d'un `config.db` sur un nœud réinstallé (service `pve-cluster` arrêté, copie de la base, redémarrage).

Ce qu'elle ne permet **pas** : récupérer les **disques** des VMs (Ceph hyperconvergé perdu avec les nœuds : seules les sauvegardes PBS des VMs les rendent) ; reformer Corosync avec les anciennes clés sur des machines neuves sans précaution ; recréer Ceph à l'identique (nouveau `fsid`).

Démarche : reconstruire un cluster neuf depuis le code (mini-projet M09-E46), restaurer les VMs depuis PBS, et ne puiser dans `config.db` restauré que ce que le code ne décrit pas (fichiers d'invités, notes, droits ajoutés à la main — chacun étant un écart à corriger dans le code).
