# Module 03 — Corrigé du palier 2 : Opérationnel

⚠️ Corrigé — à lire après avoir cherché.

Fichiers complets par exercice dans [`fichiers/`](fichiers/). État complet du projet à la fin du palier : superposer, dans l'ordre, `M03-E02/images/`, `M03-E05/images/`, `M03-E06/images/`, `M03-E07/images/`, `M03-E08/images/`, `M03-E09/images/`, `M03-E10/images/`.

---

### M03-E06 — Image de base Rocky Linux 10 avec kickstart

**Solution**

Fichiers : [`fichiers/M03-E06/images/rocky10-base/`](fichiers/M03-E06/images/rocky10-base/) — [`build.pkr.hcl`](fichiers/M03-E06/images/rocky10-base/build.pkr.hcl), [`variables.pkr.hcl`](fichiers/M03-E06/images/rocky10-base/variables.pkr.hcl), [`http/ks.cfg`](fichiers/M03-E06/images/rocky10-base/http/ks.cfg). Le script de dépôt de E05 gère déjà les deux familles ([`outils/deposer-iso.sh`](fichiers/M03-E05/images/outils/deposer-iso.sh)).

*1. ISO.* Le fichier `CHECKSUM` de Rocky a un autre format (`SHA256 (nom) = somme`, précédé de lignes de commentaire `# nom: taille bytes`) et une signature détachée `CHECKSUM.asc` ; la clé publique se télécharge depuis `dl.rockylinux.org`, et son empreinte (`FC22 6859 C086 0BF0 DDB9 5B08 5B10 6C73 6FED FC85` au moment de la rédaction, ⚠️ à comparer avec la page officielle) est contrôlée avant usage.
```
admin@adm01:~/src/images$ ssh pve01 'bash -s' -- rocky10 < outils/deposer-iso.sh
…
ISO vérifiée et déposée : hdd-bulk:iso/Rocky-10.2-x86_64-boot.iso
iso_name   = "Rocky-10.2-x86_64-boot.iso"
iso_sha256 = "bf3a75907948563d0c11f3d1b8546ee9216e18a3ea2dc0a67eb4c45452e210f9"
```
Le script ignore le lien `Rocky-10-latest-…` : on dépose la version **nommée**, pour savoir ce qu'on a construit.

*2. Kickstart.* Validation du fichier rendu :
```
admin@adm01:~/src/images/rocky10-base$ sed -e 's/${build_username}/packer/g' -e 's/${build_password}/factice/g' http/ks.cfg > /tmp/ks-rendu.cfg
admin@adm01:~/src/images/rocky10-base$ uv tool run --from pykickstart ksvalidator -v RHEL10 /tmp/ks-rendu.cfg
Checking kickstart file /tmp/ks-rendu.cfg
```
Aucune autre ligne : fichier valide. Sur un disque vierge démarré en BIOS, `autopart --type=plain --nohome --noswap` crée une table GPT avec une petite partition `biosboot` (1 Mio, pour GRUB), une partition `/boot` (1 Gio, XFS) et la racine XFS sur le reste, en dernier. Pas de LVM : `growpart` (cloud-init) agrandit une partition et son système de fichiers, pas un volume logique.

*3. `boot_command`.* `boot/grub2/grub.cfg` de l'ISO (BIOS) :
```
set default="1"
…
set timeout=60
menuentry 'Install Rocky Linux 10.2' --class fedora … {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Rocky-10-2-x86_64-dvd quiet
	initrd /images/pxeboot/initrd.img
}
menuentry 'Test this media & install Rocky Linux 10.2' --class fedora … {
	linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Rocky-10-2-x86_64-dvd rd.live.check quiet
…
```
L'entrée par défaut (`default="1"`) vérifie le support avant d'installer (`rd.live.check`) : plusieurs minutes perdues à chaque build, sans intérêt puisque la somme de l'ISO a été vérifiée au dépôt. RHEL 10 et ses dérivés démarrent leur ISO **avec GRUB 2 aussi en BIOS** (plus d'isolinux) : on sélectionne la première entrée (`<up>`), on l'édite (`e`), on descend à la ligne `linux` (troisième ligne de l'éditeur, après `setparams` et une ligne vide), on ajoute les paramètres d'Anaconda en fin de ligne, et `Ctrl-x` démarre :
```hcl
boot_command = [
  "<up><wait>e<wait>",
  "<down><down><end>",
  " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
  "<leftCtrlOn>x<leftCtrlOff>",
]
```
⚠️ Non testé sur la version 10.2 en conditions réelles : si l'éditeur affiche une ligne de plus ou de moins, ajuste le nombre de `<down>` en observant la console (ajoute `<wait5>` entre les étapes pendant la mise au point).

*4. Règle de validation* (dans `variables.pkr.hcl`) :
```hcl
variable "cpu_type" {
  type    = string
  default = "x86-64-v3"
  validation {
    condition     = contains(["x86-64-v3", "x86-64-v4", "host"], var.cpu_type)
    error_message = "Rocky Linux 10 ne démarre pas sous x86-64-v3 : utilise x86-64-v3, x86-64-v4 ou host."
  }
}
```
```
admin@adm01:~/src/images/rocky10-base$ packer validate -var-file=../vars/lab.pkrvars.hcl -var cpu_type=x86-64-v2-AES .
Error: Invalid value for variable
…
Rocky Linux 10 ne démarre pas sous x86-64-v3 : utilise x86-64-v3, x86-64-v4 ou host.
```
Packer exige que le message soit une phrase complète (majuscule initiale, point final) : sinon, c'est la règle elle-même qui est refusée.

*5. Build.* 15 à 30 minutes. En mode texte, Anaconda affiche sa progression dans la console (VGA) : écran texte avec l'avancement de l'installation des paquets ; `Alt-F2` (impossible par `boot_command` une fois le build en attente SSH, mais possible dans la console web) donne un shell, `Alt-F3`/`F4` les journaux.

*6. Contrôle.*
```
root@pve01:~# qm clone 9002 2031 --name m03-rocky-test --pool lab
root@pve01:~# qm set 2031 --tags env-m03 --ipconfig0 ip=dhcp --nameserver 10.10.20.10 \
    --searchdomain par1.medisphere.internal --ciuser admin --sshkeys /root/cle-adm01.pub && qm start 2031
admin@adm01:~$ ssh admin@<IP-2031> 'cloud-init status; getenforce; sudo firewall-cmd --list-services; sudo ls /root /var/log/anaconda'
status: done
Enforcing
dhcpv6-client ssh
anaconda-ks.cfg  ks-post.log  original-ks.cfg
anaconda.log  dbus.log  journal.log  ks-script-….log  packaging.log  program.log  storage.log …
```
`/root/original-ks.cfg` est **une copie du kickstart reçu, avec le mot de passe de construction en clair** ; `anaconda-ks.cfg` contient la configuration reconstituée (mot de passe haché). `/var/log/anaconda/` garde tout le déroulé de l'installation. À supprimer en E07 : c'est la fuite la plus classique des images RHEL.

*7. Différences Debian / Rocky qui comptent pour une image* (contenu attendu de `debian-vs-rocky.md`) :

