# RB-353 — `hp01` : hyperviseur de PAR2 à côté de PBS

| | |
|---|---|
| Changement | CHG-3503 (`docs/changements/fiches/CHG-3503-hyperviseur-par2.md`) |
| Portée | `hp01` (nœud `pbs01`) : Proxmox VE 9.2 ajouté à PBS 4.2 ; stockage `par2-vms`, pool `par2`, `vmbr2`, table `inet par2`, `wg1` ; amorçage de `envs/par2` |
| Durée de référence | go/no-go 30 min ; sauvegarde 10 min ; installation 30 min ; contrôles 30 min ; réseau et VMs 2 h |
| Interdits | toucher `ds-lab`, `/etc/proxmox-backup`, `vmbr0`, `vmbr1`, `wg0` ; installer pendant une fenêtre de sauvegarde ; redémarrer `hp01` sans accès de secours vérifié |

> ⚠️ **Attention** : `hp01` porte **toutes les sauvegardes du lab**. Chaque section se termine par un contrôle ; un contrôle rouge = on s'arrête et on applique le retour arrière de la section.

## 0. Accès de secours (avant tout)

- Console de l'iLO (M11, `~/.config/workbook/ilo-hp01.env`) : ouverte, invite de connexion visible.
- SSH `root@<IP-HP01-LAN>` depuis le LAN maison : fonctionne **sans** passer par `wg0`.
- Mot de passe `root@pam` de `hp01` : connu de deux personnes (enveloppe).

## 1. Go/no-go

```
root@pbs01:~# cat > /etc/apt/sources.list.d/pve-install-repo.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
root@pbs01:~# apt-get update
root@pbs01:~# /root/f5/go-no-go-hp01.sh          # copie de plateforme/infra outils/par2/go-no-go-hp01.sh
```

Critères de **go** (tous) : services de PBS actifs ; `ds-lab` présent ; aucune tâche en cours, aucune en échec depuis 24 h ; ≥ 12 Gio de mémoire disponible ; ≥ 150 Gio libres sur le système de fichiers de `ds-lab` ; Debian 13 et noyau `-pve` ; `pbs01` résolu vers 10.20.10.10 ; port 8006 libre ; sauvegarde de configuration du jour (§2) ; **simulation APT** : aucun paquet retiré, aucun `proxmox-backup*` touché, aucun noyau Debian installé. Plus, hors script : la dernière tâche de vérification (*verify*) de `ds-lab` est verte, et une restauration d'essai d'un fichier depuis un instantané récent a réussi (interface de PBS, « File Restore »).

La sortie du script et la simulation (`/root/f5/simulation-apt-*.txt`) sont jointes à CHG-3503. **No-go** : on retire le fichier `.sources` (`rm /etc/apt/sources.list.d/pve-install-repo.sources && apt-get update`) et on note la raison.

`/etc/hosts` doit contenir, avant l'installation, la ligne `10.20.10.10 pbs01.par2.medisphere.internal pbs01` (et plus aucune ligne qui associe `pbs01` à une adresse du LAN ou à `127.0.1.1`) : Proxmox VE (pmxcfs) refuse un nom d'hôte résolu vers une adresse locale.

## 2. Sauvegarde de la configuration de PBS

```
root@pbs01:~# /root/f5/sauvegarder-config-pbs.sh
archive : /root/f5/pbs-config-20261110.tar.gz (180K)
admin@adm01:~$ install -d -m 700 ~/f5 && scp root@pbs01:/root/f5/pbs-config-20261110.tar.gz* ~/f5/
admin@adm01:~$ cd ~/f5 && sha256sum -c pbs-config-20261110.tar.gz.sha256
```

L'archive contient des clés privées (WireGuard, TLS de PBS) : `~/f5` en 700, fichiers en 600, **pas** de copie dans Git ; une copie chiffrée (`age` vers la clé publique de restauration du M25) part dans l'enveloppe à la prochaine vérification.

## 3. Installation de Proxmox VE

Fenêtre : hors des tâches de sauvegarde (après la vérification du matin, avant 20 h).

```
root@pbs01:~# apt-get install proxmox-ve postfix open-iscsi chrony
```

