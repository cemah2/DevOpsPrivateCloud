# Module 11 — Introduction : le provisioning bare-metal

## Des palettes de serveurs

Jeudi, 8 h 40. OpenStack tourne, le cluster Proxmox imbriqué a été reconstruit deux fois depuis le code. Karim Benali pose sur ton bureau un bon de livraison : trente-deux serveurs pour PAR1, livrés en trois vagues à partir du mois prochain.

> **De** : Karim Benali — Ingénieur plateforme senior
> **À** : toi
> **Cc** : Claire Morel, Sophie Laurent, Nadia Roussel
> **Objet** : Provisioning bare-metal — plus jamais de clé USB
>
> Salut,
>
> Tu as vu le bon de livraison. Chez InfoGér, un serveur neuf, c'était une demi-journée : clé USB, écran et clavier sur un chariot, réponses tapées à la main, mot de passe root noté dans un tableur, et une machine qui ne ressemblait à aucune autre. Trente-deux comme ça, c'est deux semaines perdues et trente-deux serveurs différents.
>
> Ce que je veux à la fin du module :
> 1. un **réseau de provisioning** (VLAN 60) : un serveur branché qui démarre sur le réseau trouve tout seul de quoi s'installer, en BIOS comme en UEFI ;
> 2. des installations **sans intervention** de Debian 13 et de Rocky Linux 10, et d'un nœud Proxmox VE, avec nos standards dès le premier démarrage (compte `admin`, clé SSH, racine de la PKI) ;
> 3. **NetBox décide** : un serveur déclaré « prévu » s'installe avec le nom, l'adresse et le système que NetBox lui donne, puis passe « actif » et entre dans l'inventaire Ansible ;
> 4. l'alimentation **pilotée à distance** par le contrôleur de gestion (IPMI, Redfish), pas par quelqu'un dans la salle ;
> 5. une **évaluation de MAAS** de Canonical face à notre chaîne maison : Claire veut un ADR avant de signer quoi que ce soit.
>
> Le seul vrai serveur que nous ayons sous la main, c'est `hp01`, et il porte PBS : on lit son iLO, on ne le réinstalle **jamais**. Les « serveurs » du module sont des VMs vides qui démarrent en PXE.
>
> Sophie a déjà ses questions : qui peut démarrer quoi sur le VLAN 60, où sont les mots de passe des installations, et qui a accès aux iLO. Prépare tes réponses.
> Karim

---

## Ce que tu construis dans ce module

À la fin du module 11, la documentation porte l'étiquette **`provisioning-v1`** (dépôt `plateforme/medisphere`) et le projet GitLab **`plateforme/provisioning`** contient la chaîne complète :

- le **VLAN 60 PROV** servi par Kea (`dns01`/`dns02`, sous-réseau `id: 60`) à travers le relais des passerelles, avec des **classes** qui reconnaissent un client PXE BIOS, un client PXE UEFI et iPXE ;
- **`pxe01`** : TFTP (`tftpd-hpa`) pour les chargeurs iPXE, HTTP (nginx) pour les scripts iPXE, les noyaux et les fichiers d'installation, avec des installateurs téléchargés **et vérifiés** (signatures, empreintes) ;
- des **preseed** (Debian) et **kickstart** (Rocky) validés en CI, générés pour chaque serveur depuis **NetBox** (équipements `bm01` à `bm04`, rôle `serveur-bm`) ;
- un outil de **pilotage d'alimentation** (API Proxmox pour les VMs `bm*`, Redfish pour l'iLO de `hp01`) ;
- **MAAS 3.7** sur `maas01`, essayé de bout en bout sur les mêmes machines, puis évalué dans l'ADR-0110 ;
- au palier 3 et au mini-projet : la chaîne authentifiée (iPXE construit par nos soins, HTTPS de bout en bout), l'installation d'un nœud Proxmox VE, la boucle complète NetBox → serveur en service, l'inventaire matériel de `hp01` lu sur son iLO.

Le **palier 1** pose le réseau de démarrage et les deux installations automatiques ; le **palier 2** branche NetBox, le contrôleur de gestion et MAAS ; le **palier 3** sécurise la chaîne, l'étend à Proxmox VE, la rend autonome et tranche entre MAAS et la chaîne maison ; le **palier 4** la casse et la lit sur le fil ; le **mini-projet** la livre comme un service.

## Architecture du module

