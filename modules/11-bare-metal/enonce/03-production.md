# Module 11 — Palier 3 : Production

La chaîne fonctionne : un serveur déclaré dans NetBox démarre sur le réseau, Kea lui donne une adresse et un chargeur, `pxe01` lui sert iPXE, un noyau, un preseed ou un kickstart, et il s'installe seul ; MAAS a fait la même chose avec ses propres outils, et tu sais lire et piloter l'iLO de `hp01`. Mais tout transite **en clair**, n'importe quelle machine branchée sur le VLAN 60 peut se faire passer pour `pxe01`, et l'installation se termine encore par un geste humain. Sophie Laurent le résume en une phrase : « Un serveur qui s'installe depuis le réseau exécute ce que le réseau lui donne. Si le réseau ment, le serveur appartient à quelqu'un d'autre dès sa première seconde. » Karim Benali veut que les futurs nœuds Proxmox s'installent par le même chemin que les autres serveurs, Claire Morel veut une chaîne qui aille de NetBox au serveur en service **sans personne**, et une décision écrite entre MAAS et la chaîne maison. Nadia Roussel, elle, veut savoir quel firmware tourne sur le seul vrai serveur du parc.

Ordre conseillé : E13 (tout le reste s'appuie sur la chaîne en HTTPS) → E14 → E15 → E18 → E16 → E17. Durée du palier : 16 à 20 h.

> **Rappels** : tout se lance depuis `adm01`. Clones de travail : `~/src/provisioning` (projet `plateforme/provisioning` : `ipxe/`, `preseed/`, `kickstart/`, `pve-answer/`, `gabarits/`, `outils/`), `~/src/ansible` (rôle `pxe`, `kea_dhcp4`, `relais_dhcp`, matrice des flux `inventories/lab/host_vars/gw01/pare_feu.yml`), `~/src/infra` (état OpenTofu `provisioning` : `pxe01`, `bm01-04`), documentation `~/medisphere` (variable `WB_DEPOT`). Les serveurs cibles `bm01-04` (2112-2115) sont décrits dans NetBox comme des **équipements** (rôle `serveur-bm`, interface `eno1` avec son adresse MAC) ; leur adresse est réservée dans Kea depuis NetBox (M11-E06). Accès à l'iLO de `hp01` : `~/.config/workbook/ilo-hp01.env` (compte `wb-redfish`, M11-E07), jamais `curl -k`.

**Chemin imposé** (introduction du module) : configuration des hôtes par un **rôle Ansible** (ansible-lint profil `production`) appliqué par le pipeline de `plateforme/ansible` ; VMs par **OpenTofu** (état `provisioning`) ; tout fichier servi par `pxe01` (scripts iPXE, preseed, kickstart, fichiers de réponse) est **rendu depuis `plateforme/provisioning`** (gabarits, `outils/netbox-provision.py`), jamais écrit à la main sur `pxe01` ; tout flux nouveau est une ligne de `pare_feu.yml` (identique sur `gw01` et `gw02`) reportée dans `docs/socle/matrice-flux.md` ; tout secret est en Ansible Vault (identité `critique`) et inscrit au registre des secrets.

> ⚠️ **`hp01` porte PBS** : dans ce palier, aucune action n'éteint ni ne redémarre `hp01`. Une modification de configuration de l'**iLO** (E13, E18) peut redémarrer l'iLO lui-même (pas le serveur) : vérifie avant, dans l'interface de l'iLO, que l'opération ne touche que le contrôleur, et annonce-la à Nadia (ticket CHG). Garde une session ouverte sur l'iLO avec ton compte administrateur pendant toute modification de comptes ou de protocoles.

---

### M11-E13 — Sécuriser la chaîne de provisioning  `LAB` `★★★`

> **Ticket SEC-1230** — *De : Sophie Laurent* — *Copie : Karim Benali*
> J'ai relu la chaîne de démarrage réseau. Aujourd'hui, un poste branché sur le VLAN 60 qui répond plus vite que Kea, ou qui usurpe `pxe01`, installe ce qu'il veut sur nos futurs serveurs, et récupère au passage nos preseed. Avant d'aller plus loin, je veux :
> - une chaîne **authentifiée** de bout en bout : à partir du chargeur iPXE, plus rien ne s'exécute qui ne vienne de `pxe01` en HTTPS, avec un certificat de notre PKI, vérifié par iPXE ;
> - aucun mot de passe en clair dans un preseed, un kickstart ou un dépôt ; le compte root verrouillé sur les serveurs installés ;
> - le VLAN 60 isolé : un serveur en cours d'installation n'a pas à voir le VLAN MGMT ni les services du socle, à part le DNS ;
> - IPMI sur IP coupé sur l'iLO de `hp01`, et le compte `wb-redfish` réduit au strict nécessaire.
> Tu me donnes une ADR courte sur la façon dont iPXE fait confiance à `pxe01`.

**Objectifs pédagogiques**
- Établir une chaîne de confiance du démarrage réseau : ce que garantit (et ne garantit pas) chaque maillon (DHCP, TFTP, iPXE, HTTPS, installateur, dépôt de paquets signé).
- Construire un binaire iPXE qui fait confiance à la racine MédiSphère et seulement à elle, de façon reproductible et versionnée.
- Supprimer les secrets des fichiers d'installation (empreintes de mots de passe, clés publiques, compte root verrouillé).
- Réduire la surface du VLAN de provisioning et du contrôleur de gestion.

**Prérequis** : M11-E02 à E06 (chaîne PXE, preseed, kickstart, génération depuis NetBox), M11-E07 (iLO), M06-E18 (rôle `certificats_acme`), M06-E30 (durcissement, matrice des flux).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Le paquet Debian `ipxe` fournit des binaires génériques (`/usr/lib/ipxe/`). Par défaut, iPXE ne fait confiance qu'à la racine du projet iPXE pour HTTPS ; pour une PKI privée, la racine doit être **intégrée au binaire à la construction**. Les algorithmes de la PKI MédiSphère (step-ca) sont à base de courbes elliptiques (ECDSA P-256) : le binaire doit savoir vérifier ces signatures. Le support des courbes elliptiques et de TLS par iPXE dépend de la version : consulte [ipxe.org/crypto](https://ipxe.org/crypto) et les notes de version avant de choisir ce que tu construis.
- La construction se fait **dans une VM jetable** (VMID 2117 `m11-build`, clone lié de l'image dorée Debian `current`, VNet `vsandbox`, étiquette `env-m11`), jamais sur `adm01` ni sur `pxe01`. Ce qui est versionné, c'est la **procédure** (script de construction, version de l'amont, options), pas le binaire ; le binaire produit est déposé sur `pxe01` par le rôle `pxe`, avec son empreinte SHA-256 consignée.
- Certificat de `pxe01` : rôle `certificats_acme` (défi HTTP-01, puis renouvellement par le certificat lui-même). `pxe01` doit joindre l'API de `ca01` (443), et `ca01` le port 80 de `pxe01` pour le défi : c'est le seul flux INFRA → PROV à ouvrir.
- Le port 80 de `pxe01` reste ouvert pour le défi ACME ; il ne doit plus servir ni script iPXE, ni preseed, ni kickstart.
- Les installateurs Debian et Rocky ne connaissent pas la racine MédiSphère : ils ne pourraient pas télécharger leur fichier de réponse en HTTPS depuis `pxe01`. Cherche comment iPXE peut **leur remettre** ce fichier sans que l'installateur ait à le télécharger lui-même.
- iLO 4 : le réglage d'IPMI sur IP est dans l'interface d'administration de l'iLO (section sécurité ou accès) ; l'état des protocoles se lit aussi en Redfish (`/redfish/v1/Managers/1/NetworkService/`).

**Travail demandé**
1. **Analyse.** Dans `docs/provisioning/securite-chaine.md` (`plateforme/medisphere`), dessine la chaîne actuelle (DHCP → TFTP → iPXE → HTTP → noyau, initrd → installateur → miroir de paquets) et, pour chaque maillon : qui peut usurper, ce qu'on y gagne, la protection retenue. Indique ce qui reste non protégé après ce ticket (DHCP et TFTP, notamment) et pourquoi c'est acceptable dans ce lab.
2. **Certificat de `pxe01`.** Étends le rôle `pxe` : nginx en HTTPS sur 443 avec un certificat ACME de `ca01` (chaîne complète, renouvellement automatique), port 80 réduit au défi ACME et à une redirection. Ouvre le flux `ca01` → `pxe01:80` dans `pare_feu.yml`.
3. **iPXE de confiance.** Dans `plateforme/provisioning`, écris `ipxe/construire-ipxe.sh` : récupération d'une version **épinglée** de l'amont iPXE (étiquette et empreinte du commit vérifiées), options de construction (HTTPS, commandes utiles, racine MédiSphère comme **seule** racine de confiance), construction de `undionly.kpxe` (BIOS) et `ipxe.efi` (UEFI x64), affichage des empreintes. Lance-le dans la VM 2117, dépose les binaires par le rôle `pxe` (empreintes en variables), puis détruis la VM 2117.
4. **Chaîne en HTTPS.** Kea (classe iPXE) et tous les scripts iPXE n'utilisent plus que `https://pxe01.par1.medisphere.internal/…`. Le preseed et le kickstart parviennent à l'installateur **par iPXE** (pas de téléchargement par l'installateur depuis `pxe01`). Les paquets viennent toujours des miroirs officiels : explique dans ton analyse pourquoi c'est sûr (et à quelles conditions).
5. **Secrets.** Plus aucun mot de passe en clair dans `plateforme/provisioning` ni sur `pxe01` : compte `admin` par clé SSH, empreinte de mot de passe (algorithme moderne) seulement si un mot de passe console est nécessaire, en Vault ; root verrouillé (preseed et kickstart). Vérifie l'historique Git du projet : si un mot de passe y a été commité, considère-le comme compromis.
6. **VLAN 60.** Revois `pare_feu.yml` : depuis 10.10.60.0/24, seuls le DNS (10.10.20.10/.16), les miroirs Internet nécessaires aux installateurs et le DHCP relayé sont permis vers l'extérieur du VLAN, plus, pour **`pxe01` seul**, l'ACME de `ca01` (émission et renouvellement de son certificat) ; rien vers MGMT ni vers les autres services du socle. `adm01` garde l'accès au VLAN 60.
7. **iLO.** Désactive IPMI sur IP (et retire le flux UDP 623 de la matrice) ; vérifie que `wb-redfish` n'a que les privilèges dont ont besoin les exercices restants (lecture ; justifie le cas échéant le contrôle de l'alimentation) ; consigne le changement (CHG-1230).
8. **ADR-0111** « Confiance du démarrage réseau » (`docs/socle/adr/`, gabarit MADR, une page) : racine intégrée au binaire, signature des scripts (`imgtrust`/`imgverify`), Secure Boot UEFI, ou rien ; décision et conséquences (renouvellement de la racine, reconstruction du binaire).
9. Réinstalle `bm01` (BIOS) et `bm03` (UEFI) de bout en bout par la nouvelle chaîne. Garde la trace de la console qui montre les téléchargements en `https://`.

**Critères de réussite**
- [ ] `https://pxe01.par1.medisphere.internal/boot.ipxe` répond, avec un certificat émis par l'intermédiaire MédiSphère et vérifié par `adm01` ; le port 80 ne sert plus ni script iPXE ni fichier de réponse.
- [ ] Les binaires servis en TFTP ne sont pas ceux du paquet Debian ; leurs empreintes sont dans le code Ansible ; `ipxe/construire-ipxe.sh` est sur `main`, sans remarque ShellCheck.
- [ ] La configuration de Kea et tous les scripts iPXE servis ne contiennent plus aucune URL `http://` vers `pxe01`.
- [ ] Aucun preseed ni kickstart servi ne contient de mot de passe en clair ; root y est verrouillé.
- [ ] Depuis `pxe01`, le DNS de `dns01` répond, mais ni `adm01:22` ni `git01:443` ne sont joignables ; `ca01` joint `pxe01:80`.
- [ ] L'iLO ne répond plus en IPMI sur IP ; la matrice ne contient plus de flux vers l'iLO sur 623.
- [ ] `docs/provisioning/securite-chaine.md` et l'ADR-0111 sont sur `main`.

**Vérification** : `lab/bin/check 11 13`

<details><summary>Indice 1</summary>

La documentation de construction d'iPXE décrit deux paramètres de `make` qui intègrent des certificats au binaire : l'un les **rend disponibles**, l'autre en fait des **racines de confiance**. Si tu ne donnes que le premier, ton binaire continue de faire confiance à la racine du projet iPXE. Les fonctions optionnelles (HTTPS, commandes) s'activent dans `src/config/local/general.h`, qui n'est jamais écrasé par une mise à jour de l'amont.
</details>

<details><summary>Indice 2</summary>

Le noyau Linux accepte plusieurs initrd concaténés, et iPXE sait **fabriquer** une petite archive cpio autour d'un fichier si tu lui donnes un chemin de destination. L'installateur Debian cherche un `preseed.cfg` à la racine de son initrd ; Anaconda accepte un kickstart désigné par un chemin `file:`.
</details>

<details><summary>Indice 3</summary>

iPXE vérifie aussi les **dates** des certificats : l'horloge de la machine compte. Et si un certificat contient une adresse OCSP, iPXE essaie de la joindre. Teste chaque étape dans le shell iPXE (Ctrl-B au démarrage) : `imgfetch https://…` puis `imgstat` disent tout de suite si la chaîne TLS est acceptée, et le code d'erreur se décode sur `https://ipxe.org/err/<code>`.
</details>

**Pour aller plus loin** (facultatif) : signer les scripts iPXE et les noyaux (`imgtrust`, `imgverify`) avec une clé de signature de code distincte de la PKI TLS ; Secure Boot avec iPXE 2.0 et shim (notes de version et documentation sur [ipxe.org](https://ipxe.org/)) ; un cache `apt-cacher-ng` sur `pxe01` pour ne plus dépendre d'Internet ; [ipxe.org/crypto](https://ipxe.org/crypto), [ipxe.org/cmd/initrd](https://ipxe.org/cmd/initrd).

---

### M11-E14 — Provisionner un nœud Proxmox VE par le réseau  `LAB` `★★★`

> **Ticket PLAT-1231** — *De : Karim Benali*
> Au module 09, tu as installé `hv01-03` avec l'installateur automatique de Proxmox, depuis une ISO préparée. Les nœuds du futur datacenter, eux, n'auront pas de lecteur : ils démarreront sur le réseau comme les autres. Proxmox VE 9.2 sait le faire. Montre-moi un nœud installé par la chaîne de provisioning, avec un fichier de réponse propre à la machine, servi en HTTPS, protégé par un jeton, et sans mot de passe root en clair nulle part. Tu reprends le fichier de réponse de `hv01`, adapté. La VM est jetée ensuite, on n'en a pas besoin.

**Objectifs pédagogiques**
- Préparer l'installateur de Proxmox VE 9.2 pour un démarrage PXE (`proxmox-auto-install-assistant prepare-iso --pxe`) et comprendre ce qu'il produit.
- Servir un fichier de réponse par machine en HTTP(S), authentifié par jeton, choisi d'après l'identité que l'installateur envoie.
- Mesurer les contraintes d'un installateur chargé entièrement en mémoire (taille de l'initrd, mémoire de la machine, BIOS ou UEFI).

**Prérequis** : M09-E01 à E03 (fichier de réponse, `prepare-iso`), M11-E13 (chaîne HTTPS).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Machine cible : `bm04` (2115, OVMF/UEFI, CPU `host`). L'initrd produit contient tout l'installateur ; il est chargé en mémoire avant le démarrage : porte la mémoire de `bm04` à **8 Go** et son disque à **32 Go** dans le code OpenTofu le temps de l'exercice (le nœud imbriqué n'a pas besoin de plus).
- Fichier de réponse : clés en *kebab-case* (PVE 9.1+). Avec `--fetch-from http`, l'installateur envoie un **POST** contenant une description de la machine (dont les adresses MAC de ses interfaces) et attend le fichier de réponse en retour, au format TOML ou JSON ; un jeton facultatif est envoyé dans l'en-tête `Authorization`. Une URL HTTPS vers un certificat d'une PKI privée exige d'épingler l'empreinte du certificat du serveur (`--cert-fingerprint`). Lis la page officielle [Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation) avant de commencer, en entier.
- nginx sert des fichiers statiques et refuse un POST sur un fichier : il faut un **petit service** derrière nginx qui choisit la réponse d'après la MAC et vérifie le jeton.
- Outil : `proxmox-auto-install-assistant` (paquet du dépôt Proxmox), là où tu l'as installé au module 09.
- Adresse et nom de `bm04` : ceux de NetBox (réservation Kea du M11-E06), domaine `par1.medisphere.internal`.

**Travail demandé**
1. Dans `plateforme/provisioning`, crée `pve-answer/bm04.toml` à partir du fichier de `hv01` (M09) : nom, adresse **du VLAN 60** de `bm04` prise dans NetBox, disque, clé SSH de `adm01` pour root, **empreinte** du mot de passe root (pas le mot de passe), redémarrage en fin d'installation. Valide-le avec la sous-commande de validation de l'outil.
2. Écris un service de réponse (dans le rôle Ansible de `pxe01` ou un rôle dédié) : écoute locale seulement, derrière nginx sur `https://pxe01.par1.medisphere.internal/pve/reponse`, compare le jeton reçu à celui du Vault, cherche dans le corps de la requête une MAC connue et renvoie le fichier de réponse correspondant ; `403` sans jeton valide, `404` pour une MAC inconnue ; aucune journalisation du jeton.
3. Prépare l'ISO de PVE 9.2 (déposée et vérifiée comme au M09) pour le PXE, avec la récupération du fichier de réponse en HTTP(S) vers ton service, le jeton, l'empreinte du certificat de `pxe01` et le chargeur iPXE. Lis ce que l'outil a produit (fichiers, script iPXE) et dépose noyau et initrd sur `pxe01` sous `/pve/9.2/` par ta chaîne habituelle (empreintes vérifiées). Note où se retrouve le jeton.
4. Écris le script iPXE de `bm04` pour ce démarrage (gabarit dans `gabarits/`), puis installe `bm04`. Mesure le temps de bout en bout, la taille de l'initrd et le pic de mémoire de la VM pendant le chargement.
5. Vérifie le nœud : version, nom, adresse, clé SSH de root acceptée depuis `adm01`, interface web sur 8006 depuis `adm01`.
6. Réfléchis au renouvellement : le certificat de `pxe01` est renouvelé tous les 30 jours. Qu'arrive-t-il à un initrd préparé avec l'ancienne empreinte ? Propose une procédure (et écris-la dans `docs/provisioning/pve-pxe.md`).
7. Détruis le nœud : `bm04` est recréée **vide** par OpenTofu (même MAC, mémoire et disque d'origine), le statut NetBox de `bm04` revient à `planned`, le fichier de réponse reste dans le code pour la prochaine fois ; ce que tu as déposé sous `/pve/` sur `pxe01` est retiré s'il contient un secret, et le jeton est renouvelé.

**Critères de réussite**
- [ ] `pve-answer/bm04.toml` est sur `main`, en *kebab-case*, sans `root-password` en clair, et passe la validation de l'outil.
- [ ] Un POST sans jeton vers le service de réponse est refusé ; avec le bon jeton et une MAC inconnue, il ne renvoie aucun fichier de réponse.
- [ ] Le gabarit iPXE de l'installation PVE est dans `gabarits/` ; après l'exercice, plus aucun initrd PVE (il contient le jeton) ne reste sur `pxe01`, et le jeton a été renouvelé dans le Vault.
- [ ] Le jeton n'apparaît dans aucun dépôt (il est en Vault) ; ton compte rendu dit où il se trouve en clair et ce que cela implique.
- [ ] `docs/provisioning/pve-pxe.md` contient la mesure (temps, taille, mémoire) et la procédure de renouvellement.
- [ ] `bm04` est de nouveau une VM vide, à 2 Go, dans l'état de départ.

**Vérification** : `lab/bin/check 11 14` (à lancer **après** l'étape 7).

<details><summary>Indice 1</summary>

L'outil de préparation a une option pour chacun des points de la consigne (source du fichier de réponse, URL, jeton, empreinte, PXE et chargeur). `--help` de la sous-commande `prepare-iso`, puis la page officielle : certaines options en impliquent d'autres.
</details>

<details><summary>Indice 2</summary>

Ton service n'a pas besoin de comprendre toute la structure envoyée par l'installateur : toutes les MAC de la machine y figurent sous la forme habituelle `xx:xx:xx:xx:xx:xx`. Une expression régulière et une table « MAC → fichier » suffisent ; la bibliothèque standard de Python suffit aussi pour le serveur HTTP. Compare le jeton en temps constant.
</details>

<details><summary>Indice 3</summary>

L'empreinte attendue par l'installateur est celle du **certificat** présenté par `pxe01`, au format SHA-256 que montre `openssl x509 -fingerprint -sha256`. Elle change à chaque renouvellement, pas seulement quand la clé change.
</details>

**Pour aller plus loin** (facultatif) : la source `from-dhcp` de l'URL (option DHCP 250 posée par Kea pour la seule classe des futurs nœuds) ; un script `[first-boot]` qui rejoint le nœud au cluster ; l'enregistrement TXT `proxmox-auto-installer` ; [Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation).

---

### M11-E15 — De la source de vérité au serveur en service  `LIBRE` `★★★`

> **Ticket PLAT-1232** — *De : Claire Morel* — *Copie : Karim Benali, Nadia Roussel*
> Aujourd'hui, pour installer un serveur, quelqu'un rend les fichiers, allume la machine, attend, change le démarrage pour qu'elle ne se réinstalle pas en boucle, lance Ansible, met à jour NetBox. Cinq gestes, cinq oublis possibles. Je veux qu'un serveur déclaré `planned` dans NetBox soit **en service** — installé, configuré, dans le DNS, dans l'inventaire Ansible, avec sa clé d'hôte signée, `active` dans NetBox — sans qu'un humain touche à autre chose que NetBox et au bouton « lancer » du pipeline. Et si quelque chose rate, je veux le savoir, et pouvoir relancer sans tout casser.

**Objectifs pédagogiques**
- Concevoir un orchestrateur de provisioning piloté par la source de vérité : états, transitions, reprise après échec, idempotence.
- Résoudre la boucle « démarrage réseau → réinstallation » sans geste humain.
- Faire entrer un serveur installé dans l'exploitation courante : inventaire Ansible, DNS, certificats SSH, statut NetBox.

**Prérequis** : M11-E06 (génération depuis NetBox), M11-E08 (alimentation par API), M11-E13 (chaîne HTTPS), M06-E12 (inventaire NetBox), M06-E15 (DNS piloté par le code), M06-E19 (clé d'hôte signée).
**Durée indicative** : 5 à 6 h.

**Contraintes**
- Point d'entrée unique : un job **manuel** du pipeline de `plateforme/provisioning` (variable : nom de l'équipement), qui tourne sur `runner01`. Le même outil se lance aussi depuis `adm01` pour le dépannage.
- Le cycle de vie se lit dans NetBox : `planned` (déclaré) → `staged` (installation en cours) → `active` (en service) ; un échec laisse l'équipement dans un état qui le dit (statut, journal de l'objet NetBox), jamais `active`.
- Pas de réinstallation en boucle : une machine dont l'installation est terminée redémarre sur son disque, même si son ordre de démarrage met le réseau en premier ; une machine `active` ne se réinstalle **jamais** par erreur (un redémarrage de `bm01` en service ne doit rien effacer).
- Pas de secret sur la machine installée qui donnerait un droit d'écriture sur NetBox, Proxmox ou la forge : la machine en cours d'installation ne « rappelle » personne avec un jeton.
- Droits minimaux : l'alimentation des seules VMs `bm*` ; l'écriture NetBox limitée au statut et au journal des équipements du rôle `serveur-bm` (compte `svc-automatisation`, autorisation à étendre et à justifier dans le registre des secrets) ; DNS par le chemin du M06.
- Relancer l'outil sur un équipement déjà `active` ne change rien ; le relancer après un échec reprend là où c'était utile.
- Le serveur installé entre dans l'inventaire Ansible NetBox (groupe à créer pour les équipements `serveur-bm` actifs), reçoit la racine de la PKI, sa clé d'hôte signée, le rôle `base`, et se joint depuis `adm01` sans question sur l'empreinte.
- Délai maximal par étape, et un message clair à l'échec (étape, cause probable, où regarder).
- Documentation : `docs/provisioning/orchestration.md` (diagramme d'états, ce qui se passe à chaque transition, reprise), mise à jour de RB-110.

**Critères de réussite**
- [ ] Un équipement `bm0x` passé à `planned` dans NetBox puis traité par le job manuel finit `active`, résolu dans le DNS, joignable en SSH depuis `adm01` avec un certificat d'hôte reconnu, présent dans l'inventaire Ansible, avec la racine MédiSphère installée — démontré pour une machine **BIOS** Debian et une machine **UEFI** Rocky.
- [ ] Un redémarrage d'une machine `active` la ramène sur son système installé, sans réinstallation.
- [ ] Le journal NetBox de l'équipement retrace les transitions (qui, quand, quelle étape).
- [ ] Une relance sur une machine `active` ne change rien (sortie et code de retour le montrent).
- [ ] `docs/provisioning/orchestration.md` et RB-110 à jour sont sur `main`.

**Vérification** : `lab/bin/check 11 15`

<details><summary>Indice 1</summary>

Qui sait que l'installation est finie ? Pas la machine (elle n'a aucun droit) : l'orchestrateur, s'il observe quelque chose qu'il contrôle déjà. Les deux installateurs savent **éteindre** la machine au lieu de la redémarrer en fin d'installation, et l'orchestrateur sait lire l'état d'alimentation.
</details>

<details><summary>Indice 2</summary>

Le script iPXE propre à une MAC peut dire « installe » ou « démarre sur le disque » : c'est le statut NetBox qui doit décider lequel est servi. iPXE sait rendre la main au micrologiciel pour qu'il passe au périphérique suivant de l'ordre de démarrage.
</details>

<details><summary>Indice 3</summary>

Écris d'abord le diagramme d'états avec, pour chaque transition, la condition observable qui la déclenche et le délai maximal. Le code vient ensuite, presque mécaniquement, et la reprise après échec se lit sur le diagramme.
</details>

**Pour aller plus loin** (facultatif) : déclencher le pipeline depuis NetBox (*event rule* + *webhook* vers l'API de déclenchement de GitLab) dès qu'un équipement passe à `planned` ; [NetBox event rules](https://netboxlabs.com/docs/netbox/features/event-rules/), [pipeline triggers GitLab](https://docs.gitlab.com/ci/triggers/).

---

### M11-E16 — ADR : MAAS, Tinkerbell ou chaîne maison ?  `RED` `★★`

> **Ticket PLAT-1233** — *De : Claire Morel*
> On a maintenant deux chaînes qui fonctionnent : MAAS, essayé au palier 2, et la nôtre, construite autour de NetBox, Kea et `pxe01`. Tinkerbell, que la communauté Kubernetes pousse, a été évoqué en réunion. Les premières palettes arrivent dans six mois : 40 serveurs à PAR1, 12 à PAR2, deux constructeurs, puis une vingtaine par an. Je veux une décision écrite, que je puisse défendre devant la DSI et que Sophie puisse relire.

**Objectifs pédagogiques**
- Comparer des outils de provisioning sur des critères d'exploitation, pas sur des listes de fonctions.
- Relier la décision au reste de l'architecture (source de vérité, DHCP du socle, PKI, sécurité, compétences de l'équipe).
- Rédiger une décision défendable, avec ses conséquences négatives et ses conditions de révision.

**Prérequis** : M11-E09, E10 (MAAS), M11-E15 (chaîne maison), fiche Tinkerbell de l'introduction.
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/socle/adr/ADR-0110-outil-de-provisioning.md` (gabarit MADR, deux pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Poser le contexte chiffré (volumes, sites, constructeurs, cadence, équipe de quatre personnes) et les exigences (HDS, isolation, source de vérité NetBox, DHCP Kea du socle, PKI step-ca).
2. Comparer les trois options sur au moins : qui fait foi (NetBox ou la base de l'outil), DHCP (qui le sert, coexistence avec Kea), systèmes installables (Debian, Rocky, Proxmox VE, images personnalisées), pilotage des contrôleurs (Redfish, IPMI), dépendances d'exécution (Ubuntu + snap + PostgreSQL ; Kubernetes ; rien de plus que le socle), sécurité (comptes, TLS, secrets), effort d'exploitation et de montée de version, compétences requises, pérennité (éditeur, communauté, licence).
3. Utiliser les **mesures** de tes exercices (temps d'installation, nombre de gestes, ce qui a coincé) plutôt que des impressions.
4. Trancher, et dire ce qu'on fait des deux autres (abandon, veille, réévaluation à une date ou un seuil).
5. Lister les conséquences négatives et les actions (dont le sort de `maas01`, détruite au mini-projet, et du compte `wb-maas`).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en deux pages, et contient un tableau comparatif sur les critères ci-dessus.
- [ ] Les arguments s'appuient sur au moins trois mesures ou constats faits dans le module.
- [ ] La décision dit ce qui la ferait changer (seuil, événement).
- [ ] Les conséquences négatives et les actions sont écrites, avec un responsable ou un module du workbook.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

La question la plus structurante n'est pas « quel outil installe le mieux », c'est « **qui fait foi** pour l'existence et l'état d'un serveur » : MAAS a sa propre base et son propre DHCP ; Tinkerbell décrit les machines en ressources Kubernetes ; ta chaîne lit NetBox. Relis ton ADR-0060.
</details>

<details><summary>Indice 2</summary>

Une décision « maison » n'est défendable que si tu écris honnêtement ce qu'elle coûte : ce que MAAS fait et que tu devras écrire ou acheter (découverte du matériel, tests de *commissioning*, effacement sécurisé, gestion des images, interface pour les autres équipes).
</details>

**Pour aller plus loin** (facultatif) : [documentation MAAS](https://canonical.com/maas/docs), [Tinkerbell](https://tinkerbell.org/), [Ironic](https://docs.openstack.org/ironic/latest/) (provisioning bare-metal d'OpenStack, lien avec le module 10).

---

### M11-E17 — Questions de production : provisioning  `Q` `★★★`

> **Ticket PLAT-1234** — *De : Karim Benali*
> Avant la revue de la chaîne, je te pose les questions que poseront l'auditeur et l'équipe qui recevra les serveurs. Réponds par écrit et argumente : pas de « ça dépend » sans dire de quoi.

**Objectifs pédagogiques**
- Consolider les choix d'exploitation d'une chaîne de provisioning : sécurité, disponibilité, cycle de vie, reprise.
- S'entraîner à argumenter une réponse technique comme en revue d'architecture.

**Prérequis** : M11-E13 à E15.
**Durée indicative** : 1 h 30.

**Questions**

1. Le DHCP et le TFTP ne sont pas authentifiés. Après E13, que peut encore faire un attaquant présent sur le VLAN 60 ? Que ne peut-il plus faire ? Cite deux mesures réseau qui réduiraient encore le risque sur de vrais commutateurs.
2. QCM — Le binaire iPXE intègre la racine MédiSphère. L'intermédiaire de `ca01` est renouvelé (même racine). Que faut-il faire ?
   a) reconstruire iPXE ; b) rien côté iPXE, à condition que `pxe01` présente la chaîne complète ; c) redéployer le certificat de `pxe01` seulement ; d) désactiver la vérification le temps du changement.
3. Pourquoi un serveur en cours d'installation ne doit-il porter aucun jeton d'écriture vers NetBox ou Proxmox ? Comment l'orchestrateur sait-il alors que l'installation est terminée ?
4. Comment empêcher qu'un serveur `active` se réinstalle après une coupure électrique, si son ordre de démarrage met le réseau en premier ? Donne deux mécanismes indépendants.
5. `pxe01` tombe pendant l'installation de dix serveurs. Que se passe-t-il pour chacun selon l'étape où il en est ? Faut-il rendre `pxe01` redondant ? Argumente avec le besoin réel.
6. QCM — Un preseed contient `d-i passwd/user-password-crypted password $6$…`. Quelle affirmation est vraie ?
   a) l'empreinte est sans valeur pour un attaquant ; b) l'empreinte peut être attaquée hors ligne : le preseed reste un document sensible, et l'algorithme compte ; c) d-i refuse les empreintes SHA-512 ; d) l'empreinte n'est utile que si root est déverrouillé.
7. Le miroir Debian est joint en HTTP depuis le VLAN 60. Pourquoi les paquets installés sont-ils malgré tout authentiques ? Quel maillon, s'il était compromis, casserait cette garantie ?
8. MAAS et Kea sur le même VLAN : pourquoi est-ce interdit, et comment l'as-tu évité au palier 2 ? Que se serait-il passé dans le cas contraire ?
9. Sur l'iLO, pourquoi désactiver IPMI sur IP alors que Redfish reste ouvert ? Cite au moins deux faiblesses propres à IPMI 2.0 (RAKP, chiffrement, comptes).
10. QCM — Un nouveau serveur UEFI avec Secure Boot actif refuse de démarrer `ipxe.efi`. Quelle est la cause la plus probable ?
    a) l'image n'est pas signée par une clé acceptée par le micrologiciel ; b) TFTP est trop lent ; c) l'option 93 vaut 0x0000 ; d) le certificat HTTPS de `pxe01` a expiré.
11. Quelles informations le serveur installé doit-il remonter dans NetBox, et lesquelles ne doivent **pas** y être écrites automatiquement ? Relie ta réponse à l'ADR-0060.
12. Un firmware d'iLO a une vulnérabilité critique publiée. Comment ton inventaire (E18) te permet-il de savoir en cinq minutes quels serveurs sont touchés ? Que manque-t-il pour le savoir automatiquement ?

**Critères de réussite**
- [ ] Les 12 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as noté tes deux points les plus faibles et un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1, 2, 6, 7 et 10 : ta propre analyse de E13 (`securite-chaine.md`), la page [ipxe.org/crypto](https://ipxe.org/crypto) et la documentation de `apt-secure`. Pour 9 : les avis publics sur IPMI 2.0 (recherche « IPMI 2.0 RAKP hash disclosure »).
</details>

<details><summary>Indice 2</summary>

Pour 3, 4 et 5, raisonne sur le diagramme d'états de E15 : à chaque état, qui détient l'information, qui a le droit d'agir, que se passe-t-il si le maillon suivant disparaît.
</details>

---

### M11-E18 — Inventaire matériel et firmware  `LAB` `★★`

> **Ticket PLAT-1235** — *De : Nadia Roussel* — *Copie : Sophie Laurent*
> Dans NetBox, `hp01` n'a ni numéro de série, ni version de BIOS, ni version d'iLO. Le jour où HPE publie un avis de sécurité, on ne sait pas si on est concerné sans aller lire l'écran de l'iLO. Je veux que l'inventaire matériel vienne **du contrôleur**, par l'API, et soit tenu à jour automatiquement. Et une première lecture : nos firmwares sont-ils à jour ?
> *Sophie Laurent, en commentaire* : lecture seule sur l'iLO. Aucun redémarrage, aucune mise à jour de firmware dans ce ticket.

**Objectifs pédagogiques**
- Lire l'inventaire d'un serveur en Redfish : système, châssis, contrôleur, processeurs, mémoire, inventaire des firmwares (extensions propres au constructeur comprises).
- Écrire cet inventaire dans NetBox sans écraser ce qui relève de l'intention (ADR-0060) : champs personnalisés, éléments d'inventaire.
- Comparer les versions installées aux versions publiées par le constructeur, et en faire une information exploitable.

**Prérequis** : M11-E07 (Redfish), M06-E11 (synchronisation vers NetBox).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Ressources Redfish d'un iLO 4 : `/redfish/v1/Systems/1/` (modèle, numéro de série, version du BIOS, résumé processeurs et mémoire), `/redfish/v1/Chassis/1/`, `/redfish/v1/Managers/1/` (version du firmware de l'iLO), et l'inventaire des firmwares, qui est une ressource propre à HPE sur les iLO 4 (cherche-la à partir de `Systems/1` : liens et section `Oem`). Selon la version du firmware, certains champs manquent : ton script ne doit pas échouer pour autant.
- NetBox : l'équipement `hp01` (site PAR2) existe depuis M06-E04. Le numéro de série est un champ natif ; les versions de firmware n'en ont pas : crée des **champs personnalisés** sur les équipements `firmware_bios`, `firmware_ilo` (texte) et `inventaire_maj` (date) ; les composants (processeurs, barrettes mémoire) sont des **éléments d'inventaire** (*inventory items*) de l'équipement.
- Écriture dans NetBox : compte `svc-automatisation` (jeton `netbox-auto.token`) ; ses droits actuels ne couvrent pas les équipements : étends-les **au minimum** nécessaire et inscris la modification au registre des secrets.
- Versions de référence : la page de support HPE de ton modèle de ProLiant (la dernière version d'iLO 4 est la 2.82).

**Travail demandé**
1. Explore les ressources ci-dessus avec `curl` (identifiants lus depuis `ilo-hp01.env`, vérification TLS comme au M11-E07) et `jq`. Note pour chaque information utile le chemin et le champ exacts.
2. Crée dans NetBox les champs personnalisés `firmware_bios`, `firmware_ilo`, `inventaire_maj` (objets : équipements) et étends les droits de `svc-automatisation` (équipements : modification ; éléments d'inventaire : création, modification, suppression), limités par contrainte aux équipements concernés.
3. Écris `outils/inventaire-redfish.py` dans `plateforme/provisioning` (projet `uv`, `requests`) : lit l'iLO, met à jour l'équipement `hp01` dans NetBox (série, champs personnalisés) et ses éléments d'inventaire (un par processeur et par barrette, avec leur numéro de série quand l'API le donne), en ne touchant qu'aux champs qu'il possède. Option `--dry-run` qui affiche les écarts sans rien écrire. Aucun secret en argument de ligne de commande.
4. Exécution hebdomadaire par un job planifié du pipeline (variables protégées, `runner01` → iLO à travers la bordure : flux à ajouter si nécessaire) ; échec visible.
5. Compare les versions lues à celles publiées par HPE et consigne le résultat dans `docs/provisioning/firmware.md` (tableau : composant, version installée, dernière version, écart, avis de sécurité connus, décision). Pas de mise à jour dans ce ticket : ouvre un ticket CHG si une mise à jour s'impose.

**Critères de réussite**
- [ ] Dans NetBox, `hp01` a son numéro de série (identique à celui de l'iLO), `firmware_bios` et `firmware_ilo` renseignés et une date `inventaire_maj` de moins de 8 jours.
- [ ] `hp01` porte au moins un élément d'inventaire par processeur et par barrette mémoire.
- [ ] `outils/inventaire-redfish.py --dry-run` ne signale aucun écart juste après un passage réel.
- [ ] Le jeton `svc-automatisation` ne peut toujours pas modifier un équipement hors de ceux prévus (essai consigné).
- [ ] `docs/provisioning/firmware.md` est sur `main`, avec la comparaison aux versions publiées.

**Vérification** : `lab/bin/check 11 18`

<details><summary>Indice 1</summary>

Ne code pas les chemins en dur : un client Redfish **suit les liens** (`@odata.id`) à partir de la racine. C'est ce qui rend un script portable d'un iLO 4 à un iLO 5 ou à un autre constructeur, où la même information n'est pas au même endroit.
</details>

<details><summary>Indice 2</summary>

Pour ne rien écraser, ton script doit savoir quels éléments d'inventaire **il** a créés (une étiquette, ou un champ `discovered` à vrai) : il les met à jour ou les supprime, et ne touche jamais aux éléments saisis à la main.
</details>

<details><summary>Indice 3</summary>

Les contraintes d'autorisation de NetBox sont des filtres sur les objets (par exemple sur le rôle de l'équipement ou son nom), exprimés en JSON dans l'objet de permission. Teste le refus avec le jeton, sur un autre équipement, avant de conclure.
</details>

**Pour aller plus loin** (facultatif) : la même collecte sur les VMs `bm*` (numéro de série SMBIOS posé par OpenTofu, lu sur la machine installée) ; le [DMTF Redfish](https://www.dmtf.org/standards/redfish) et le [HPE iLO 4 RESTful API](https://hewlettpackard.github.io/ilo-rest-api-docs/ilo4/) ; les avis de sécurité HPE.