- `postfix` : choisir « Local only » (pas de relais).
- Le paquet `proxmox-ve` ajoute `/etc/apt/sources.list.d/pve-enterprise.sources` : le désactiver (`Enabled: no`) sans abonnement.
- Le noyau ne change pas de famille (`proxmox-kernel`) : **pas de redémarrage** nécessaire ; si APT installe une version de noyau plus récente, le redémarrage attend une fenêtre annoncée, avec l'iLO ouvert (le noyau 7.0 peut renommer les interfaces : relire `/etc/network/interfaces` avant).

Contrôles d'après (tous verts, sinon §8) :

```
root@pbs01:~# pveversion
pve-manager/9.2.x/… (running kernel: 7.0.x-pve)
root@pbs01:~# systemctl is-active proxmox-backup-proxy proxmox-backup pveproxy pvedaemon pve-cluster
root@pbs01:~# proxmox-backup-manager datastore list
root@pbs01:~# ss -tlnp | grep -E ':(8006|8007) '
```

Puis : interface PBS (`https://10.20.10.10:8007`) et PVE (`https://10.20.10.10:8006`) ouvertes depuis `adm01` ; **la sauvegarde nocturne suivante** se termine (contrôle du lendemain, noté dans CHG-3503) ; `lab/bin/check F5 3` (partie PBS).

## 4. Stockage, pool, compte d'automatisation, image dorée