```
  adm01 (1001) 10.10.10.10 — VLAN 10 MGMT          LAN maison <LAN-MAISON>
  ~/src/provisioning · outils/alim.sh                ├── pve01 :8006 (API Proxmox)
     │ SSH, HTTP, API                                ├── hp01 = pbs01 (PBS, jamais réinstallé)
     │                                               └── iLO 4 de hp01 <IP-ILO-HP01> :443 (Redfish), UDP 623 (IPMI)
 ════╪══════════ gw01 / gw02 (VRRP, VIP .1) : routage, pare-feu, NAT, relais DHCP (VLAN 99 et 60) ═══
     │                          │ relais (giaddr .2/.3)                       ▲ adm01 → iLO (443, 623)
     │   VLAN 20 INFRA          ▼                                             │ maas01 → pve01:8006 (E10)
     │   dns01 .10 / dns02 .16 : Kea DHCPv4 (HA), sous-réseau id 60, classes PXE, réservations par MAC
     │   nbx01 .13 : NetBox (équipements bm01-04, plateformes, statut planned → active)
     │
     │   VLAN 60 PROV 10.10.60.0/24 (vprov)
  ┌──┴──────────────────────────────────────────────────────────────────────────────────────────┐
  │ pxe01 (2111) .10  tftpd-hpa :69 (/srv/tftp : undionly.kpxe, ipxe.efi)                          │
  │                   nginx :80, puis :443 en E13 (/srv/http : boot.ipxe, ipxe/, preseed/,         │
  │                                kickstart/, debian13/, rocky10/, pki/, pve/ en E14)              │
  │ maas01 (2116) .11 MAAS 3.7 (snap) + PostgreSQL 16, Ubuntu 24.04 — palier 2, DHCP du VLAN 60    │
  │                   pendant la seule partie MAAS                                                  │
  │ bm01 (2112) SeaBIOS · bm02 (2113) SeaBIOS · bm03 (2114) OVMF · bm04 (2115) OVMF                │
  │ disques vides, démarrage réseau d'abord ; réservations 10.10.60.101-104 (E06)                  │
  └──────────────────────────────────────────────────────────────────────────────────────────────┘
        Installateurs → Internet (deb.debian.org, dl.rockylinux.org) par la bordure (NAT)
```

### Un démarrage réseau, pas à pas

```
 bm0x (micrologiciel)          passerelle (relais)       Kea (dns01/dns02)          pxe01
   │ DHCPDISCOVER, opt. 93 = 0x0000 (BIOS) ou 0x0007 (UEFI)
   │──────────────────────────────▶│── giaddr 10.10.60.x ──▶│ classe pxe-bios / pxe-uefi-x64
   │◀──────── OFFER/ACK : adresse, routeur, DNS, next-server 10.10.60.10, file undionly.kpxe | ipxe.efi
   │ TFTP RRQ undionly.kpxe | ipxe.efi ───────────────────────────────────────────────▶│ :69
   │◀─────────────────────────────────────────────────────────────── le chargeur iPXE ─│
 iPXE
   │ DHCPDISCOVER, opt. 77 = « iPXE »  ─────────────────────▶│ classe ipxe
   │◀──────── ACK : file = http://pxe01.par1.medisphere.internal/boot.ipxe
   │ GET /boot.ipxe ─────────────────────────────────────────────────────────────────▶│ :80
   │ GET /ipxe/mac-02-4d-53-60-00-01.ipxe (script de CE serveur, sinon menu) ──────────▶│
   │ GET /debian13/linux, /debian13/initrd.gz ──────────────────────────────────────────▶│
 installateur
   │ GET /preseed/… ou /kickstart/… ─────────────────────────────────────────────────▶│
   │ paquets ──▶ Internet (miroirs Debian / Rocky, par la bordure)
   │ fin : extinction ; le serveur passe « actif », puis redémarre sur son disque
```

Points structurants :