| Sujet | Debian 13 | Rocky Linux 10 |
|---|---|---|
| Installation automatisée | *preseed* (debconf), isolinux en BIOS | *kickstart* (Anaconda), GRUB 2 en BIOS |
| CPU minimal | x86-64 de base (`x86-64-v2-AES` choisi pour la migrabilité) | **x86-64-v3** |
| Paquets | `apt`, `/var/lib/apt/lists`, `unattended-upgrades` | `dnf`, `/var/cache/dnf`, `dnf-automatic` |
| Réseau dans l'image | netplan + `systemd-networkd` + `systemd-resolved` (choix du module) | NetworkManager (profils *keyfile*) ; cloud-init écrit ses profils dans `/etc/NetworkManager/system-connections/` |
| Contrôle d'accès | AppArmor | SELinux `enforcing` : contexte des fichiers déposés (`restorecon`) |
| Pare-feu local | aucun par défaut | `firewalld` actif |
| sudo | groupe `sudo` | groupe `wheel` |
| Traces de l'installeur | `/var/log/installer/` | `/var/log/anaconda/`, `/root/*ks*.cfg` (**mot de passe en clair**) |
| Nom de l'utilisateur cloud-init par défaut | `debian` | `rocky` (renommé `admin` par `ciuser`) |

**Explications**

- **x86-64-v3** : RHEL 10 est compilé pour le niveau de microarchitecture x86-64-v3 (AVX2, BMI2, FMA, MOVBE…). Sous `kvm64` (défaut du plugin) ou `x86-64-v2-AES` (défaut de Proxmox), le noyau ou le chargeur s'arrête dès le démarrage. `x86-64-v3` reste un modèle **générique** (migrable entre hôtes qui le supportent) ; `host` expose tout le processeur réel, au prix de la migrabilité vers un hôte différent.
- **`inst.text`** : l'installation graphique demande plus de mémoire et une console VNC ; en texte, rien à cliquer. **`inst.ks=`** : Anaconda configure le réseau (DHCP) dans l'initramfs pour pouvoir télécharger le kickstart.
- **Le dépôt en ligne** (`url`, `repo`) : l'ISO *boot* ne contient que l'installeur ; on installe directement les versions à jour, comme le *netinst* de Debian.

**Alternatives**

- ISO *minimal* (2 Go, paquets inclus) : installation sans réseau, plus rapide et reproductible à l'instant de l'ISO, mais système moins à jour (mise à jour à faire en provisioner) ; `cdrom` à la place de `url`.
- Image *GenericCloud* de Rocky (qcow2) importée et personnalisée par `proxmox-clone` : rapide ; même discussion que pour Debian (E01, question 9).
- Le kickstart servi sur un volume étiqueté `OEMDRV` (Anaconda le charge seul) : plus de `boot_command` à part le choix de l'entrée, mais il faut créer et téléverser un ISO par build (`cd_files`, privilège `Datastore.AllocateTemplate`).

**Pièges classiques**

- Laisser l'entrée par défaut : vérification du support à chaque build.
- `rootpw` en clair « pour déboguer » : il finit dans `original-ks.cfg` et dans l'image.
- `autopart` sans `--type=plain` : LVM par défaut, racine non extensible par cloud-init.
- `--noswap` oublié : une partition swap après la racine.
- Kickstart non validé : une faute de syntaxe arrête Anaconda sur un écran d'erreur, Packer attend SSH jusqu'au délai maximal.

**En production chez MédiSphère**

Les dérivés RHEL se construisent depuis un miroir interne (dépôts BaseOS/AppStream synchronisés, figés à une date), avec un kickstart relu comme du code. La certification de l'éditeur porte souvent sur une version **mineure** précise : l'image Rocky est alors épinglée sur cette mineure (dépôt `vault` ou miroir figé) plutôt que sur `10` qui avance.

---

### M03-E07 — Provisioners et préparation au clonage

**Solution**

Fichiers : [`fichiers/M03-E07/images/scripts/preparer-clonage.sh`](fichiers/M03-E07/images/scripts/preparer-clonage.sh) et l'extrait du bloc `build` [`provisioners-extrait.pkr.hcl`](fichiers/M03-E07/provisioners-extrait.pkr.hcl) (versions complètes des deux builds : [`fichiers/M03-E08/images/`](fichiers/M03-E08/images/)).

*1. Ce qui doit disparaître.*

