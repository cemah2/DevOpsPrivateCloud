# Stockage externe : le cluster `hv-par1` consomme `ceph-par1` (RBD)

> PLAT-1022 (M09-E12). Raccordement testé puis **retiré** : `hv-par1` utilise son Ceph hyperconvergé (`ceph-vm`) ; ce document sert de procédure le jour où un cluster Proxmox doit consommer `ceph-par1` (ou un autre Ceph externe).

## Principe

| Élément | Valeur |
|---|---|
| Cluster Ceph | `ceph-par1` (cephadm, Tentacle 20.2), moniteurs 10.10.30.51, .52, .53 (VLAN 30, MTU 9000) |
| Pool | un pool **par client** (`hv-par1`), application `rbd` |
| Identité | `client.<pool>` : `mon 'profile rbd'`, `osd 'profile rbd pool=<pool>'`, `mgr 'profile rbd pool=<pool>'` |
| Stockage Proxmox | type `rbd`, `monhost` = les trois moniteurs, `pool`, `username` (sans `client.`), contenu `images`, `krbd 0` (QEMU parle RBD directement) |
| Clé côté Proxmox | `/etc/pve/priv/ceph/<STOCKAGE>.keyring` (pmxcfs, `root` seul, répliqué sur les nœuds du cluster) |
| Clé de référence | Ansible Vault `critique` (`vault_ceph_<pool>_cle`), registre des secrets |
| Flux | aucun : les nœuds Proxmox ont une patte sur le VLAN 30 |

`profile rbd` donne exactement ce qu'il faut à un client RBD : lire la carte des moniteurs et les profils, créer/lire/écrire/supprimer des images **dans le pool désigné**, et pour `mgr` les opérations RBD déléguées au gestionnaire (tâches de fond, statistiques par image). Il n'autorise ni la création de pool, ni l'accès aux autres pools, ni l'administration du cluster. `client.admin` permettrait tout cela à quiconque obtient `root` sur **un seul** nœud Proxmox.

## Raccordement

1. Côté Ceph (sur `ceph01`) :
   ```
   [root@ceph01 ~]# cephadm shell -- ceph osd pool create hv-par1
   [root@ceph01 ~]# cephadm shell -- ceph osd pool application enable hv-par1 rbd
   [root@ceph01 ~]# cephadm shell -- rbd pool init hv-par1
   [root@ceph01 ~]# cephadm shell -- ceph auth get-or-create client.hv-par1 \
                      mon 'profile rbd' osd 'profile rbd pool=hv-par1' mgr 'profile rbd pool=hv-par1' >/dev/null
   [root@ceph01 ~]# cephadm shell -- ceph auth get client.hv-par1 | grep -v key   # contrôle des capacités
   ```
2. Transport du trousseau, de `ceph01` à `hv01`, **sans disque intermédiaire** (le flux passe par `adm01` en mémoire seulement) :
   ```
   admin@adm01:~$ ssh ceph01 'sudo cephadm shell -- ceph auth get client.hv-par1 2>/dev/null' \
                    | ssh root@hv01 'umask 077; cat > /root/hv-par1.keyring'
   admin@adm01:~$ ssh root@hv01 'grep -c "^\[client.hv-par1\]" /root/hv-par1.keyring'   # 1 attendu
   ```
   Copie de référence dans Vault, par le même chemin :
   ```
   admin@adm01:~/src/ansible$ ssh ceph01 'sudo cephadm shell -- ceph auth print-key client.hv-par1 2>/dev/null' \
       | uv run ansible-vault encrypt_string --encrypt-vault-id critique --stdin-name vault_ceph_hv_par1_cle \
       >> inventories/lab/group_vars/hv_par1/vault-critique.yml
   ```