- **Deux temps de démarrage.** Le micrologiciel ne sait faire que DHCP et TFTP ; on lui donne le plus petit programme possible (iPXE), qui sait ensuite parler HTTP, exécuter des scripts et télécharger vite. Le serveur DHCP doit donc reconnaître **qui** demande (micrologiciel BIOS, UEFI, ou iPXE) : c'est le rôle des classes de Kea.
- **Une seule source de vérité.** Nom, adresse, système et statut d'un serveur viennent de NetBox (palier 2). OpenTofu « fabrique » seulement les VMs qui jouent le rôle du matériel livré, avec des adresses MAC fixes.
- **Un serveur installé ne se réinstalle pas tout seul.** Les VMs démarrent sur le réseau d'abord ; c'est le script iPXE qui décide « installer » (statut `planned` au palier 2 ; tu rendras cette règle plus sûre au palier 3) ou « démarrer sur le disque » (tout autre cas). Une installation se termine par une **extinction**, pas un redémarrage.
- **À partir du palier 3, tout passe en HTTPS** après le chargeur iPXE, et ce chargeur est construit par nous (racine MédiSphère intégrée) : le schéma ci-dessus montre la chaîne des paliers 1 et 2.
- **Un seul serveur DHCP par VLAN.** Kea sert le VLAN 60, sauf pendant la partie MAAS (E10), où le DHCP de MAAS le remplace après une fiche de changement : deux serveurs DHCP sur un même segment, c'est une panne garantie.

### Hôtes du module

