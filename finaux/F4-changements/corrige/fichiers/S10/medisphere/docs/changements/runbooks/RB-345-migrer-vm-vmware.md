# RB-345 — Migrer une VM VMware vers Proxmox VE

> Écrit pour CHG-3410 (VMs d'InfoGér, F4-S10). Outil : `convertir-vm-infoger.sh` (plateforme/outils,
> dossier `migration/`) ; à adapter pour une VM qui n'est pas une Debian.

## Avant (J-7)
1. **Intégrité** : manifeste `.mf` (format `SHA256(f)= somme`, converti pour `sha256sum -c`) **et** sommes reçues par un autre canal. Une somme fausse = no-go.
2. **Audit hors ligne** (`virt-inspector`, `virt-cat`, `guestfish --ro`) : système, noyau, pilotes dans l'initramfs (`MODULES=` de `/etc/initramfs-tools/`), nom d'interface et configuration réseau, comptes et accès, services, tâches planifiées, données, adresses et noms codés en dur. Résultat dans l'inventaire réel.
3. **Descripteur** : micrologiciel (`firmware`, Secure Boot), contrôleur, carte, MAC. `qm importovf` ne reprend que nom, cœurs, mémoire, disques : le reste est à poser à la main.
4. Code préparé (OpenTofu sans `import`, Ansible, répartiteurs), flux ouverts, sauvegarde de la veille, communication.

## Pendant (une VM à la fois)
1. `qm importovf <vmid> <ovf> local-nvme --dryrun 1`, puis sans `--dryrun`.
2. **Matériel avant tout démarrage** : `--scsihw virtio-scsi-single`, disque `discard=on,iothread=1,ssd=1`, `--net0 virtio=<MAC du plan>,bridge=vinfra`, `--cpu x86-64-v2-AES`, `--ostype l26`, `--serial0 socket --vga serial0`, `--agent enabled=1`, `--onboot 1`, étiquettes ; **EFI à l'origine** → `--bios ovmf` + `--efidisk0 local-nvme:1,efitype=4m,pre-enrolled-keys=0` (Secure Boot désactivé chez VMware) ; pool `lab`.
3. **Invité, hors ligne** (`virt-customize -a $(pvesm path <volid>)`, VM arrêtée) : interface `ens18` + adresse du plan, résolveurs, `/etc/hosts` ; `open-vm-tools` purgé ; `qemu-guest-agent` installé ; compte `admin` + clé d'`adm01` + sudo ; accès du tiers fermé (compte verrouillé et expiré, clé et sudo supprimés, `AllowUsers` revu) ; configurations applicatives re-adressées ; `update-initramfs -u -k all` puis **contrôle** que `virtio_scsi` est dans chaque initramfs.
4. Démarrage, agent (`qm guest cmd <vmid> ping`), console série en cas de doute (`qm terminal <vmid>`, sortie `Ctrl+O`).
5. Re-adressages qui exigent le service démarré (ex. `RENAME USER` MariaDB).
6. Code : blocs `import` dans `envs/f4-infoger`, `tofu plan -generate-config-out` la première fois (avec des blocs `import` littéraux, un par VM : la génération refuse un `import` à `for_each`), nettoyage, `tofu apply` (import + NetBox + DNS), **plan vide** ; pipeline Ansible ; répartiteurs (un à la fois).
7. Sauvegarde : travail PBS dédié (`pvesh create /cluster/backup --id f4-infoger --vmid 3401,3402,3403 --storage pbs-par2 --schedule '02:30' --mode snapshot …`), première sauvegarde à la main, restauration d'essai d'**un** fichier.

## Après
Contrôles de succès, mesures de la sonde dans la fiche, `lab/bin/check F4 10`, exceptions au registre (EXC-H), fiche complétée.

## Pièges rencontrés
- `AllowUsers` du tiers : le compte `admin` est refusé tant qu'on ne remplace pas la directive.
- Interface nommée par emplacement PCI : `ens192` (VMware) → `ens18` (Proxmox, carte `net0`). Une configuration liée à la **MAC** (fichier `.link`, règle udev) casse quand la MAC change.
- `fstab` par nom de périphérique (`/dev/sdX`) : change si le contrôleur change (`virtio-blk` → `/dev/vdX`). Toujours `UUID=`/`PARTUUID=`.
- Initramfs réduit (`MODULES=dep` généré sur l'ancien matériel, ou `MODULES=list`) : pas de pilote VirtIO, pas de racine.
- FTP passif : l'adresse annoncée (`pasv_address`) est dans la configuration du serveur.
- Comptes de base liés à une adresse cliente.

## Retour arrière
VM arrêtée, sauvegardée, détruite ; ré-import depuis l'export intact (≈ 20 min par VM). Après des écritures côté MédiSphère, le retour vers l'export perd ces écritures : « réparer en avant ».
