# Final F4 — Phase 3 : Migrations (corrigé)

> ⚠️ Corrigé : à n'ouvrir qu'après avoir cherché. Ce sont des **solutions de référence** : d'autres chemins sont valables s'ils tiennent les contraintes et les critères. Fichiers complets dans [`fichiers/`](fichiers/) (`S09/` à `S13/`).

**Points non testés en conditions réelles** (à vérifier sur ton lab, et à signaler pour correction) :
- fabrication de l'export (`ressources/S09/`) : comportement de `virt-customize` sur Proxmox VE 9 (réseau de la machine d'appoint, `update-grub` lors du remplacement du noyau *cloud*, MariaDB temporaire démarrée dans la machine d'appoint) ;
- démarrage OVMF des images Debian 12 *genericcloud* sans entrée de démarrage (chemin de secours `\EFI\BOOT\BOOTX64.EFI`) : si la VM reste au shell UEFI, repasse-la en SeaBIOS (image hybride) et note l'écart ;
- configuration OpenTofu de VMs importées (`bpg/proxmox` 0.116) : quelques attributs relus peuvent différer (format du disque, ordre des étiquettes) ;
- objets de mariadb-operator 26.6 : étiquettes des pods créées par l'opérateur, nom du conteneur (`mariadb`), variable `MARIADB_ROOT_PASSWORD` dans le pod, héritage des étiquettes par le `ServiceMonitor` (`inheritMetadata`), compatibilité PSA `restricted` des Jobs de sauvegarde et des `SqlJob`, besoins réseau de ces Jobs (vers l'API) ;
- valeurs du chart de l'opérateur au-delà des clés vérifiées dans `values.yaml` de l'étiquette `v26.6.0`.

---

### F4-S09 — Plan de migration du VMware d'InfoGér

**Solution**

Fichiers : [`S09/pve01/inspecter-export.sh`](fichiers/S09/pve01/inspecter-export.sh) (audit hors ligne, lecture seule), [`S09/medisphere/docs/changements/`](fichiers/S09/medisphere/docs/changements/) (`migration-vmware.md`, `inventaire-reel.csv`, `fiches/CHG-3410.md`).

1. **Fabrication** de l'export (`ressources/S09/README.md`), sommes « du courriel » copiées hors de `pve01` (dans le ticket CHG-3409) :
   ```
   root@pve01:~# apt-get install -y libguestfs-tools
   root@pve01:~# /root/DevOpsPrivateCloud/finaux/F4-changements/ressources/S09/fabriquer-export-vmware.sh | tee /root/courriel-infoger.txt
   ```
2. **Intégrité** : manifeste converti (`SHA256(f)= somme` → `somme  f`) puis `sha256sum -c`, et comparaison avec les sommes du courriel :
   ```
   root@pve01:~# cd /mnt/pve/hdd-bulk/import/infoger-export/legacy-rdv01
   root@pve01:…# sed -nE 's/^SHA256\(([^)]+)\)= ([0-9a-f]{64})$/\2  \1/p' legacy-rdv01.mf | sha256sum -c -
   ```
   (Le chemin du stockage dépend de ton lab : `pvesh get /storage/hdd-bulk --output-format json | jq -r .path`.)
