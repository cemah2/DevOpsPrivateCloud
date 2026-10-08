# Module 11 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Un dossier par exercice dans [`fichiers/`](fichiers/), sous la forme d'un **extrait des projets** : `ansible/` = `plateforme/ansible`, `infra/` = `plateforme/infra`, `provisioning/` = `plateforme/provisioning`, `medisphere/` = la documentation. On **superpose** les dossiers dans l'ordre (E02, E03, E04…) : un fichier d'un exercice plus récent remplace le précédent. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.rendu.json` des configurations **produites** (pour lecture). Les valeurs `<EN-MAJUSCULES>` des fichiers d'installation sont à remplacer par les tiennes (empreintes, clé publique).

**Ce qui a été testé, ce qui ne l'a pas été.**
- *Kea 3.0.4* (paquets ISC) : la configuration produite par le gabarit `kea_dhcp4` de M11 (sous-réseaux 99 et 60, classes, réservations) passe `kea-dhcp4 -t` ; une expression de classe fautive est refusée avec sa position. Rendu par Ansible 2.21 depuis les fichiers du corrigé : [`kea-dhcp4-vlan60.rendu.json`](fichiers/M11-E06/ansible/kea-dhcp4-vlan60.rendu.json).
- *pxe-installateurs* (outil du rôle `pxe`) exécuté contre les miroirs réels le 8 octobre 2026 : Debian trixie (Release signé à trois signatures, `SHA256SUMS`, `linux`, `initrd.gz`) et Rocky Linux 10.2 (`.treeinfo`, `vmlinuz`, `initrd.img` de 224 Mo) ; second passage « inchangé » ; URL fausse refusée.
- *Preseed* : `debconf-set-selections -c` sur `preseed/debian13.cfg` ; *kickstart* : `ksvalidator -v RHEL10` (pykickstart 3.78) sur `kickstart/rocky10.ks` ; `outils/verifier.sh` détecte les mots de passe en clair (preseed et kickstart).
- *OpenTofu 1.13.1* : `tofu validate` de `envs/provisioning` (avec `vm-debian` v2 et `enregistrement-dns` de M06) et du fournisseur `bpg/proxmox` 0.116 (attributs `bios`, `boot_order`, `efi_disk.pre_enrolled_keys`, `network_device.mac_address` lus dans son schéma).
- *Ansible* : ansible-lint 26 en profil `production` sur les rôles `pxe` et `relais_dhcp`, le playbook et le scénario Molecule ; ShellCheck 0.11 et `bash -n` sur les scripts.

**Non rejoués sur un lab réel** : un démarrage PXE complet sur Proxmox (comportement exact de la ROM iPXE de QEMU en BIOS, pile PXE d'OVMF en UEFI), une installation Debian et Rocky de bout en bout, le relais dnsmasq avec plusieurs VLANs et VRRP, les journaux exacts de tftpd-hpa. Ils sont signalés « ⚠️ À vérifier sur ton lab » : signale tes retours.

---

### M11-E01 — Test de positionnement : installer des serveurs

**Barème** : 2 points par question, total sur 30. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. En dessous de 15, relis les concepts clés de l'introduction avant E02 ; les questions 12 à 14 sont reprises en E07, la question 15 en E10 et dans l'ADR (E16).

**1. Où et quoi.** Le champ **`siaddr`** de l'en-tête BOOTP (*next-server* : l'adresse du serveur TFTP) et le champ **`file`** (nom du fichier de démarrage, 128 octets), ou leurs équivalents en options : 66 (*TFTP server name*, un **nom** ou une adresse sous forme de texte) et 67 (*bootfile name*). Différence : `siaddr` est une adresse IPv4 dans l'en-tête, comprise par tous les micrologiciels PXE ; l'option 66 est une chaîne qui doit parfois être résolue, et certains clients PXE anciens l'ignorent. Kea renseigne `siaddr` par `next-server`, `file` par `boot-file-name`.

**2. Réponse B.** L'option 93 (RFC 4578) est envoyée par tout client PXE et dit précisément l'architecture du micrologiciel (`0x0000` BIOS x86, `0x0006` UEFI IA32, `0x0007`/`0x0009` UEFI x86-64, `0x000b` UEFI ARM64…). A est faux : un même constructeur vend des cartes pour des serveurs BIOS et UEFI, et la même carte démarre dans les deux modes. C n'a pas de sens. D : l'option 12 est le nom d'hôte, souvent absent au démarrage.

**3. Relais.** Il reçoit la diffusion du client sur son interface du VLAN, inscrit son adresse dans `giaddr` et transmet en **unicast** au(x) serveur(s) ; le serveur choisit le sous-réseau d'après `giaddr` et répond au relais, qui rediffuse au client. Le TFTP, lui, n'est **pas** une diffusion : une fois son adresse obtenue, le client parle en unicast au `next-server`, routé normalement (ici, il est même sur le même VLAN). Seule la découverte DHCP a besoin d'un relais, parce qu'un client sans adresse ne peut que diffuser.

**4. TFTP d'abord.** Parce que c'est ce que les ROM PXE savent faire : la spécification PXE impose UDP, DHCP et TFTP, simples à tenir dans quelques kilo-octets de ROM (pas de TCP). Défauts : **aucune authentification ni intégrité** (n'importe qui sur le segment peut répondre à la place du serveur), **lent** (un bloc de 512 octets par aller-retour, un peu mieux avec l'option `blksize`), sensible aux pertes, difficile à filtrer (transferts sur des ports éphémères). D'où le minimum par TFTP (quelques centaines de Ko d'iPXE) et tout le reste en HTTP.

