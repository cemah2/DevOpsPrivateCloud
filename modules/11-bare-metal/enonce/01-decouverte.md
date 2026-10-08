# Module 11 — Palier 1 : Découverte

Un serveur neuf n'a rien : pas de système, pas d'adresse, pas de nom. Ce palier construit ce qu'il trouve en démarrant sur le réseau : un sous-réseau DHCP qui le reconnaît (BIOS, UEFI ou iPXE), un serveur TFTP et HTTP qui lui donne de quoi démarrer, puis deux installations qui se déroulent sans personne devant l'écran, l'une pour Debian 13, l'autre pour Rocky Linux 10. NetBox n'intervient pas encore : les choix se font dans un menu iPXE, et c'est au palier 2 qu'ils viendront de la source de vérité.

Prérequis : module 07 terminé (`socle-v2` : `gw01` et `gw02` en VRRP) et `lab/bin/check 06 46` vert. Lis [`00-introduction.md`](00-introduction.md), en particulier la séquence de démarrage, les flux et les règles du module.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| VLAN 60 PROV | 10.10.60.0/24, VNet `vprov`, passerelle (VIP) 10.10.60.1 ; `gw01` = .2, `gw02` = .3 |
| `pxe01` | VMID 2111, 10.10.60.10, `pxe01.par1.medisphere.internal`, état OpenTofu `envs/provisioning` |
| `bm01`-`bm04` | VMID 2112-2115, MAC `02:4d:53:60:00:01` à `:04`, SeaBIOS (`bm01`, `bm02`) / OVMF (`bm03`, `bm04`) |
| Kea | sous-réseau `id: 60`, plage 10.10.60.100-199, `next-server` 10.10.60.10 ; rôle `kea_dhcp4` (M06-E16 à E25), `group_vars/role_dns/kea.yml` |
| Projet | `plateforme/provisioning`, copie de travail `~/src/provisioning` |

---

### M11-E01 — Test de positionnement : installer des serveurs  `Q` `★★`

> **Ticket PLAT-1201** — *De : Karim Benali*
> Le rituel, version « salle machine » : DHCP, PXE, TFTP, micrologiciels, installateurs, contrôleurs de gestion. Par écrit, sans moteur de recherche ni IA, sans rien exécuter, 45 minutes. Tu as sûrement déjà installé des serveurs ; ici on regarde ce qui se passe avant que le premier octet du système n'arrive sur le disque.