3. **Audit hors ligne** : `inspecter-export.sh --sommes /root/courriel-infoger.txt > /root/audit-infoger.txt`. Il lit les descripteurs (matériel), puis les disques **sans les démarrer** : `virt-inspector` (système, noyau), `virt-cat` (fichiers de configuration, en masquant les lignes de secrets), `guestfish --ro` (tâches planifiées, comptes, unités activées, clés autorisées), et compte les rendez-vous et les pièces jointes en lisant le **vidage nocturne d'InfoGér** en flux (aucune copie sur disque). Les comptes MariaDB ne se lisent pas sans serveur : on les **déduit** (`/etc/stats/stats.cnf` de `stats01`, `/etc/hosts`) et on les confirme au premier démarrage (S10).
4. **Inventaire réel** et **plan** : voir les fichiers de référence. Ce qu'il fallait trouver :
   - `stats01` a une adresse (192.168.50.40) et lit la base de `legacy-rdv01` chaque nuit (02:15) avec le compte `stats`, limité à l'hôte 192.168.50.40, par le nom `legacy-rdv01.infoger.local` de `/etc/hosts` ; personne ne lit ses fichiers depuis 2020 ;
   - la base de `legacy-rdv01` écoute sur toutes les interfaces ; un vidage SQL non chiffré est fait chaque nuit dans `/var/backups/infoger/` ;
   - environ 290 pièces jointes **référencées** pour environ 120 fichiers **présents** (la purge efface les fichiers sans toucher la base) ;
   - `ftp-part01` : FTP en clair, `pasv_address=192.168.50.30`, `nologin` ajouté à `/etc/shells` ;
   - partout : `ens192` en adresse fixe (ifupdown), cloud-init **désactivé**, `open-vm-tools`, compte `infoger` (sudo avec mot de passe, clé d'InfoGér), `AllowUsers infoger`, `root` verrouillé ; EFI sans Secure Boot pour deux VMs, BIOS et LSI Logic pour `stats01` ;
   - secrets en clair : mot de passe de 2014 (`config.php`), mot de passe de `stats` (`/etc/stats/stats.cnf`).
5. **Vagues** : `ftp-part01` seule d'abord (indépendante, valide la méthode), puis `legacy-rdv01` et `stats01` **ensemble** (couplées par la base, le compte et le nom).

**Explications**

Un export VMware n'est pas une boîte noire : ses disques se lisent sans démarrer la VM. C'est la seule façon d'auditer **avant** d'introduire chez soi un système inconnu (démarrer une VM d'un tiers, c'est exécuter son code sur son réseau). Le manifeste prouve la cohérence de la livraison, pas son origine : seules des sommes reçues par un autre canal la prouvent. La fiche du prestataire sortant décrit ce qu'il croit avoir, pas ce qu'il a : l'inventaire se refait toujours à partir des disques.

**Alternatives**
- Démarrer chaque VM dans un VNet de quarantaine sans sortie (VLAN 99 isolé) pour l'audit : plus rapide pour les comptes MariaDB, mais exécute du code inconnu et modifie les disques (journaux, horloges) ; à faire sur une **copie**.
- `virt-v2v` (conversion VMware → KVM en une commande, pilotes VirtIO injectés) : outil de référence pour les migrations en masse, surtout pour Windows ; il n'est pas dans les dépôts de Proxmox et n'apprend pas ce que fait la conversion.
- Assistant d'import d'OVF de Proxmox VE (interface) : lit en plus la carte réseau et le micrologiciel.

**Pièges classiques**
- Comparer le manifeste… avec lui-même (il voyage avec les fichiers).
- Recopier un secret trouvé dans le document de migration (le check refuse le mot de passe de 2014).
- Croire la fiche : « `stats01` : pas d'adresse, pas de dépendance ».
- Oublier les copies de données : vidages locaux, export lui-même (ce sont des données de santé à effacer un jour, F4-S14).
- Planifier `stats01` et `legacy-rdv01` dans deux vagues : la statistique de la nuit casse.

**En production chez MédiSphère**
Avec un vrai ESXi, on importe directement (stockage `esxi` de Proxmox), on fait signer le PV de réversibilité **après** l'audit, et on exige du prestataire sortant les mots de passe par un canal chiffré avant l'arrêt de son infrastructure ; l'audit hors ligne est scripté et versionné (`plateforme/outils`), pour les vingt VMs suivantes.

---

### F4-S10 — Migrer les VMs d'InfoGér vers Proxmox VE

**Solution**

Fichiers : [`S10/pve01/convertir-vm-infoger.sh`](fichiers/S10/pve01/convertir-vm-infoger.sh), [`S10/infra/envs/f4-infoger/`](fichiers/S10/infra/envs/f4-infoger/), [`S10/ansible/`](fichiers/S10/ansible/) (`playbooks/f4-infoger.yml`, `group_vars/env_f4/infoger.yml`, `group_vars/role_lb/legacy-rdv.yml` et extraits pour `haproxy.yml` et `certificats.yml`, groupe de sonde `continuite-legacy-rdv` de `mon01`, gabarit nftables), [`S10/medisphere/docs/changements/runbooks/RB-345-migrer-vm-vmware.md`](fichiers/S10/medisphere/docs/changements/runbooks/RB-345-migrer-vm-vmware.md).

1. **Préparation** (MR avant la fenêtre) : flux de la matrice (répartiteurs → 10.10.20.44:80, MGMT → 10.10.20.45:21 et 40000-40100, `K8S_TRAV` → 9100 des trois VMs, `stats01` → `legacy-rdv01`:3306 dans le même VLAN : pare-feu local) ; code OpenTofu **sans** les blocs `import` (les VMs n'existent pas encore) ; publication de `rdv` prête mais non jouée.
2. **Vague 1 — `ftp-part01`**, puis **vague 2 — `legacy-rdv01` et `stats01`**, une VM à la fois :
   ```
   admin@adm01:~$ scp ~/.ssh/id_ed25519.pub root@pve01:/root/cle-admin.pub
   root@pve01:~# ./convertir-vm-infoger.sh --vm ftp-part01 --cle /root/cle-admin.pub --sommes /root/courriel-infoger.txt
   ```
   Le script : vérifie le manifeste **et** les sommes du courriel ; `qm importovf … --dryrun 1` puis l'import (seuls nom, cœurs, mémoire et disque sont repris) ; pose le matériel **avant tout démarrage** (`virtio-scsi-single`, disque `discard,iothread,ssd`, `net0` `virtio` sur `vinfra` avec une MAC du plan, `x86-64-v2-AES`, console série, agent, `onboot`, étiquettes ; `ovmf` + `efidisk0 … pre-enrolled-keys=0` pour les VMs EFI sans Secure Boot) ; adapte **hors ligne** l'invité avec `virt-customize` sur `$(pvesm path <volid>)` (interface `ens18` + adresse du plan, résolveurs, `/etc/hosts`, `open-vm-tools` purgé, `qemu-guest-agent` installé, compte `admin` + clé + sudo, `10-infoger.conf` remplacé par `AllowUsers admin`, compte `infoger` verrouillé et expiré, sa clé et son sudo supprimés, `pasv_address` et `stats.cnf` re-adressés, `update-initramfs` puis contrôle de `virtio_scsi` dans chaque initramfs) ; démarre, attend l'agent ; pour `legacy-rdv01`, `RENAME USER 'stats'@'192.168.50.40' TO 'stats'@'10.10.20.46'`.
3. **Code** : blocs `import` ajoutés, première configuration générée puis nettoyée :
   ```
   admin@adm01:~/src/infra/envs/f4-infoger$ tofu plan -generate-config-out=genere.tf   # première fois seulement
   admin@adm01:~/src/infra/envs/f4-infoger$ tofu apply      # par le pipeline de plateforme/infra
   admin@adm01:~/src/infra/envs/f4-infoger$ tofu plan -detailed-exitcode   # 0 : aucun changement
   ```
   `infoger.tf` de référence décrit les trois VMs (ressource `proxmox_virtual_environment_vm` à `for_each`, `prevent_destroy`), NetBox (VM, interface `ens18`, adresse, IP primaire), DNS (module `enregistrement-dns`) et le CNAME `rdv` vers `lb.par1.medisphere.internal`.
4. **Ansible** (pipeline protégé) : `playbooks/f4-infoger.yml` sur le groupe `env_f4` (étiquette NetBox `env-f4`) : contrôles (Debian 12), outils VMware absents, agent, mises à jour de sécurité automatiques, accès d'InfoGér fermé, pare-feu local (flux inventoriés), `node_exporter` et `alloy` (+ journal applicatif de Legacy-RDV). Le rôle `durcissement` n'est **pas** joué (Debian 12 hors référentiel) : exception EXC-H-034 au registre, avec ces mesures compensatoires et une date de revue = décommissionnement.
5. **Répartiteurs** : extraits de `haproxy.yml` et `certificats.yml` (`rdv` comme `sso` au M24 : terminaison TLS locale, `be_legacy_rdv` dont les lignes viennent de `legacy_rdv_cible` = `vm`) ; `--limit lb02`, contrôle, `--limit lb01`. Exception EXC-H-035 : HTTP répartiteurs → `legacy-rdv01` jusqu'à CHG-3413.
6. **Mot de passe de 2014** : décision écrite dans CHG-3410 : inchangé sur la VM jusqu'à S12 (compte `legacy_rdv@localhost` seulement, base filtrée par le pare-feu local, VM à durée de vie courte) ; il meurt à la sortie de la VM.
7. **Sauvegarde et supervision** : travail PBS dédié, première sauvegarde manuelle :
   ```
   root@pve01:~# pvesh create /cluster/backup --id f4-infoger --vmid 3401,3402,3403 --storage pbs-par2 \
       --schedule '02:30' --mode snapshot --enabled 1 --prune-backups keep-daily=7,keep-weekly=4 \
       --comment "VMs migrées d'InfoGér (CHG-3410)"
   root@pve01:~# vzdump 3402 --storage pbs-par2 --mode snapshot
   ```
   Sonde de continuité : groupe **`continuite-legacy-rdv`** (étiquette `service: legacy-rdv`, cible `https://rdv.par1.medisphere.internal/`) ajouté à `host_vars/mon01/supervision_temoin.yml` de `plateforme/ansible` ([extrait](fichiers/S10/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait-F4-S10)), joué par le rôle `supervision_temoin` : c'est la même sonde qui mesurera la bascule (S13). Le port FTP se suit par `node_exporter` et `alloy` (le témoin du M21 n'a pas de module TCP : en ajouter un est une amélioration possible, pas un prérequis).
8. **Preuves de service** : `curl -s https://rdv.par1.medisphere.internal/ | grep 'Rendez-vous'` ; un dépôt FTP de test en passif depuis `adm01` (`curl -T test.csv ftp://partenaire-labo@10.10.20.45/entrant/`, mot de passe du partenaire **réinitialisé** et transmis au partenaire par Nadia, ou compte de test temporaire supprimé ensuite) ; statistique lancée à la main sur `stats01` (`sudo /opt/stats/stats-rdv.sh`), fichier du jour non vide.

**Explications**

`qm importovf` (Proxmox VE 9, `PVE::GuestImport::OVF`) analyse le descripteur et en tire nom, cœurs, mémoire, type de système, micrologiciel (`firmware=efi` → `ovmf`), disques et modèle des cartes, mais la **commande** n'applique que le nom, les cœurs, la mémoire et les disques (placés sur le contrôleur SCSI par défaut) : la carte, le micrologiciel et le type de système sont à poser à la main (l'assistant de l'interface, lui, les reprend). Le noyau standard de Debian a les pilotes VirtIO et l'initramfs `MODULES=most` les embarque : le passage de pvscsi à VirtIO SCSI est sans risque **ici** (S11 montre quand il ne l'est pas). Le nom d'interface dépend de l'emplacement PCI : `ens192` chez VMware (emplacement 192 du descripteur), `ens18` pour `net0` chez Proxmox. Tout ce qui contenait une adresse d'InfoGér est lu à un moment différent : au démarrage (réseau), à chaque connexion (FTP passif : l'adresse est **annoncée** au client), chaque nuit (statistiques), à l'authentification (compte MariaDB lié à l'adresse cliente). L'import dans OpenTofu rattache sans recréer ; `prevent_destroy` protège des disques qui n'existent nulle part ailleurs.

**Alternatives**
- Premier démarrage « tel quel » dans un VNet isolé, puis conversion en ligne par la console série (`init=/bin/bash` dans GRUB pour reprendre la main) : plus proche d'une vraie migration sans `libguestfs`, plus lent, et chaque erreur se paie d'un redémarrage.
- Lecteur cloud-init (comme au M09-E23) : **inopérant ici** (cloud-init désactivé par InfoGér) ; le réactiver = supprimer `/etc/cloud/cloud-init.disabled` hors ligne, puis laisser cloud-init réécrire réseau et comptes : possible, mais il réécrit aussi ce qu'on ne voulait pas (clés d'hôte, réseau sur `ens18` en DHCP).
- Garder la MAC VMware (`00:50:56:…`) : inutile ici (aucune licence liée), et trompeur dans NetBox.
- Réinstaller les services sur des VMs neuves (`vm-debian`, Debian 13) et ne migrer que les **données** : souvent le meilleur choix, ici réservé à Legacy-RDV (S12).

**Pièges classiques**
- Démarrer avant d'avoir posé le matériel : la VM EFI démarre en BIOS (ou pas), la carte manque.
- `AllowUsers infoger` : le compte `admin` créé est refusé par SSH, sans message côté client (« Permission denied »).
- Oublier `RENAME USER` : la statistique de la nuit échoue (« Access denied for user 'stats'@'10.10.20.46' »).
- Oublier `pasv_address` : la connexion FTP s'établit, la liste des fichiers ne vient jamais (le client tente 192.168.50.30).
- `tofu apply` d'une configuration non nettoyée : OpenTofu veut **remplacer** une VM (attribut qui force la recréation) ; d'où `prevent_destroy` et la relecture du plan.
- Laisser une adresse d'InfoGér dans `/etc/hosts` : la résolution « marche » jusqu'au jour où l'adresse est réutilisée.

**En production chez MédiSphère**
La conversion se fait dans un VNet de quarantaine, sans sortie, jusqu'au contrôle de conformité (matériel, agent, comptes, outils, sauvegarde) ; les comptes partenaires sont renouvelés avec les partenaires (pas de mot de passe hérité) ; FTPS ou SFTP est imposé dans les 90 jours ; chaque VM migrée porte une date de fin de vie dans NetBox.

---

### F4-S11 — Panne : la VM migrée ne démarre pas comme avant

Script : [`pannes/break-S11.sh`](pannes/break-S11.sh). Toutes les variantes prennent d'abord un instantané `avant_f4_s11` (sans mémoire) ; `--annuler` y revient si la VM est encore en panne, sinon supprime seulement l'instantané.

**Démarche de diagnostic** (commune)

1. **Symptôme** → couche : la VM tourne-t-elle (`qm status`) ? L'agent répond-il (`qm guest cmd <vmid> ping`) ? Que dit la console (`qm terminal <vmid>`, sortie par `Ctrl+O`) : micrologiciel, GRUB, noyau, initramfs, systemd, invite de connexion ?
2. **Qu'est-ce qui a changé ?** Proxmox garde la configuration de chaque instantané : `qm listsnapshot <vmid>`, `qm config <vmid> --snapshot avant_f4_s11` contre `qm config <vmid>` (pas de retour à l'instantané : on **compare**). Dans l'invité arrêté : `virt-cat -a $(pvesm path <volid>) /etc/fstab`, `/etc/network/interfaces`, `/etc/systemd/network/`, `/etc/initramfs-tools/conf.d/`, et le journal système du dernier démarrage (`virt-log -a $(pvesm path <volid>)`, VM arrêtée).
3. **Hypothèses** dans l'ordre du démarrage, chacune confirmée ou écartée par une observation.

**Variante 1 — `stats01` en mode urgence (virtio-blk + `fstab` par nom de périphérique)**
- Console : `Timed out waiting for device /dev/sda15` (ou `dev-sda15.device`), `Dependency failed for /boot/efi`, `You are in emergency mode` ; root verrouillé : `Cannot open access to console, the root account is locked`.
- Configuration : `virtio0:` au lieu de `scsi0:` (comparaison avec l'instantané) ; dans l'invité, `/etc/fstab` désigne `/dev/sda1` et `/dev/sda15` (« wiki d'InfoGér »). Avec `virtio-blk`, le disque est `/dev/vda` : `/dev/sda15` n'apparaîtra jamais.
- **Cause racine** : deux changements combinés : `fstab` par nom de périphérique (fragile) + changement de bus du disque.
- **Correctif** : `fstab` par `UUID=` ou `PARTUUID=` (hors ligne : `virt-customize -a … --run-command "…"` ou `guestfish --rw` puis `edit /etc/fstab` ; valeurs par `virt-filesystems --long --uuid -a …` ou `blkid` dans `guestfish`) ; disque remis en `scsi0` (`qm set <vmid> --delete virtio0` puis `--scsi0 <volid>,discard=on,iothread=1,ssd=1 --boot order=scsi0`) pour rester conforme au code (le plan OpenTofu l'exige) ; redémarrage.
- **Prévention** : contrôle de conformité « `fstab` sans `/dev/sdX` » (Testinfra ou S10 « pour aller plus loin ») ; RB-345 ; virtio-blk n'apporte rien ici face à VirtIO SCSI avec `iothread`.

**Variante 2 — `ftp-part01` injoignable (nom d'interface figé par la MAC, puis nouvelle MAC)**
- Console ou agent : la VM démarre, l'agent répond, mais `ip -br a` (par `qm guest exec <vmid> -- ip -br a`) montre `ens18` **sans adresse** ; `systemctl status networking` : `Cannot find device "lan0"`.
- Configuration : la MAC de `net0` a changé (comparaison avec l'instantané) ; `/etc/systemd/network/10-infoger-lan0.link` lie le nom `lan0` à l'**ancienne** MAC ; `/etc/network/interfaces` configure `lan0`.
- **Cause racine** : configuration réseau liée à un identifiant matériel qui a changé.
- **Correctif** : soit remettre la MAC du plan (`BC:24:11:20:34:02`, celle du code : c'est elle que veut `tofu plan`) et garder le `.link` (déconseillé), soit **supprimer** le `.link`, revenir à `ens18` dans `interfaces`, `update-initramfs -u` (le `.link` est aussi copié dans l'initramfs), et remettre la MAC du code. Puis redémarrer et tester un dépôt FTP.
- **Prévention** : la MAC fait partie du code (`network_device.mac_address`) : un changement de carte passe par OpenTofu et se voit au plan ; pas de nommage par MAC sur des VMs (l'emplacement PCI est stable chez Proxmox).

**Variante 3 — `stats01` à l'invite `(initramfs)` (initramfs « réduit »)**
- Console : `Gave up waiting for root file system device`, `ALERT! UUID=… does not exist. Dropping to a shell!`, invite `(initramfs)` ; `cat /proc/modules` ou `ls /dev/sd*` dans ce shell : aucun disque.
- Configuration Proxmox inchangée. Dans l'invité : `/etc/initramfs-tools/conf.d/zz-infoger-reduit.conf` (`MODULES=list`), `/etc/initramfs-tools/modules` complété de `vmw_pvscsi`, `vmxnet3`, `ext4` ; `lsinitramfs` (hors ligne : `virt-copy-out` de l'initrd, puis `lsinitramfs` sur `pve01`) : pas de `virtio_scsi`.
- **Cause racine** : initramfs régénéré sans le pilote du contrôleur réel (une configuration pensée pour VMware : `MODULES=list` ou `MODULES=dep` généré sur l'ancien matériel produit le même effet).
- **Correctif** : hors ligne (`virt-customize -a … --delete /etc/initramfs-tools/conf.d/zz-infoger-reduit.conf --run-command 'sed -i "/Wiki InfoGér/,\$d" /etc/initramfs-tools/modules' --run-command 'update-initramfs -u -k all'`) puis contrôle de `virtio_scsi` dans l'initramfs ; ou démarrage sur un autre noyau du menu GRUB s'il en reste un avec un ancien initramfs.
- **Prévention** : toute régénération d'initramfs suivie d'un contrôle `lsinitramfs | grep virtio_scsi` (RB-345, rôle Ansible) ; jamais de `MODULES=dep` sur une VM qui peut changer de contrôleur.

**Post-mortem** (toutes variantes) : `docs/changements/post-mortems/INC-6011-<sujet>.md`, même forme que INC-6006 (S06) : chronologie, hypothèses écartées et ce qui les a écartées, cause racine (mécanisme, pas « Lucas »), correction, prévention (contrôle de conformité de S10, RB-345 complété, consignes d'un tiers relues avant application). Une fois le check vert : `lab/bin/break F4 11 --annuler` pour supprimer l'instantané `avant_f4_s11`.

**Explications**
Un démarrage Linux est une chaîne : micrologiciel → chargeur → noyau → initramfs (pilotes, racine) → systemd (montages de `fstab`, réseau) → services. Chaque variante casse un maillon différent, avec un symptôme qui ne nomme pas la cause : la console série dit **où** on s'arrête, la comparaison de configuration (instantané, fichiers) dit **ce qui** a changé.

**Pièges classiques**
- Revenir à l'instantané « pour voir » : on perd la preuve et on ne sait pas pourquoi c'était cassé.
- Corriger en rendant la VM non conforme au code (laisser `virtio0`, garder une MAC aléatoire) : `tofu plan` le signalera au prochain passage, ou, pire, `apply` « réparera » à contretemps.
- Chercher dans le réseau une panne d'initramfs (la VM tourne, l'agent ne répond pas : rien à voir avec le réseau).

**En production chez MédiSphère**
Les modifications d'invités passent par Ansible (jamais une « petite maintenance » à la main), la dérive est détectée la nuit (`tofu plan`, Testinfra) et les « wikis » d'un ancien prestataire sont relus avant d'être appliqués.

---

### F4-S12 — Legacy-RDV sur Kubernetes

**Solution**

Fichiers ([`S12/`](fichiers/S12/)) :
- `legacy-rdv/` (projet `legacy/legacy-rdv`, version 2.4.0) : `config.php`, `inc/commun.php` (sessions en base si `LEGACY_RDV_SESSIONS=base`, port), `inc/sessions.php` (`SessionHandlerInterface` sur `mysqli`), `index.php` (« maintenant » calculé par PHP), `pret.php` (disponibilité, sans session), `cron/purge-uploads.php` (base mise à jour avec le disque, sessions expirées), `sql/V2__sessions.sql`, `conteneur/php-legacy-rdv.ini`, `conteneur/apache-legacy-rdv.conf` (`mod_remoteip`), `Dockerfile`, `.dockerignore`, `.gitlab-ci.yml` (composants `@v2.11.0`, `php -l`), `sante.php` (M12, inchangé) ;
- `charts-miroir/charts.yaml.extrait-F4` ; `gitops/` (Applications `mariadb-operator-crds` en vague −1 et `mariadb-operator` en vague 0, valeurs, AppProject `legacy`, ApplicationSet `legacy-rdv`, extrait du projet `plateforme`) ;
- `k8s/` : espaces `mariadb-system`, `legacy-rdv-recette`, `legacy-rdv-prod` (namespace, quota, limites, SecretStore), locataire Capsule `legacy`, ClusterRole `wb-checks-donnees-mariadb` ;
- `secrets/tofu/eso-espaces.extrait-F4.tf`, `politiques/kyverno/images/exiger-signature-medisphere.extrait-F4.yaml` ;
- `legacy-deploiement/` (dépôt `legacy/deploiement`) : `base/` (`ExternalSecret`, `MariaDB`, `Database`, `User`, `Grant`, `SqlJob` v1 et v2, `Backup`, ConfigMap, PVC `cephfs` RWX, Deployment, Service, PDB, HTTPRoute, CiliumNetworkPolicy, CronJob de purge) et `overlays/recette|prod` ;
- `outils/copier-donnees-legacy.sh` ; `medisphere/` : `CHG-3412.md`, extrait de `legacy-rdv-12-facteurs.md`.

Étapes :
1. **Code** (MR sur `legacy/legacy-rdv`, relue par Karim et Claire) : les correctifs ci-dessus ; étiquette `v2.4.0` posée par semantic-release ; image construite, analysée, signée par la clé de transit, attestation SBOM ; empreinte relevée dans Harbor.
2. **Opérateur** : `charts.yaml` (deux charts OCI 26.6.0, empreintes relevées à la main et relues) → pipeline de `plateforme/charts-miroir` ; `plateforme/k8s` : espace `mariadb-system` ; `plateforme/gitops` : les deux Applications et les valeurs (CRD par le chart séparé, `crds.enabled: false` ; webhook et certificats par le `cert-controller` de l'opérateur ; contextes de sécurité pour PSA `restricted` ; métriques avec `ServiceMonitor`) ; projet `plateforme` étendu (objets de cluster des charts). Ce que l'opérateur crée en ton nom : ClusterRoles et webhooks (cluster), puis, dans chaque espace, StatefulSet, Services, PVC, Secrets de configuration, Jobs de sauvegarde, `ServiceMonitor` ; il se connecte à chaque base en root pour créer comptes, bases et droits.
3. **Locataire et espaces** : `legacy` (propriétaire `oidc:plateforme`, classes `ceph-rbd` et `cephfs`, aucun libre-service) ; espaces rattachés (`outils/rattacher-locataires.sh`) ; SecretStores ; rôles OpenBao `eso-legacy-rdv-<env>` (`plateforme/secrets`) ; secrets écrits par une personne de `plateforme-admins` sans que la valeur passe par une ligne de commande :
   ```
   admin@adm01:~$ bao login -method=oidc
   admin@adm01:~$ for env in recette prod; do
       ( umask 077
         printf '{"root":"%s","application":"%s","migrateur":"%s"}' \
           "$(openssl rand -hex 24)" "$(openssl rand -hex 24)" "$(openssl rand -hex 24)" > /dev/shm/legacy.json
         bao kv put "kv/legacy/$env/mariadb" @/dev/shm/legacy.json
         shred -u /dev/shm/legacy.json )
     done
   ```
   (`printf` est une commande interne du shell : les valeurs n'apparaissent dans aucune liste de processus ; le fichier vit en mémoire, 600, quelques millisecondes.) Identité S3 `mariadb-legacy-rdv` (compartiment de même nom) créée sur `s3-01` comme celles des modules précédents, clés dans `kv/legacy/<env>/s3`.
4. **Kyverno** : MR sur `plateforme/politiques` (Sophie), espaces ajoutés à `exiger-signature-medisphere`.
5. **Déploiement** : `legacy/deploiement` (copie de la racine MédiSphère en `base/medisphere-root-ca.crt`, empreinte de l'image dans les overlays), ApplicationSet `legacy-rdv` : recette synchronisée automatiquement, prod à la main.
6. **Données de recette** :
   ```
   admin@adm01:~$ ./copier-donnees-legacy.sh --espace legacy-rdv-recette
   >> rendez-vous : legacy-rdv01 = 2606 ; legacy-rdv-recette = 2606
   >> fichiers : legacy-rdv01 = 118 ; legacy-rdv-recette = 118
   ```
   Tout passe dans des tuyaux SSH → `kubectl exec`, rien sur disque ; le mot de passe root de la base est lu **dans** le pod. Contrôles : témoins `dr-temoin` aux mêmes heures, pièce `9003` identique (`sha256sum`).
7. **Deux réplicas réellement actifs** : six chargements de `prendre.php` avec le même cookie → même jeton ; soumission de dix formulaires (rendez-vous de test, supprimés ensuite) sans « session expirée ».
8. **Sauvegarde et restauration** : `Backup` quotidienne (préfixe = environnement) ; restauration éprouvée par une `MariaDB` jetable dans `wb-essais` amorcée par `bootstrapFrom` (S3, préfixe `recette`), comptage, puis suppression ; pièces jointes : sauvegarde Velero de l'espace (PVC par Kopia).
9. **Production prête** : MariaDB vide (schéma v1 et v2 par les `SqlJob`), application à deux réplicas prête (`pret.php` compte 0), aucun trafic (nom non publié).

**Explications**
Deux réplicas ne fonctionnent qu'une fois **tout** l'état sorti des pods : sessions (sinon le jeton CSRF d'un formulaire n'existe pas sur l'autre réplica), fichiers (PVC RWX), configuration. Le reste est de la plateforme : l'opérateur donne des objets déclaratifs pour ce qu'on faisait à la main sur la VM (`CREATE DATABASE`, `GRANT`, `mariadb-dump`), ESO livre les mots de passe d'OpenBao, Kyverno n'admet que l'image signée par empreinte, Capsule cloisonne. Le fuseau : les `DATETIME` sont des heures de Paris sans fuseau ; la VM comparait avec `NOW()` d'un serveur à l'heure de Paris ; une base en conteneur est en UTC par défaut : la liste « à venir » aurait glissé d'une ou deux heures. Calculer « maintenant » dans PHP (fuseau des cabinets) supprime la dépendance ; `timeZone: Europe/Paris` sur la base couvre le reste.

**Alternatives**
- **Valkey** pour les sessions (`session.save_handler = redis`, extension `phpredis` à compiler dans l'image) : verrouillage de session possible, un composant de plus ; MédiAgenda en a déjà un (M27) mais le partager mélangerait deux applications.
- **StatefulSet MariaDB fait main** : rien de nouveau à installer, mais sauvegardes, comptes et restaurations à scripter ; ou **CloudNativePG** après conversion de schéma vers PostgreSQL : la bonne cible à terme si Legacy-RDV était réécrit (ADR-0340).
- **Galera** (3 instances) : haute disponibilité réelle de la base, trois fois la mémoire, pour 40 cabinets.
- **Stockage objet** (RGW) pour les pièces jointes : plus de PVC RWX, sauvegarde et réplication simplifiées ; demande de réécrire `prendre.php` et `piece.php`.
- Mots de passe générés par l'opérateur (`generate: true`) : plus simple, mais ils ne sont plus dans OpenBao (rotation, audit, bris de glace) : écarté.

**Pièges classiques**
- PDB `minAvailable: 1` sur une base à **une** instance : plus aucun drain ne passe (F4-S06).
- Sonde de vivacité sur `index.php` : chaque panne de base redémarre le web en boucle (README de l'application, point 8) ; sonde de disponibilité qui ouvre une session : une ligne `sessions` toutes les 10 s par pod.
- `readOnlyRootFilesystem` sans `emptyDir` pour `/var/run/apache2`, `/var/lock/apache2`, `/tmp` : Apache ne démarre pas, PHP ne reçoit plus les téléversements.
- `kubectl cp` ou fichier `dump.sql` sur `adm01` : une copie de données de santé qui traîne.
- CRD et opérateur dans la même Application sans vagues : premier `sync` en échec (« no matches for kind MariaDB ») ; CRD élaguées avec l'Application : **toutes** les bases supprimées.
- Oublier de mettre les espaces de Legacy-RDV dans la politique de signature : une image non signée passerait.

**En production chez MédiSphère**
La base aurait une sauvegarde physique en plus (`PhysicalBackup`) et une restauration testée chaque mois par un job ; les tableaux de bord de l'opérateur et des alertes (`MariaDB` non prête, sauvegarde de plus de 26 h) ; une analyse de la purge (combien de références remises à NULL) relue la première semaine.

---

### F4-S13 — La bascule de Legacy-RDV

**Solution**

Fichiers : [`S13/outils/bascule-legacy-rdv.sh`](fichiers/S13/outils/bascule-legacy-rdv.sh), [`retour-arriere-legacy-rdv.sh`](fichiers/S13/outils/retour-arriere-legacy-rdv.sh), [`S13/ansible/…/role_lb/legacy-rdv.yml`](fichiers/S13/ansible/inventories/lab/group_vars/role_lb/legacy-rdv.yml) (cibles `vm`, `maintenance`, `k8s`), [`RB-346`](fichiers/S13/medisphere/docs/changements/runbooks/RB-346-bascule-legacy-rdv.md), [`CHG-3413`](fichiers/S13/medisphere/docs/changements/fiches/CHG-3413.md).

1. **Choix de synchronisation** : vidage logique complet **dans** la fenêtre (environ 2 600 lignes : moins d'une minute à la répétition) ; pièces jointes pré-copiées la veille (`--pre-copie`, horodatée), rattrapées dans la fenêtre (`find -newermt`). La réplication depuis la VM est écartée par la mesure : quelques secondes de gain pour un flux 3306 et un compte de réplication sur une VM qu'on éteint.
2. **Répétition** (`--repetition`, vers la recette, sans gel ni répartiteurs) chronométrée ; durée dans la fiche ; trois MR des répartiteurs préparées et approuvées (`maintenance`, `k8s`, `vm`).
3. **Fenêtre** (RB-346) :
   ```
   admin@adm01:~/src/outils/legacy-rdv$ ./bascule-legacy-rdv.sh
   ```
   go/no-go → MR `maintenance` (page 503 servie par les répartiteurs : **plus aucune écriture** n'atteint la VM) → gel (`REVOKE INSERT, UPDATE, DELETE` du compte applicatif, vérifié par `SHOW GRANTS`) → **référence** (nombre, identifiant max.) → vidage → rattrapage des pièces → contrôles (nombre égal, témoins, **empreinte de toutes les dates** `DATE_FORMAT(date_rdv)` + praticien des deux côtés, sommes d'un échantillon de pièces et de la pièce témoin) → **point de non-retour** : MR `k8s` (lb02, contrôle, lb01) → contrôles fonctionnels par l'URL des cabinets → fin d'annonce.
4. **Retour arrière** (48 h) : `retour-arriere-legacy-rdv.sh` : maintenance, rapatriement des rendez-vous `id > identifiant max. au gel` (vidage partiel `--where`) et des pièces déposées depuis la bascule, droits rendus, MR `vm`. Décision écrite : aucun rendez-vous pris sur Kubernetes n'est perdu.
5. **Après** : `stats01` : tâche nocturne désactivée (aucun lecteur depuis 2020, décision de Claire dans la fiche) — l'alternative documentée serait un Service interne exposé à `stats01`, impossible proprement dans un locataire qui refuse les `LoadBalancer` (exception Capsule à écrire) ; sauvegarde de production vérifiée le lendemain ; sonde de `mon01` sur `rdv` ; fiche complétée (mesure de la sonde : début et fin de la page de maintenance).

**Explications**
Un vidage logique transporte des **valeurs** : `DATETIME` tels quels (heures de Paris sans fuseau), `TIMESTAMP` en UTC avec l'en-tête `SET TIME_ZONE='+00:00'` (option `--tz-utc` par défaut) puis reconvertis à la lecture. Rien ne décale un rendez-vous **dans la base** ; ce qui le décale, c'est l'interprétation à l'affichage ou dans une comparaison (fuseau de PHP, de la base, de « maintenant ») : d'où le contrôle de l'**affichage** des témoins, pas seulement des valeurs. Passer de MariaDB 10.11 à 11.8 par un vidage logique évite les questions de format physique ; les collations `utf8mb4_unicode_ci` sont toujours servies en 11.8. La page de maintenance des répartiteurs gèle plus proprement qu'un arrêt d'Apache : les cabinets voient un message et l'heure de retour, la VM reste lisible pour les contrôles.

**Alternatives**
- **Réplication** MariaDB (10.11 → 11.8 en réplica, `CHANGE MASTER` vers la VM) : fenêtre réduite au gel + bascule (≈ 2 min), au prix d'un flux à ouvrir et sécuriser, d'un binlog à activer (redémarrage de MariaDB sur la VM) et d'un compte de réplication.
- Bascule par le DNS (`rdv` en CNAME vers le nom de la Gateway) : dépend des TTL et des caches des postes des cabinets ; les répartiteurs donnent une bascule instantanée et réversible.
- Geler par `read_only=1` sur la VM : bloque aussi le compte root (sauf `SUPER`) ; les droits du compte applicatif suffisent et se vérifient.

**Pièges classiques**
- Oublier de geler : des rendez-vous pris sur la VM pendant le vidage sont perdus.
- Vider avec `--skip-tz-utc` ou recharger dans une session à un autre fuseau sans le savoir : les `cree_le` glissent (sans effet pour les cabinets, mais faux).
- Comparer seulement le nombre de lignes : un décalage d'heure garde le même nombre.
- Rendre le nom à la VM après 24 h sans rapatrier les rendez-vous pris sur Kubernetes.
- `rsync`/`kubectl cp` vers `adm01` « pour aller plus vite » : une copie de données de santé de plus à effacer.

**En production chez MédiSphère**
La bascule se fait avec Nadia en ligne avec deux cabinets pilotes, une page d'état publique, et la décision du point de non-retour prise à voix haute par Claire ; la fiche est relue en revue après mise en œuvre (F4-S14).