1. **Stockage `par2-vms` plafonné** : si le disque de `hp01` est en ZFS, jeu `rpool/par2-vms` avec `quota` et `refquota` (rôle `hote_par2`) ; sinon, volume logique séparé (`lvcreate` sur l'espace libre du groupe, `mkfs.ext4`, montage dans `/etc/fstab`) **préparé à la main** et décrit ici avec sa taille. Jamais un simple dossier sur le système de fichiers de `ds-lab`.
2. **Rôle `hote_par2`** (plateforme/ansible) : stockage, pool `par2`, `vmbr2`, `inet par2`, `wg1`, chrony.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site-par2.yml --limit pbs01 --diff
   ```
3. **Compte OpenTofu** : `outils/par2/compte-tofu-par2.sh <VMID-TEMPLATE>` (après l'étape 4) ; secret dans Ansible Vault « critique » (`vault_pve_par2_jeton`) et `~/.config/workbook/pve-par2.env` (600) sur `adm01` puis `adm02`.
4. **Image dorée** (pas d'image sur `hp01`) : sauvegarde du template `current` de `pve01` dans PBS, espace de noms `par1/images` (stockage `pbs-par2-images` de `pve01`, créé comme `pbs-par2-identite` au M24), puis restauration sur `hp01` :
   ```
   root@pve01:~# vzdump <VMID-TEMPLATE> --storage pbs-par2-images --mode stop
   root@pbs01:~# pvesm add pbs pbs-local --server 10.20.10.10 --datastore ds-lab --namespace par1/images \
       --username wb-restauration@pbs --fingerprint <EMPREINTE-PBS> --password <MOT-DE-PASSE> \
       --encryption-key <FICHIER-CLE-PBS> --content backup
   root@pbs01:~# qmrestore pbs-local:backup/vm/<VMID-TEMPLATE>/<DATE> <VMID-TEMPLATE> --storage par2-vms
   root@pbs01:~# qm set <VMID-TEMPLATE> --tags 'current;debian13;gold' && qm template <VMID-TEMPLATE>
   ```
   `wb-restauration@pbs` : utilisateur PBS en lecture seule (`DatastoreReader`) sur `/datastore/ds-lab/par1`. Le stockage `pbs-local` ne porte **aucune** tâche de sauvegarde (contenu `backup` en lecture pour les restaurations : image dorée, `kms01` en S05).

## 5. Amorçage de `envs/par2`

```
admin@adm01:~/src/infra/envs/par2$ cp amorcage/backend-local.tf.exemple backend_override.tf
admin@adm01:~/src/infra/envs/par2$ set -a; . ~/.config/workbook/pve-par2.env; set +a
admin@adm01:~/src/infra/envs/par2$ tofu init -reconfigure
admin@adm01:~/src/infra/envs/par2$ tofu apply -var 'absentes=["reg02","k8s-par2-n01","bao-par2"]'
admin@adm01:~/src/infra$ tofu -chdir=socle apply          # noms de PAR2 (socle/dns-par2.tf), MR fusionnée avant
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site-par2.yml --limit site_par2 --diff
admin@adm01:~/src/infra/envs/par2$ rm backend_override.tf
admin@adm01:~/src/infra/envs/par2$ set -a; . ~/.config/workbook/s3-tofu-par2.env; set +a
admin@adm01:~/src/infra/envs/par2$ tofu init -migrate-state
admin@adm01:~/src/infra/envs/par2$ shred -u terraform.tfstate terraform.tfstate.backup
admin@adm01:~/src/infra/envs/par2$ tofu plan        # aucun changement
```

Puis la même chose depuis `adm02` (clone **du miroir** de `plateforme/infra`, fichiers d'accès copiés) : `tofu plan` vide. Pour ne pas dépendre du registre public le jour J : `tofu providers mirror /srv/tofu-fournisseurs` sur `adm02` et `provider_installation { filesystem_mirror { … } }` dans `~/.tofurc` de `adm02`.

**Si `s3-02` est perdu** : (1) versions précédentes de l'objet `envs/par2/terraform.tfstate` (versionnage) si le compartiment survit ; (2) sinon, recréer `s3-02` par le même amorçage (état local, `-target`), puis `tofu import` des autres VMs : `tofu import 'module.vm["adm02"].proxmox_virtual_environment_vm.vm' pbs01/1050` (VMID du catalogue) ; `tofu plan` doit redevenir vide.

## 6. Réseau : vérifications et retour arrière

Contrôles : `ip -4 addr show vmbr2` (10.20.20.1/24) ; `nft list table inet par2` ; depuis `adm02` : `ping 10.10.20.10` (par `wg0`), `curl -sI https://deb.debian.org` (Internet), `ping <une-adresse-du-LAN-maison>` **en échec** ; depuis ton poste par `wg1` : `ssh admin@10.20.20.10`.

Retour arrière (dans cet ordre, chacun testé avant la mise en service) :
```
root@pbs01:~# systemctl disable --now wg-quick@wg1 nftables-par2
root@pbs01:~# pvesh delete /nodes/pbs01/network/vmbr2 && pvesh set /nodes/pbs01/network
root@pbs01:~# rm /etc/sysctl.d/90-par2.conf && sysctl -w net.ipv4.ip_forward=0
```
`vmbr0`, `vmbr1` et `wg0` ne sont jamais modifiés par ce runbook : s'ils changent, c'est une erreur, et l'archive du §2 contient leur configuration.

## 7. DNS

- MR sur `plateforme/ansible` : `host_vars/dns03/*`, ajout de 10.20.20.11 aux `powerdns_auth_notifier` de `dns01`, noms globaux dans la zone parente (`powerdns_auth.yml.extrait-F5`) ; flux de la bordure (extrait `pare_feu.yml`).
- Contrôle : `dig @10.20.20.11 SOA par1.medisphere.internal +short` = même série que `dig @10.10.20.10 …` ; `dig @10.10.20.10 mediagenda.medisphere.internal CNAME` : TTL ≤ 60.

## 8. Retour arrière de l'installation de Proxmox VE

À appliquer si un contrôle du §3 est rouge, ou si PBS se comporte anormalement dans les 7 jours (CHG-3503). Avant : aucune VM de PAR2 en service (sinon d'abord `envs/par2` détruit, sauf `s3-02` et son état exportés).

```
root@pbs01:~# grep -A3 'Commandline: apt-get install proxmox-ve' /var/log/apt/history.log    # transaction exacte
root@pbs01:~# apt-get -s purge <PAQUETS-INSTALLÉS-PAR-CETTE-TRANSACTION>                       # simulation d'abord
root@pbs01:~# apt-get purge <PAQUETS-INSTALLÉS-PAR-CETTE-TRANSACTION>
root@pbs01:~# rm /etc/apt/sources.list.d/pve-install-repo.sources /etc/apt/sources.list.d/pve-enterprise.sources
root@pbs01:~# apt-get update
root@pbs01:~# diff <(dpkg --get-selections) <(tar -xzOf /root/f5/pbs-config-<DATE>.tar.gz ./dpkg-selections.txt)
```

La simulation ne doit retirer **aucun** paquet `proxmox-backup*`, `proxmox-kernel*` ni `ifupdown2` : sinon, arrêt et purge paquet par paquet. Le `diff` final doit être vide. Contrôles du §3 côté PBS, sauvegarde nocturne suivante vérifiée.

**Limite écrite** : ce retour arrière n'est pas documenté par Proxmox ; il repose sur l'historique d'APT. La restauration complète (réinstallation de PBS par ISO et import du datastore, qui reste intact sur son disque) est le dernier recours.