| Élément | Debian | Rocky | Recréé sur le clone par | Risque s'il reste |
|---|---|---|---|---|
| Compte de construction, droits sudo | `packer`, `/etc/sudoers.d/90-build-packer` | idem | rien (et c'est voulu) | compte root connu de la chaîne de build dans toutes les VMs |
| Utilisateur cloud-init du build (builds par clonage) | `/etc/sudoers.d/90-cloud-init-users` | idem | cloud-init (`ciuser` du clone) | droits du compte de build |
| Réseau du build | `/etc/netplan/90-build.yaml` | profils `/etc/NetworkManager/system-connections/*.nmconnection` | cloud-init (configuration de la VM) | double configuration, DHCP sur une VM en adresse statique |
| État cloud-init | `/var/lib/cloud/instance*`, `seed/`, journaux | idem | cloud-init | clone considéré comme déjà initialisé (E21) |
| Configurations générées par cloud-init | `50-cloud-init.yaml`, `sshd_config.d/50-cloud-init.conf` | profils NM, idem | cloud-init | réglages d'une autre instance |
| `machine-id` | `/etc/machine-id` (+ `/var/lib/dbus/machine-id` si copie) | idem | systemd au premier démarrage (`uninitialized`) | DHCP, journaux, supervision confondus |
| Clés d'hôte SSH | `/etc/ssh/ssh_host_*` | idem | module `ssh` de cloud-init (Rocky : aussi `sshd-keygen@`) | usurpation entre VMs |
| Graine aléatoire, secret des *credentials* | `/var/lib/systemd/random-seed`, `credential.secret` | idem | systemd | entropie initiale et secrets locaux partagés |
| Baux DHCP | `/var/lib/dhcp/` (si présent) | `/var/lib/NetworkManager/*.lease` | client DHCP | renouvellement d'une adresse d'une autre VM |
| Journaux, historiques | `/var/log/*`, journal, `.bash_history` | idem | — | données du build, chemins, parfois des secrets |
| Caches de paquets | `/var/cache/apt`, `/var/lib/apt/lists` | `/var/cache/dnf` | `apt update` / `dnf` | taille de l'image, métadonnées périmées |
| Traces d'installeur | `/var/log/installer/` | `/var/log/anaconda/`, `/root/original-ks.cfg`, `/root/anaconda-ks.cfg` | — | **mot de passe de build en clair** (Rocky) |
| Temporaires | `/tmp`, `/var/tmp` | idem | — | fichiers du build |

`cloud-init clean` couvre l'état (`/var/lib/cloud`), avec `--logs` ses journaux, `--seed` les données de source mises en cache, `--machine-id` le `machine-id`, `--configs all` les configurations réseau et SSH qu'il a générées.

*2-3. Script et provisioners.* Voir les fichiers. Le script détecte la famille par `/etc/os-release` (`ID_LIKE`), applique tout ce qui précède, puis **vérifie** (`machine-id` à `uninitialized`, aucune clé d'hôte, compte absent, plus de sudoers de build, plus d'état cloud-init, plus de kickstart) et sort en erreur si un contrôle échoue : le build s'arrête et aucun template n'est produit. Il finit par `fstrim` (le disque est en `discard=on` sur LVM-thin : les blocs libérés par le nettoyage reviennent au *thin pool*).

La préparation est le **dernier** provisioner : tout ce qui s'exécute après elle (un provisioner, un `apt install`) peut recréer un journal, un cache, une clé ou un état. Si un provisioner écrivait ensuite dans `/var/log`, la trace partirait dans tous les clones ; c'est pourquoi le script vide les journaux en dernier et que rien ne le suit.

*4.* `userdel --force` supprime un compte même s'il a des processus (la session SSH de Packer) : la session reste ouverte jusqu'à la fin du provisioner. À l'étape suivante, pour un build par clonage, Packer tente de retirer sa clé éphémère de `~/.ssh/authorized_keys` : la commande échoue (compte et dossier supprimés), Packer journalise l'erreur et **continue** (étape « cosmétique » de nettoyage, voir `StepCleanupTempKeys` du SDK). Pas grave. Puis l'arrêt passe par l'agent QEMU, pas par SSH.

*5-6. Preuve.*
```
root@pve01:~# for i in 2030 2031; do qm clone 9001 $i --name m03-prep-$([ $i = 2030 ] && echo a || echo b) --pool lab; \
    qm set $i --tags env-m03 --ipconfig0 ip=dhcp --nameserver 10.10.20.10 --searchdomain par1.medisphere.internal \
    --ciuser admin --sshkeys /root/cle-adm01.pub; qm start $i; done
admin@adm01:~$ for i in 2030 2031; do ssh pve01 "qm guest exec $i -- sh -c 'cat /etc/machine-id; ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub; hostname -I; id packer'" | jq -r '."out-data", ."err-data" // empty'; done
3f9c…
256 SHA256:Qm8… root@m03-prep-a (ED25519)
10.10.99.137
id: 'packer': no such user
8a01…
256 SHA256:Zc4… root@m03-prep-b (ED25519)
10.10.99.142
id: 'packer': no such user
```
En E03, les adresses étaient identiques parce que `systemd-networkd` construit son identifiant de client DHCP (DUID) à partir du `machine-id` : même `machine-id`, même client pour `dns01`, même bail.

**Explications**

- **`uninitialized`** plutôt qu'un fichier vide ou absent : systemd voit alors un « premier démarrage » (`ConditionFirstBoot`, application des *presets*) et écrit un nouvel identifiant (`man machine-id`).
- **Les clés d'hôte** sont régénérées par le module `ssh` de cloud-init (paramètre `ssh_deletekeys`, génération des types de `ssh_genkeytypes`). Conséquence : une image Debian sans source cloud-init démarre **sans** clé d'hôte, et `sshd` refuse de démarrer. Nos templates ont toujours un lecteur cloud-init ; c'est une dépendance assumée, à documenter.
- **Contexte d'exécution des provisioners** : le script est copié dans `/tmp` de la VM, rendu exécutable et lancé par `execute_command` ; `{{ .Vars }}` contient les `environment_vars` (et `PACKER_BUILD_NAME`, `PACKER_BUILDER_TYPE`) ; `sudo env {{ .Vars }} …` les transmet à travers `sudo`, qui sinon les filtrerait.

**Alternatives**

- `virt-sysprep` après le build, hors ligne (sur le disque du template, en root sur `pve01`) : liste d'opérations très complète, mais hors du build Packer (et sur un volume de template, protégé).
- Laisser cloud-init gérer les clés (déjà le cas) et le reste par un service *first-boot* : plus de pièces mobiles.

**Pièges classiques**

- Supprimer `/etc/machine-id` au lieu de le réinitialiser (selon la distribution, le système démarre en lecture seule de ce fichier ou en génère un « transitoire »).
- `rm -rf /tmp/*` : supprime le script en cours (sans dommage tant qu'il est déjà lu, mais un `script` Packer qui suit échouerait).
- `grep -q` ou `head` en fin de tube sous `pipefail` : faux échecs intermittents.
- Oublier les traces d'Anaconda : le mot de passe de build dans toutes les VMs Rocky.
- Vérifications qui « affichent » au lieu d'échouer : un template à moitié préparé passe inaperçu.

**En production chez MédiSphère**

La liste de préparation est un document de sécurité relu (Sophie Laurent), et le test d'image (E14) vérifie sur un clone, à chaque build, l'unicité de l'identité et l'absence de comptes de construction.

---

### M03-E08 — Variables, fichiers de variables et secrets de build

**Solution**

Fichiers : [`fichiers/M03-E08/images/`](fichiers/M03-E08/images/) — `debian13-base/` et `rocky10-base/` complets, [`vars/lab.pkrvars.hcl`](fichiers/M03-E08/images/vars/lab.pkrvars.hcl), [`outils/construire.sh`](fichiers/M03-E08/images/outils/construire.sh).

*1. Précédence observée* (de la plus faible à la plus forte) : variable d'environnement `PKR_VAR_essai` < fichiers `*.auto.pkrvars.hcl` du dossier < options `-var-file` et `-var` **dans l'ordre de la ligne de commande** (la dernière l'emporte). Une valeur par défaut ne sert que si aucune source n'en fournit. Conséquences pour `vars/lab.pkrvars.hcl` (passé par `-var-file`) :
- il ne contient **jamais** de secret (versionné) ;
- il ne contient pas ce qui dépend de la machine ou de l'installation et que l'environnement doit pouvoir fixer : une valeur posée dans ce fichier **écraserait** `PKR_VAR_…` de l'environnement (CI comprise). Le nœud (`<NOEUD>`, propre à chaque installation), l'URL et le jeton viennent donc de l'environnement ; `http_bind_address` aussi (valeur par défaut pour `adm01`, surchargée en CI pour `runner01`).

*2. Variables sûres* (extrait de `variables.pkr.hcl`) :
```hcl
variable "vm_id" {
  type    = number
  default = 9001
  validation {
    condition     = var.vm_id >= 9001 && var.vm_id <= 9099
    error_message = "Le VMID doit être dans la plage des templates construits (9001-9099)."
  }
}
```
et règles analogues sur `proxmox_url` (`^https://[^/]+:8006/api2/json$`) et `proxmox_username` (`^[^@!]+@[^@!]+![A-Za-z0-9_-]+$`). Essais :
```
admin@adm01:~/src/images/debian13-base$ packer validate -var-file=../vars/lab.pkrvars.hcl -var vm_id=1001 .
Error: Invalid value for variable
…
Le VMID doit être dans la plage des templates construits (9001-9099).
```

*3. Mot de passe de build* :
```hcl
local "build_password" {
  expression = uuidv4()
  sensitive  = true
}
```
`uuidv4()` produit une valeur aléatoire ; un `local` est évalué une fois par build, donc la même valeur sert au preseed et au communicateur SSH. Dans la sortie de `packer build`, toute occurrence de la valeur est remplacée par `<sensitive>`. Elle apparaît malgré tout : dans le preseed servi en HTTP (en clair sur le VLAN SANDBOX pendant le build), dans la base debconf de l'installeur et ses journaux (`/var/log/installer/`), dans `original-ks.cfg` pour Rocky. Ce n'est plus un problème : le mot de passe ne vaut que pour **ce** build, le compte est supprimé et les traces effacées par `preparer-clonage.sh`, et rien n'est conservé.

*4. L'outil* : voir [`construire.sh`](fichiers/M03-E08/images/outils/construire.sh). Points de conception :
- accès : l'environnement d'abord (CI), sinon le fichier, refusé s'il n'est pas en 600 (code 3) ; `set -a` / `set +a` exporte les variables vers Packer sans les afficher ; le secret n'est jamais un argument (visible dans `ps`) ;
- traçabilité : `git rev-parse --short=12 HEAD` ; dépôt modifié refusé (code 3) sauf `--brouillon`, et alors commit suffixé `-modifie` ;
- `packer init` (installe le plugin manquant), version du plugin lue dans `packer plugins installed`, `packer validate` avec **les mêmes** options que le build ;
- journal `manifests/build-<image>-<horodatage>.log` (`tee`, code de sortie récupéré par `PIPESTATUS`) ;
- verrou `flock -n` par image ;
- `CHECKPOINT_DISABLE=1` : Packer n'interroge pas HashiCorp pour annoncer les nouvelles versions (pas de sortie réseau inutile depuis la CI).
```
admin@adm01:~/src/images$ outils/construire.sh truc ; echo $?
construire.sh : image inconnue : truc (pas de truc/build.pkr.hcl)
2
admin@adm01:~/src/images$ outils/construire.sh debian13-base
== Construction de debian13-base (commit 4e1f0c9a7b2d, plugin v1.2.4) — journal : …/manifests/build-debian13-base-20261007-142210.log
…
```

*5. Notes du template 9001* après reconstruction :
```
Debian 13 de base installée depuis debian-13.7.0-amd64-netinst.iso (sha256 a7ef94ac…).
Construite le 2026-10-07 14:41 CEST par Packer 1.16.1, plugin proxmox v1.2.4.
Projet plateforme/images, commit 4e1f0c9a7b2d.
```

*6. Secrets.* `gitleaks git --no-banner --redact --verbose .` dans `~/src/images` : aucun résultat attendu. Dans le journal du build : `grep -c '<sensitive>' manifests/build-*.log` montre les remplacements ; aucune valeur de jeton.

**Explications**

- **`sensitive`** masque par **remplacement de chaîne** dans tout ce que Packer affiche ou journalise. Corollaire : une valeur sensible très courte (`x`, `lab`) masque aussi tous les mots qui la contiennent dans les journaux, et une valeur transformée (encodée en base64, hachée) n'est pas reconnue.
- **Supprimer plutôt que protéger** : un mot de passe généré, utilisé et détruit dans le même build n'a pas à être stocké, transmis, renouvelé ni inscrit au registre des secrets.
- **Une seule commande** pour le poste et la CI : la CI (E15) appelle `outils/construire.sh` avec les variables `PKR_VAR_*` de ses variables protégées ; les garde-fous et la traçabilité sont les mêmes.

**Alternatives**

- Fichier `*.auto.pkrvars.hcl` local ignoré par git pour les accès : pratique, mais un fichier de plus contenant un secret, dans l'arborescence du projet (risque de `git add -f`).
- `Taskfile` (M02) ou `Makefile` à la place du script : bien pour les tâches simples ; les garde-fous (droits du fichier, dépôt propre, verrou) se lisent mieux en Bash.
- Paire de clés SSH éphémère générée par l'outil et servie à l'installeur à la place du mot de passe : pas de mot de passe du tout, mais un preseed plus complexe.

**Pièges classiques**

- Mettre `proxmox_node` dans `lab.pkrvars.hcl` : il écrase silencieusement la valeur de l'environnement.
- `export PKR_VAR_proxmox_token=…` tapé dans le shell : dans l'historique.
- `packer build` lancé à la main « pour aller vite » : pas de commit dans les notes, pas de journal, pas de garde-fous.
- Message de validation sans majuscule ou sans point final : Packer refuse la règle (« Invalid validation error message »).

**En production chez MédiSphère**

Les accès viennent du gestionnaire de secrets (module 25) au moment du build ; l'outil de construction est le seul chemin autorisé, et la CI refuse de publier une image dont les notes n'indiquent pas un commit de `main`.

---

### M03-E09 — Image dorée Debian 13 v1

**Solution**

Fichiers : [`fichiers/M03-E09/images/`](fichiers/M03-E09/images/) — [`debian13-gold/build.pkr.hcl`](fichiers/M03-E09/images/debian13-gold/build.pkr.hcl), [`variables.pkr.hcl`](fichiers/M03-E09/images/debian13-gold/variables.pkr.hcl), [`scripts/gold-debian13.sh`](fichiers/M03-E09/images/scripts/gold-debian13.sh), [`fichiers/`](fichiers/M03-E09/images/fichiers/) (CA, `ssh/10-medisphere.conf`, `chrony/ms-ntp-passerelle` et son service, `journald/50-medisphere.conf`, `apt/20auto-upgrades`, `apt/52medisphere-unattended-upgrades`), [`outils/pve.sh`](fichiers/M03-E09/images/outils/pve.sh) et [`outils/finaliser-template.sh`](fichiers/M03-E09/images/outils/finaliser-template.sh).

Construction (VMID choisi à la main dans cette v1, après vérification ; E10 l'automatise) :
```
admin@adm01:~/src/images$ ssh pve01 pvesh get /cluster/nextid --vmid 9010
9010
admin@adm01:~/src/images$ outils/construire.sh debian13-gold -var vm_id=9010 -var version=20261007-1
```

Choix de conception :
- **Build par clonage** (`proxmox-clone`, clone complet de 9001) : l'installation est faite une fois (image de base), l'image dorée ne fait que l'enrichir ; clone **complet** pour que le template doré ne dépende pas du disque de 9001, qui est reconstruit.
- **Chaque exigence vérifiée** dans `gold-debian13.sh` : CA présente dans le magasin consolidé, `sshd -T` effectif, origines d'`unattended-upgrades`, services activés. Un écart fait échouer le build.
- **CA provisoire** : certificat **public** versionné dans `fichiers/ca/`, installé dans `/usr/local/share/ca-certificates/` puis `update-ca-certificates`.
- **`sshd`** : fichier `10-medisphere.conf`. `sshd` retient la **première** valeur lue pour chaque mot-clé et lit `sshd_config.d/*.conf` par ordre alphabétique avant le reste de `sshd_config` ; cloud-init écrit `50-cloud-init.conf` (`PasswordAuthentication yes` si on lui demande `ssh_pwauth`) : « 10- » passe devant, quoi que cloud-init écrive.
- **`chrony`** : sources Internet (`pool`) commentées, `sourcedir /etc/chrony/sources.d` ; un service `ms-ntp-passerelle` (après `network-online.target`) lit la **route par défaut** du clone, écrit `server <passerelle> iburst` dans `/etc/chrony/sources.d/passerelle.sources` et fait `chronyc reload sources`. Fonctionne en DHCP comme en statique, dans n'importe quel VLAN. Limite assumée : un changement de passerelle à chaud n'est pris en compte qu'au redémarrage (ou en relançant le service). Le fichier écrit pendant le build est supprimé.
- **Journal** : `Storage=persistent` (avec plafond `SystemMaxUse=200M`) dans `journald.conf.d/` : explicite, quelle que soit la valeur par défaut de la distribution.
- **`unattended-upgrades`** : la liste par défaut de `50unattended-upgrades` contient `label=Debian` (mises à jour de la version intermédiaire) **et** les sécurités ; une liste redéfinie dans un autre fichier **s'ajoute** à la première. `#clear Unattended-Upgrade::Origins-Pattern;` (directive de `apt.conf`) la vide avant de ne déclarer que `codename=${distro_codename}-security,label=Debian-Security`. Contrôle : `apt-config dump | grep Origins-Pattern`.
- **Valeurs par défaut cloud-init du template** : Packer retire `nameserver` et `searchdomain` avant la conversion (E03) ; un clone qui n'en préciserait pas hériterait de ceux de **l'hyperviseur** (comportement documenté de Proxmox : « same setting as on the host »), injoignables depuis le lab. Un post-processor `shell-local` appelle `outils/finaliser-template.sh`, qui les repose par l'API (`PUT …/config`, privilège `VM.Config.Cloudinit`). ⚠️ À vérifier sur ta version : Proxmox accepte cette modification sur un template (ce sont des options, pas des disques) ; si elle était refusée, les consommateurs devraient toujours préciser le résolveur.
- **Pas de mise à niveau au premier démarrage** : `cloud_init_disable_upgrade_packages = true` pose `ciupgrade: 0` sur le template ; sinon le *user-data* de Proxmox contient `package_upgrade: true` et chaque clone passe plusieurs minutes à se mettre à jour (et diffère de l'image testée).

Recette :
```
root@pve01:~# qm clone 9010 2034 --name m03-gold-test --pool lab
root@pve01:~# qm set 2034 --tags env-m03 --net0 virtio,bridge=vinfra \
    --ipconfig0 ip=10.10.20.49/24,gw=10.10.20.1 --ciuser admin --sshkeys /root/cle-adm01.pub && qm start 2034
admin@adm01:~$ ssh admin@10.10.20.49 'cloud-init status; id packer; chronyc -n sources; resolvectl dns; sudo sshd -T | grep -E "^(permitrootlogin|passwordauthentication) "'
status: done
id: 'packer': no such user
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^* 10.10.20.1                    3   6    17    12   +105us[ +180us] +/-   18ms
Global:
Link 2 (eth0): 10.10.20.10
permitrootlogin no
passwordauthentication no
```
(Valeurs indicatives.) Le résolveur 10.10.20.10 vient du template, sans avoir été précisé au clonage.

**Explications**

- **Ce qui est dans l'image, ce qui vient du clonage** : l'image ne contient aucun utilisateur humain, aucune clé, aucune adresse ; cloud-init apporte `admin`, sa clé, le nom, l'adresse. Le résolveur et le domaine sont des valeurs par défaut du **template** (configuration Proxmox), pas de l'image : un clone peut les surcharger.
- **Vérifier pendant le build** : un réglage appliqué mais non vérifié peut être annulé par un paquet, un ordre de lecture, une valeur par défaut ; le build est le meilleur endroit pour l'attraper, avant qu'un clone n'existe.

**Alternatives**

- **NTP par DHCP** (option 42 fournie par `dns01`, `sourcedir /run/chrony-dhcp`) : élégant en DHCP, inopérant en adresse statique.
- **Module `ntp` de cloud-init** dans un *vendor-data* par VLAN : un snippet par VLAN, dépendance à `hdd-bulk`.
- **Adresse fixe unique** (`gw01` sur une adresse de service routée) : simple, mais contraire à la règle du lab et à la tolérance aux pannes futures (`gw02`, VRRP au module 07).
- **Contenu par Ansible** sur un build Packer (provisioner `ansible`) : réutilise les rôles du module 04 (base, ssh durci) ; c'est l'évolution naturelle quand les rôles existeront.

**Pièges classiques**

- `sshd_config.d/90-medisphere.conf` : cloud-init (50-) passe devant, le durcissement est ignoré en silence.
- `Origins-Pattern` redéfini sans `#clear` : les mises à jour non-sécurité continuent.
- Oublier de neutraliser `sourcedir /run/chrony-dhcp` ou les lignes `pool` : `chrony` va chercher l'heure sur Internet.
- Template sans résolveur par défaut : les clones en adresse statique ne résolvent rien (et leur cloud-init échoue à installer quoi que ce soit).
- Clone **lié** de 9001 pour l'image dorée : 9001 ne peut plus être reconstruit.

**En production chez MédiSphère**

Le contenu de l'image dorée suit un référentiel (CIS, ANSSI) relu par la sécurité (E13), avec un contrôle de conformité automatique sur chaque clone de test (E14). Les clés de la CA sont celles de step-ca après le module 06 (le certificat de `fichiers/ca/` change, l'image est reconstruite).

---

### M03-E10 — Versionner et publier les images

**Solution**

Fichiers : [`fichiers/M03-E10/images/`](fichiers/M03-E10/images/) — [`outils/version-image.sh`](fichiers/M03-E10/images/outils/version-image.sh), [`outils/publier-image.sh`](fichiers/M03-E10/images/outils/publier-image.sh), [`outils/construire.sh`](fichiers/M03-E10/images/outils/construire.sh) (version E10), [`outils/pve.sh`](fichiers/M03-E10/images/outils/pve.sh) (fonctions `pve_premier_libre`, `pve_famille` ajoutées), [`scripts/manifeste-paquets.sh`](fichiers/M03-E10/images/scripts/manifeste-paquets.sh), [`debian13-gold/build.pkr.hcl`](fichiers/M03-E10/images/debian13-gold/build.pkr.hcl), [`tests/tester-image.sh`](fichiers/M03-E10/images/tests/tester-image.sh) (copie du test minimal fourni).

*1. Le test minimal* vérifie qu'un clone **démarre et s'administre** : clone lié, cloud-init `status --wait` à 0 (ni erreur ni avertissement), connexion SSH par clé, `sudo -n`, agent. Il ne vérifie ni l'unicité de l'identité, ni le temps, ni `sshd`, ni la CA, ni les mises à jour (E14). `ControlPath=none` : sur `adm01`, `~/.ssh/config` active le multiplexage (`ControlMaster auto`, M00-E15) ; une connexion maîtresse déjà ouverte vers la même adresse (une ancienne VM de test qui avait la même IP) serait **réutilisée** et le test parlerait à la mauvaise machine. La clé SSH est encodée en URL **avant** d'être envoyée : l'API de Proxmox attend un paramètre `sshkeys` déjà encodé (piège de M00-E18), que `curl --data-urlencode` encode une seconde fois comme paramètre de formulaire.

*2. Version et VMID.*
```
admin@adm01:~/src/images$ outils/version-image.sh debian13
9011 20261007-2
```
VMID : premier de la plage pour lequel `GET /cluster/nextid?vmid=N` répond (libre sur **tout** le cluster, y compris si une VM hors du pool l'occupe, invisible pour le jeton). Version : `AAAAMMJJ-N`, N = 1 + plus grand N du jour parmi les noms `deb13-gold-<jour>-N` visibles. Plage pleine : code 3 et message « appliquer la rotation » : on ne déborde jamais dans une autre plage.

*3. Manifeste.* Dans `debian13-gold/build.pkr.hcl` : `manifeste-paquets.sh` (liste `nom<TAB>version`, triée en locale `C`, donc stable) puis provisioner `file` en `direction = "download"` vers `manifests/<nom>-paquets.txt`, **avant** la préparation au clonage (après elle, les caches et le compte ont disparu, et l'étape doit rester la dernière) ; post-processor `manifest` (`manifests/<nom>.json`, `custom_data` : image, version, famille, source, commit, versions de Packer et du plugin). `construire.sh` (version E10) appelle `version-image.sh` pour une image dorée sans `-var vm_id=`.

*4. Publication.* Décisions dans le code de `publier-image.sh` :
- ordre : **retirer** `current` de l'ancienne version, **puis** la poser sur la nouvelle. Pendant un instant, aucune image n'est `current` : un consommateur qui lit à ce moment **échoue** bruyamment (« aucune image courante ») et sera relancé. L'ordre inverse donnerait un instant avec **deux** `current` : un consommateur qui prend « la première » pourrait choisir l'ancienne en silence. On préfère l'échec visible à l'erreur silencieuse ;
- image déjà `current` : rien à faire, code 0 (idempotent) ;
- contrôle final : exactement une `current` dans la famille, sinon code 1 et message d'anomalie ;
- refus (code 3) si ce n'est pas un template `gold` d'une famille connue, si le test est absent ou en échec ;
- notes complétées (date, auteur technique, test, empreinte de la liste des paquets) avant de poser l'étiquette.
```
admin@adm01:~/src/images$ outils/construire.sh debian13-gold
== debian13-gold : VMID 9011, version 20261007-2
…
admin@adm01:~/src/images$ outils/publier-image.sh --dry-run 9011
== Test de 9011 (deb13-gold-20261007-2)
== Clone lié 9011 → 2030 (m03-test-9011)
…
  [OK] cloud-init a terminé sans erreur
…
[simulation] 9011 : notes complétées :
Publiée le 2026-10-07 15:32 CEST par wb-packer@pve après succès de tests/tester-image.sh.
Paquets : 412 paquets, sha256 6d2d….
== Retrait de current sur 9010
[simulation] 9010 : tags=debian13;gold
== Pose de current sur 9011 (deb13-gold-20261007-2)
[simulation] 9011 : tags=current;debian13;gold
admin@adm01:~/src/images$ outils/publier-image.sh 9011
…
deb13-gold-20261007-2 (9011) publiée : gold;debian13;current
admin@adm01:~/src/images$ CLE_SSH=/nonexistent outils/publier-image.sh 9010; echo $?
…
REFUS : test en échec : deb13-gold-20261007-1 n'est PAS publiée
3
```
(Valeurs indicatives.)

*6.* La v1 de E09 (9010) reste un template doré, sans `current` ; la rotation (E16) la retirera quand trois versions plus récentes existeront.

**Explications**

- **La version n'est pas le VMID** : le VMID est un emplacement réutilisable (la rotation libère des places), la version identifie un contenu. Les consommateurs utilisent les étiquettes, les humains lisent le nom et les notes.
- **Le test conditionne la publication** : `current` signifie « testée et choisie », pas « la plus récente ». Un build réussi n'est pas une image publiable.
- **Les étiquettes** se modifient par `PUT …/config` (`tags`, privilège `VM.Config.Options`). ⚠️ Le réglage de centre de données `user-tag-access` peut restreindre les étiquettes qu'un utilisateur non root peut poser (valeur par défaut : libre) : à vérifier si un refus apparaît.

**Alternatives**

- Version sémantique (`1.4.0`) : pertinente pour un logiciel dont l'interface change ; pour une image reconstruite chaque semaine à contenu équivalent, la date dit l'essentiel (fraîcheur des correctifs).
- Étiquette par version (`v20261007-2`) : les étiquettes Proxmox ne sont pas faites pour des valeurs uniques ; le nom et les notes suffisent.
- Registre externe (NetBox, M06, ou un catalogue dans `docs/socle/images.md`) : complément pour l'audit, pas un remplaçant de l'étiquette lue par les outils.

**Pièges classiques**

- Calculer le VMID libre avec `/cluster/resources` : une VM hors pool est invisible et le VMID « libre » est déjà pris (échec du build, ou pire avec `-force`).
- Rapatrier la liste des paquets après la préparation : liste faussée (paquets de build déjà purgés) ou fichier absent.
- `custom_data` avec un nombre : le post-processor attend des chaînes (`"${var.base_vm_id}"`).
- Publier sans tester « parce que le build est vert ».

**En production chez MédiSphère**

La publication est un job de pipeline protégé (E15), déclenché après le test ; elle enregistre aussi la version dans le catalogue documentaire (E25) et notifie les équipes consommatrices. Le manifeste JSON est signé (pour aller plus loin), et les consommateurs pourraient vérifier la signature avant d'utiliser une image (module 13 pour les conteneurs).

---

### M03-E11 — cloud-init avancé : vendor-data, multi-part, réseau v2

**Solution**

Fichiers : [`fichiers/M03-E11/`](fichiers/M03-E11/) — [`m03-e11-config.yaml`](fichiers/M03-E11/m03-e11-config.yaml) (partie 1, Jinja), [`m03-e11-inscription.sh`](fichiers/M03-E11/m03-e11-inscription.sh) (partie 2), [`m03-e11-network.yaml`](fichiers/M03-E11/m03-e11-network.yaml), [`fabriquer-vendor.sh`](fichiers/M03-E11/fabriquer-vendor.sh).

*1. Assemblage.*
```
admin@adm01:~/m03/e11$ ./fabriquer-vendor.sh
Valid schema m03-e11-network.yaml
Valid schema m03-e11-config.rendu.yaml
2
m03-e11-vendor.mime prêt
admin@adm01:~/m03/e11$ scp m03-e11-vendor.mime m03-e11-network.yaml pve01:/mnt/hdd-bulk/snippets/
```
(`2` : nombre de parties.) La partie Jinja est rendue avec les données d'instance d'`adm01` (`cloud-init devel render`) pour valider la configuration **rendue** : un gabarit peut produire du YAML invalide.

*2. Fusion.* Les configurations issues du *user-data* et du *vendor-data* sont fusionnées clé par clé, le *user-data* l'emportant : une clé de premier niveau présente dans les deux (par exemple `runcmd`, `packages`) prend **la valeur du *user-data*** et celle du *vendor-data* est ignorée (pas de concaténation des listes, sauf directive `merge_how`). Le *user-data* de Proxmox ne contient que `hostname`, `fqdn`, `manage_etc_hosts`, `user`, `ssh_authorized_keys`, `chpasswd`, `users`, `package_upgrade` : nos clés n'entrent pas en conflit. Passer la configuration par `cicustom user=` **remplacerait** ce *user-data* : plus d'utilisateur `admin`, plus de clé SSH (piège de M00-E11).

*3. VM et ce que fournit Proxmox.*
```
root@pve01:~# qm clone <VMID-CURRENT> 2032 --name m03-ci-avance --pool lab
root@pve01:~# qm set 2032 --tags env-m03 --net0 virtio=BC:24:11:03:20:32,bridge=vsandbox \
    --ciuser admin --sshkeys /root/cle-adm01.pub \
    --cicustom "vendor=hdd-bulk:snippets/m03-e11-vendor.mime,network=hdd-bulk:snippets/m03-e11-network.yaml"
root@pve01:~# qm cloudinit dump 2032 network | head -3
# m03-e11-network.yaml — network-config v2 de la VM 2032 m03-ci-avance (M03-E11).
…
```
`<VMID-CURRENT>` : le template `gold` + `debian13` + `current` (`pvesh get /cluster/resources --type vm` puis filtre sur les étiquettes). Avec `cicustom network=`, Proxmox ne génère plus la configuration réseau : `ipconfig0`, `nameserver` et `searchdomain` sont **ignorés** (le résolveur doit être dans le fichier). L'identifiant d'instance reste l'empreinte du *user-data* et du réseau, désormais **le contenu du snippet**.

*4. Contrôle.*
```
admin@adm01:~$ ssh admin@10.10.99.251 'ip -br a show eth0; resolvectl dns eth0; cat /etc/motd; git --version; cat /var/lib/mediagenda/inscription; cat /var/log/mediagenda-demarrages.log; cloud-init status; echo $?'
eth0             UP             10.10.99.251/24 …
Link 2 (eth0): 10.10.20.10
VM de développement MédiAgenda — instance 6b1d…
debian trixie, plateforme nocloud.
Aucune donnée de patient réelle sur cette VM.
git version 2.47.3
inscrite le 2026-10-07T16:02:44+02:00
instance 6b1d…
adresses 10.10.99.251
demarrage 2026-10-07T16:02:10+02:00
status: done
0
```
(Valeurs indicatives.) Après un redémarrage : une ligne de plus dans `mediagenda-demarrages.log` (`bootcmd`, à chaque démarrage) ; `motd`, `git`, inscription inchangés (une fois par instance).

*5.* Ajouter un serveur DNS modifie le snippet réseau, donc l'identifiant d'instance : **nouvelle instance**, l'inscription est refaite (nouvelle date, nouvel identifiant), les clés d'hôte SSH sont régénérées, le `motd` réécrit. Pour Julien, ce n'est pas souhaitable : une modification réseau anodine « réinscrit » la VM et change ses clés. Un script d'inscription doit donc être **idempotent** côté inventaire (mise à jour plutôt que création), et une modification réseau d'une VM durable passe par Ansible (M04), pas par cloud-init.

*6. Réponse à Julien* (éléments attendus) : faisable sans toucher à l'image (*vendor-data* multi-part + réseau) ; limites : un snippet réseau **par VM** (il contient l'adresse), la configuration Proxmox (`ipconfig0`) ne dit plus la vérité, les snippets sont lisibles par quiconque lit `hdd-bulk` (aucun secret), toute VM qui les référence **ne démarre plus** si `hdd-bulk` est hors ligne (Proxmox régénère le lecteur cloud-init à chaque démarrage), et chaque modification réseau crée une nouvelle instance ; ce qui relève d'Ansible : l'installation et la mise à jour d'outils, l'inscription dans l'inventaire (NetBox au module 06), les changements après création.

**Explications**

- **Multi-part** : un *vendor-data* MIME peut mêler des parties de types différents (`text/cloud-config`, `text/x-shellscript`, `text/jinja2`, …) ; chaque partie est traitée par son gestionnaire. Les scripts d'un *vendor-data* sont rangés à part (`/var/lib/cloud/instance/scripts/vendor/`) et lancés à l'étape Final par `scripts_vendor`, une fois par instance.
- **Jinja** : la première ligne `## template: jinja` indique un gabarit, rendu **dans la VM** avec ses données d'instance (`/run/cloud-init/instance-data.json`) avant d'être traité selon sa deuxième ligne (`#cloud-config`).
- **Réseau v2** : syntaxe de netplan ; `match` + `set-name` nomment l'interface ; `routes` remplace `gateway4` (déprécié) ; `nameservers` est porté par l'interface et appliqué par `systemd-resolved`.

**Alternatives**

- Mettre l'adresse dans `ipconfig0` et les deux DNS dans `--nameserver "10.10.20.10 10.10.20.16"` : Proxmox génère la configuration (v1), pas de snippet par VM ; c'est la bonne solution tant qu'on n'a pas besoin de fonctions avancées (routes supplémentaires, *bonds*, VLAN dans la VM).
- Données d'instance personnalisées : cloud-init 25.1 sait lire une source *NoCloud* dont le `meta-data` est fourni par `cicustom meta=` ; on pourrait y placer des informations propres à la VM (équipe, rôle) utilisables par Jinja.

**Pièges classiques**

- `cicustom` en plusieurs `qm set` successifs : chaque appel **remplace** toute la valeur (`vendor=` puis `network=` → seul le dernier reste) ; tout mettre dans une seule option, séparé par des virgules.
- Adresse MAC du snippet en minuscules et celle de Proxmox en majuscules : la correspondance est faite sans tenir compte de la casse par netplan (⚠️ à vérifier sur ta version si l'interface n'est pas reconnue) ; en cas de doute, écris-la comme dans `qm config`.
- Gabarit Jinja validé sans rendu : `cloud-init schema` sur le fichier brut ne voit pas les erreurs produites par le rendu.
- Script de *vendor-data* non idempotent : rejoué à chaque nouvelle instance.

**En production chez MédiSphère**

Les *vendor-data* communs sont versionnés dans `plateforme/images` (ou dans le module OpenTofu qui crée les VMs, M05), déposés par l'outillage, jamais à la main ; le réseau des VMs durables vient de NetBox (M06) par OpenTofu.

---

### M03-E12 — Revue du template Packer d'un stagiaire

**Lecture du build** (ce qui se passerait) : Packer se connecte à l'API en **`root@pam`** sans vérifier le certificat ; il télécharge l'ISO sur `adm01` **sans aucun contrôle** et la téléverse dans `local` (disque système de `pve01`) ; il crée une VM avec le premier VMID libre, hors de tout pool, carte sur **`vmbr0`** (LAN maison) ; il ouvre un serveur HTTP sur **toutes** les interfaces d'`adm01`, qui sert **tout le dossier**, dont `build.pkr.hcl` avec le mot de passe de `root@pam` ; l'installeur prend une adresse de la box, lit le preseed, installe avec une IP fixe du LAN maison et un mot de passe root connu ; Packer se connecte en `root` par mot de passe, exécute un script téléchargé sur Internet ; le template garde l'IP fixe, le mot de passe root, `PermitRootLogin yes`, pas de cloud-init, ses clés d'hôte et son `machine-id`.

`packer validate` : avertissements de dépréciation pour `iso_url`, `iso_checksum`, `iso_storage_pool`, `unmount_iso` (bloc `boot_iso` attendu), et « A checksum of 'none' was specified ».

**Revue**

| N° | Fichier : ligne(s) | Défaut | Catégorie | Gravité | Impact concret | Correction |
|---|---|---|---|---|---|---|
| 1 | build : 6-7, 39 ; preseed : 16-17 | Mot de passe de **`root@pam`** en clair dans un fichier destiné à la forge, réutilisé comme mot de passe root de l'image | Sécurité | **Critique** | Quiconque lit le dépôt (ou le serveur HTTP, n° 3) administre l'hyperviseur entier et toutes les VMs issues de l'image | Jeton dédié `wb-packer@pve!packer` par l'environnement (E02, E08) ; changer **immédiatement** le mot de passe root de `pve01` s'il a été poussé ; jamais de mot de passe permanent dans l'image |
| 2 | preseed : 16-17, 31 ; build : 38 | Compte `root` à mot de passe connu, `PermitRootLogin yes` | Sécurité | **Critique** | Toutes les VMs clonées acceptent `root` avec le même mot de passe : une fuite = tout le parc | Pas de mot de passe root, compte de construction jetable supprimé (E05-E07), `sshd` durci (E09) |
| 3 | build : 30 (+ absence de `http_bind_address`) | `http_directory = "."` sur toutes les interfaces | Sécurité | **Critique** | Pendant chaque build, n'importe quel appareil du LAN maison peut télécharger `build.pkr.hcl` (mot de passe root@pam) | `http_content` avec les seuls fichiers nécessaires, `http_bind_address` et ports fixés (E05) |
| 4 | build : 8 | `insecure_skip_tls_verify = true` | Sécurité | **Élevée** | Le mot de passe root@pam part vers quiconque s'interpose | Vérification TLS avec l'autorité de `pve01` dans le magasin système (E02) |
| 5 | build : 13-16 | ISO téléchargée sans somme ni signature (`iso_checksum = "none"`), options dépréciées | Sécurité / exploitation | **Élevée** | Une ISO altérée (miroir, proxy) devient le socle de toutes les VMs ; options qui disparaîtront | ISO déposée après vérification de signature et somme, bloc `boot_iso` (E05) |
| 6 | build : 27 ; preseed : 4-9 | VM de build sur `vmbr0` (LAN maison), IP fixe 192.168.1.150 inscrite dans l'image | Sécurité / fonctionnement | **Élevée** | Le build contourne le pare-feu de `gw01` ; **chaque clone** démarre avec 192.168.1.150 (conflit d'adresses sur le LAN maison) ; les clones dans un VLAN du lab n'ont pas de réseau | Build sur `vsandbox` en DHCP ; aucune configuration réseau propre à une machine dans l'image (cloud-init) |
| 7 | build : 46-53 | `curl … \| bash` d'un script Internet, en root, sans vérification | Sécurité (chaîne d'approvisionnement) | **Élevée** | Le contenu du script peut changer entre deux builds ; une compromission du site entre dans toutes les images | Paquet signé, ou fichier versionné dans le projet avec empreinte vérifiée ; sinon, pas dans l'image (Ansible) |
| 8 | build : absence de `cloud_init`, `qemu_agent` ; preseed : 26 | Pas de cloud-init dans l'image ni de lecteur sur le template, pas d'agent | Fonctionnement | **Élevée** | Impossible de donner un nom, une adresse, un utilisateur ou une clé à un clone ; pas d'IP ni d'arrêt propre par l'agent | Paquets `cloud-init`, `qemu-guest-agent`, `cloud_init = true` (E05) |
| 9 | build : tout le bloc `build` | Aucune préparation au clonage | Sécurité | **Élevée** | Clés d'hôte SSH et `machine-id` identiques dans tous les clones (E03, E07) | `scripts/preparer-clonage.sh` en dernier provisioner |
| 10 | build : 9-11 (absence de `vm_id`, `pool`) | VMID « premier libre », hors pool `lab` | Exploitation | Moyenne | Le template peut prendre un VMID de la plage du socle ou de tes VMs perso ; hors pool : pas de sauvegarde `lab-nuit`, invisible pour les outils du lab | `vm_id` explicite contrôlé par validation, `pool = "lab"` (E08) |
| 11 | build : 18 (et absence de `cpu_type`, `scsi_controller`, `os`) | Matériel par défaut du plugin : `kvm64`, contrôleur `lsi`, 1 Go, OS `other`, pas de console série | Fonctionnement | Moyenne | Performances disque dégradées, pas de console série, instructions CPU modernes absentes | Matériel des templates du lab (introduction) |
| 12 | build : 15 | ISO téléversée dans `local` à chaque build | Exploitation | Moyenne | Remplit le disque système de `pve01` (800 Mo par version), hors du stockage prévu | ISO sur `hdd-bulk`, déposée une fois |
| 13 | preseed : 22 | Recette `atomic` (swap après la racine) | Fonctionnement | Faible | La racine d'un clone ne s'agrandit pas avec son disque | Partition racine unique en dernier (E05) |
| 14 | build : 1-2, 11 (absence de bloc `packer`, nom sans version, pas de notes) | Plugin non déclaré (`required_plugins`), template `debian-gold` non versionné, sans manifeste | Exploitation | Faible | `packer init` impossible sur un autre poste, version du plugin au hasard ; impossible de savoir ce que contient le template ni de le remplacer proprement | Bloc `packer` avec version contrainte, nom `deb13-gold-AAAAMMJJ-N`, notes et manifeste (E10) |

Remarques mineures, non comptées : `pkgsel/upgrade none` (image construite sans les derniers correctifs) ; `vim`, `htop` dans une image de base ; locale `fr_FR` (messages d'erreur moins faciles à rechercher, choix discutable) ; domaine `maison`.

**Ordre de traitement** : d'abord ce qui est **déjà** un incident si le fichier a quitté son poste (1, 3 : changer le mot de passe root de `pve01`, vérifier que rien n'a été poussé), puis ce qui expose les VMs (2, 4, 5, 6, 7, 9), puis ce qui rend l'image inutilisable (8, 10, 11), puis l'hygiène (12-14).

**Recommandation** : ne pas corriger ce fichier ligne à ligne ; repartir de `debian13-gold/` du projet (image dorée par clonage de `tpl-debian13-base`) et y apporter, s'il y en a, les besoins réels de l'équipe MédiAgenda (par un *vendor-data*, E11, ou un rôle Ansible, M04). Les versions corrigées de référence sont celles de E08 (base) et E10 (dorée).

**Conseils à Lucas sur sa méthode**
- « Ça marche » prouve que le build termine, pas que l'image est sûre ni utilisable : clone-la deux fois et compare (E03), essaie-la dans un VLAN du lab, en adresse statique.
- Un fichier qui contient un mot de passe ne se « corrige plus tard » : dès qu'il a été partagé (dépôt, serveur HTTP, capture d'écran), le secret est à changer.
- Lis les avertissements de `packer validate` : ici, ils signalaient déjà deux défauts.

**Explications**

Les défauts les plus graves sont invisibles quand on teste « est-ce que le build passe » : ils tiennent à **qui** se connecte (root@pam), à **ce qui est exposé** pendant le build (serveur HTTP, réseau), et à ce que **héritent les clones** (mots de passe, IP, identité). Une revue d'image suit le chemin du build puis celui d'un clone.

**Alternatives**

Pour une équipe qui veut « son » image : une image dorée commune + un *vendor-data* ou un rôle Ansible d'équipe, plutôt qu'une image par équipe (prolifération, E01 question 12).

**Pièges classiques**

- Relire seulement le fichier HCL et pas le preseed (la moitié des défauts y est).
- Proposer de « chiffrer le mot de passe dans le fichier » : le problème est le compte (root@pam) et sa présence dans un dépôt, pas son format.

**En production chez MédiSphère**

Toute MR sur `plateforme/images` passe par Gitleaks (secrets), `packer validate` en CI (E15) et une revue par un pair ; une image n'est consommable qu'après le pipeline de test et de publication, quel que soit son auteur.