**5. Boucle et classe iPXE.** Le micrologiciel obtient `undionly.kpxe` et l'exécute ; iPXE refait une requête DHCP pour configurer **sa** pile réseau ; s'il reçoit la même réponse (`undionly.kpxe`), il le recharge… indéfiniment. Le serveur la casse en reconnaissant iPXE : option 77 (*user class*) égale à `iPXE` (ou présence de l'option 175, propre à iPXE) → on lui donne l'URL d'un script au lieu du binaire. C'est la classe `ipxe` de E03, et c'est pourquoi les classes `pxe-*` excluent explicitement iPXE.

**6. Réponse C.** Avec Secure Boot actif et les clés Microsoft (la configuration d'usine de presque tous les serveurs), le micrologiciel n'exécute qu'un binaire EFI signé par une clé de la base `db` : en pratique *shim* (signé par Microsoft), qui vérifie à son tour le chargeur suivant avec une clé de distribution (ou une clé de la machine, MOK). A est un binaire BIOS (pas EFI du tout) ; B n'est pas signé ; D est faux : Secure Boot vérifie **chaque** exécutable EFI chargé, à commencer par le premier. iPXE 2.0 (amont) se distribue désormais avec un *shim* signé ; le paquet de Debian 13 non.

**7. Pas de réinstallation en boucle.** Approches : (a) le serveur de démarrage décide selon l'**état** connu de la machine : script « installer » si elle est à installer, « démarrer sur le disque » (`exit`, `sanboot`) sinon — c'est ce que font MAAS, Foreman et notre chaîne (statut NetBox) ; (b) changer l'ordre de démarrage après l'installation (par le BMC : Redfish `Boot.BootSourceOverrideTarget`, IPMI `chassis bootdev`), avec le risque de ne plus pouvoir réinstaller par le réseau sans repasser par le BMC ; (c) un menu dont le choix par défaut est le disque local. Le pire : démarrer le disque en dernier recours et réinstaller tout ce qui démarre sur le réseau.

**8. debian-installer.** `auto=true` (alias de `auto-install/enable=true`) retarde les questions de langue et de clavier **après** la configuration du réseau, pour qu'elles puissent venir du preseed téléchargé ; `priority=critical` ne pose que les questions critiques (les autres prennent leur valeur par défaut ou celle du preseed). Le nom d'hôte se décide pendant la configuration du réseau (`netcfg`), donc **avant** que le preseed de `url=` soit téléchargé : seul un paramètre noyau (`hostname=`, `domain=`) ou la réponse DHCP peut le fixer à temps.

**9. Réponse B.** `--iscrypted` avec une empreinte (`$6$…` = SHA-512 crypt) : le fichier ne contient rien de réutilisable tel quel. A et C mettent le mot de passe en clair (C est même pire : « 600 sur le serveur HTTP » ne protège rien, le fichier est servi à quiconque le demande sur le VLAN). D est faux : `user` existe. Une empreinte dans un fichier lisible reste attaquable par dictionnaire : mot de passe long et aléatoire, et la vraie authentification se fait par clé SSH.

**10. Intégrité.** Noyau et initrd : par nos soins, au téléchargement sur `pxe01` (Release signé → `SHA256SUMS` → empreintes) ; **entre `pxe01` et le serveur**, en HTTP clair, rien ne les vérifie (sauf signature d'image iPXE, `imgverify`, ou HTTPS, M11-E13). Paquets : apt vérifie le `Release` signé du miroir et les empreintes des paquets : un miroir ou un réseau malveillant ne peut pas injecter de paquet. Le preseed en HTTP n'est **ni authentifié ni intègre** : quelqu'un sur le VLAN qui le modifie en route (ou usurpe `pxe01`) peut ajouter une clé SSH, désactiver la vérification d'apt (`allow_unauthenticated`), ou exécuter n'importe quoi dans `late_command`. C'est l'argument central de M11-E13.

**11. Extinction.** Parce que la suite n'appartient pas à l'installateur : la chaîne doit **constater** la fin (machine éteinte), mettre à jour la source de vérité (statut `active`), régénérer le script de démarrage (« disque local »), puis rallumer. Un redémarrage immédiat ferait repartir la machine sur le réseau avec un script encore « installer » : réinstallation en boucle. C'est aussi ce que fait MAAS (il éteint ou redémarre lui-même, par le BMC).

**12. BMC.** *Baseboard Management Controller* : un microcontrôleur avec son propre système, sa propre carte réseau (ou une carte partagée), alimenté dès que le serveur est branché. Même serveur éteint ou planté : allumer, éteindre, redémarrer ; console texte ou graphique à distance ; lire capteurs (températures, ventilateurs, tensions, consommation) et journaux matériels ; inventaire (numéro de série, mémoire, firmware) ; monter un média virtuel ; changer l'ordre de démarrage ; mettre à jour des firmwares.

**13. Réponse B.** IPMI 2.0 (RAKP) : le BMC envoie, à quiconque demande à ouvrir une session pour un nom de compte valide, une empreinte HMAC salée dérivée du mot de passe, attaquable hors ligne (problème de conception du protocole, CVE-2013-4786 : pas de correctif possible sauf ne pas exposer IPMI) ; et la suite de chiffrement « cipher 0 » (aucune authentification), activée sur certains BMC, permet d'ouvrir une session avec n'importe quel mot de passe. A : la vitesse n'est pas le sujet. C est faux (`chassis power off`). D : IPMI ne demande pas de licence (l'iLO en demande pour la console graphique et le média virtuel).

**14. TLS sans `-k`.** De la plus rapide à la plus propre : (1) **épingler** le certificat présenté (`--cacert` avec ce certificat, ou `--pinnedpubkey sha256//…`), après avoir vérifié son empreinte par un autre chemin ; (2) récupérer et installer comme ancre la **CA du constructeur** qui a signé le certificat par défaut, si elle existe et si le certificat porte le bon nom ; (3) **remplacer** le certificat du BMC par un certificat de notre PKI (CSR générée par le BMC, signée par step-ca, importée), avec le nom DNS du BMC : la vérification devient normale, mais il faut gérer son renouvellement (pas d'ACME sur iLO 4).

**15. Maison ou MAAS.** Chaîne maison : l'état est dans **NetBox** (statut, nom, adresse, plate-forme), la configuration dans Git, l'alimentation dans un outil à nous (ou le BMC à la main) ; chaque brique (Kea, TFTP, HTTP) est indépendante, connue et déjà supervisée ; si un générateur tombe, les fichiers déjà publiés continuent de servir. MAAS : l'état est dans **sa** base PostgreSQL (cycle *New* → *Ready* → *Deployed*), il pilote l'alimentation lui-même (pilotes IPMI, Redfish, Proxmox…), il fournit DHCP, DNS, TFTP, HTTP, proxy et images ; s'il tombe, plus aucun déploiement, et une resynchronisation avec la source de vérité est à prévoir. Il apporte la mise en service (inventaire, tests matériels) que la chaîne maison n'a pas.

---

### M11-E02 — Le réseau de provisioning

**Solution**

Fichiers : [`envs/provisioning/`](fichiers/M11-E02/infra/envs/provisioning/) (`versions.tf`, `providers.tf`, `variables.tf`, `pxe01.tf`, `terraform.tfvars.exemple`) ; rôle [`pxe`](fichiers/M11-E02/ansible/roles/pxe/) et son [scénario Molecule](fichiers/M11-E02/ansible/molecule/pxe/), [`playbooks/pxe.yml`](fichiers/M11-E02/ansible/playbooks/pxe.yml), [`host_vars/pxe01/pxe.yml`](fichiers/M11-E02/ansible/inventories/lab/host_vars/pxe01/pxe.yml) ; rôle [`kea_dhcp4`](fichiers/M11-E02/ansible/roles/kea_dhcp4/) (gabarit et valeurs par défaut, version M11) et [`group_vars/role_dns/kea.yml`](fichiers/M11-E02/ansible/inventories/lab/group_vars/role_dns/kea.yml) ; rôle [`relais_dhcp`](fichiers/M11-E02/ansible/roles/relais_dhcp/) (plusieurs VLANs) et [`host_vars/gw01/relais_dhcp.yml`](fichiers/M11-E02/ansible/inventories/lab/host_vars/gw01/relais_dhcp.yml), [`gw02`](fichiers/M11-E02/ansible/inventories/lab/host_vars/gw02/relais_dhcp.yml) ; flux : [`pare_feu.yml.extrait`](fichiers/M11-E02/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`dns01/pare_feu_local.yml.extrait`](fichiers/M11-E02/ansible/inventories/lab/host_vars/dns01/pare_feu_local.yml.extrait) ; documentation : [`matrice-flux.extrait.md`](fichiers/M11-E02/medisphere/docs/socle/matrice-flux.extrait.md).

1. **OpenTofu.** Un environnement à part (`envs/provisioning`, clé d'état `envs/provisioning/terraform.tfstate`) : tout ce qui est créé dans ce module se détruit d'un `tofu destroy` sans risque pour le socle. `pxe01` par `vm-debian` avec `ipv4_imposee = "10.10.60.10"` (l'adresse est le `next-server` annoncé par Kea : elle ne peut pas être allouée au hasard), `vnet = "vprov"`, étiquettes `env-m11` et `role-pxe` ; nom par `enregistrement-dns`. Les trois fournisseurs (Proxmox, NetBox, PowerDNS) sont configurés comme dans `envs/lab-m06` (M06-E13, E14) : URL dans le code, secrets dans `TF_VAR_netbox_api_token` et `TF_VAR_pdns_api_key`, variables éphémères.
   ```
   admin@adm01:~/src/infra/envs/provisioning$ set -a; . ~/.config/workbook/pve-tofu.env; . ~/.config/workbook/netbox-tofu.env; . ~/.config/workbook/powerdns-api.env; . ~/.config/workbook/s3-tofu.env; set +a
   admin@adm01:~/src/infra/envs/provisioning$ tofu init && tofu plan
   ```
   Le plan montre l'ordre de M06-E13 : VM NetBox → interface → adresse 10.10.60.10/24 → IP primaire → VM Proxmox → A et PTR. En vrai, `plan` en MR et `apply` par le pipeline protégé. **Avant** le premier `apply` : les étiquettes `env-m11` et `role-pxe` (puis `role-maas` en E09) doivent exister dans NetBox (le module les pose sur la VM NetBox, M06-E13), et dans Proxmox rien n'est à créer (les étiquettes Proxmox sont libres). Le préfixe 10.10.60.0/24 et le VLAN 60 existent depuis la modélisation de M06-E05.
2. **Le rôle `pxe`** (lis [`tasks/main.yml`](fichiers/M11-E02/ansible/roles/pxe/tasks/main.yml)) :
   - `tftpd-hpa` : `TFTP_ADDRESS="10.10.60.10:69"`, `TFTP_OPTIONS="--secure --verbose"` (racine en chroot, chemins relatifs, chaque lecture journalisée), **pas** de `--create` (personne n'écrit) ; `undionly.kpxe` et `ipxe.efi` copiés de `/usr/lib/ipxe` (paquet `ipxe`).
   - nginx : un site `pxe` qui écoute sur `10.10.60.10:80` seulement, `autoindex off`, `limit_except GET` (lecture seule ; GET implique HEAD), `allow 10.10.60.0/24; allow 10.10.10.0/24; deny all;` — les serveurs à installer, et `adm01` pour la publication et les vérifications. Le reste du lab n'a rien à lire là : un preseed contient une empreinte de mot de passe. Le site `default` (toutes adresses, `/var/www/html`) est retiré ; `nginx -t` avant tout rechargement.
   - Dossiers : le rôle gère `/srv/tftp`, `/srv/http/{debian13,rocky10,pki}` ; il **crée** `ipxe/`, `preseed/`, `kickstart/` mais n'y écrit jamais (ils appartiennent à `plateforme/provisioning`). Deux écrivains, deux territoires : sans cette règle, un passage du rôle effacerait une publication, ou l'inverse.
   - Contrôle sur le service rendu : `curl tftp://10.10.60.10/undionly.kpxe` (curl sait parler TFTP) et un `GET` de la racine de la PKI.
   - Molecule (instance 2049) : services actifs, les deux binaires servis en TFTP, évasion `../etc/passwd` refusée, pas de liste de répertoire, `PUT` refusé, écoute sur la seule adresse de service. Pas de téléchargement d'installateur dans le scénario (260 Mo).
   - `pare_feu_local` n'est **pas** appliqué à `pxe01` : le TFTP répond depuis un port éphémère, ce qui demande l'assistant de suivi de connexion `nf_conntrack_tftp` dans nftables ; écart noté pour M11-E13.
3. **Kea.** Le gabarit de M06-E25 ne connaît pas `next-server` : il gagne une clé facultative `serveur_suivant` par sous-réseau (et, pour la suite, `reservations` et une liste globale `kea_dhcp4_classes` : [`kea-dhcp4.conf.j2`](fichiers/M11-E02/ansible/roles/kea_dhcp4/templates/kea-dhcp4.conf.j2)). Dans `kea.yml`, un second élément `id: 60` : plage .100-.199, routeur et NTP .1, `serveur_suivant: 10.10.60.10`, `ddns: false`. Sur `dns01`, avant l'application :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/dns01.yml --limit dns01 --check --diff --tags kea
   root@dns01:~# kea-dhcp4 -t /etc/kea/kea-dhcp4.conf        # après application : déjà fait par « validate » du rôle
   root@dns01:~# printf '{"command":"config-get"}' | socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket \
                   | jq '.arguments.Dhcp4.subnet4[] | select(.id == 60) | {subnet, "next-server", pools}'
   ```
   (`playbooks/dns01.yml` et son étiquette `kea` : M06-E25.) Même configuration sur `dns02` : c'est le même gabarit avec les mêmes variables ; la haute disponibilité de Kea exige des sous-réseaux **identiques** (mêmes `id`) sur les deux pairs.
4. **Relais et flux.** Le rôle `relais_dhcp` passe à une liste `relais_dhcp_vlans` (`interface`, `adresse_locale`) ; la forme de M06/M07 (`relais_dhcp_interface`, `relais_dhcp_adresse_locale`) reste acceptée quand la liste est vide, et `relais_dhcp_actif` (M07-E24) garde son sens : le playbook `playbooks/routeurs.yml` n'applique pas le rôle là où il est faux, et le rôle lui-même n'y touche à rien. Pour `gw01` : `ens19.99` / 10.10.99.2 et `ens19.60` / 10.10.60.2 ; pour `gw02` : .3. Le fichier rendu contient, par VLAN, `interface=ens19.60` et `dhcp-relay=10.10.60.2,10.10.20.10` puis `…,10.10.20.16`. Flux **nouveaux** (matrice commune `group_vars/role_routeur/pare_feu.yml`) : entrée des passerelles (clients du VLAN 60 → relais) ; transit (renouvellements en unicast VLAN 60 → `dns01`/`dns02`) ; `pare_feu_local` de `dns01` et `dns02` (requêtes relayées depuis 10.10.20.2 et .3, renouvellements depuis 10.10.60.0/24). **Existants** : réponses de Kea au relais (règle d'entrée de M07-E24, sans destination : elle vaut pour les giaddr .2/.3 de tous les VLANs), DNS du lab, NTP, sortie Internet, MGMT → tout. Ordre d'application : Kea d'abord (un sous-réseau sans relais ne gêne personne), puis les flux, puis le relais (`playbooks/routeurs.yml`, une passerelle à la fois). `docs/socle/matrice-flux.md` est régénérée par `ms-matrice-flux`.
5. **Preuve sans client.**
   ```
   admin@pxe01:~$ sudo nmap --script broadcast-dhcp-discover -e ens18
   | broadcast-dhcp-discover:
   |   Response 1 of 2:
   |     Interface: ens18
   |     IP Offered: 10.10.60.1xx
   |     DHCP Message Type: DHCPOFFER
   |     Server Identifier: 10.10.20.10
   |     Router: 10.10.60.1
   |     Domain Name Server: 10.10.20.10, 10.10.20.16
   |     …
   ```
   Deux réponses : une par passerelle qui relaie (le maître **et** le secours relaient tous les deux, chacun avec son giaddr) — c'est normal, le client prend la première. Le `next-server` n'est pas affiché par le script (il est dans l'en-tête BOOTP, pas dans les options) : la capture le montre (`siaddr`).
   ```
   root@gw01:~# tcpdump -n -v -i any 'udp port 67 or udp port 68' -c 6
   … ens19.60 In  IP 0.0.0.0.68 > 255.255.255.255.67: BOOTP/DHCP, Request … DHCP-Message (53), length 1: Discover
   … ens19.20 Out IP 10.10.20.2.67 > 10.10.20.10.67: BOOTP/DHCP, Request … Gateway-IP 10.10.60.2 …
   … ens19.20 In  IP 10.10.20.10.67 > 10.10.60.2.67: BOOTP/DHCP, Reply … Your-IP 10.10.60.1xx Server-IP 10.10.60.10 …
   root@dns01:~# journalctl -u isc-kea-dhcp4-server --since -5min | grep -E 'DHCP4_(PACKET_RECEIVED|LEASE_ADVERT|SUBNET_SELECTED)' | tail
   ```
   (Libellés exacts des messages selon la version.) Aucun bail : `DISCOVER`/`OFFER` ne réserve rien ; un bail n'existe qu'après `REQUEST`/`ACK`. Kea garde seulement l'adresse « proposée » quelques secondes. `nmap` utilise par défaut une MAC fixe (`DE:AD:C0:DE:CA:FE`, argument `broadcast-dhcp-discover.mac`) justement pour ne pas épuiser la plage : même répété, le test ne touche qu'une entrée.
6. **Non-régression** : redémarre le réseau d'une VM du VLAN 99 (`sudo networkctl renew ens18`, ou `dhclient -r && dhclient`) et lis le bail dans Kea (`lease4-get-all` ou `/var/lib/kea/kea-leases4.csv`).

**Explications**

- **Pourquoi étendre et ne pas ajouter.** Un second serveur DHCP (dnsmasq sur `pxe01`, par exemple) serait plus simple pour le PXE, mais ferait deux sources d'adresses, deux supervisions, deux configurations à tenir en haute disponibilité. Kea sait déjà tout faire (classes, réservations, API) et il est en HA.
- **Le giaddr avec VRRP.** La VIP .1 n'existe que sur le maître : un relais qui l'utiliserait comme giaddr sur le secours enverrait des requêtes que Kea ne pourrait pas rattacher… et les réponses reviendraient vers une adresse que le secours n'a pas. Avec l'adresse propre, chaque relais reçoit les réponses à ses propres requêtes ; le client reçoit deux offres identiques (même adresse, même serveur), ce que le protocole prévoit.
- **Pas de DDNS sur le VLAN 60.** Le nom d'un serveur est décidé dans NetBox et publié par `medictl dns sync` ; si Kea publiait aussi des noms, deux écrivains se disputeraient les mêmes enregistrements (et Kea en inventerait pour les clients sans nom).

**Alternatives**
- *dnsmasq en « proxy DHCP »* sur `pxe01` : il ne donne pas d'adresse, seulement les options PXE, à côté du serveur DHCP existant. Élégant, mais il exige d'être sur le même segment que les clients (pas de relais) et ajoute un second répondant sur le VLAN.
- *UEFI HTTP Boot* : le micrologiciel télécharge directement en HTTP (classe `HTTPClient`, option 60), sans TFTP. Pris en charge par OVMF et les serveurs récents ; pas par le BIOS. Une seconde famille de classes à écrire ; intéressant pour un parc 100 % UEFI.
- *Réservations « hors plage »* : donner aux serveurs connus des adresses hors de 100-199 ; plus lisible, mais il faut une seconde plage dans le plan d'adressage. Le corrigé garde les réservations dans la plage (comportement par défaut de Kea 3.0).

**Pièges classiques**
- Oublier `dns02` : la configuration HA diverge, Kea refuse ou se comporte de façon incohérente lors d'une bascule.
- Relayer avec la VIP comme adresse locale : le relais du secours ne relaie rien, la panne n'apparaît qu'à la bascule.
- Ouvrir les réponses de Kea en **transit** alors qu'elles sont destinées à la passerelle elle-même (giaddr) : elles arrivent par la chaîne d'**entrée**.
- Garder 10.10.20.1 comme source des requêtes relayées dans `pare_feu_local` de `dns01` : depuis M07, ce sont .2 et .3. Symptôme : le VLAN 99 marche (règle ancienne encore là, par chance) mais pas le 60, ou l'inverse.
- `TFTP_ADDRESS=":69"` (défaut Debian) : tftpd écoute partout ; `--create` laissé d'un tutoriel : n'importe qui sur le VLAN dépose un `ipxe.efi` à sa façon.
- Le site `default` de nginx laissé en place : il écoute sur `0.0.0.0:80` et masque les erreurs de `server_name`.

**En production chez MédiSphère**

Un VLAN de provisioning par salle (pas de démarrage réseau sur les VLAN de production), des relais seulement sur ce VLAN, une supervision de la chaîne (TFTP et HTTP sondés, taux d'offres sans `REQUEST` dans Kea), et `pxe01` en deux exemplaires derrière la même adresse (VRRP) ou un `next-server` par salle.

---

### M11-E03 — PXE et iPXE : démarrer sur le réseau

**Solution**

Fichiers : [`envs/provisioning/bm.tf`](fichiers/M11-E03/infra/envs/provisioning/bm.tf) ; [`kea.yml`](fichiers/M11-E03/ansible/inventories/lab/group_vars/role_dns/kea.yml) (classes) ; dans `plateforme/provisioning` : [`ipxe/boot.ipxe`](fichiers/M11-E03/provisioning/ipxe/boot.ipxe), [`ipxe/menu.ipxe`](fichiers/M11-E03/provisioning/ipxe/menu.ipxe), [`outils/publier.sh`](fichiers/M11-E03/provisioning/outils/publier.sh), [`outils/verifier.sh`](fichiers/M11-E03/provisioning/outils/verifier.sh), [`.gitlab-ci.yml`](fichiers/M11-E03/provisioning/.gitlab-ci.yml), [`README.md`](fichiers/M11-E03/provisioning/README.md), [`.gitignore`](fichiers/M11-E03/provisioning/.gitignore) ; note [`demarrage-reseau.md`](fichiers/M11-E03/medisphere/docs/provisioning/demarrage-reseau.md).

1. **Les VMs.** Une ressource `for_each` sur une table locale (VMID, MAC, UEFI ou non, mémoire, disque), sans `clone` ni `initialization` : des disques vides. `bios = "ovmf"` ou `"seabios"`, `boot_order = ["net0", "scsi0"]`, un bloc `efi_disk` **dynamique** (seulement en UEFI) avec `pre_enrolled_keys = false`, `cpu.type = "host"`, `started = false`, agent activé (il servira après l'installation).
   ```
   root@pve01:~# qm config 2114 | grep -E '^(bios|boot|efidisk0|net0|cpu|machine)'
   bios: ovmf
   boot: order=net0;scsi0
   cpu: host
   efidisk0: local-nvme:vm-2114-disk-0,efitype=4m,pre-enrolled-keys=0,size=4M
   machine: q35
   net0: virtio=02:4D:53:60:00:03,bridge=vprov
   ```
   **MAC fixe** : les réservations DHCP (E06), les scripts iPXE par machine et NetBox reposent sur elle ; une MAC tirée au hasard par Proxmox changerait à chaque recréation de la VM. **Localement administrée** (deuxième bit du premier octet à 1 : `02:…`) : elle ne peut pas entrer en collision avec une adresse attribuée à un constructeur (OUI), donc avec une vraie carte du LAN, et elle se reconnaît au premier coup d'œil.
2. **Les classes** ([`kea.yml`](fichiers/M11-E03/ansible/inventories/lab/group_vars/role_dns/kea.yml)) :
   ```yaml
   kea_dhcp4_classes:
     - nom: ipxe
       test: "substring(option[77].hex,0,4) == 'iPXE'"
       fichier: http://pxe01.par1.medisphere.internal/boot.ipxe
     - nom: pxe-bios
       test: "option[93].hex == 0x0000 and not (substring(option[77].hex,0,4) == 'iPXE')"
       fichier: undionly.kpxe
     - nom: pxe-uefi-x64
       test: "(option[93].hex == 0x0007 or option[93].hex == 0x0009) and not (substring(option[77].hex,0,4) == 'iPXE')"
       fichier: ipxe.efi
   ```
   Une option absente vaut une chaîne vide dans une expression de Kea : un client sans option 93 n'entre dans aucune classe `pxe-*`. La validation avant application est faite par le rôle (`validate: kea-dhcp4 -t %s`) : une expression fautive arrête le playbook sans toucher au service (`… error: <string>:1.16: Invalid character: = …`). Pour la voir à la main : `--check --diff`, puis `kea-dhcp4 -t` sur une copie du fichier rendu.
3. **Scripts et publication.** `boot.ipxe` tente `ipxe/mac-${netX/mac:hexhyp}.ipxe` (le 404 n'est pas une erreur : `|| goto menu`), puis le menu. `menu.ipxe` affiche MAC, adresse, plate-forme, version, et démarre sur le disque (`exit`) au bout de 30 s. `publier.sh` construit un dossier temporaire puis `rsync --delete` dossier par dossier, `--rsync-path='sudo -n rsync'`, fichiers `root:root` 644 ; il refuse de publier un script sans `#!ipxe` ou un mot de passe en clair. `verifier.sh` (pipeline) : en-têtes iPXE, mots de passe, ShellCheck (et, plus tard, preseed et kickstart).
   ```
   admin@adm01:~/src/provisioning$ outils/verifier.sh && outils/publier.sh --simulation && outils/publier.sh
   admin@adm01:~$ curl -s http://pxe01.par1.medisphere.internal/boot.ipxe | head -n 1
   #!ipxe
   ```
4. **Démarrage de `bm03`.** `qm start 2114 && qm terminal 2114` (la sortie de l'UEFI va sur l'écran : noVNC est plus lisible ; la console série affiche iPXE). Séquence et preuves : voir la note. Sur `pxe01` :
   ```
   admin@pxe01:~$ sudo journalctl -t in.tftpd --since -10min
   … in.tftpd[…]: RRQ from 10.10.60.1xx filename ipxe.efi
   admin@pxe01:~$ sudo tail -n 3 /var/log/nginx/pxe-acces.log
   10.10.60.1xx - - […] "GET /boot.ipxe HTTP/1.1" 200 … "iPXE/1.21.1+…"
   10.10.60.1xx - - […] "GET /ipxe/mac-02-4d-53-60-00-03.ipxe HTTP/1.1" 404 …
   10.10.60.1xx - - […] "GET /ipxe/menu.ipxe HTTP/1.1" 200 …
   ```
   (⚠️ À vérifier sur ton lab : l'identifiant de journal de tftpd-hpa peut être `in.tftpd` ou `tftpd-hpa`.)
5. **La différence.** `bm01` (SeaBIOS) ne lit rien en TFTP : la ROM réseau des cartes virtuelles de QEMU **est** iPXE, elle s'annonce avec l'option 77 dès la première requête et reçoit directement l'URL de `boot.ipxe` ; le menu affiche alors une version d'iPXE différente de celle du paquet Debian (celle embarquée par QEMU). En UEFI, OVMF utilise sa propre pile PXE (sans option 77) : séquence complète, avec `ipxe.efi`. Sur un vrai serveur, le BIOS ferait la séquence complète avec `undionly.kpxe`. (⚠️ À vérifier sur ton lab : le comportement exact dépend des ROM livrées avec ta version de `pve-qemu`.)
6. La note : [`demarrage-reseau.md`](fichiers/M11-E03/medisphere/docs/provisioning/demarrage-reseau.md).

**Explications**

- **`exit` pour démarrer sur le disque.** iPXE rend la main au micrologiciel, qui essaie le périphérique suivant de son ordre de démarrage (le disque). C'est plus portable que `sanboot --drive 0x80` (BIOS seulement) et que de deviner le chemin EFI du chargeur du disque.
- **`${netX}`** désigne la dernière interface ouverte (celle qui vient d'obtenir son bail) : le script marche quel que soit le nombre de cartes.
- **Secure Boot désactivé.** `pre-enrolled-keys=0` : OVMF démarre sans clés Microsoft, donc sans Secure Boot, et accepte le `ipxe.efi` non signé du paquet Debian. En production, on garderait Secure Boot avec un chargeur signé (*shim* + iPXE 2.0 signé, ou le *shim* des distributions) : sujet de M11-E13.

**Alternatives**
- *Une seule ressource par VM* au lieu du `for_each` : quatre blocs presque identiques, des différences invisibles. La table locale rend les écarts (UEFI, mémoire) lisibles d'un coup d'œil.
- *Menu servi par TFTP* (pxelinux, GRUB réseau) : possible, mais on retombe dans les limites de TFTP ; iPXE + HTTP est la norme des chaînes modernes (MAAS, Tinkerbell, netboot.xyz).
- *`publier.sh` remplacé par le rôle Ansible* (un `synchronize` depuis le dépôt) : un seul outil de déploiement, mais le rôle aurait alors à connaître un second dépôt et le rendu de NetBox ; la séparation garde un territoire par écrivain.

**Pièges classiques**
- Classes non exclusives : iPXE (qui envoie aussi l'option 93) entre dans `pxe-bios` **et** `ipxe` ; il reçoit la valeur de la première classe définie, souvent `undionly.kpxe` : boucle.
- Oublier `--autofree`/`|| goto` : un 404 sur le script par MAC arrête iPXE au lieu de passer au menu.
- `${net0/mac}` au lieu de `${netX/mac}` : faux sur une machine à plusieurs cartes, où la carte qui a démarré n'est pas forcément `net0`.
- Fichier enregistré avec une marque d'ordre d'octets (BOM) ou des fins de ligne CRLF : iPXE ne reconnaît pas `#!ipxe` (« Exec format error »).
- OVMF avec clés préinstallées : « Access Denied » ou retour immédiat au menu du micrologiciel au chargement de `ipxe.efi`.
- Démarrer les VMs par OpenTofu (`started = true`) : chaque `apply` qui recrée une VM la lance en installation.

**En production chez MédiSphère**

Les serveurs réels n'ont pas de « MAC fixée par OpenTofu » : la MAC est lue à la réception (étiquette, bon de livraison, ou BMC) et saisie dans NetBox (E06). Les scripts iPXE sont signés (`imgtrust`, `imgverify`) ou servis en HTTPS (M11-E13) ; le menu par défaut est désactivé sur les VLAN de production (un serveur inconnu n'y démarre rien).

---

### M11-E04 — Installer Debian sans intervention (preseed)

**Solution**

Fichiers : outil [`pxe-installateurs`](fichiers/M11-E02/ansible/roles/pxe/files/pxe-installateurs) (rôle `pxe`) et [`host_vars/pxe01/pxe.yml`](fichiers/M11-E04/ansible/inventories/lab/host_vars/pxe01/pxe.yml) ; [`preseed/debian13.cfg`](fichiers/M11-E04/provisioning/preseed/debian13.cfg) ; [`ipxe/menu.ipxe`](fichiers/M11-E04/provisioning/ipxe/menu.ipxe).

1. **Installateur vérifié.** `pxe-installateurs debian debian13 trixie https://deb.debian.org/debian /srv/http`, lancé par le rôle pour chaque élément de `pxe_installateurs`. Chaîne : `Release` + `Release.gpg` → `gpgv` avec `debian-archive-keyring` → empreinte de `main/installer-amd64/current/images/SHA256SUMS` lue dans la section `SHA256:` du `Release` → `SHA256SUMS` téléchargé et comparé → empreintes de `netboot/debian-installer/amd64/linux` et `initrd.gz` → publication. Le `Release` de trixie porte **trois** signatures (clés de bookworm, de trixie et une clé plus récente) : `gpgv` sort en erreur s'il lui manque une seule clé publique ; l'outil fait comme apt (au moins une `VALIDSIG`, aucune `BADSIG`, `EXPKEYSIG` ni `REVKEYSIG`, lus par `--status-fd`). Publication **atomique** : copie dans `.versions/debian13.<horodatage>/`, puis lien `debian13` remplacé par `mv -T` (un renommage est atomique) ; deux versions gardées pour revenir en arrière. Sortie `inchangé` / `mis à jour` → `changed_when` du rôle.
   ```
   admin@pxe01:~$ cat /srv/http/debian13/EMPREINTES
   2b2358b3…0e08  linux
   57303d15…5f2  initrd.gz
   ```
   Preuve du refus, sur une copie : modifie un octet du `Release` téléchargé et rejoue `gpgv` (BADSIG) ; ou appelle l'outil avec un miroir qui ne répond pas (`curl` 404, code 22, rien n'est publié).
2. **Le preseed** : lis le fichier, il est commenté section par section. Points clés : réseau en DHCP sur l'interface qui a un lien ; miroir `deb.debian.org` et dépôts `security` et `updates` ; `passwd/root-login false` (root verrouillé, `admin` dans `sudo`) ; `passwd/user-password-crypted` ; LVM « atomic » sur `/dev/sda` ; `grub-installer/force-efi-extra-removable` ; `pkgsel/include` (agent QEMU, sudo, curl, ca-certificates) ; `late_command` qui télécharge la racine de la PKI, **compare son empreinte** à celle écrite dans le fichier et échoue sinon, puis dépose la clé SSH ; `debian-installer/exit/poweroff true`. Empreinte du mot de passe :
   ```
   admin@adm01:~$ sudo apt install whois        # fournit mkpasswd
   admin@adm01:~$ mkpasswd -m sha-512           # demande le mot de passe, sans écho, n'affiche que l'empreinte
   Password:
   $6$…
   admin@adm01:~$ sha256sum /usr/local/share/ca-certificates/medisphere-root-ca.crt
   ```
   Le mot de passe lui-même va dans ton gestionnaire de mots de passe (console de secours). Pipeline : `verifier.sh` lance `debconf-set-selections -c` et refuse `passwd/…-password password <valeur>`, `--plaintext`, etc.
3. **Le menu** : entrée `debian13` — `kernel …/debian13/linux initrd=initrd.gz auto=true priority=critical url=…/preseed/debian13.cfg hostname=bm-${netX/mac:hexhyp} domain=par1.medisphere.internal`, puis `initrd …/initrd.gz`, `boot` ; chaque commande avec `|| goto erreur`.
4. **`bm01`.** Menu → « Debian 13 (preseed) » → plus rien à toucher. Durée typique : 8 à 15 minutes (selon le débit vers le miroir). La VM s'éteint ; `qm start 2112` → menu → 30 s → disque.
5. **Contrôles.**
   ```
   root@pve01:~# qm guest cmd 2112 network-get-interfaces | jq -r '.[] | select(.name != "lo") | .["ip-addresses"][] | select(.["ip-address-type"] == "ipv4") | .["ip-address"]'
   10.10.60.1xx
   admin@adm01:~$ ssh admin@10.10.60.1xx 'hostname; sudo -n true && echo sudo-ok; sudo -n lvs --noheadings -o lv_name,vg_name; ls -l /usr/local/share/ca-certificates/; sudo -n passwd -S root'
   bm-02-4d-53-60-00-01
   sudo-ok
     root   bm-02-4d-53-60-00-01-vg
     swap_1 bm-02-4d-53-60-00-01-vg
   -rw-r--r-- 1 root root … medisphere-root-ca.crt
   root L …                                   # L : mot de passe verrouillé
   ```
   La clé d'hôte SSH n'est pas encore signée (elle le sera par `ssh_ca_hote` quand la machine entrera dans l'inventaire, M11-E15) : la première connexion demande d'accepter une empreinte, à comparer avec `qm guest exec 2112 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.
6. **`bm03` (UEFI)** : même fichier. Différences : une partition système EFI (FAT32, `/boot/efi`) en tête de disque, table GPT ; `grub-efi-amd64` installé, une entrée de démarrage `debian` dans la NVRAM d'OVMF **et** la copie de secours `\EFI\BOOT\BOOTX64.EFI` (grâce à `force-efi-extra-removable`). L'ordre de démarrage reste réseau d'abord : OVMF reconstruit son ordre à partir de celui que Proxmox lui transmet (⚠️ à vérifier sur ton lab ; si la VM démarre sur `debian` avant le réseau, c'est sans conséquence ici, mais la chaîne ne pourrait plus réinstaller cette machine par le réseau sans corriger l'ordre).

**Explications**

- **Qui vérifie quoi.** Le Release est signé par les clés de l'archive Debian ; `SHA256SUMS` des images y est référencé ; les images sont référencées par `SHA256SUMS`. On vérifie sur `pxe01`, une fois, ce que des dizaines de serveurs vont exécuter. Entre `pxe01` et les serveurs, HTTP clair : l'intégrité repose sur le réseau (VLAN dédié) jusqu'à M11-E13.
- **`late_command` qui échoue.** debian-installer affiche alors une erreur et attend : le serveur ne sort pas « installé » sans la bonne racine. Mieux vaut une installation arrêtée qu'un serveur qui fait confiance à une racine substituée.
- **Un mot de passe pour la console seulement.** La connexion SSH par mot de passe est désactivée par les rôles `ssh_durci` (M04) au premier passage d'Ansible ; avant cela, Debian accepte par défaut les mots de passe en SSH : la fenêtre entre la fin d'installation et le premier passage d'Ansible est un risque, réduit par le mot de passe long et l'isolement du VLAN 60. Une ligne de `late_command` (`PasswordAuthentication no` dans `/target/etc/ssh/sshd_config.d/`) la fermerait dès l'installation : bon réflexe, garde-la si tu veux.

**Alternatives**
- *Image disque* (le template doré, M03) écrite directement sur le disque par un petit système de démarrage (*image-based provisioning*, comme MAAS avec ses images, ou Tinkerbell) : bien plus rapide (une minute), identique octet pour octet ; mais il faut un système réseau intermédiaire et une image par type de matériel (pilotes, firmware).
- *Cloud-init* sur une installation minimale : le preseed fait le minimum, cloud-init (source « NoCloud » servie par HTTP) fait le reste. Un seul mécanisme pour VMs et serveurs ; une dépendance de plus sur le serveur.
- *Preseed dans l'initrd* (fichier `preseed.cfg` ajouté à l'initrd) : pas de téléchargement, mais un initrd à reconstruire à chaque changement.

**Pièges classiques**
- `gpgv` « en échec » à cause d'une clé manquante alors qu'une signature est bonne (ou, à l'inverse, un `|| true` qui accepte tout) : lis `--status-fd`.
- Oublier `initrd=initrd.gz` en UEFI : le noyau démarre sans initrd (« VFS: Unable to mount root fs »).
- `hostname` dans le preseed de `url=` : ignoré (le réseau est déjà configuré) ; l'installateur prend le nom de la réponse DHCP ou `debian`.
- `partman-auto/disk` absent sur une machine à plusieurs disques : l'installateur pose la question (installation bloquée) — ou pire, choisit un disque inattendu.
- Redémarrage en fin d'installation (`reboot_in_progress` sans `exit/poweroff`) : la VM repart sur le réseau, et un menu dont le défaut serait « installer » la réinstallerait.
- Clé SSH collée avec un retour à la ligne dans le preseed : `authorized_keys` invalide, échec de connexion silencieux (lis `/var/log/auth.log` sur la machine).

**En production chez MédiSphère**

Un cache de paquets (apt-cacher-ng) ou un miroir interne signé ; preseed et kickstart servis en HTTPS ou des scripts iPXE signés (E13) ; mot de passe de console **différent par serveur** (généré, déposé dans Vault, M25) ; contrôles d'acceptation automatiques après installation (RB-110, E12).

---

### M11-E05 — Installer Rocky Linux sans intervention (kickstart)

**Solution**

Fichiers : [`host_vars/pxe01/pxe.yml`](fichiers/M11-E05/ansible/inventories/lab/host_vars/pxe01/pxe.yml) ; [`kickstart/rocky10.ks`](fichiers/M11-E05/provisioning/kickstart/rocky10.ks) ; [`ipxe/menu.ipxe`](fichiers/M11-E05/provisioning/ipxe/menu.ipxe).

1. **Installateur.** `pxe-installateurs rocky rocky10 10.2 https://dl.rockylinux.org/pub/rocky /srv/http` : `.treeinfo` du dépôt BaseOS 10.2 (vérifie aussi que sa ligne `version = 10.2` correspond), empreintes `images/pxeboot/vmlinuz` et `images/pxeboot/initrd.img` de la section `[checksums]`, téléchargement et comparaison, publication atomique. **Ce que ça garantit** : les fichiers sont ceux que décrit le `.treeinfo` du miroir officiel, joint en HTTPS avec un certificat vérifié (et `--proto-redir =https` : pas de redirection vers HTTP). **Ce que ça ne garantit pas** : `.treeinfo` n'est pas signé ; un miroir compromis (ou une erreur de synchronisation) pourrait servir un `.treeinfo` et des images cohérents mais faux. Debian a une signature détachée de bout en bout ; pour Rocky, l'équivalent passerait par l'image ISO (`CHECKSUM` signé de `isos/`) dont on extrairait `images/pxeboot/` : plus lourd, à envisager en production. Les **paquets**, eux, sont vérifiés par dnf (clé GPG de Rocky dans l'installateur).
2. **Le kickstart** (lis-le) : `text`, `url` et `repo` en HTTPS sur la **même** version mineure, `timesource --ntp-server` (forme RHEL 9/10 ; `timezone --ntpservers` est dépréciée), `network --bootproto=dhcp --device=link`, `rootpw --lock`, `user … --iscrypted`, `sshkey`, `ignoredisk --only-use=sda` + `clearpart --all --drives=sda` + `autopart --type=lvm`, `selinux --enforcing`, `firewall --enabled --service=ssh`, `services`, `%packages` (`@^minimal-environment`, agent, curl), `%post --erroronfail` qui vérifie l'empreinte de la racine avant `update-ca-trust`, `poweroff`.
   ```
   admin@adm01:~/src/provisioning$ uvx --from pykickstart==3.78 ksvalidator -v RHEL10 kickstart/rocky10.ks
   Checking kickstart file kickstart/rocky10.ks
   ```
   (Aucune autre ligne = valide ; une erreur indique la ligne et l'option.)
3. **Menu** : `kernel …/rocky10/vmlinuz initrd=initrd.img inst.repo=https://dl.rockylinux.org/pub/rocky/10.2/BaseOS/x86_64/os/ inst.ks=…/kickstart/rocky10.ks ip=dhcp`, `initrd …/initrd.img`. Installation de `bm04` : 10 à 20 minutes ; Anaconda télécharge d'abord `install.img` (environ 900 Mo, en mémoire : d'où les 3 Gio).
4. **Contrôles.**
   ```
   admin@adm01:~$ ssh admin@10.10.60.1xx 'sudo -n true && echo sudo-ok; getenforce; sudo -n firewall-cmd --list-services; sudo -n lvs --noheadings -o lv_name; trust list --filter=ca-anchors | grep "MédiSphère Root CA"'
   sudo-ok
   Enforcing
   cockpit dhcpv6-client ssh
   root
   swap
       label: MédiSphère Root CA
   ```
   Pour prouver la confiance (et pas seulement la présence), copie un certificat du socle sur la machine et vérifie-le : `openssl verify -CAfile /etc/pki/tls/certs/ca-bundle.crt <certificat>` (aucun service HTTPS du socle n'est joignable depuis le VLAN 60, et c'est voulu). Les services `cockpit` et `dhcpv6-client` viennent de la zone par défaut de `firewalld` : à retirer dans le rôle de durcissement (M26), ou dès le kickstart (`firewall --enabled --service=ssh --remove-service=cockpit,dhcpv6-client`, ⚠️ à vérifier avec `ksvalidator` et sur ta version).
5. **Comparatif** :

   | | preseed (debian-installer) | kickstart (Anaconda) |
   |---|---|---|
   | Source des paquets | miroir apt (`mirror/http/*`), Release signé | `url` + `repo` (dépôts dnf), paquets signés |
   | Partitionnement | `partman-auto` (recettes `atomic`, `home`, `multi`), syntaxe ésotérique | `autopart` ou `part`/`logvol`, lisible |
   | Comptes | questions `passwd/*`, root ou premier utilisateur sudo | `rootpw`, `user`, `sshkey` explicites |
   | Commande finale | `preseed/late_command` (une ligne, `/target`, `in-target`) | `%post` (script complet, chroot par défaut, `--erroronfail`, `--log`) |
   | Validation hors ligne | `debconf-set-selections -c` (syntaxe seulement) | `ksvalidator -v RHEL10` (commandes et options) |

**Explications**

- **Version mineure fixée.** Anaconda refuse un `install.img` (stage 2) d'une autre version que son initrd. `10` (lien vers la dernière mineure) marche… jusqu'à la sortie de la 10.3, où le dépôt change et l'initrd téléchargé la veille ne correspond plus. Fixer `10.2` à trois endroits (rôle, menu, kickstart) et monter de version par une MR qui change les trois rend le changement visible. À la sortie de la 10.3, la 10.2 part dans `vault.rockylinux.org` : c'est le signal de la MR.
- **`%post` chrooté** : par défaut, `%post` s'exécute dans le système installé, réseau actif ; `--nochroot` l'exécute dans l'installateur (le système est sous `/mnt/sysroot`).

**Alternatives**
- *Miroir interne* (dépôt Rocky synchronisé par `dnf reposync` sur `pxe01` ou un dépôt Pulp) : installations rapides et reproductibles (les paquets ne bougent pas pendant la vague), dépendance Internet supprimée.
- *Image de démarrage sur `pxe01`* avec `inst.stage2=http://pxe01…/rocky10/` : l'image d'installation vient de notre serveur, les paquets d'ailleurs.

**Pièges classiques**
- 2 Go de mémoire : Anaconda échoue au chargement de `install.img` (« not enough RAM », ou le noyau tue le processus) ; 3 Gio pour une installation HTTP.
- `clearpart --all` sans `--drives` ni `ignoredisk` : sur un serveur à plusieurs disques, **tous** sont effacés.
- CPU `x86-64-v2-AES` (le type par défaut de nos VMs) : le noyau de Rocky 10 refuse de démarrer (« CPU not supported ») ; d'où `host`.
- `inst.ks=` avec `https` sans que l'installateur connaisse la CA : échec TLS (et pas de `inst.noverifyssl` !). En HTTP pour l'instant, HTTPS en M11-E13.
- `%post` sans `--erroronfail` : une racine refusée laisse quand même un serveur « installé ».

**En production chez MédiSphère**

Même vigilance qu'en E04, plus : abonnement aux annonces de sécurité de Rocky pour savoir quand monter de mineure, et un test d'installation automatique dans le pipeline du projet (une VM jetable installée par la chaîne à chaque MR qui touche un kickstart).
