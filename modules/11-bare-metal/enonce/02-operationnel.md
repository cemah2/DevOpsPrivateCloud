# Module 11 — Palier 2 : Opérationnel

Le palier 1 a une chaîne qui marche… à condition de choisir dans un menu, avec un nom d'hôte tiré de l'adresse MAC. Ce palier en fait un outil d'exploitation : **NetBox décide** du nom, de l'adresse et du système de chaque serveur, et la chaîne en déduit tout le reste (réservation DHCP, script iPXE, kickstart, nom DNS). Puis on quitte le réseau pour la main du serveur : le **contrôleur de gestion** de `hp01`, interrogé en Redfish et en IPMI, et un outil qui pilote l'alimentation d'un serveur comme d'une VM. Enfin, **MAAS** fait la même chose à sa façon, sur les mêmes machines, pour que l'ADR du palier 3 compare des faits et non des plaquettes. Tu termines par la revue des fichiers d'InfoGér et le runbook qui servira à l'arrivée des palettes.

> **Rappels du module** (introduction) : VMs par OpenTofu (`envs/provisioning`), configuration par rôle Ansible appliqué par le pipeline, fichiers d'installation dans `plateforme/provisioning`, flux dans la matrice de la bordure. `hp01` n'est jamais réinstallé ; pas de `curl -k` ; aucun secret en argument de commande. Les VMs `bm*` sont jetables.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| NetBox | `https://nbx01.par1.medisphere.internal` ; jetons de M06 : `netbox-moi.token` (toi, écriture), `netbox-ansible.env` (`svc-automatisation`, lecture), `netbox-checks.token` (lecture, checks) |
| Équipements NetBox (E06) | `bm01`-`bm04`, site `par1`, rôle `serveur-bm`, type `serveur-nu-vm` (fabricant `generique`), plateformes `debian-13` et `rocky-10`, étiquette `env-m11`, interface `eno1` + adresse MAC primaire, IP primaire 10.10.60.101-104/24 (`dns_name` = `bmNN.par1.medisphere.internal`) |
| Répartition des systèmes | `bm01` Debian (BIOS), `bm02` Rocky (BIOS), `bm03` Debian (UEFI), `bm04` Rocky (UEFI) |
| iLO de `hp01` | `<IP-ILO-HP01>`, iLO 4 ; compte `wb-redfish` ; `~/.config/workbook/ilo-hp01.env` et `ilo-hp01.pem` (600) |
| Proxmox (E08) | `wb-maas@pve!maas`, rôle `WBMaas`, `~/.config/workbook/pve-maas.env` (600) |
| MAAS (E09-E10) | `maas01` (2116, 10.10.60.11), `http://10.10.60.11:5240/MAAS/`, administrateur `<MOI>`, clé `~/.config/workbook/maas-api.key` (600), profil CLI `maas01` sur `maas01` |

---

### M11-E06 — Des installations décrites par NetBox  `LAB` `★★★`

> **Ticket PLAT-1210** — *De : Karim Benali*
> Le menu iPXE, c'est bien pour une démo. Pour trente-deux serveurs, je veux que celui qui réceptionne la palette saisisse les serveurs dans NetBox (nom, numéro de série, adresse MAC, système voulu), les passe en « prévu », et que la chaîne fasse le reste : réservation DHCP, script de démarrage, fichier d'installation, nom DNS. Aucun fichier écrit à la main par serveur. Et si une donnée est incohérente dans NetBox, je veux un refus clair, pas un serveur installé n'importe comment.

**Objectifs pédagogiques**
- Modéliser des serveurs physiques dans NetBox (équipements, plateformes, adresses MAC, statut) et ouvrir au compte d'automatisation la lecture dont il a besoin, rien de plus.
- Écrire un générateur qui transforme la source de vérité en configuration (gabarits Jinja2), en refusant les données incohérentes.
- Organiser la propriété des fichiers entre plusieurs écrivains (Kea, `pxe01`, DNS) et rendre la chaîne rejouable.

**Prérequis** : M11-E04, M11-E05 ; M06-E10 (permissions NetBox), M06-E15 (`medictl dns sync`).
**Durée indicative** : 4 h.

**Contexte technique**
- Les serveurs du lab sont des VMs, mais NetBox les décrit comme des **équipements** (*devices*) : c'est ainsi que seront décrits les vrais serveurs. Consigne ce choix dans la description du type d'équipement.
- NetBox 4.6 : depuis la 4.2, une adresse MAC est un **objet** (`dcim.mac-addresses`) rattaché à une interface, et l'interface désigne sa MAC primaire (`primary_mac_address`). Plateforme = champ natif d'un équipement.
- Statuts : `planned` → la chaîne installe ; tout autre statut → le serveur démarre sur son disque. Le passage à `active` est manuel dans cet exercice (il sera automatisé en M11-E15).
- Lecture par l'outil : jeton de `svc-automatisation` en lecture (`netbox-ansible.env`, variable `NETBOX_TOKEN`). Ses permissions de M06-E10 ne couvrent pas les équipements : à étendre (lecture seulement). Les objets eux-mêmes se créent avec ton jeton personnel.
- Sorties attendues de l'outil (`outils/netbox-provision.py`, projet `uv` du dépôt `plateforme/provisioning`) :
  - un script iPXE par machine, `ipxe/mac-<MAC avec tirets>.ipxe` : installation selon la plate-forme si `planned`, démarrage local sinon ;
  - un kickstart par machine Rocky (`kickstart/<nom>.ks`) ; Debian réutilise `preseed/debian13.cfg` (le nom passe par la ligne de commande du noyau) ;
  - les réservations Kea du sous-réseau 60 (MAC, adresse, nom) sous la forme d'un fichier de variables pour `plateforme/ansible`, appliqué par MR et pipeline.