**Objectifs pédagogiques**
- Évaluer tes acquis sur le démarrage réseau et l'installation automatisée.
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 45 min (+ 20 min d'auto-correction).

**Travail demandé**

Réponds aux 15 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*DHCP et PXE*

1. Un client PXE envoie un `DHCPDISCOVER`. Cite les deux champs (ou options) de la réponse qui lui disent **où** et **quoi** télécharger. Quelle est la différence entre le champ `siaddr` (*next-server*) et l'option 66 ?

2. *(QCM)* Un serveur DHCP doit donner `undionly.kpxe` à un client BIOS et `ipxe.efi` à un client UEFI x86-64. Sur quoi se fonde-t-il de la façon la plus fiable ?
   - A. L'adresse MAC du client (préfixe du constructeur)
   - B. L'option 93 (*client system architecture*) de la requête
   - C. La taille de la requête DHCP
   - D. L'option 12 (*host name*)

3. Le client et le serveur DHCP ne sont pas sur le même VLAN. Que fait le relais ? Pourquoi le relais n'a-t-il **pas** à relayer le TFTP, alors qu'il relaie le DHCP ?

4. Pourquoi TFTP plutôt que HTTP à la toute première étape ? Cite deux défauts de TFTP qui justifient de n'y faire passer que le minimum.

*iPXE et chaînage*

5. Décris la « boucle infinie » du chaînage iPXE : PXE charge iPXE, qui refait une requête DHCP, qui… Comment le serveur DHCP la casse-t-il ?

6. *(QCM)* Quel fichier un client UEFI x86-64 avec **Secure Boot actif** et les clés Microsoft peut-il exécuter tel quel ?
   - A. `undionly.kpxe`
   - B. Un `ipxe.efi` compilé depuis les sources, non signé
   - C. Un chargeur signé par Microsoft (par exemple *shim*), qui vérifie à son tour la suite
   - D. N'importe quel binaire EFI, Secure Boot ne s'applique qu'au noyau

7. Un serveur installé redémarre. Sa carte réseau est en premier dans l'ordre de démarrage. Que faut-il prévoir pour qu'il ne se réinstalle pas en boucle ? Donne deux approches.

*Installateurs*

8. Pour debian-installer, que font les paramètres noyau `auto=true` et `priority=critical` ? Pourquoi le nom d'hôte se passe-t-il sur la ligne de commande du noyau plutôt que dans le preseed téléchargé par `url=` ?

9. *(QCM)* Dans un kickstart, laquelle de ces lignes est acceptable pour le compte `admin` ?
   - A. `user --name=admin --password=MotDePasse123`
   - B. `user --name=admin --iscrypted --password=$6$…`
   - C. `user --name=admin --plaintext --password=MotDePasse123` dans un fichier en mode 600 sur le serveur HTTP
   - D. Aucune : un kickstart ne peut pas créer d'utilisateur

10. Un installateur télécharge son noyau, son initrd et ses paquets sur le réseau. Où se situe la vérification d'intégrité dans chacun des trois cas, pour Debian ? Qu'est-ce qui n'est **pas** vérifié si le preseed est servi en HTTP ?

11. Pourquoi terminer une installation automatique par une **extinction** plutôt que par un redémarrage, dans une chaîne pilotée par une source de vérité ?

*Contrôleurs de gestion*

12. Qu'est-ce qu'un BMC ? Cite quatre choses qu'il permet de faire même quand le système du serveur est arrêté ou planté.

13. *(QCM)* Pourquoi recommande-t-on de désactiver IPMI over LAN quand Redfish est disponible ?
    - A. IPMI est plus lent que Redfish
    - B. L'authentification RAKP d'IPMI 2.0 permet de récupérer une empreinte du mot de passe crackable hors ligne, et le chiffrement « cipher 0 » peut contourner l'authentification
    - C. IPMI ne permet pas d'éteindre un serveur
    - D. IPMI exige une licence

14. Un BMC présente un certificat TLS autosigné. Cite trois façons de lui parler en HTTPS **sans** désactiver la vérification, de la plus rapide à la plus propre.

*Outils*

15. Compare en quelques lignes une chaîne maison (DHCP + TFTP + HTTP + gabarits) et un outil intégré comme MAAS : qui détient l'état des machines, qui pilote l'alimentation, qu'est-ce qui se passe si l'outil tombe ?

**Critères de réussite**
- [ ] Les 15 réponses sont rédigées dans ton journal (`~/m11/e01/reponses.md`), avant toute lecture du corrigé.
- [ ] Auto-correction faite avec le barème du corrigé ; les notions à revoir sont notées en tête du fichier.

<details><summary>Indice 1</summary>

Pour les questions 1 à 5, dessine l'échange : client, relais, serveur DHCP, serveur TFTP, serveur HTTP, en notant qui envoie quoi à qui (diffusion ou unicast).
</details>

<details><summary>Indice 2</summary>

Pour la question 10, distingue « authentifié » (on sait qui l'a produit) et « intègre » (pas modifié en route) : une somme de contrôle téléchargée au même endroit que le fichier ne prouve que la seconde, et encore.
</details>

**Pour aller plus loin** (facultatif) : la spécification PXE 2.1 d'Intel (1999) est courte et toujours lisible ; compare-la avec le *HTTP Boot* d'UEFI 2.5, qui se passe de TFTP.

---

### M11-E02 — Le réseau de provisioning  `LAB` `★★`

> **Ticket PLAT-1202** — *De : Karim Benali*
> Avant de parler d'installation, il faut qu'un serveur branché sur le VLAN 60 obtienne une adresse et trouve un serveur de démarrage. Le VLAN existe dans le plan d'adressage depuis le module 00, il n'a jamais servi. Kea et le relais sont déjà en place pour le VLAN 99 : on étend, on ne bricole pas un dnsmasq de plus. Et `pxe01` passe par le chemin habituel, OpenTofu puis Ansible.

**Objectifs pédagogiques**
- Étendre un service DHCP existant (Kea en haute disponibilité, relais redondant) à un nouveau VLAN sans perturber les autres.
- Déployer un serveur TFTP et HTTP de démarrage avec un rôle Ansible testé.
- Vérifier un échange DHCP relayé de bout en bout sans client installé.

**Prérequis** : M06-E16, M06-E25 (Kea, relais), M06-E30 (filtrage local), M07-E24/E25 (deux passerelles, VRRP), M05 (pipeline de `plateforme/infra`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Sous-réseau à servir : voir « Faits communs ». Routeur et serveur NTP : 10.10.60.1 (VIP). DNS : 10.10.20.10 et 10.10.20.16. Pas de mise à jour DNS dynamique sur ce sous-réseau : les noms des serveurs viendront de NetBox (E06). Durée de bail : celle du sous-réseau 99, ou plus courte (justifie).
- Le relais tourne sur `gw01` **et** `gw02` (M07). Kea choisit le sous-réseau d'après le giaddr : chaque passerelle relaie avec **sa propre** adresse dans le VLAN.
- `pxe01` : voir l'introduction (ressources, étiquettes `env-m11` et `role-pxe`, adresse imposée). Groupe d'inventaire `role_pxe`. Paquets Debian : `tftpd-hpa`, `nginx`, `ipxe` (qui fournit `/usr/lib/ipxe/undionly.kpxe` et `/usr/lib/ipxe/ipxe.efi`).
- Répartition des fichiers sur `pxe01` : le rôle Ansible gère `/srv/tftp`, la configuration des services et les dossiers `/srv/http/{debian13,rocky10,pki}` ; le projet `plateforme/provisioning` publiera `boot.ipxe`, `ipxe/`, `preseed/`, `kickstart/` (E03). Le rôle crée ces derniers dossiers mais n'y écrit pas.
- ⚠️ Kea et le relais servent aussi le VLAN 99. Une configuration invalide sur `dns01`/`dns02`, ou un relais mal écrit, coupe le DHCP de la sandbox. Instantanés (`ms-snapshot --prefix avant-m11`) de `dns01`, `dns02`, `gw01`, `gw02` avant l'application ; retour arrière = MR inverse appliquée par le pipeline, ou retour à l'instantané si le pipeline lui-même ne passe plus.

**Travail demandé**
1. **OpenTofu.** Crée l'environnement `envs/provisioning/` dans `plateforme/infra` (état séparé du socle, même backend) et déclare `pxe01` avec `vm-debian` et son nom DNS. MR, plan relu, `apply` par le pipeline.
2. **Le rôle `pxe`.** Dans `plateforme/ansible`, écris le rôle : TFTP limité à l'adresse de service et à sa racine, aucun envoi de fichier possible ; HTTP en lecture seule sur 10.10.60.10:80, sans liste de répertoires, limité aux réseaux qui en ont besoin (justifie lesquels) ; binaires iPXE copiés du paquet ; racine de la PKI publiée sous `/srv/http/pki/medisphere-root-ca.crt`. Contrôle final dans le rôle sur le service **rendu** (un téléchargement TFTP, un HTTP). Scénario Molecule, ansible-lint `production`, playbook pour le groupe `role_pxe`.
3. **Kea.** Ajoute le sous-réseau 60 à la configuration générée par `kea_dhcp4` (fais évoluer le gabarit si une clé te manque : `next-server`), sans toucher au sous-réseau 99. La configuration doit rester identique sur les deux pairs.
4. **Relais et flux.** Ajoute le VLAN 60 au relais des deux passerelles, puis les flux DHCP nécessaires (lis le tableau de l'introduction : lesquels existent déjà ?) dans la matrice de la bordure **et** dans le filtrage local de `dns01`/`dns02`. Reporte-les dans `docs/socle/matrice-flux.md`.
5. **Preuve sans client.** Depuis `pxe01` (qui a une adresse fixe et ne prend pas de bail), provoque un `DHCPDISCOVER` diffusé sur le VLAN 60 et montre l'`OFFER` reçu, avec son adresse proposée, son routeur et son `next-server`. Retrouve l'échange dans le journal de Kea **et** dans une capture sur la passerelle maître. Explique pourquoi ce test ne laisse aucun bail actif.
6. **Non-régression.** Montre qu'une VM du VLAN 99 obtient toujours un bail après tes changements.

**Critères de réussite**
- [ ] `pxe01` (2111) existe sur `vprov`, répond en SSH à 10.10.60.10, et `pxe01.par1.medisphere.internal` se résout (direct et inverse).
- [ ] TFTP sert `undionly.kpxe` et `ipxe.efi` ; HTTP sert la racine de la PKI ; aucun des deux n'écoute sur toutes les adresses.
- [ ] La configuration **chargée** par Kea, sur `dns01` comme sur `dns02`, contient le sous-réseau 60 avec sa plage, son routeur et son `next-server` ; le sous-réseau 99 est inchangé.
- [ ] Le relais de `gw01` et celui de `gw02` écoutent sur `ens19.60` ; un `DHCPDISCOVER` émis depuis le VLAN 60 reçoit une offre dans 10.10.60.100-199.
- [ ] La matrice des flux (code et documentation) contient les flux DHCP du VLAN 60.

**Vérification** : `lab/bin/check 11 02`

<details><summary>Indice 1</summary>

Pour le test sans client, `nmap` sait diffuser un `DHCPDISCOVER` et afficher l'offre (script `broadcast-dhcp-discover`, option `-e` pour choisir l'interface). Un `DISCOVER` suivi d'une `OFFER` ne crée pas de bail : seul le couple `REQUEST`/`ACK` le fait.
</details>

<details><summary>Indice 2</summary>

Dans Kea, `next-server` est une clé de sous-réseau (et de classe) ; dans le gabarit du rôle, ajoute-la comme une clé facultative de chaque élément de `kea_dhcp4_sous_reseaux`. Pour le relais, la directive `dhcp-relay` de dnsmasq prend l'adresse **locale** comme premier champ : la VIP n'existe que sur le maître.
</details>

<details><summary>Indice 3</summary>

Les réponses de Kea reviennent au **giaddr** (10.10.60.2 ou .3), donc vers la passerelle elle-même (chaîne d'entrée), pas en transit. Et `dns01`/`dns02` reçoivent les requêtes relayées depuis l'adresse INFRA des passerelles, qui n'est plus 10.10.20.1 depuis le module 07.
</details>

**Pour aller plus loin** (facultatif) : lis la section *Host Reservations* de Kea et la différence entre réservations « dans la plage » et « hors plage » (`reservations-in-subnet`, `reservations-out-of-pool`) : laquelle conviendra aux serveurs du palier 2 ?

---

### M11-E03 — PXE et iPXE : démarrer sur le réseau  `LAB` `★★`

> **Ticket PLAT-1203** — *De : Karim Benali*
> Le premier lot sera mixte : des vieux serveurs en BIOS, des neufs en UEFI. Prépare quatre « serveurs nus » dans le lab, deux de chaque, et fais-les arriver jusqu'à un menu iPXE qui affiche ce qu'il sait d'eux. Pas d'installation aujourd'hui : je veux d'abord voir la chaîne de démarrage fonctionner, et comprendre ce qui passe par TFTP et ce qui passe par HTTP.

**Objectifs pédagogiques**
- Créer des machines sans système, à adresse MAC fixe, en BIOS et en UEFI, par OpenTofu.
- Écrire des classes DHCP qui distinguent un micrologiciel BIOS, UEFI et iPXE.
- Écrire un script iPXE de démarrage et un menu, et les publier par un outil versionné.

**Prérequis** : M11-E02.
**Durée indicative** : 2 h 30.

**Contexte technique**
- `bm01` à `bm04` : voir l'introduction (VMID, MAC, firmware, mémoire, disque). Ordre de démarrage : réseau d'abord, disque ensuite. CPU `host` (Rocky Linux 10 exige x86-64-v3). Pas de cloud-init, pas de clone : des disques vides. Les VMs ne sont **pas** démarrées par OpenTofu.
- OVMF : un disque EFI est nécessaire ; **sans clés préinstallées** (Secure Boot désactivé).
- Classes attendues : `pxe-bios` (option 93 = `0x0000`) → `undionly.kpxe` ; `pxe-uefi-x64` (option 93 = `0x0007` ou `0x0009`) → `ipxe.efi` ; `ipxe` (option 77 commence par `iPXE`) → `http://pxe01.par1.medisphere.internal/boot.ipxe`. Un client ne doit appartenir qu'à **une** de ces classes.
- Dans `plateforme/provisioning` : `ipxe/boot.ipxe` (publié à la racine HTTP) cherche d'abord un script propre à la machine, `ipxe/mac-<MAC avec des tirets>.ipxe`, et à défaut charge `ipxe/menu.ipxe`. Le menu affiche au moins la MAC, l'adresse, la plate-forme (`pcbios` ou `efi`) et la version d'iPXE, et démarre sur le disque local par défaut au bout de 30 secondes.
- Publication : un script `outils/publier.sh` du projet copie `ipxe/boot.ipxe` et les dossiers `ipxe/`, `preseed/`, `kickstart/` vers `pxe01:/srv/http/` (rsync en SSH, `sudo -n` côté `pxe01`), en supprimant ce qui n'est plus dans le dépôt, **seulement** dans ces dossiers.

**Travail demandé**
1. Déclare `bm01` à `bm04` dans `envs/provisioning/`. Après l'`apply`, lis la configuration Proxmox de `bm01` et `bm03` (`qm config`) : retrouve l'ordre de démarrage, la MAC, le firmware et le disque EFI. Pourquoi une MAC fixe ? Pourquoi « localement administrée » ?
2. Ajoute les trois classes à Kea (rôle `kea_dhcp4`) ; prouve sur `dns01` que la configuration est valide **avant** de l'appliquer.
3. Crée `boot.ipxe` et `menu.ipxe`, puis `outils/publier.sh` (ShellCheck propre, `set -euo pipefail`, aucun secret). Ajoute au pipeline du projet une étape qui vérifie que chaque fichier de `ipxe/` commence par `#!ipxe` et que `publier.sh` passe ShellCheck. Publie.
4. Démarre `bm03` (UEFI) en suivant la console (`qm terminal 2114` ou noVNC). Puis `bm01` (BIOS). Pour chacune, reconstitue la séquence depuis les journaux : bail(s) dans Kea, lecture TFTP sur `pxe01`, requêtes HTTP dans le journal de nginx.
5. Observation : la séquence de `bm01` diffère de celle de `bm03`. Laquelle saute le TFTP, et pourquoi ? (Regarde ce que la ROM réseau de la carte virtuelle annonce, et la version d'iPXE affichée par ton menu.) Qu'est-ce qui changerait sur un vrai serveur ?
6. Éteins les deux VMs depuis le menu ou par `qm stop`, puis écris dans `docs/socle/provisioning/demarrage-reseau.md` le schéma de la séquence observée pour chacune.

**Critères de réussite**
- [ ] `bm01` à `bm04` existent avec leur MAC fixe, l'ordre de démarrage réseau puis disque, SeaBIOS ou OVMF selon le tableau, Secure Boot désactivé sur les deux OVMF.
- [ ] Kea charge les trois classes (sur les deux pairs) ; un client ne peut appartenir qu'à une seule.
- [ ] `http://pxe01.par1.medisphere.internal/boot.ipxe` et `ipxe/menu.ipxe` sont servis et commencent par `#!ipxe` ; leur contenu est celui de `main` du projet.
- [ ] Les journaux de `pxe01` montrent une lecture TFTP de `ipxe.efi` et des requêtes HTTP de `boot.ipxe` venant du VLAN 60.
- [ ] La note `demarrage-reseau.md` décrit les deux séquences et explique la différence.

**Vérification** : `lab/bin/check 11 03`

<details><summary>Indice 1</summary>

Dans le fournisseur `bpg/proxmox`, cherche `bios`, `boot_order`, le bloc `efi_disk` (attribut `pre_enrolled_keys`) et l'attribut `mac_address` du bloc `network_device`. Un bloc `dynamic` évite d'écrire deux ressources.
</details>

<details><summary>Indice 2</summary>

Expressions de Kea : `option[93].hex == 0x0000`, `substring(option[77].hex,0,4) == 'iPXE'`, opérateurs `and`, `or`, `not` et parenthèses. Le champ renvoyé est `boot-file-name`. `kea-dhcp4 -t <fichier>` valide aussi les expressions.
</details>

<details><summary>Indice 3</summary>

iPXE : `chain --autofree <url> || goto menu`, la variable `${netX/mac:hexhyp}` donne la MAC avec des tirets, `${platform}`, `${version}`, `${netX/ip}` ; un menu se construit avec `menu`, `item`, `choose --timeout … --default …`. Pour « démarrer sur le disque », `exit` rend la main au micrologiciel, qui passe au périphérique suivant.
</details>

**Pour aller plus loin** (facultatif) : capture le TFTP de `bm03` avec `tcpdump -n -i ens18 port 69` sur `pxe01` : les données arrivent-elles par le port 69 ? Lis les options `blksize` et `tsize` négociées (RFC 2348, 2349) ; c'est le sujet de M11-E23.

---

### M11-E04 — Installer Debian sans intervention (preseed)  `LAB` `★★`

> **Ticket PLAT-1204** — *De : Claire Morel*
> Le prestataire nous a laissé un preseed de 600 lignes que personne ne comprend, avec le mot de passe root en clair. Repars de zéro : un fichier court que tu sais expliquer ligne par ligne, et un serveur Debian 13 qui sort de l'installation aux standards MédiSphère. Et je veux savoir d'où viennent le noyau et l'initrd qu'on fait démarrer à nos serveurs.

**Objectifs pédagogiques**
- Servir l'installateur réseau de Debian après avoir vérifié sa chaîne de confiance (Release signé, empreintes).
- Écrire un preseed minimal et complet : réseau, miroir, partitionnement LVM, compte, paquets, commande finale.
- Installer un serveur BIOS et un serveur UEFI sans aucune réponse au clavier.

**Prérequis** : M11-E03.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Installateur : `netboot` de trixie, fichiers `linux` et `initrd.gz` sous `dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/` du miroir `https://deb.debian.org/debian`. Les empreintes sont dans `…/images/SHA256SUMS`, dont l'empreinte figure dans le fichier `Release` signé de la suite. Clés : paquet `debian-archive-keyring` de `pxe01`. Dossier servi : `/srv/http/debian13/` (rôle `pxe`).
- Paquets : téléchargés par l'installateur depuis `deb.debian.org`, à travers la bordure (flux « lab vers Internet »).
- Standards attendus en fin d'installation : partitionnement LVM sur tout le disque ; compte `admin` membre de `sudo`, mot de passe **haché** (SHA-512) pour la seule console, clé publique SSH de `adm01` ; connexion `root` désactivée ; serveur SSH, agent QEMU, `curl`, `ca-certificates` installés ; racine « MédiSphère Root CA » installée dans `/usr/local/share/ca-certificates/medisphere-root-ca.crt` **après vérification de son empreinte** ; fuseau `Europe/Paris`, NTP 10.10.60.1 ; extinction en fin d'installation.
- Le preseed est servi en HTTP clair (le passage en HTTPS est l'objet de M11-E13) : n'y mets rien que tu ne publierais pas sur le VLAN 60.
- Nom d'hôte provisoire tant que NetBox ne décide pas (E06) : dérivé de la MAC, par exemple `bm-02-4d-53-60-00-01`.

**Travail demandé**
1. **Installateur vérifié.** Étends le rôle `pxe` (variable de liste d'installateurs, outil de téléchargement idempotent) pour télécharger `linux` et `initrd.gz`, vérifier la signature du `Release` puis les empreintes, et ne publier qu'en cas de succès, sans jamais laisser un client lire un mélange de deux versions. Prouve qu'un fichier altéré est refusé (fais l'essai sur une copie, pas sur `pxe01`).
2. **Le preseed.** Écris `preseed/debian13.cfg` dans `plateforme/provisioning`. Calcule l'empreinte du mot de passe sur `adm01` sans qu'il apparaisse dans l'historique ni dans `ps`. Ajoute au pipeline une validation de syntaxe (`debconf-set-selections -c`) et une règle qui fait échouer la MR si un mot de passe en clair apparaît.
3. **Le menu.** Ajoute à `menu.ipxe` une entrée « Debian 13 (preseed) » qui charge le noyau et l'initrd depuis `pxe01` avec les paramètres d'une installation automatique. Publie.
4. **Installer `bm01` (BIOS)**, en suivant la console : ne touche plus au clavier après le choix dans le menu. Note la durée. À l'extinction, redémarre-la : elle doit démarrer sur son disque (menu, puis délai).
5. **Contrôler** depuis `adm01` : connexion SSH par clé, `sudo -n true`, LVM, racine de la PKI, absence de connexion `root` par mot de passe. Récupère l'adresse par l'agent QEMU.
6. **Installer `bm03` (UEFI)** avec le même fichier. Quelle différence vois-tu dans le partitionnement, et qu'a fait l'installateur pour le chargeur d'amorçage ?

**Critères de réussite**
- [ ] `/srv/http/debian13/linux` et `initrd.gz` sur `pxe01` ont les empreintes publiées par Debian, et leur provenance est vérifiée par signature.
- [ ] `preseed/debian13.cfg` est sur `main`, passe `debconf-set-selections -c`, ne contient aucun mot de passe en clair ; le pipeline le valide.
- [ ] `bm01` (et `bm03`) : Debian 13 installée sans intervention, `admin` joignable par clé et `sudo`, racine sur LVM, racine de la PKI installée, `root` sans mot de passe utilisable, agent QEMU actif.
- [ ] Après l'installation, la VM redémarre sur son disque sans se réinstaller.

**Vérification** : `lab/bin/check 11 04`

<details><summary>Indice 1</summary>

Le fichier `Release` de la suite porte **plusieurs** signatures (les clés de plusieurs versions de Debian) ; `gpgv` échoue dès qu'une clé manque à ton trousseau, même si une autre signature est bonne. Regarde ce que `gpgv --status-fd` écrit, et ce qu'apt exige.
</details>

<details><summary>Indice 2</summary>

`mkpasswd -m sha-512` (paquet `whois`) lit le mot de passe sur son entrée standard si tu ne le lui donnes pas en argument. Questions utiles du preseed : `passwd/root-login`, `passwd/user-password-crypted`, `partman-auto/method`, `partman-auto/choose_recipe`, `pkgsel/include`, `preseed/late_command`, `debian-installer/exit/poweroff`. L'exemple officiel de trixie les commente toutes.
</details>

<details><summary>Indice 3</summary>

Dans `late_command`, le système installé est monté sous `/target` ; `in-target <commande>` l'exécute dans ce système. L'installateur a `wget` et `sha256sum` (BusyBox). Pour l'iPXE en UEFI, ajoute `initrd=initrd.gz` aux paramètres du noyau : c'est ainsi que le noyau retrouve l'image chargée par iPXE.
</details>

**Pour aller plus loin** (facultatif) : un cache `apt-cacher-ng` sur `pxe01` (configuration `mirror/http/proxy`) diviserait le temps d'installation par trois au deuxième serveur et ne ferait sortir les paquets qu'une fois. Qu'est-ce qu'il faudrait vérifier pour que ce cache ne devienne pas un point d'injection ?

---

### M11-E05 — Installer Rocky Linux sans intervention (kickstart)  `LAB` `★★`

> **Ticket PLAT-1205** — *De : Karim Benali*
> Les nœuds Ceph tournent en Rocky Linux 10 (module 08) ; les prochains seront physiques. Même exercice qu'avec Debian, côté Anaconda : un kickstart court, validé avant d'arriver sur un serveur, et les mêmes standards. Je veux aussi qu'on sache dire, noir sur blanc, ce que nous vérifions et ce que nous ne vérifions pas de ce qui est téléchargé.

**Objectifs pédagogiques**
- Servir l'installateur réseau de Rocky Linux 10 et en vérifier les empreintes.
- Écrire et valider un kickstart (`ksvalidator`) qui applique les standards MédiSphère.
- Comparer les mécanismes de debian-installer et d'Anaconda (sources, partitionnement, fin d'installation).

**Prérequis** : M11-E03 ; M11-E04 conseillé (rôle `pxe` étendu).
**Durée indicative** : 2 h.

**Contexte technique**
- Installateur : `vmlinuz` et `initrd.img` de `images/pxeboot/` du dépôt BaseOS (`https://dl.rockylinux.org/pub/rocky/<VERSION>/BaseOS/x86_64/os/`). Leurs empreintes sont dans le fichier `.treeinfo` du même dépôt. Version : 10.2 (fixe-la dans une variable : l'initrd et le dépôt de l'installation doivent être de la **même** version). Dossier servi : `/srv/http/rocky10/`.
- Paramètres noyau : `inst.repo=` (dépôt BaseOS) et `inst.ks=` (URL du kickstart sur `pxe01`), `ip=dhcp`.
- Machine : `bm04` (UEFI, 4 Go). L'installateur réseau de RHEL 10 demande 3 Gio de mémoire.
- `ksvalidator` vient du paquet Python `pykickstart` ; version de syntaxe à valider : `RHEL10`.
- Standards : ceux de E04 (LVM automatique, `admin` dans `wheel` avec mot de passe haché et clé SSH, `root` verrouillé, SSH, agent QEMU, SELinux en mode `enforcing`, pare-feu actif avec SSH ouvert, racine de la PKI vérifiée puis ajoutée au magasin du système, NTP 10.10.60.1, extinction en fin d'installation).

**Travail demandé**
1. Étends la liste d'installateurs du rôle `pxe` pour Rocky 10.2. Explique dans ton journal ce que la vérification par `.treeinfo` garantit et ce qu'elle ne garantit pas, par comparaison avec Debian.
2. Écris `kickstart/rocky10.ks`. Ajoute au pipeline `ksvalidator -v RHEL10` et la règle « pas de mot de passe en clair ».
3. Ajoute l'entrée « Rocky Linux 10 (kickstart) » au menu iPXE, publie, installe `bm04` sans toucher au clavier ; note la durée.
4. Contrôle depuis `adm01` : SSH par clé, `sudo -n true`, `getenforce`, `firewall-cmd --list-services`, LVM, racine de la PKI dans le magasin (`trust list` ou `openssl verify` d'un certificat du socle).
5. Dans ton journal, un tableau comparatif de cinq lignes entre preseed et kickstart : source des paquets, partitionnement, comptes, commande finale, validation hors ligne.

**Critères de réussite**
- [ ] `/srv/http/rocky10/vmlinuz` et `initrd.img` ont les empreintes du `.treeinfo` de la version choisie.
- [ ] `kickstart/rocky10.ks` est sur `main`, passe `ksvalidator -v RHEL10`, ne contient aucun mot de passe en clair ; le pipeline le valide.
- [ ] `bm04` : Rocky Linux 10 installé sans intervention, `admin` joignable par clé et `sudo`, SELinux `enforcing`, `firewalld` actif, racine de la PKI de confiance, agent QEMU actif ; redémarrage sur le disque.

**Vérification** : `lab/bin/check 11 05`

<details><summary>Indice 1</summary>

Commandes kickstart utiles : `url`, `repo`, `text`, `lang`, `keyboard`, `timezone`, `timesource`, `network`, `rootpw --lock`, `user … --iscrypted`, `sshkey`, `zerombr`, `clearpart`, `autopart --type=lvm`, `selinux`, `firewall`, `services`, `%packages`, `%post`, `poweroff`. La documentation « Kickstart commands and options reference » de RHEL 10 les décrit toutes.
</details>

<details><summary>Indice 2</summary>

`.treeinfo` est un fichier INI ; la section `[checksums]` contient `images/pxeboot/vmlinuz = sha256:…`. Il n'est pas signé : seule la connexion HTTPS au miroir officiel l'authentifie.
</details>

<details><summary>Indice 3</summary>

Dans `%post`, le système installé est la racine (pas de `/target`) et le réseau est disponible. La racine de la PKI se dépose dans `/etc/pki/ca-trust/source/anchors/` puis `update-ca-trust`.
</details>

**Pour aller plus loin** (facultatif) : installe aussi `bm02` (BIOS, 3 Go) ; puis essaie avec 2 Go de mémoire et observe comment Anaconda échoue. Lis la documentation de `inst.stage2` : dans quel cas faut-il séparer la source de l'image d'installation de celle des paquets ?