3. Stockage (une fois, sur n'importe quel nœud ; `storage.cfg` est commun au cluster) :
   ```
   root@hv01:~# pvesm add rbd ceph-par1-rbd --monhost "10.10.30.51 10.10.30.52 10.10.30.53" \
                  --pool hv-par1 --username hv-par1 --content images --krbd 0 \
                  --keyring /root/hv-par1.keyring
   root@hv01:~# shred -u /root/hv-par1.keyring
   root@hv01:~# ls -l /etc/pve/priv/ceph/ceph-par1-rbd.keyring
   root@hv01:~# pvesm status --storage ceph-par1-rbd
   ```
4. Contrôle des limites (depuis un nœud, avec l'identité restreinte) :
   ```
   root@hv01:~# R="-c /dev/null -m 10.10.30.51 --id hv-par1 --keyring /etc/pve/priv/ceph/ceph-par1-rbd.keyring"
   root@hv01:~# rbd $R ls hv-par1                        # OK (vide ou images vm-…)
   root@hv01:~# rbd $R ls volumes                        # refus : « (1) Operation not permitted »
   root@hv01:~# ceph $R osd pool create essai            # refus : « Error EACCES: access denied »
   ```
   `-c /dev/null` : le nœud a son propre `ceph.conf` (celui du Ceph hyperconvergé, autre `fsid`) ; on ne veut aucune de ses valeurs. Le nom du pool du module 08 est à adapter ; les libellés d’erreur exacts dépendent de la version du client.

## Comportement observé (M09-E12, étape 6)

- Arrêt d'**un** nœud de `ceph-par1` : la VM continue sans interruption visible ; quelques secondes de latence au plus sur les écritures en cours le temps que les PG concernés changent d'OSD primaire ; `ceph -s` côté `ceph-par1` passe en `HEALTH_WARN` (PG dégradés), les écritures restent possibles (`min_size` 2 atteint).
- Arrêt des **trois** nœuds : les entrées/sorties de la VM se **figent** (pas d'erreur : QEMU attend) ; la VM semble gelée, la HA ne voit rien (le processus QEMU tourne). Au retour de Ceph, elle reprend. Au-delà des délais du noyau invité (souvent 120 s pour une tâche bloquée, 180 s pour le SCSI), l'invité peut remonter des erreurs d'E/S et passer son système de fichiers en lecture seule.

## Retrait

Dans cet ordre (l'inverse du raccordement) :

1. Aucune image sur le stockage : déplacer les disques (`qm disk move <VMID> <disque> ceph-vm --delete 1`), puis `pvesm list ceph-par1-rbd` vide.
2. `pvesm remove ceph-par1-rbd` ; vérifier que `/etc/pve/priv/ceph/ceph-par1-rbd.keyring` a disparu (sinon `rm`), et qu'aucun `hv-par1.keyring` ne traîne dans `/root` des nœuds.
3. Côté Ceph :
   ```
   [root@ceph01 ~]# cephadm shell -- ceph auth rm client.hv-par1
   [root@ceph01 ~]# cephadm shell -- ceph config set mon mon_allow_pool_delete true
   [root@ceph01 ~]# cephadm shell -- ceph osd pool rm hv-par1 hv-par1 --yes-i-really-really-mean-it
   [root@ceph01 ~]# cephadm shell -- ceph config set mon mon_allow_pool_delete false
   [root@ceph01 ~]# cephadm shell -- ceph config get mon mon_allow_pool_delete     # false
   ```
4. Vault : retirer `vault_ceph_hv_par1_cle` ; registre des secrets : ligne marquée « révoqué le <date> ».
5. Arrêter `ceph01-03` si elles ne servent pas (budget mémoire du profil `infra`).

## Pourquoi on ne garde pas ce raccordement pour `hv-par1`

- Deux clusters Ceph à surveiller pour un seul cluster de virtualisation, et une dépendance entre deux plateformes qui n'ont pas les mêmes fenêtres de maintenance.
- Un cluster HA dont le stockage peut disparaître sans que la HA le voie (VMs figées, pas arrêtées) : il faudrait une supervision commune et des alertes sur la latence RBD.
- `ceph-par1` est dimensionné pour OpenStack (M10) et Kubernetes (M16) : le partager ajoute un locataire de plus sans nécessité.
Le raccordement reste la bonne réponse pour un cluster Proxmox **sans** disques locaux (nœuds de calcul) ou pour une migration de données entre plateformes.