- Les gabarits vivent dans `gabarits/` ; les fichiers rendus ne sont **pas** versionnés (dossier `rendu/` ignoré) ; `outils/publier.sh` publie le rendu avec le reste.
- Contrôles de cohérence minimaux : MAC présente et unique, IP primaire présente, unique, dans 10.10.60.100-199, plate-forme connue, nom conforme (`bm` + deux chiffres).

**Travail demandé**
1. **Modéliser.** Avec ton jeton personnel, crée le rôle, le type, les deux plateformes, puis `bm01`-`bm04` en `planned` (numéro de série : invente-le, ou prends l'UUID SMBIOS de la VM), leur interface `eno1` avec la MAC de E03, leur IP primaire avec `dns_name`. Rends l'opération rejouable (script idempotent ou fichier d'import : justifie).
2. **Ouvrir la lecture.** Étends la permission de lecture de `svc-automatisation` aux types dont l'outil a besoin, et à eux seuls. Prouve avec le jeton de lecture qu'il lit les équipements mais ne peut toujours écrire nulle part.
3. **Générer.** Écris l'outil et ses gabarits. Il lit NetBox, contrôle, rend, et termine par un résumé (machines rendues, refusées et pourquoi). Code de sortie non nul si une machine `planned` est refusée. Aucun jeton dans la sortie ni dans les fichiers rendus. Tests automatisés sans réseau (données de NetBox simulées) dans le pipeline, avec `ksvalidator` sur un kickstart rendu.
4. **Appliquer.** Réservations : MR sur `plateforme/ansible` avec le fichier généré, pipeline. Fichiers : `publier.sh`. DNS : `medictl dns sync` (M06-E15). Vérifie les quatre noms, direct et inverse.
5. **Démontrer.** Efface le disque de `bm01` et de `bm02` (`qm set … --delete scsi0` puis recrée-le par OpenTofu, ou réinitialise-les : explique ton choix), démarre-les sans toucher au clavier. Elles doivent s'installer avec le **bon** nom, la **bonne** adresse et le **bon** système, puis s'éteindre.
6. **Clore.** Passe `bm01` et `bm02` en `active` dans NetBox, régénère, publie, redémarre-les : elles démarrent sur leur disque.
7. **Refus.** Mets une MAC en double sur `bm03`, lance l'outil : il doit refuser `bm03`, ne rien publier pour elle, et le dire. Remets la donnée en ordre.

**Critères de réussite**
- [ ] NetBox contient `bm01`-`bm04` avec rôle, type, plate-forme, MAC primaire de `eno1` égale à celle de Proxmox, IP primaire 10.10.60.101-104 et `dns_name`.
- [ ] Le jeton de lecture de `svc-automatisation` lit les équipements ; il n'a aucun droit d'écriture.
- [ ] Kea (sur les deux pairs) charge une réservation par machine, conforme à NetBox.
- [ ] `pxe01` sert un script `ipxe/mac-….ipxe` par machine, cohérent avec son statut ; les kickstarts rendus passent `ksvalidator`.
- [ ] `bm01` et `bm02` ont été installées par la chaîne avec leur nom et leur adresse NetBox, sont `active` et démarrent sur leur disque ; `bmNN.par1.medisphere.internal` se résout.
- [ ] L'outil, ses gabarits et ses tests sont sur `main` ; le pipeline les exécute.

**Vérification** : `lab/bin/check 11 06`

<details><summary>Indice 1</summary>

Pour lire une interface et sa MAC : `/api/dcim/interfaces/?device_id=<id>&name=eno1` (champ `primary_mac_address`, et `mac_address` en lecture), ou en une requête GraphQL. Pour créer : l'interface, puis l'objet `dcim.mac-addresses` (`assigned_object_type: dcim.interface`), puis un `PATCH` de l'interface avec `primary_mac_address`. Les types d'objets à lire : `dcim | device`, `dcim | interface`, `dcim | MAC address`, `dcim | platform`, `dcim | device role`.
</details>

<details><summary>Indice 2</summary>

Sépare la lecture (NetBox → liste de machines normalisées), le contrôle (liste → machines valides + refus) et le rendu (machines valides → fichiers). Les deux premiers se testent avec des dictionnaires. Le rendu doit être déterministe (tri par nom) pour que deux exécutions identiques produisent les mêmes fichiers octet pour octet.
</details>

<details><summary>Indice 3</summary>

`rsync --delete` ne supprime que dans les dossiers qu'il synchronise : construis un dossier de publication temporaire (fichiers du dépôt + rendu), puis synchronise `ipxe/`, `preseed/`, `kickstart/` un par un. Un script iPXE d'une machine retirée de NetBox doit disparaître de `pxe01`.
</details>

**Pour aller plus loin** (facultatif) : NetBox 4.x sait rendre des gabarits lui-même (*config templates* attachés à une plate-forme ou à un rôle, accessibles par `/api/dcim/devices/<id>/render-config/`). Compare cette approche avec un générateur externe : où vit le gabarit, qui le relit, que devient la chaîne quand NetBox est en panne ?

---

### M11-E07 — IPMI et Redfish : découvrir l'iLO de `hp01`  `LAB` `★★`

> **Ticket PLAT-1211** — *De : Claire Morel* — *Cc : Sophie Laurent*
> Nos futurs serveurs auront tous un contrôleur de gestion. `hp01` en a un, l'iLO, et personne ne s'y est connecté depuis l'achat. Apprends à lui parler, en IPMI et en Redfish, et dis-moi ce qu'on peut en tirer pour l'exploitation (capteurs, journaux, inventaire).
>
> *Sophie* : un BMC, c'est un accès total au serveur, même éteint. Compte dédié avec le strict minimum, mot de passe hors des dépôts, et je ne veux pas voir un seul `-k` dans vos commandes. Le certificat de l'iLO est autosigné ? Alors vous le vérifiez autrement, et vous m'expliquez comment.

**Objectifs pédagogiques**
- Comprendre le rôle d'un BMC et les deux protocoles de pilotage (IPMI over LAN, Redfish).
- Créer un compte de service à privilèges minimaux sur un BMC, et en protéger les identifiants.
- Faire confiance à un certificat autosigné par épinglage, après vérification par un second chemin.
- Lire l'inventaire, les capteurs et les journaux d'un serveur par API.

**Prérequis** : M02 (curl, jq) ; aucun exercice du module (indépendant du VLAN 60).
**Durée indicative** : 2 h 30.

**Contexte technique**
- ⚠️ `hp01` porte PBS et le QDevice : **lecture seule**. Aucune action d'alimentation, aucune modification de réglage de l'iLO autre que la création du compte `wb-redfish`. Ne touche ni au réseau de l'iLO, ni à ses comptes existants.
- L'iLO est sur le LAN maison (`<IP-ILO-HP01>`). Depuis `adm01`, il faut un flux explicite à travers la bordure (TCP 443 pour Redfish, UDP 623 pour IPMI), limité à `adm01`. La création du compte se fait dans l'interface web de l'iLO, depuis ton poste (LAN maison ou VPN d'administration).
- Privilèges d'un compte iLO 4 : *Login*, *Remote Console*, *Virtual Power and Reset*, *Virtual Media*, *Configure iLO Settings*, *Administer User Accounts*. Côté IPMI, ils se traduisent en niveaux `USER`, `OPERATOR`, `ADMINISTRATOR`.
- Fichier `~/.config/workbook/ilo-hp01.env` (600, jamais dans un dépôt), lu par les outils et les vérifications : `ILO_HOST` (adresse IP), `ILO_NOM_TLS` (nom présenté par le certificat), `ILO_USER`, `ILO_PASSWORD`. Certificat épinglé : `~/.config/workbook/ilo-hp01.pem`.
- Redfish sur iLO 4 (firmware ≥ 2.30) : racine `/redfish/v1/`, puis `Systems/1`, `Chassis/1` (`Thermal`, `Power`), `Managers/1` (dont `LogServices/IEL`, le journal de l'iLO), `Systems/1/LogServices/IML` (journal de gestion intégré). iLO 4 accepte l'authentification HTTP *basic* et les sessions (`SessionService`).
- `ipmitool` 1.8.19 (paquet Debian) : interface `lanplus` ; l'option `-E` lit le mot de passe dans la variable d'environnement `IPMI_PASSWORD`.

**Travail demandé**
1. **Repérage.** Dans l'interface de l'iLO : version du firmware, licence (Standard ou Advanced), état d'*IPMI/DCMI over LAN*. Note ce que la licence Standard ne permet pas.
2. **Compte.** Crée `wb-redfish` avec les **seuls** privilèges nécessaires à la lecture. Justifie dans ton journal chaque case cochée ou non, et ce que changerait l'ajout de *Virtual Power and Reset*. Génère le mot de passe (long, aléatoire), crée `ilo-hp01.env` sans que le mot de passe passe par l'historique, inscris le compte au registre des secrets.
3. **Flux.** Ajoute les deux flux à la matrice de la bordure (MR, pipeline) et à `matrice-flux.md`.
4. **Confiance.** Récupère le certificat de l'iLO depuis `adm01`. Vérifie son empreinte SHA-256 par un **second chemin** indépendant de la bordure (depuis `hp01` lui-même, qui est sur le même LAN que l'iLO), et compare son numéro de série avec celui qu'affiche l'interface web. Épingle-le : toutes tes requêtes Redfish vérifient TLS avec ce certificat et le nom qu'il porte. Explique pourquoi une connexion par l'adresse IP échoue, et comment tu le contournes **sans** désactiver la vérification.
5. **Redfish.** Écris `outils/redfish.sh` dans `plateforme/provisioning` (lecture seule : `GET` d'un chemin, identifiants lus dans le fichier et jamais sur la ligne de commande, TLS épinglé). Avec lui et `jq`, relève : modèle, numéro de série, version du BIOS (ROM), état d'alimentation, mémoire totale, processeur ; températures et ventilateurs ; consommation ; version du firmware de l'iLO ; les cinq dernières entrées de l'IEL et de l'IML. Lis aussi `Actions` dans `Systems/1` : quelles valeurs de remise à zéro (`ResetType`) l'iLO accepte-t-il ? (lecture seulement).
6. **IPMI.** Avec `ipmitool` : `chassis status`, `sdr elist`, `sel list`. Quel niveau de privilège (`-L`) faut-il demander avec ce compte, et que se passe-t-il sans ? Compare dans un tableau ce que donnent les deux protocoles (contenu, sécurité du transport et de l'authentification, facilité d'automatisation).
7. **Sécurité.** Dans ton journal, explique en cinq lignes pourquoi IPMI over LAN devra être désactivé (M11-E13) et pourquoi un BMC ne doit jamais être joignable depuis un réseau utilisateur.

**Critères de réussite**
- [ ] `ilo-hp01.env` et `ilo-hp01.pem` existent en mode 600 ; aucun mot de passe de l'iLO dans un dépôt ni dans l'historique du shell.
- [ ] Une requête Redfish depuis `adm01` vérifie le certificat épinglé et réussit avec `wb-redfish`.
- [ ] `wb-redfish` n'a que le privilège de connexion (ni configuration, ni comptes, ni console, ni média virtuel, ni alimentation).
- [ ] Les flux 443/TCP et 623/UDP vers l'iLO sont dans la matrice (code et documentation), limités à `adm01`.
- [ ] `outils/redfish.sh` est sur `main` et ton journal contient les relevés et le tableau comparatif.

**Vérification** : `lab/bin/check 11 07`

<details><summary>Indice 1</summary>

`openssl s_client -connect <IP>:443 -showcerts </dev/null` affiche la chaîne ; `openssl x509 -noout -fingerprint -sha256 -serial -subject -ext subjectAltName` résume un certificat. Le second chemin : la même commande lancée sur `hp01` (`ssh pbs01`), qui joint l'iLO sans passer par la bordure du lab.
</details>

<details><summary>Indice 2</summary>

Le certificat de l'iLO porte un nom (souvent `ILO` + numéro de série), pas l'adresse IP : `curl --cacert ilo-hp01.pem --resolve <NOM-TLS-ILO>:443:<IP-ILO-HP01> https://<NOM-TLS-ILO>/…`. curl accepte un certificat non autosigné comme ancre (*partial chain*) depuis la version 7.68. Pour les identifiants : `curl -K -` lit `user = "…"` sur l'entrée standard.
</details>

<details><summary>Indice 3</summary>

Sans `-L USER`, ipmitool demande le niveau `ADMINISTRATOR` à l'ouverture de session : un compte qui n'a que *Login* est refusé avant même la première commande, avec un message d'erreur d'établissement de session peu explicite.
</details>

**Pour aller plus loin** (facultatif) : la bibliothèque `python-redfish-library` de HPE et l'outil `ilorest` savent parcourir l'API ; la DMTF publie un validateur de service (*Redfish Service Validator*). Regarde aussi ce que contient `/redfish/v1/Systems/1/` dans le bloc `Oem.Hp` : c'est là que vivent les extensions propres au constructeur.

---

### M11-E08 — Piloter l'alimentation par API  `LAB` `★★`

> **Ticket PLAT-1212** — *De : Karim Benali*
> Allumer, éteindre, redémarrer un serveur, c'est la première chose que fait une chaîne de provisioning, et la dernière chose qu'on veut confier à un compte trop puissant. Fais-moi un outil unique, `alim`, qui pilote nos « serveurs » du lab par l'API Proxmox et qui sache lire l'état de `hp01` par son iLO, avec un compte Proxmox qui ne puisse **rien** faire d'autre que voir et alimenter `bm01` à `bm04`. Ce compte servira à MAAS ensuite : regarde ce dont son pilote a besoin.

**Objectifs pédagogiques**
- Créer un compte et un jeton Proxmox à privilèges minimaux, limités à quatre VMs, et le prouver.
- Écrire un outil d'alimentation à plusieurs « pilotes » (API Proxmox, Redfish), sûr par construction.
- Lire le code d'un pilote existant (MAAS) pour en déduire les droits dont il a besoin.

**Prérequis** : M11-E03 (VMs `bm*`), M11-E07 ; M00-E17 (jetons Proxmox).
**Durée indicative** : 2 h.

**Contexte technique**
- Compte `wb-maas@pve`, jeton `maas` (avec séparation des privilèges), rôle personnalisé `WBMaas`, ACL sur `/vms/2112`, `/vms/2113`, `/vms/2114`, `/vms/2115` seulement. Fichier `~/.config/workbook/pve-maas.env` au format de `pve-api.env` (`PVE_API_URL`, `PVE_NODE`, `PVE_TOKEN_ID`, `PVE_TOKEN_SECRET`, `PVE_CACERT`).
- Le pilote d'alimentation `proxmox` de MAAS 3.7 est dans le code source de MAAS : `src/provisioningserver/drivers/power/proxmox.py` (dépôt `git.launchpad.net/maas`, branche `3.7`). Lis quels points d'API il appelle.
- Outil : `outils/alim.sh` dans `plateforme/provisioning`. Usage attendu : `alim.sh <cible> <action>` ; cibles `bm01`…`bm04` (API Proxmox, actions `etat`, `allumer`, `eteindre`, `cycle`) et `hp01` (Redfish, actions `etat` et `types` seulement). L'outil **refuse** toute action d'alimentation sur `hp01` : un redémarrage de `hp01` passe par une procédure annoncée, pas par un script.
- ⚠️ Redémarrer `hp01` interrompt PBS et le QDevice. Ce n'est **pas** demandé ; si tu veux le faire une fois (facultatif) : fiche de changement, fenêtre hors des sauvegardes (`proxmox-backup-manager task list` sur `pbs01` vide de tâche en cours), privilège *Virtual Power and Reset* ajouté **temporairement** à `wb-redfish` puis retiré.

**Travail demandé**
1. **Lire le pilote.** Dans le code du pilote `proxmox` de MAAS, relève les appels d'API (méthode, chemin) pour l'état, l'allumage, l'extinction et le redémarrage. Déduis-en les privilèges Proxmox nécessaires, et note ce que le pilote ne sait **pas** faire (ordre de démarrage, remise à zéro) et ce que cela impose à nos VMs.
2. **Compte.** Crée le rôle, l'utilisateur, le jeton, les ACL (pour le jeton **et** l'utilisateur : pourquoi les deux ?). Écris `pve-maas.env`. Prouve avec le jeton : il voit exactement quatre VMs dans `/cluster/resources`, il peut démarrer `bm03`, il ne peut ni modifier sa configuration, ni démarrer `pxe01`, ni lire le stockage.
3. **L'outil.** Écris `alim.sh` : identifiants lus dans les fichiers (jamais en argument), TLS vérifié des deux côtés, actions idempotentes (`allumer` une machine allumée ne fait rien et le dit), `cycle` qui attend réellement l'arrêt avant de rallumer, codes de sortie documentés, ShellCheck propre, ajouté au pipeline.
4. **Démonstration.** `alim.sh bm03 allumer`, `etat`, `eteindre` ; `alim.sh hp01 etat` et `alim.sh hp01 types` ; `alim.sh hp01 cycle` doit être refusé.
5. **Facultatif** : le redémarrage annoncé de `hp01` par Redfish, dans les conditions ci-dessus. Mesure le temps jusqu'au retour de PBS et du tunnel `wg0`.

**Critères de réussite**
- [ ] Le rôle `WBMaas` n'a que les privilèges nécessaires au pilote ; l'ACL ne couvre que 2112-2115, pour l'utilisateur et le jeton.
- [ ] Avec le jeton, `/cluster/resources` ne montre que `bm01`-`bm04`.
- [ ] `pve-maas.env` est en 600 et inscrit au registre des secrets.
- [ ] `outils/alim.sh` est sur `main`, passe ShellCheck dans le pipeline, et refuse toute action d'alimentation sur `hp01`.
- [ ] `wb-redfish` n'a pas gardé de privilège d'alimentation.

**Vérification** : `lab/bin/check 11 08`

<details><summary>Indice 1</summary>

Le pilote cherche la VM dans `GET /cluster/resources?type=vm` (par VMID ou par nom), puis appelle `POST /nodes/<nœud>/qemu/<vmid>/status/start` ou `…/stop`. Une VM n'apparaît dans `/cluster/resources` que si l'on a `VM.Audit` sur elle.
</details>

<details><summary>Indice 2</summary>

Avec la séparation des privilèges (`--privsep 1`, la valeur par défaut), les droits effectifs d'un jeton sont l'**intersection** de ceux de l'utilisateur et de ceux du jeton. `pveum user permissions 'wb-maas@pve!maas'` (ou `pvesh get /access/permissions --userid …`) affiche ce qu'il peut réellement faire.
</details>

<details><summary>Indice 3</summary>

`status/stop` coupe brutalement (« débrancher la prise »), `status/shutdown` demande un arrêt propre à l'invité (ACPI). Un `cycle` qui rallume avant que la VM soit arrêtée échoue ou ne fait rien : interroge `status/current` jusqu'à `stopped`, avec un délai maximal.
</details>

**Pour aller plus loin** (facultatif) : écris le même outil en Python avec `proxmoxer` et `requests` (comme `medictl`, M02), avec une classe par pilote et une interface commune `etat/allumer/eteindre`. C'est exactement la structure des pilotes de MAAS et d'Ironic.

---

### M11-E09 — Installer MAAS  `LAB` `★★`

> **Ticket PLAT-1213** — *De : Claire Morel*
> Avant de décider si on garde notre chaîne maison, je veux qu'on essaie sérieusement MAAS : installé comme en production (pas la base de test), sur la version que nous avons figée, et documenté. Pas de démonstration sur un portable : une VM du lab, par le chemin habituel.

**Objectifs pédagogiques**
- Construire un template Ubuntu 24.04 à partir de l'image cloud officielle, après vérification de sa signature.
- Installer MAAS 3.7 en mode « région + rack » avec une base PostgreSQL de production.
- Prendre en main l'interface, la CLI et les images de démarrage de MAAS.

**Prérequis** : M11-E02 ; M00 (template `tpl-debian13`), M05 (pipeline de `plateforme/infra`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Template **9050 `tpl-ubuntu2404`** : image `ubuntu-24.04-server-cloudimg-amd64.img` de `https://cloud-images.ubuntu.com/releases/24.04/release/`, avec `SHA256SUMS` et sa signature `SHA256SUMS.gpg` (clé « UEC Image Automatic Signing Key ») ; construit sur `pve01` comme `tpl-debian13` au module 00 (import du disque, lecteur cloud-init, agent QEMU, console série), étiquettes `ubuntu2404` et `template`, pool `lab`.
- `maas01` : voir l'introduction ; clone complet de 9050, cloud-init (adresse fixe 10.10.60.11/24, passerelle 10.10.60.1, DNS du lab, compte `admin` avec la clé de `adm01`), déclaré dans `envs/provisioning/` avec son enregistrement NetBox et son nom DNS. Le module `vm-debian` ne clone que l'image Debian `current` : écris les ressources directement.
- MAAS 3.7 : snap `maas`, canal `3.7/stable` ; PostgreSQL 16 du système (paquet Ubuntu), base `maasdb`, utilisateur `maas`, accès local seulement ; initialisation `maas init region+rack` avec l'URI de la base et `--maas-url http://10.10.60.11:5240/MAAS`. Configuration par un rôle Ansible `maas` (groupe `role_maas`).
- ⚠️ `maas init` n'accepte le mot de passe de la base que **dans l'URI**, en argument : exception à la règle du module. Limite-la (exécution unique par Ansible avec `no_log`, sur une VM où personne d'autre n'est connecté), consigne-la dans le registre des secrets, et note ce que la documentation de MAAS propose.
- Administrateur MAAS : `<MOI>` ; clé d'API dans `~/.config/workbook/maas-api.key` (600) sur `adm01` ; profil CLI `maas01` sur `maas01`. L'interface est en HTTP (port 5240) : écart à traiter en M11-E13.
- Images : Ubuntu 24.04 LTS amd64 depuis la source officielle `images.maas.io` (sortie Internet par la bordure).

**Travail demandé**
1. **Template.** Télécharge l'image, vérifie la signature de `SHA256SUMS` (et l'empreinte de la clé, par une source indépendante) puis l'empreinte de l'image ; construis 9050. Écris la procédure dans un script versionné (`plateforme/infra` ou `plateforme/outils` : justifie).
2. **VM.** Déclare `maas01` dans `envs/provisioning/`, MR, `apply`. Vérifie SSH, nom DNS, NetBox.
3. **Rôle `maas`.** PostgreSQL 16 (utilisateur et base, `pg_hba.conf` local seulement, mot de passe en Vault), snap au bon canal, initialisation idempotente, racines de confiance (`MédiSphère Root CA` et l'ancre de `pve01`, M02-E08) dans le magasin du système. ansible-lint ; pas de Molecule pour ce rôle (justifie).
4. **Administration.** Crée l'administrateur (`maas createadmin`, mot de passe saisi au clavier), récupère sa clé d'API dans `maas-api.key` sans qu'elle s'affiche, connecte la CLI (`maas login`) sans la passer en argument. Configure : DNS amont (10.10.20.10), serveur NTP (10.10.60.1), ta clé SSH publique.
5. **Images.** Sélectionne Ubuntu 24.04 amd64 et lance la synchronisation ; suis-la. Où MAAS stocke-t-il les images, et quelle place prennent-elles ?
6. **Lecture.** Dans ton journal : les services du snap (`maas status`), les ports ouverts par `maas01` et leur rôle (5240, 5248, 69, 53, 8000…), et ce que MAAS ferait s'il trouvait un autre serveur DHCP sur son VLAN.

**Critères de réussite**
- [ ] Le template 9050 `tpl-ubuntu2404` existe (template, étiquettes `ubuntu2404` et `template`), construit depuis une image dont la signature a été vérifiée.
- [ ] `maas01` (2116) tourne sur `vprov` à 10.10.60.11, se résout dans le DNS et figure dans NetBox.
- [ ] MAAS 3.7 (snap, canal `3.7/stable`) en mode région + rack, sur PostgreSQL 16 local ; l'API répond.
- [ ] `maas-api.key` est en 600 et la clé permet de lire l'API ; Ubuntu 24.04 amd64 est synchronisé.
- [ ] Le DHCP de MAAS est **désactivé** à ce stade (Kea sert toujours le VLAN 60).

**Vérification** : `lab/bin/check 11 09`

<details><summary>Indice 1</summary>

`gpg --verify SHA256SUMS.gpg SHA256SUMS` ; l'empreinte de la clé de signature des images cloud d'Ubuntu est publiée sur la page *Verifying Ubuntu cloud images* et sur `keyserver.ubuntu.com` : compare les deux avant de faire confiance. Puis `sha256sum -c --ignore-missing SHA256SUMS`.
</details>

<details><summary>Indice 2</summary>

`maas init region+rack --help` liste ses options. La documentation « Install MAAS » de la 3.7 donne la création de l'utilisateur et de la base PostgreSQL et la ligne de `pg_hba.conf` (restreins-la à `127.0.0.1/32`, méthode `scram-sha-256`). `maas apikey --username <MOI>` affiche la clé ; `maas login <profil> <URL> -` la lit sur l'entrée standard.
</details>

<details><summary>Indice 3</summary>

Une initialisation idempotente se reconnaît à un fichier qu'elle crée : la configuration de la région dans le dossier du snap (`/var/snap/maas/…`), ou un fichier témoin que ton rôle écrit après le succès.
</details>

**Pour aller plus loin** (facultatif) : MAAS sait servir son interface en HTTPS (`maas config-tls enable`). Avec quel certificat, et comment le renouveler tous les 30 jours avec notre ACME ? Garde la question pour M11-E13.

---

### M11-E10 — MAAS : inventorier et déployer des machines  `LAB` `★★★`

> **Ticket PLAT-1214** — *De : Claire Morel*
> MAAS est installé ; maintenant, le vrai essai : qu'il prenne la main sur deux de nos serveurs, un BIOS et un UEFI, les inventorie, les teste, les déploie, puis qu'on lui rende la main proprement. Je veux des faits pour l'ADR : temps, étapes manuelles, ce qui a coincé. Le VLAN 60 change de serveur DHCP le temps de l'essai : fiche de changement, et on revient à Kea à la fin.

> **Changement CHG-1215** — *À rédiger par toi, validation : Karim Benali* — bascule du DHCP du VLAN 60 de Kea vers MAAS, puis retour.

**Objectifs pédagogiques**
- Basculer le DHCP d'un VLAN d'un serveur à un autre sans période à deux serveurs, avec retour arrière.
- Confier à MAAS des machines pilotées par le pilote d'alimentation `proxmox`, TLS vérifié.
- Parcourir le cycle de vie MAAS : *New* → *Commissioning* → *Ready* → *Deploying* → *Deployed* → *Released*.

**Prérequis** : M11-E08 (`wb-maas`), M11-E09.
**Durée indicative** : 3 h 30.

**Contexte technique**
- Machines confiées à MAAS : `bm01` (BIOS) et `bm03` (UEFI). `bm02` et `bm04` restent éteintes pendant l'essai.
- ⚠️ Pendant l'essai, le VLAN 60 n'a **pas** de Kea : une machine qui démarre sur le réseau parle à MAAS. Retire d'abord le sous-réseau 60 de Kea et le VLAN 60 du relais des deux passerelles (MR, pipeline), vérifie qu'aucune offre n'arrive plus (`nmap` depuis `pxe01`, comme en E02), **puis** active le DHCP de MAAS. Retour arrière : désactiver le DHCP de MAAS, puis MR inverse. Le DHCP du VLAN 99 ne doit pas être affecté.
- Sous-réseau dans MAAS : passerelle 10.10.60.1, DNS 10.10.20.10 et .16 ; plages réservées 10.10.60.1-99 et 10.10.60.200-254 ; plage dynamique 10.10.60.150-199 ; les adresses des machines déployées sont prises dans 10.10.60.100-149.
- Pilote `proxmox` (paramètres CLI : `power_address`, `power_user`, `power_token_name`, `power_token_secret`, `power_vm_name`, `power_verify_ssl`) : adresse `<IP-PVE01>`, utilisateur `wb-maas@pve`, jeton `maas`, VM désignée par son VMID pour `bm01` et par son **nom** pour `bm03` (le pilote accepte les deux formes : garde-les, tu les compareras en M11-E22), vérification TLS **activée** (avec les certificats du système de `maas01`, d'où l'ancre de `pve01` installée en E09). Le secret du jeton se saisit dans l'interface web (champ masqué), pas en argument de la CLI.
- Flux `maas01` → `pve01` TCP 8006 : bordure **et** pare-feu Proxmox. Nouvel IPSet `maas` (contenant 10.10.60.11) plutôt que `automation` : justifie.
- Fin d'essai : machines **libérées** (*Release* : éteintes), DHCP de MAAS désactivé, Kea et relais rétablis, services MAAS arrêtés et `maas01` éteinte (elle resservira en M11-E16 et E22). Lance la vérification **avant** d'éteindre `maas01`, puis après.

**Travail demandé**
1. **Préparer.** Rédige CHG-1215 dans `docs/provisioning/changements/` (but, étapes, contrôles, retour arrière, critère d'abandon). Ouvre le flux et l'IPSet ; vérifie depuis `maas01`, avec `curl` sans option de contournement, que l'API de `pve01` répond avec un certificat reconnu.
2. **Basculer.** Exécute la première moitié de la fiche ; montre qu'il n'y a jamais eu deux serveurs DHCP en même temps sur le VLAN 60, et que le VLAN 99 est intact.
3. **Machines.** Crée `bm01` et `bm03` dans MAAS (MAC, architecture `amd64/generic`, pilote `proxmox`) ; vérifie que MAAS lit leur état d'alimentation. Lance la mise en service (*commissioning*) avec les tests matériels par défaut ; observe MAAS allumer et éteindre les VMs. Compare l'inventaire relevé par MAAS (CPU, mémoire, disques, interfaces) avec la configuration Proxmox.
4. **Déployer.** Déploie Ubuntu 24.04 sur les deux ; connecte-toi en SSH (quel compte ? quelle clé ?). Note la durée de chaque étape et chaque geste manuel.
5. **Rendre la main.** Libère les deux machines, puis exécute le retour de la fiche ; démarre `bm01` : elle doit arriver au menu ou au script de **notre** chaîne. Arrête MAAS et `maas01`.
6. **Bilan pour l'ADR** (`~/m11/e10/bilan.md`) : chronologie, gestes manuels, ce que MAAS fait mieux que la chaîne maison, ce qu'il fait moins bien, ce qu'il impose (base, réseau, DHCP, DNS), et ce qui t'a surpris.

**Critères de réussite**
- [ ] CHG-1215 est dans la documentation, avec ses contrôles et son retour arrière.
- [ ] Pendant l'essai : MAAS gère `bm01` et `bm03` avec le pilote `proxmox`, vérification TLS activée, et les a déployées (Ubuntu 24.04).
- [ ] Le flux `maas01` → `pve01:8006` est dans la matrice et dans le pare-feu Proxmox (IPSet `maas`).
- [ ] À la fin : DHCP de MAAS désactivé, Kea sert de nouveau le sous-réseau 60 (deux pairs), le relais des deux passerelles couvre de nouveau le VLAN 60, `maas01` arrêtée ou MAAS sans DHCP.
- [ ] Le bilan existe et chiffre les étapes.

**Vérification** : `lab/bin/check 11 10` (avant d'éteindre `maas01`, puis après)

<details><summary>Indice 1</summary>

CLI de MAAS (sur `maas01`, profil `maas01`) : `subnets read`, `ipranges create type=reserved|dynamic …`, `vlan update <fabric> <vid> dhcp_on=True primary_rack=<id-du-rack>`, `machines create architecture=amd64/generic mac_addresses=… power_type=proxmox power_parameters_…`, `machine commission <id>`, `machine deploy <id> distro_series=noble`, `machine release <id>`. L'identifiant du rack : `rack-controllers read`.
</details>

<details><summary>Indice 2</summary>

La vérification TLS du pilote utilise les certificats « du système » : ceux de l'environnement du snap. Si le pilote échoue avec une erreur de certificat alors que `curl` réussit depuis `maas01`, regarde où le snap lit son magasin et redémarre MAAS après avoir ajouté l'ancre (⚠️ à confirmer sur ta version).
</details>

<details><summary>Indice 3</summary>

Le pilote `proxmox` ne sait pas changer l'ordre de démarrage : la VM doit démarrer sur le réseau en premier, et c'est MAAS qui, par sa réponse PXE, lui dit de démarrer sur son disque une fois déployée. C'est la même logique que nos scripts iPXE par statut.
</details>

**Pour aller plus loin** (facultatif) : MAAS sait aussi « découvrir » toutes les VMs d'un hôte Proxmox (`machines add-chassis chassis_type=proxmox`). Pourquoi ne l'avons-nous pas fait, avec un jeton limité à quatre VMs ? Et que ferait le même appel avec un jeton d'administration ?

---

### M11-E11 — Revue : les fichiers d'installation du prestataire  `REV` `★★`

> **Ticket SEC-1216** — *De : Sophie Laurent*
> En archivant le partage d'InfoGér, Lucas a trouvé leur preseed et leur kickstart « de production ». Avant qu'on les mette au coffre (ou à la poubelle), je veux une revue : tout ce qui est dangereux, pourquoi, et ce qu'il faut vérifier sur les serveurs qu'ils ont installés avec ça. Certains de ces serveurs tournent encore chez l'hébergeur actuel.

**Objectifs pédagogiques**
- Lire un preseed et un kickstart avec un œil de sécurité et d'exploitation.
- Classer des défauts par gravité et en déduire des actions, y compris sur l'existant.

**Prérequis** : M11-E04, M11-E05.
**Durée indicative** : 1 h 15.

**Fichiers fournis** : [`ressources/M11-E11/`](../ressources/M11-E11/) — `preseed-infoger.cfg`, `ks-infoger.cfg`, `LISEZMOI.md` (contexte donné par InfoGér).

**Travail demandé**
1. Lis les deux fichiers. Relève **tous** les défauts (ils sont au moins sept, répartis entre les deux fichiers) : sécurité, fiabilité, exploitation.
2. Pour chacun : ligne(s), risque concret (qu'est-ce qu'un attaquant ou un incident en ferait ?), gravité (critique, majeure, mineure), correction.
3. Liste les **contrôles à faire sur les serveurs déjà installés** par InfoGér avec ces fichiers (ce que les défauts y ont laissé), sous forme de commandes à lancer.
4. Conclus : archiver, corriger ou détruire ces fichiers ? Où les ranger s'ils sont gardés ?

**Livrable** : `docs/provisioning/revue-infoger.md` (tableau des défauts, contrôles, conclusion), par MR.

**Critères de réussite**
- [ ] Au moins sept défauts relevés, chacun avec son risque, sa gravité et sa correction.
- [ ] Les contrôles sur l'existant sont des commandes exécutables.
- [ ] La conclusion dit ce qu'on fait des fichiers et des secrets qu'ils contiennent.

<details><summary>Indice 1</summary>

Pour chaque ligne, demande-toi : qui peut lire ce fichier (il est servi en HTTP sur un VLAN) ? que se passe-t-il sur un serveur qui a deux disques ? que se passe-t-il au redémarrage qui suit l'installation ? qui d'autre que nous peut se connecter au serveur installé ?
</details>

<details><summary>Indice 2</summary>

Un mot de passe qui a été dans un fichier servi en clair est **compromis**, même s'il n'est plus utilisé dans le nouveau fichier : la correction ne s'arrête pas au fichier.
</details>

**Pour aller plus loin** (facultatif) : écris une règle `pre-commit` (ou une étape du pipeline) qui détecte trois des défauts automatiquement dans `plateforme/provisioning`.

---

### M11-E12 — Runbook : provisionner un serveur  `RED` `★★`

> **Ticket PLAT-1217** — *De : Nadia Roussel*
> La première palette arrive un vendredi, évidemment. Le collègue de permanence n'a jamais vu votre chaîne. Il me faut le RB-110 : de la palette au serveur en service, ce qu'il saisit, ce qu'il lance, ce qu'il vérifie, et quoi faire quand ça bloque. Une page qu'on suit sans réfléchir à 18 h.

**Objectifs pédagogiques**
- Écrire une procédure d'exploitation exécutable par quelqu'un qui ne connaît pas la chaîne.
- Penser les points de contrôle et les cas d'échec fréquents.

**Prérequis** : M11-E06, M11-E08.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Format des runbooks du socle (M06-E23) : but, prérequis et accès, étapes numérotées avec la commande et le résultat attendu, contrôles, retour arrière, dépannage, références.
- Ce que la chaîne fait aujourd'hui (fin du palier 2) : génération depuis NetBox, réservations par MR, publication, installation, extinction ; le passage à `active` est encore manuel (automatisé en E15, qui mettra le runbook à jour).

**Travail demandé**
1. Écris `docs/provisioning/runbooks/RB-110-provisionner-un-serveur.md` : réception (saisie NetBox, données obligatoires, où lire la MAC et le numéro de série sur un vrai serveur), génération et application, démarrage par le contrôleur de gestion, suivi de l'installation, contrôles d'acceptation, passage en service, et le cas « réinstaller un serveur existant ».
2. Ajoute un tableau de dépannage d'au moins six symptômes (« le serveur n'obtient pas d'adresse », « iPXE affiche une erreur de téléchargement », « l'installateur pose une question »…) avec la première vérification à faire.
3. Fais relire le runbook par une personne qui ne connaît pas la chaîne (ou relis-le toi-même après une nuit) et exécute-le sur `bm03` en suivant **seulement** le runbook ; corrige ce qui manquait.

**Critères de réussite**
- [ ] RB-110 est sur `main` de `plateforme/medisphere`, au format des runbooks du socle.
- [ ] Chaque étape a sa commande et son résultat attendu ; aucun secret n'y figure (seulement où le trouver).
- [ ] Le tableau de dépannage couvre au moins six symptômes.
- [ ] Une exécution sur `bm03` en suivant le seul runbook est consignée en fin de document (date, durée, corrections apportées).

<details><summary>Indice 1</summary>

Un bon test : chaque fois que tu écris « vérifier que… », écris aussi **comment** (commande) et **ce qu'on doit voir**. Chaque fois que tu écris « si ça échoue », renvoie vers une ligne du tableau de dépannage.
</details>

<details><summary>Indice 2</summary>

Sur un vrai serveur, la MAC et le numéro de série se lisent sur l'étiquette, dans le bon de livraison, ou par le contrôleur de gestion (`Systems/1` en Redfish : `SerialNumber`, et les interfaces réseau sous `EthernetInterfaces` quand le firmware les expose).
</details>

**Pour aller plus loin** (facultatif) : transforme les contrôles d'acceptation du runbook en un script `outils/accepter.sh <nom>` qui sort en 0 seulement si le serveur est conforme : le runbook n'aura plus qu'une ligne à cet endroit.
