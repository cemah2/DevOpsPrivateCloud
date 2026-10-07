# RB-038 — Diagnostiquer un build d'image ou un premier démarrage

| | |
|---|---|
| **Déclencheur** | job `build:*`/`test:*` en échec ou bloqué ; VM issue d'une image qui ne démarre pas, n'applique pas sa configuration, ou entre en conflit avec une autre |
| **Accès** | `adm01` ; root sur `pve01` (console, `qm`) ; `gw01`, `dns01` (sudo) ; `~/src/images` |
| **Principe** | situer l'**étape** qui échoue avant de chercher la cause ; mesurer, ne pas relire seulement |

## 1. Build bloqué sur « Waiting for SSH » (proxmox-iso, proxmox-clone)

Packer demande l'adresse de la VM à l'**agent QEMU** : « Waiting for SSH » couvre tout ce qui précède.

| Console de la VM | Étape | Vérifier | Commande décisive |
|---|---|---|---|
| installeur : « Network autoconfiguration failed » | DHCP | bail sur `dns01`, plage du VLAN 99 | `journalctl -u dnsmasq -f` sur `dns01` pendant le démarrage |
| installeur : « Failed to retrieve the preconfiguration file » | HTTP de Packer | flux `vsandbox` → machine de build 8100-8199 | compteurs `sudo nft list chain inet filter forward` sur `gw01` ; `tcpdump -ni ens19.99 portrange 8100-8199` |
| installeur : « Bad archive mirror » / téléchargement impossible | DNS ou Internet | DNS de `vsandbox` vers `dns01` | `tcpdump -ni ens19.99 port 53` sur `gw01` ; règles de rejet ajoutées à chaud |
| invite `login:` | après l'installation | agent présent et démarré ? | `qm guest cmd <VMID> ping` (root, `pve01`) ; `pkgsel/include` du preseed, `%packages` du kickstart |
| invite `login:`, agent OK | SSH | flux machine de build → `vsandbox` 22, compte de build | `PACKER_LOG=1` : erreurs d'authentification ou de connexion |

Toujours : `git status` / `git diff` dans la copie de travail (un `--brouillon` construit ce qui n'est pas commité) ; `sudo nft -c -f /etc/nftables.conf` et comparaison règles chargées / fichier sur `gw01` ; `dnsmasq --test` sur `dns01`.
Reproduire **en zone d'essai** : `outils/construire.sh --brouillon debian13-base -var vm_id=9090` (jamais sans `-var vm_id` : `-force` viserait 9001).

## 2. Clones qui se marchent dessus

| Symptôme | Identité partagée | Preuve | Correction sur la VM | Correction de l'image |
|---|---|---|---|---|
| même IPv4 pour deux MAC différentes | `machine-id` (DUID DHCP) | `cat /etc/machine-id` (agent) ; `log-dhcp` de dnsmasq | vider puis `systemd-machine-id-setup`, redémarrer | `cloud-init clean --machine-id` (préparation E07) |
| même empreinte de clé d'hôte | clés d'hôte + `ssh_deletekeys: false` | `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` | supprimer les clés, `ssh-keygen -A`, recharger sshd, mettre à jour `known_hosts` | suppression des clés + pas de `ssh_deletekeys: false` |
| même nom d'hôte | `preserve_hostname: true` | `hostname`, `/etc/cloud/cloud.cfg.d/` | retirer la clé, `hostnamectl set-hostname <nom>` | pas de nom figé dans l'image |
| connectivité intermittente, ARP instable | même MAC (création des VMs) | `qm config` des deux VMs | nouvelle MAC (`qm set --net0 virtio,bridge=…` sans `macaddr`) | rien : corriger le script de création |

Contrôle de non-régression : `tests/tester-image.sh <VMID>` (deux clones, unicité vérifiée).

## 3. cloud-init n'applique pas la configuration

```
admin@<vm>:~$ cloud-init status --long          # status, boot_status_code, detail
admin@<vm>:~$ sudo cat /run/cloud-init/ds-identify.log
admin@<vm>:~$ sudo grep -E 'restored from|new instance|cache' /var/log/cloud-init.log | tail
root@pve01:~# qm cloudinit dump <VMID> meta      # instance-id attendu
```

| Constat | Cause | Correction |
|---|---|---|
| `disabled-by-marker-file` | `/etc/cloud/cloud-init.disabled` | supprimer le fichier, chercher qui l'a posé |
| `disabled-by-generator`, `blkid -t LABEL=cidata` vide | lecteur cloud-init absent | `qm set <VMID> --ide2 <stockage>:cloudinit` |
| `disabled-by-generator`, lecteur présent | `datasource_list` sans NoCloud (`ds-identify.log` cite le fichier) | retirer la surcharge de `cloud.cfg.d` |
| `done`, « restored from cache » | `manual_cache_clean: true` | retirer la clé et `/var/lib/cloud/instance/manual-clean` |

Puis faire rejouer : `sudo cloud-init clean --logs` et redémarrer (ou laisser le changement d'instance-id agir).

## 4. VM qui ne démarre pas

| Dernier message (console) | Étape | Réglage à comparer au template |
|---|---|---|
| « No bootable device », iPXE, *UEFI Interactive Shell* | micrologiciel | `boot: order=…`, `bios` (SeaBIOS/OVMF) |
| `dracut-initqueue timeout`, racine introuvable, shell d'urgence | initramfs | `scsihw` (Rocky : pas de `lsi`), type de disque |
| « Fatal glibc error: CPU does not support x86-64-v3 », `Kernel panic … Attempted to kill init` | espace utilisateur | `cpu` (Rocky 10 : `x86-64-v3` ou `host`) |

Toujours comparer `qm config <VMID>` à `qm config <TEMPLATE>` : le template est la référence testée.

## Après l'incident

Journal dans `docs/socle/journal/` (numéro `INC-…`), test ajouté à `tests/tester-image.sh` si l'image était en cause, ligne ajoutée à ce runbook si le cas était nouveau.