| Hôte | VMID | Adresse | Ressources | Étiquettes | Firmware / système | Exercice |
|---|---|---|---|---|---|---|
| `pxe01` | 2111 | 10.10.60.10 (fixe, `next-server`) | 1 vCPU, 1 Go, 20 Go | `env-m11`, `role-pxe` | Debian 13 (image dorée `current`) | E02 |
| `bm01` | 2112 | 10.10.60.101 (réservée en E06) | 2 vCPU, 2 Go, 20 Go | `env-m11`, `role-bm` | SeaBIOS — Debian 13 | E03 |
| `bm02` | 2113 | 10.10.60.102 | 2 vCPU, 3 Go, 20 Go | `env-m11`, `role-bm` | SeaBIOS — Rocky Linux 10 | E03 |
| `bm03` | 2114 | 10.10.60.103 | 2 vCPU, 2 Go, 20 Go | `env-m11`, `role-bm` | OVMF (UEFI) — Debian 13 | E03 |
| `bm04` | 2115 | 10.10.60.104 | 2 vCPU, 4 Go, 32 Go (8 Go le temps de E14) | `env-m11`, `role-bm` | OVMF (UEFI) — Rocky Linux 10, Proxmox VE le temps de E14 | E03 |
| `maas01` | 2116 | 10.10.60.11 (fixe) | 2 vCPU, 4 Go, 40 Go | `env-m11`, `role-maas` | Ubuntu 24.04 (template 9050) | E09 (détruite en E25) |
| `m11-build` | 2117 | DHCP du VLAN 99 (`vsandbox`) | 2 vCPU, 2 Go | `env-m11` | Debian 13 (clone lié de l'image dorée `current`), VM jetable de construction d'iPXE | E13 (détruite aussitôt) |
| `tpl-ubuntu2404` | 9050 | — | — | `ubuntu2404`, `template` | Image cloud Ubuntu 24.04 | E09 |

Toutes dans le pool `lab`, déclarées dans `plateforme/infra`, environnement **`envs/provisioning/`** (2117 : ressource conditionnelle, activée le temps de la construction) (état `envs/provisioning/terraform.tfstate` sur `s3-01`). Adresses MAC fixées : `02:4d:53:60:00:01` à `02:4d:53:60:00:04` pour `bm01` à `bm04` (localement administrées : `02`, puis « MS » `4d:53`, le VLAN `60`, le numéro). Les VMs `bm*` ont 2 Go au moins, et 3 Go pour Rocky : l'installateur réseau de RHEL 10 demande 3 Gio quand il charge son image en HTTP.

### Ports et flux du module

| Flux | Port | Exercice | Où l'ouvrir |
|---|---|---|---|
| VLAN 60 → relais des passerelles (DHCP) | UDP 67 | E02 | entrée de `gw01`/`gw02` (matrice des flux) |
| Kea (`dns01`, `dns02`) → giaddr du VLAN 60 | UDP 67 | E02 | entrée de `gw01`/`gw02` |
| VLAN 60 → `dns01`/`dns02` (renouvellements en unicast) | UDP 67 | E02 | transit `gw01`/`gw02` + `pare_feu_local` de `dns01`/`dns02` |
| VLAN 60 → `pxe01` (TFTP, HTTP) | UDP 69 (+ ports éphémères), TCP 80 | E02 | même VLAN : rien |
| VLAN 60 → DNS du lab, NTP de la passerelle | 53, 123 | E02 | existant (règles « DNS du lab », NTP) |
| VLAN 60 → Internet (miroirs des installateurs) | 80, 443 | E04 | existant (« lab vers Internet ») |
| `adm01` → VLAN 60 | tous | E02 | existant (MGMT joint tout le lab) |
| `adm01` → iLO de `hp01` | TCP 443, UDP 623 (623 retiré en E13) | E07 | transit `gw01`/`gw02` (LAN maison exclu de « lab vers Internet ») |
| `maas01` → `pve01` (API) | TCP 8006 | E10 (retiré en E25) | transit `gw01`/`gw02` **et** pare-feu Proxmox (IPSet `maas`) |
| VLAN 60 → `pxe01` (HTTPS) | TCP 443 | E13 | même VLAN : rien |
| `pxe01` → `ca01` (ACME) ; `ca01` → `pxe01` (défi HTTP-01) | TCP 443 ; TCP 80 | E13 | transit `gw01`/`gw02` |
| VLAN 60 → Internet | TCP 80 et 443 seulement | E13 | transit `gw01`/`gw02` (le VLAN 60 sort de « lab vers Internet ») |
| `runner01` → VLAN 60 (publication, accueil Ansible) | TCP 22 | E15 | transit `gw01`/`gw02` |
| `runner01` → iLO de `hp01` (inventaire) | TCP 443 | E18 | transit `gw01`/`gw02` |

Tout nouveau flux passe par la matrice des flux de la bordure (`group_vars/role_routeur/pare_feu.yml`, commune à `gw01` et `gw02` depuis M07-E24) ; `docs/socle/matrice-flux.md` en est régénérée par `ms-matrice-flux` (M07-E30).

---

## Le chemin imposé

Comme aux modules précédents :

1. **OpenTofu** : `pxe01` par le module `vm-debian` (adresse imposée), `maas01` et les `bm*` par des ressources de `envs/provisioning/` ; plan en MR, `apply` par le pipeline.
2. **DNS** : `pxe01` et `maas01` par le module `enregistrement-dns` ; les serveurs `bm*` par NetBox (`medictl dns sync`, M06-E15) à partir de E06.
3. **Ansible** : rôles `pxe`, `kea_dhcp4`, `relais_dhcp` (et `maas` en E09) dans `plateforme/ansible`, ansible-lint en profil `production`, scénario Molecule pour un rôle nouveau.
4. **Fichiers d'installation** : dans `plateforme/provisioning` (scripts iPXE, preseed, kickstart, gabarits, outils), validés par son pipeline, publiés sur `pxe01` par un outil du projet.
5. **Secrets** : jamais en clair dans un dépôt ni sur une ligne de commande ; empreintes de mots de passe seulement dans les fichiers d'installation ; tout nouveau secret au registre des secrets.

Une installation à la main n'est permise que pour **explorer**, sur une VM `bm*` (elles sont faites pour être effacées).

---

## Concepts clés

**PXE.** *Preboot eXecution Environment* : le micrologiciel de la carte réseau (ou de l'UEFI) obtient une adresse en DHCP, lit dans la réponse un serveur (`next-server`, champ `siaddr`) et un nom de fichier (`file`, ou option 67), le télécharge en **TFTP** et l'exécute. Le client s'annonce par l'option 60 (`PXEClient:Arch:…`) et l'option **93** (*client system architecture*, RFC 4578 : `0x0000` BIOS x86, `0x0007` et `0x0009` UEFI x86-64). TFTP est lent, sans authentification ni contrôle d'intégrité : on n'y fait passer que le strict minimum.

**iPXE.** Un micrologiciel réseau libre, chargé par PXE (`undionly.kpxe` en BIOS, `ipxe.efi` en UEFI), qui ajoute HTTP(S), DNS, les scripts (`#!ipxe`), les menus et le chaînage. Il s'annonce en DHCP par l'option **77** (*user class*) `iPXE` : le serveur DHCP lui répond alors par l'URL d'un script au lieu du fichier TFTP, ce qui casse la boucle « PXE charge iPXE qui recharge iPXE ». Particularité du lab : la ROM réseau des cartes virtuelles de QEMU **est déjà** iPXE, ce que tu observeras en E03.

**BIOS, UEFI et Secure Boot.** Un serveur UEFI charge un exécutable EFI, pas un secteur d'amorçage ; avec Secure Boot, ce binaire doit être signé par une clé enregistrée (en pratique celle de Microsoft, via *shim*). Le `ipxe.efi` du paquet Debian ne l'est pas : les VMs OVMF du module ont Secure Boot désactivé (pas de clés préinstallées), choix discuté au palier 3.

**Preseed et kickstart.** Les fichiers de réponses des installateurs : *preseed* pour debian-installer (questions debconf `d-i …`), *kickstart* pour Anaconda (Rocky, RHEL, Fedora). L'installateur les télécharge (paramètre noyau `url=` / `inst.ks=`) et ne pose plus de questions. Les deux savent exécuter des commandes en fin d'installation (`preseed/late_command`, `%post`) : c'est là que le serveur reçoit nos standards.

**Contrôleur de gestion (BMC).** Un petit ordinateur dans le serveur (iLO chez HPE, iDRAC chez Dell), alimenté même quand le serveur est éteint : alimentation, console, capteurs, journaux, inventaire. Deux protocoles : **IPMI** over LAN (UDP 623, ancien, faibles garanties de sécurité) et **Redfish** (API REST en HTTPS, normalisée par la DMTF). C'est ce qui permet de piloter un parc sans entrer dans la salle — et ce qui fait d'un BMC une cible de choix.

**Cycle de vie d'un serveur.** NetBox porte le statut : `planned` (livré, à installer), `staged` (en cours de mise en service), `active` (en service), `failed`, `decommissioning`, `offline`… La chaîne de provisioning est un automate : selon le statut, le serveur s'installe, démarre sur son disque ou est effacé. MAAS (*Metal as a Service*) fait la même chose avec son propre vocabulaire (*New*, *Commissioning*, *Ready*, *Deploying*, *Deployed*) et sa propre base.

**Fiche : Tinkerbell.** Projet de la CNCF (à l'origine chez Equinix Metal) qui provisionne des serveurs physiques depuis Kubernetes : chaque machine est une ressource (`Hardware`), chaque installation un `Workflow` fait d'actions en conteneurs (écrire une image disque, configurer le réseau…) exécutées par un petit système en mémoire (`HookOS`). Il apporte son DHCP et son serveur iPXE (Smee), son service de métadonnées (Hegel) et son moteur (Tink) ; il pilote les BMC par Rufio (Redfish, IPMI). Déploiement recommandé : un chart Helm sur un cluster Kubernetes. Points à retenir pour l'ADR de M11-E16 : la source de vérité devient Kubernetes, le provisioning repose sur une image disque plutôt qu'un installateur, et il faut un cluster en état de marche **avant** d'installer le premier serveur (Kubernetes n'arrive qu'au module 14). Documentation : <https://tinkerbell.org/>.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Kea 3.0 ; iPXE du paquet Debian 13 (`ipxe`, 1.21.1+git2025) aux paliers 1 et 2, puis iPXE amont **construit** (étiquette `v2.0.0`, racine MédiSphère intégrée) à partir de E13 ; tftpd-hpa et nginx 1.26 de Debian 13 ; debian-installer de trixie ; Rocky Linux 10 (10.2 au 8 octobre 2026) ; MAAS 3.7 (snap `3.7/stable`), PostgreSQL 16 d'Ubuntu 24.04 ; ipmitool 1.8.19 ; iLO 4 (Redfish 1.0, firmware 2.82 conseillé) |
| Changements de version | [`annexes/versions-bloc-B.md`](../../../annexes/versions-bloc-B.md), section « Provisioning bare-metal » |
| Projet GitLab | **`plateforme/provisioning`** (copie de travail `~/src/provisioning`) : `ipxe/` (`boot.ipxe`, `menu.ipxe`), `preseed/`, `kickstart/`, `pve-answer/` (E14), `gabarits/` (Jinja2), `outils/` (`publier.sh`, `netbox-provision.py`, `alim.sh`), `.gitlab-ci.yml` (validation) |
| `pxe01` | `/srv/tftp` (chroot de `tftpd-hpa`, `undionly.kpxe` et `ipxe.efi` copiés de `/usr/lib/ipxe`, remplacés en E13 par les binaires construits) ; `/srv/http` servi par nginx sur 10.10.60.10:80, puis en HTTPS sur 443 à partir de E13 (`pxe01.par1.medisphere.internal`, certificat ACME de `ca01`) : `debian13/`, `rocky10/`, `pki/` gérés par le rôle `pxe` (playbook `playbooks/pxe.yml`, groupe `role_pxe`), `boot.ipxe`, `ipxe/`, `preseed/`, `kickstart/` publiés par `plateforme/provisioning` (`outils/publier.sh`), `pve/` (E14, temporaire) ; journaux nginx `/var/log/nginx/pxe-acces.log` et `pxe-erreurs.log` |
| DHCP du VLAN 60 | Kea, sous-réseau `id: 60`, 10.10.60.0/24, plage 10.10.60.100-199, routeur et NTP 10.10.60.1, DNS 10.10.20.10 et .16, `next-server` 10.10.60.10, pas de DDNS ; classes `pxe-bios`, `pxe-uefi-x64`, `ipxe` ; relayé par `gw01`/`gw02` (giaddr 10.10.60.2 / .3) |
| NetBox (E06) | équipements `bm01`-`bm04` : site `par1`, rôle `serveur-bm`, type `serveur-nu-vm` (fabricant `generique`), plateformes `debian-13` / `rocky-10` (et `proxmox-ve-9` le temps de E14), étiquette `env-m11`, interface `eno1` (adresse MAC primaire), IP primaire 10.10.60.101-104 avec son `dns_name` ; statut `planned` → `active` ; répartition : `bm01` Debian (BIOS), `bm02` Rocky (BIOS), `bm03` Debian (UEFI), `bm04` Rocky (UEFI). Jetons de M06 : `netbox-ansible.env` (lecture), `netbox-auto.token` (écriture de `svc-automatisation`, droits étendus en E15 et E18). Champs personnalisés de `hp01` (E18) : `firmware_bios`, `firmware_ilo`, `inventaire_maj` |
| Installations | compte `admin` (sudo, clé SSH de `adm01`, mot de passe **haché** SHA-512), `root` sans mot de passe utilisable, racine de la PKI installée (empreinte vérifiée), agent QEMU, fin par **extinction** |
| Proxmox (E08, E15) | compte `wb-maas@pve`, jeton `wb-maas@pve!maas`, rôle `WBMaas` sur `/vms/2112` à `/vms/2115` ; fichier `~/.config/workbook/pve-maas.env` (même format que `pve-api.env`, M00-E17) ; supprimé ou désactivé au mini-projet avec MAAS. Orchestrateur de E15 : compte distinct `wb-provision@pve`, jeton `wb-provision@pve!provision`, rôle `WBProvision` sur les mêmes VMs, fichier `~/.config/workbook/pve-provision.env` (il survit à MAAS) |
| iLO de `hp01` (E07) | `<IP-ILO-HP01>` ; compte `wb-redfish` (droits minimaux) ; `~/.config/workbook/ilo-hp01.env` (600 : `ILO_HOST`, `ILO_NOM_TLS`, `ILO_USER`, `ILO_PASSWORD`) ; certificat épinglé `~/.config/workbook/ilo-hp01.pem` |
| MAAS (E09-E10) | `http://10.10.60.11:5240/MAAS/`, administrateur `<MOI>`, clé d'API dans `~/.config/workbook/maas-api.key` (600), profil CLI `maas01` ; plage dynamique 10.10.60.150-199 pendant la partie MAAS |
| Documentation | dans `plateforme/medisphere`, dossier **`docs/provisioning/`** (comme `docs/stockage/`, `docs/virtualisation/`, `docs/cloud/` des modules 08 à 10) : fiches et comptes rendus, `analyses/` (E23), `journal/` (palier 4) ; `runbooks/` : **RB-110** « provisionner un serveur » (E12), **RB-111** « diagnostiquer un démarrage réseau » (palier 4) ; `adr/` : ADR-0110 « outil de provisioning » (E16), ADR-0111 « confiance du démarrage réseau » (E13) ; `changements/` : fiches `CHG-12xx` (CHG-1215 en E10, CHG-1230 en E13). La matrice des flux et le registre des secrets restent dans `docs/socle/` |
| Numérotation | tickets `PLAT-1200`-`1209` (palier 1), `1210`-`1229` (palier 2), `1230`-`1249` (paliers 3 et 4), `1290` (mini-projet) ; `SEC-12xx`, `CHG-12xx` ; incidents `INC-3841`-`3844` (palier 4) |
| Brouillons | `~/m11/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<IP-ILO-HP01>` | Adresse de l'iLO de `hp01` sur le LAN maison (lis-la sur l'écran de démarrage de `hp01`, dans ton routeur, ou dans `lab/inventaire-local.md` si tu l'y as notée au module 00) |
| `<NOM-TLS-ILO>` | Nom que présente le certificat de l'iLO (E07), souvent `ILO` suivi du numéro de série |
| `<IP-PVE01>` | Adresse de `pve01` sur le LAN maison |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<MOI>` | Ton compte personnel (GitLab, NetBox ; administrateur de MAAS en E09) |

### Variables de `lab/lab.env`

| Variable | Valeur par défaut | Usage |
|---|---|---|
| `WB_ILO_ENV_FILE` | `$HOME/.config/workbook/ilo-hp01.env` | Accès Redfish en lecture des checks E07, E08, E18 |
| `WB_MAAS_URL` | `http://10.10.60.11:5240/MAAS` | API de MAAS (E09, E10, E22) |
| `WB_MAAS_KEY_FILE` | `$HOME/.config/workbook/maas-api.key` | Clé d'API MAAS lue par les checks et les pannes (E09, E10, E22) |
| `WB_M11_MAAS_CONSERVE` | `0` | `1` seulement si ton ADR-0110 conserve MAAS : le contrôle du mini-projet saute alors les contrôles de retrait de MAAS (E25) |

Ajoute-les à ton `lab/lab.env` (elles figurent dans `lab/lab.env.example`). Les vérifications utilisent aussi `WB_SRC` (`~/src/provisioning`, `~/src/ansible`, `~/src/infra`), `WB_PVE_HOST`, `WB_NETBOX_URL`, `WB_NETBOX_TOKEN_FILE` et le jeton GitLab des checks.

---

## Règles du module

1. **`hp01` n'est jamais réinstallé ni reconfiguré.** Il porte PBS (et le QDevice du module 09). Sur son iLO : lecture d'inventaire, de capteurs et de journaux ; création d'un compte dédié ; au plus un redémarrage **annoncé**, facultatif, hors des fenêtres de sauvegarde (E08). Aucun check n'exige d'agir sur `hp01`.
2. **Pas de vérification TLS désactivée** : ni `curl -k`, ni `--insecure`, ni « verify SSL : non » dans MAAS. Le certificat autosigné de l'iLO s'**épingle** après vérification de son empreinte par un second chemin (E07) ; celui de `pve01` se vérifie avec l'ancre construite en M02-E08.
3. **Un secret ne passe jamais en argument de commande** : fichiers en 600, entrée standard, variable d'environnement d'un seul processus (`ipmitool -E`). Les fichiers d'installation ne contiennent que des **empreintes** de mots de passe et des clés **publiques**. Une exception documentée existe (l'URI de base de données de `maas init`, E09) : elle est consignée et limitée.
4. **Un seul serveur DHCP par segment.** Avant d'activer le DHCP de MAAS, le sous-réseau 60 de Kea et le relais du VLAN 60 sont retirés par une fiche de changement avec retour arrière ; ils reviennent à la fin de la partie MAAS.
5. **Instantané avant toute intervention sur un hôte du socle** (`ms-snapshot --prefix avant-m11 <VMID>`, M02-E11) : `dns01`, `dns02` (Kea), `gw01`, `gw02` (relais, pare-feu). ⚠️ Une erreur dans le relais ou dans Kea coupe aussi le DHCP du VLAN 99 : vérifie l'accès de secours (`qm terminal <VMID>`, agent QEMU) avant, et un client du VLAN 99 après.
6. **Les VMs `bm*` sont jetables.** Les effacer et les réinstaller est le cœur du module ; `pxe01` et `maas01` aussi, mais par OpenTofu.
7. **Nettoie derrière toi** : à la fin du module (mini-projet), `maas01` et la VM jetable 2117 détruites, VMs `bm*` remises à zéro ou détruites selon ta documentation, template 9050 conservé ou supprimé selon ta décision consignée, VLAN 60 servi par Kea seul, compte `wb-maas` supprimé ou désactivé, compte `wb-redfish` réduit au strict nécessaire (E13).

---

## Préparer `adm01`

Outils nouveaux : `ipmitool` (E07), le client `maas` n'est **pas** nécessaire sur `adm01` (il tourne sur `maas01`). Vérifie avant de commencer :

```
admin@adm01:~$ lab/bin/check 06 46
admin@adm01:~$ dig +short @10.10.20.10 nbx01.par1.medisphere.internal
admin@adm01:~$ ssh dns01 'sudo -n systemctl is-active isc-kea-dhcp4-server'
admin@adm01:~$ ssh gw01 'sudo -n systemctl is-active dnsmasq keepalived'
admin@adm01:~$ cd ~/src/infra && tofu version | head -n 1
admin@adm01:~$ install -d -m 700 ~/m11
```

Le premier contrôle (mini-projet du module 06) doit être vert, et la bordure redondante du module 07 en place (`socle-v2`) : ce module ajoute un VLAN au relais des **deux** passerelles. Crée ensuite le projet GitLab `plateforme/provisioning` (branche `main` protégée, fusion par MR, gabarits CI partagés de `plateforme/ci-templates`) et clone-le dans `~/src/provisioning` : tu le rempliras dès E03.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 11 <XX>`. Elles sont en lecture seule : configuration Proxmox lue en root sur `pve01`, état des hôtes en SSH (`sudo -n`), configuration chargée par Kea (socket de contrôle), fichiers servis par `pxe01`, NetBox avec le jeton des checks, API GitLab en lecture, Redfish en lecture avec le compte `wb-redfish`, API de MAAS avec ta clé.
- Les indices sont progressifs : ouvre-les un par un.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Fichiers complets dans `corrige/fichiers/M11-EXX/` : `ansible/` = `plateforme/ansible`, `infra/` = `plateforme/infra`, `provisioning/` = `plateforme/provisioning`, `medisphere/` = la documentation ; on superpose les dossiers dans l'ordre des exercices.
- Les vérifications d'un exercice décrivent l'état **à la fin de cet exercice** : certaines ne sont plus à relancer après un exercice qui fait évoluer la même brique (par exemple la chaîne en HTTP des paliers 1 et 2 après E13) ; le mini-projet a son contrôle global.
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─┬─ E04 ─┐
                 └─ E05 ─┴─ E06 ─────────────────┐
     E07 ─ E08 (indépendants de E02-E06) ─ E09 ─ E10 ─┴─ E11 ─ E12
E13 ─ E14 ─ E15 ─ E18 ─ E16 ─ E17              (palier 3)
E19 ─ E20 ─ E21 ─ E22 ─ E23 ─ E24              (palier 4, pannes dans n'importe quel ordre)
E25                                            (mini-projet)
```

1. **E01** — positionnement, à froid.
2. **E02 → E03** — le réseau de démarrage, puis les serveurs nus qui l'utilisent.
3. **E04** et **E05** — indépendants l'un de l'autre.
4. **E06** — quand les deux installations fonctionnent à la main.
5. **E07 → E08** — le contrôleur de gestion : à faire quand tu veux, même avant E02 (ils ne touchent pas au VLAN 60, sauf l'outil d'alimentation des `bm*` en E08).
6. **E09 → E10** — MAAS, après E08 (le compte `wb-maas` sert au pilote d'alimentation) et après E04 (pour comparer). Réserve un créneau : E10 change le DHCP du VLAN 60.
7. **E11**, **E12** — en fin de palier 2.
8. **Palier 3** — E13 d'abord (tout le reste s'appuie sur la chaîne en HTTPS), puis E14, E15, E18 ; E16 et E17 à la fin, quand tu as les mesures.
9. **Palier 4** — les quatre pannes après E15 (elles supposent la chaîne du palier 3), E22 avec MAAS redémarré pour l'occasion ; E23, puis E24.
10. **E25** — le mini-projet, qui finit par le nettoyage.

Durée indicative du module : 35 à 45 heures, dont près de la moitié pour le palier 3 et le mini-projet. Les durées par exercice sont des majorants pour une première fois : elles se recouvrent (attente d'une installation ou de la synchronisation des images de MAAS pendant que tu rédiges) et se raccourcissent quand les briques précédentes sont propres.

## Pour aller plus loin

- iPXE : <https://ipxe.org/docs> (scripts : <https://ipxe.org/scripting>, commandes : <https://ipxe.org/cmd>, chaînage : <https://ipxe.org/howto/chainloading>)
- Kea, classification des clients : <https://kea.readthedocs.io/en/kea-3.0.4/arm/classify.html>
- Guide d'installation Debian, annexe B « Automating the installation using preseeding » : <https://www.debian.org/releases/trixie/amd64/apb.en.html> ; exemple officiel : <https://www.debian.org/releases/trixie/example-preseed.txt>
- Kickstart (RHEL 10, *Automatically installing RHEL*) : <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/automatically_installing_rhel/> ; Rocky : <https://docs.rockylinux.org/>
- Redfish : <https://www.dmtf.org/standards/redfish> ; iLO 4 RESTful API : <https://hewlettpackard.github.io/ilo-rest-api-docs/ilo4/>
- MAAS 3.7 : <https://canonical.com/maas/docs>
- RFC 2131/2132 (DHCP et options), RFC 3004 (*user class*), RFC 4578 (options PXE), RFC 1350 (TFTP), RFC 2347-2349 (options TFTP, `blksize`)
