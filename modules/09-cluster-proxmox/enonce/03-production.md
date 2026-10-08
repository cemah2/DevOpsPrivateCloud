# Module 09 — Palier 3 : Production

Le cluster `hv-par1` tourne : trois nœuds, Ceph hyperconvergé, HA avec règles, réplication ZFS, sauvegardes vers PBS, SDN, droits, code OpenTofu et Ansible, maintenance documentée. Il n'a pourtant jamais été **éprouvé**. Personne n'a vu un nœud tomber pour de bon et ses VMs repartir ailleurs ; personne n'a mesuré le temps que cela prend. Le seul signe qu'il va mal, aujourd'hui, c'est un utilisateur qui appelle. Le pare-feu de cluster est éteint, les comptes humains n'ont qu'un mot de passe, l'interface 8006 présente un certificat que rien ne reconnaît. La migration à chaud passe par le réseau d'administration, à côté d'un lien Corosync. Ceph est encore en Squid, comme chez InfoGér. Et si un nœud disparaissait demain avec ses disques, il faudrait improviser.

Claire Morel veut une plateforme que l'on peut confier à l'astreinte. Nadia Roussel veut des mesures, des sondes et des runbooks. Sophie Laurent veut un cluster cloisonné, une double authentification et des certificats de la PKI. Karim Benali veut que chaque changement soit répétable et passe par le code. Ce palier fait passer le cluster en production.

> ⚠️ **Rappel** : plusieurs exercices de ce palier arrêtent ou isolent volontairement un nœud. Avant chacun : (1) le cluster est sain (`pvecm status` quorate, `ceph -s` en `HEALTH_OK`, `ha-manager status` sans `error`) ; (2) tu as un accès de secours à chaque nœud **qui ne dépend pas du cluster** : la console de la VM sur `pve01` (noVNC ou `qm terminal 2091` si la VM a un port série) ; (3) seules les VMs **imbriquées** de test du palier (VMID 120-129) sont concernées. Aucun exercice de ce palier ne touche au réseau de `pve01`, ni à `pbs01` hors de ce qui est explicitement annoncé.

**Chemin imposé** (introduction du module) : les nœuds sont des VMs de l'état OpenTofu `hv` de `plateforme/infra` ; leur configuration passe par les rôles Ansible `pve_noeud` et `pve_cluster` de `plateforme/ansible` (et ceux que ce palier ajoute) appliqués par le pipeline ; les invités imbriqués durables sont décrits dans l'état `hv-invites` ; tout flux qui traverse la bordure est déclaré dans `host_vars/gw01/pare_feu.yml` (matrice commune à `gw01` et `gw02`) ; tout secret est en Vault (`critique` pour ce qui ouvre le cluster ou PBS) et inscrit au registre des secrets. Documentation : `plateforme/medisphere`, dossier `docs/virtualisation/` (`runbooks/`, `adr/`, `changements/`, `tests/`).

**VMs imbriquées de ce palier** (à l'intérieur de `hv-par1`, clones du template 199 `tpl-nested-debian13`, pool de cluster `recette`, VNet `vinv99` en DHCP sauf mention) : 120 `fence01` et 121 `fence02` (E24, sur `ceph-vm`), 122 `migr01` (E27, 4 Go), 123 à 126 `charge01` à `charge04` (E31), 127 `restau01` (E29, sur le stockage **local** de `hv03`). Vérifie toujours qu'un VMID est libre avant de l'utiliser, et détruis ces VMs quand l'exercice le demande.

**Budget mémoire** : `pve01` porte le socle (≈ 27 Go) et les trois nœuds (36 Go). `ceph01-03` restent **arrêtées** pendant tout le palier.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 09 XX`) ; elles se connectent en `root` aux nœuds par leurs alias SSH `hv01`, `hv02`, `hv03` (`~/.ssh/config` de `adm01`, M09-E03 ; clé de `adm01` posée par le fichier de réponse) et lisent `pve01` comme dans les modules précédents.

---

### M09-E24 — Le fencing à l'épreuve  `LAB` `★★★`

> **Ticket PLAT-1050** — *De : Nadia Roussel*
> Dans le dossier de recette du cluster, il est écrit « HA : redémarrage automatique des VMs en cas de panne d'un nœud ». Combien de temps ? Personne ne sait. Chez InfoGér, un nœud « figé » a gardé ses VMs vingt minutes sans que rien ne bouge, et une autre fois deux copies d'une même VM ont tourné en même temps.
> Je veux trois pannes provoquées, chronométrées, expliquées : arrêt brutal, isolement réseau, et ce qui se passe quand le nœud isolé n'a **aucune** VM HA. Et je veux qu'on ne dépende pas d'un chien de garde purement logiciel si on peut faire mieux.

**Objectifs pédagogiques**
- Comprendre le fencing par chien de garde (*watchdog*) de Proxmox VE : `watchdog-mux`, LRM, CRM, verrous dans `pmxcfs`, auto-fencing.
- Mesurer le temps de rétablissement (RTO) d'une VM HA et le décomposer en étapes.
- Distinguer arrêt brutal, perte de quorum et nœud « figé », et savoir lequel déclenche quoi.
- Remplacer le chien de garde logiciel `softdog` par un chien de garde « matériel » (émulé par QEMU sur `pve01`), par le code.

**Prérequis** : M09-E10, E11 (Ceph hyperconvergé, stockage partagé), M09-E13 (HA, règles), M09-E18 (code OpenTofu et Ansible du cluster), M09-E20 (mode maintenance).
**Durée indicative** : 3 h 30.

**Contexte technique**
- VMs de test : 120 `fence01` et 121 `fence02`, 1 vCPU, 1 Go, disque sur `ceph-vm`, ressources HA en état `started`, `max_restart` et `max_relocate` à 1. Règles : `fence01` préfère `hv02` (affinité de nœud **non stricte**), `fence01` et `fence02` sur des nœuds différents (affinité de ressources **négative**).
- Mesure de la coupure vue d'un utilisateur : [`ressources/M09-E24/mesure-coupure.sh`](../ressources/M09-E24/mesure-coupure.sh) tente une connexion TCP (port 22) vers la VM chaque seconde depuis `adm01` et affiche la durée de chaque interruption. Il ne modifie rien.
- Les nœuds sont des VMs de `pve01` (2091-2093) : un « arrêt brutal » est un `qm stop` sur `pve01` (équivalent d'une coupure d'alimentation), pas un `shutdown` dans le nœud.
- Le chien de garde « matériel » : QEMU sait émuler une carte Intel 6300ESB (option `watchdog` d'une VM Proxmox, action `reset`). La documentation HA de Proxmox VE explique comment le faire charger par `watchdog-mux` à la place de `softdog`.

> ⚠️ **Attention** : (1) `qm stop 2092` sur `pve01` est une action sur une VM du pool `lab` : vérifie trois fois le VMID ; (2) pendant l'isolement réseau de `hv02`, ne touche à rien d'autre : un second nœud perdu, et le cluster n'a plus de quorum ; (3) la règle de filtrage que tu poses dans `hv02` doit disparaître au redémarrage (aucune persistance) ; garde la commande qui la retire ; (4) le changement de chien de garde exige un arrêt complet de chaque nœud, l'un après l'autre, en mode maintenance.

**Travail demandé**
1. **Lecture et prédiction.** Lis les sections *Fencing*, *Recover Fenced Services*, *Node States* et *Service States* de la documentation HA. Avant toute manipulation, écris dans ton compte rendu la chronologie que tu attends pour un arrêt brutal de `hv02` qui porte `fence01` : quelles étapes, quels états de la ressource, quels délais (et d'où ils viennent).
2. **Préparation.** Crée les VMs 120 et 121 (dans l'état `hv-invites`), les ressources HA et les deux règles (par le code s'il les gère, sinon par `ha-manager` et en le notant). Vérifie où tourne chacune. Ouvre trois fenêtres : la sonde de mesure vers `fence01`, `ha-manager status` rafraîchi chaque seconde sur `hv01`, et les journaux de `pve-ha-crm` et `pve-ha-lrm` sur `hv01`.
3. **Scénario A — coupure d'alimentation.** Arrête brutalement `hv02` depuis `pve01`. Note l'heure de chaque transition (nœud `unknown`, ressource `fence`, `recovery`, `started` ailleurs, service rétabli). Redémarre `hv02` : `fence01` revient-elle d'elle-même ? Pourquoi ? Remets-la sur `hv02` proprement.
4. **Scénario B — isolement.** Dans `hv02` (qui porte `fence01`), bloque le trafic Corosync sur **ses deux liens** sans couper SSH. Observe `hv02` depuis sa console sur `pve01` : que se passe-t-il, au bout de combien de temps ? Que montrent `pvecm status` et `ha-manager status` des deux côtés ? Après son redémarrage, retrouve dans `journalctl -b -1` de `hv02` les traces de l'auto-fencing.
5. **Scénario C — isolement sans VM HA.** Déplace `fence01` hors de `hv02` (aucune ressource HA sur `hv02`), puis refais l'isolement. Le nœud redémarre-t-il ? Explique, et dis ce que deviennent les VMs **non HA** d'un nœud sans quorum.
6. **Chien de garde émulé.** Lis ce que la documentation dit de `softdog` et de sa limite. Ajoute le chien de garde émulé aux trois VMs de nœuds **par OpenTofu** (état `hv`), et fais charger le module correspondant par `watchdog-mux` **par Ansible** (rôle `pve_noeud`). Applique nœud par nœud : mode maintenance, arrêt complet de la VM (un redémarrage depuis l'intérieur ne suffit pas pour ajouter un périphérique), démarrage, vérification, fin de maintenance. Vérifie sur chaque nœud quel pilote sert `/dev/watchdog`.
7. **Rejouer B.** Refais le scénario B avec le chien de garde émulé. Compare les chronologies.
8. **Compte rendu.** Rédige `docs/virtualisation/tests/fencing-hv-par1.md` : prédiction, trois chronologies mesurées (tableau horodaté), RTO de chaque scénario, écart à ta prédiction et explication, ce que `softdog` ne couvre pas, et une recommandation pour le matériel réel de MédiSphère.

**Critères de réussite**
- [ ] Les VMs 120 et 121 sont des ressources HA `started`, sur deux nœuds différents ; une règle d'affinité de nœud et une règle d'affinité de ressources négative les concernent.
- [ ] Les VMs 2091-2093 ont un chien de garde émulé `i6300esb` avec l'action `reset`, déclaré dans le code OpenTofu.
- [ ] Sur chaque nœud, `watchdog-mux` utilise ce chien de garde (module chargé, `softdog` absent) ; le réglage vient du rôle `pve_noeud`.
- [ ] Les trois nœuds sont en ligne, le cluster est quorate, aucune ressource HA n'est en `error`, aucune règle de filtrage de Corosync ne subsiste.
- [ ] Le compte rendu est sur `main` de `plateforme/medisphere`, avec au moins trois mesures de RTO.

**Vérification** : `lab/bin/check 09 24`

<details><summary>Indice 1</summary>

Le CRM ne « voit » pas un nœud mourir : il voit un nœud qui ne renouvelle plus son verrou dans `pmxcfs`. Il ne relance ses VMs ailleurs qu'une fois **sûr** que le nœud ne les fait plus tourner, c'est-à-dire après le délai au bout duquel le chien de garde du nœud perdu l'a forcément redémarré. Compte ce délai, puis ajoute la durée d'un tour du gestionnaire et celle du démarrage de la VM.
</details>

<details><summary>Indice 2</summary>

Corosync utilise des ports UDP précis (liste dans *Ports used by Proxmox VE*). Une table nftables à toi, créée à la main dans `hv02`, disparaît au redémarrage. Le LRM d'un nœud n'arme le chien de garde que s'il a du travail : regarde l'état du LRM de `hv02` (`idle` ou `active`) dans `ha-manager status` avant de l'isoler.
</details>

<details><summary>Indice 3</summary>

Le module du chien de garde se choisit dans `/etc/default/pve-ha-manager` ; `wdctl` affiche l'identité du périphérique. Un module déjà chargé ne se remplace pas à chaud : c'est pour cela que l'ordre « Ansible d'abord, puis arrêt et démarrage de la VM » compte.
</details>

**Pour aller plus loin** (facultatif) : mets `hv02` en pause depuis `pve01` (`qm suspend`) pendant trois minutes, puis reprends-la, sur une VM HA **jetable** : que se passe-t-il pour `softdog`, pour le chien de garde émulé, et pour le disque RBD de la VM relancée ailleurs ? (Réponse attendue dans E32.) Voir [HA Manager](https://pve.proxmox.com/wiki/High_Availability), [`watchdog` dans `qm.conf`](https://pve.proxmox.com/pve-docs/qm.conf.5.html).

---

### M09-E25 — Superviser le cluster  `LAB` `★★`

> **Ticket PLAT-1051** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Hier, `hv03` a perdu un disque OSD à 2 h. Ceph est passé en `HEALTH_WARN`, la réplication de deux VMs vers `hv03` a échoué toute la nuit, et je l'ai appris à 9 h par un développeur. On a des sondes pour le socle (`ms-verif-services`) ; je veux la même chose pour le cluster, branchée sur la même alerte, avec une identité qui ne peut **rien** casser.

**Objectifs pédagogiques**
- Lire l'état d'un cluster Proxmox VE par l'API : quorum, nœuds, HA, Ceph, stockages, réplication, sauvegardes, certificats.
- Créer une identité de supervision en lecture seule (utilisateur, jeton, rôle, ACL) et le prouver.
- Écrire une sonde dans la lignée des `ms-verif-*` : sortie lisible, codes retour, tests sans réseau, minuterie systemd, alerte.

**Prérequis** : M06-E29 (`ms-verif-services`, `ms-alerte@`), M02-E20 (`lib/ms-commun.sh`, `pve_api`), M09-E14, E15 (réplication, sauvegardes), M09-E17 (droits).
**Durée indicative** : 3 h.

**Contexte technique**
- Identité : utilisateur `wb-supervision@pve`, jeton `wb-supervision@pve!hv` à **privilèges séparés**, rôle intégré `PVEAuditor` sur `/` (pour l'utilisateur et le jeton). Fichier d'accès sur `adm01` : `~/.config/workbook/pve-hv-supervision.env` (600, format de M00-E17 : `PVE_API_URL`, `PVE_NODE`, `PVE_TOKEN_ID`, `PVE_TOKEN_SECRET`, `PVE_CACERT`). Secret en Vault `critique`, inscrit au registre.
- Confiance TLS : jusqu'à E26, les nœuds et la VIP présentent un certificat signé par l'autorité propre du cluster (rôle `pve_cluster`, M09-E18), dont la racine est installée sur `adm01` (`/usr/local/share/ca-certificates/hv-par1-root-ca.crt`). Après E26, ce sera la racine MédiSphère : la sonde doit changer de racine par sa **configuration**.
- La sonde `ms-verif-cluster` (projet `plateforme/outils`) interroge **chaque nœud directement** (le premier qui répond) et vérifie **en plus** que la VIP `hv.par1.medisphere.internal:8006` répond : la supervision ne doit pas dépendre du point d'accès qu'elle surveille.
- Ce qu'elle doit surveiller au minimum : quorum et nombre de nœuds en ligne ; gestionnaire HA (maître présent, LRM des nœuds, aucune ressource en `error`, `fence` ou `recovery` prolongé) ; santé Ceph ; stockages actifs et taux d'occupation ; tâches de réplication (échecs, ancienneté de la dernière synchronisation) ; sauvegardes (dernier passage du job de cluster, invités non couverts) ; certificats de l'interface 8006 (expiration à moins de 10 jours).
- Interface imposée (la vérification s'en sert) : `ms-verif-cluster [-q|--quiet] [-n|--noeuds-attendus N] [-h|--help]` ; `--noeuds-attendus` remplace le nombre de nœuds de la configuration.
- Mêmes conventions que `ms-verif-services` : configuration dans `/usr/local/etc/ms-verif-cluster.conf`, codes retour 0/1/2, « rien vu » n'est jamais « tout va bien », unités `ms-verif-cluster.service` (utilisateur `admin`, `OnFailure=ms-alerte@%n.service`) et `.timer` (toutes les **5 minutes**), tests bats sans réseau.

**Travail demandé**
1. **Explorer l'API.** Depuis un nœud, parcours les chemins utiles (`pvesh ls /cluster`, `pvesh get /cluster/status`, `/cluster/resources`, `/cluster/ha/status/current`, `/cluster/ha/status/manager_status`, `/cluster/ceph/status`, `/nodes/<nœud>/replication`, `/cluster/backup-info/not-backed-up`, `/nodes/<nœud>/certificates/info`) et note, pour chaque contrôle, le champ qui fait foi et sa valeur « saine ».
2. **L'identité.** Crée l'utilisateur, le jeton et les ACL par le code (Ansible, rôle `pve_cluster`, secret jamais affiché). Prouve **avec le jeton** qu'il lit tout ce dont la sonde a besoin et qu'il ne peut rien modifier : liste ses privilèges effectifs par l'API, puis tente une action d'écriture sans effet possible.
3. **La sonde.** Écris `bin/ms-verif-cluster`, sa configuration et ses tests bats (au moins un test « rouge » par domaine), par MR sur `plateforme/outils`. Installe-la sur `adm01` (`task install:systeme`), avec ses unités.
4. **Elle voit les pannes.** Sans attendre une vraie panne, provoque et constate une alerte pour : un OSD arrêté sur `hv03` (`noout` posé avant, retiré après), une tâche de réplication en échec (cible injoignable : choisis une méthode réversible), et un nœud arrêté (maintenance). À chaque fois : la sonde passe en code 1, `ms-alerte@` se déclenche, l'alerte dit **quoi** et **où**. Puis retour au vert.
5. **Ce que Proxmox sait déjà dire.** Lis la page *Notifications* de la documentation : quels événements (fencing, réplication, sauvegarde, mises à jour) passent par ce système, vers quelles cibles ? Note ce que tu brancherais quand la plateforme d'observabilité existera (module 21), et pourquoi la sonde reste utile.

**Critères de réussite**
- [ ] `wb-supervision@pve` et son jeton `!hv` existent ; leurs seuls droits viennent de `PVEAuditor` ; le jeton n'a aucun privilège d'écriture.
- [ ] `~/.config/workbook/pve-hv-supervision.env` est en 600 sur `adm01` et ne contient pas d'autre identité.
- [ ] `ms-verif-cluster` est installée, sa minuterie tourne toutes les 5 minutes, son service déclenche `ms-alerte@` en cas d'échec ; elle répond 0 sur le cluster sain, 1 si on lui annonce un nœud de trop, 2 sur une option inconnue.
- [ ] Les tests bats de la sonde sont sur `main` de `plateforme/outils` et passent en CI.

**Vérification** : `lab/bin/check 09 25`

<details><summary>Indice 1</summary>

Un jeton à privilèges séparés n'a **que** les droits qui lui sont accordés explicitement, et jamais plus que ceux de son utilisateur : il faut une ACL pour l'utilisateur **et** une pour le jeton. Le chemin `/access/permissions`, appelé avec le jeton, renvoie ses privilèges effectifs.
</details>

<details><summary>Indice 2</summary>

`ha-manager status` en ligne de commande et `/cluster/ha/status/current` disent la même chose, mais le second est structuré (type d'entrée, état). Pour la réplication, chaque nœud ne connaît que les tâches dont il est la **source** : il faut interroger chaque nœud. La bibliothèque `ms-commun.sh` lit `PVE_API_URL` dans le fichier d'accès : pour essayer plusieurs nœuds, la sonde peut la redéfinir avant chaque appel.
</details>

<details><summary>Indice 3</summary>

Pour les tests bats, inspire-toi de ceux de `ms-verif-services` : la fonction `pve_api` et `openssl` sont remplacées par des fonctions qui répondent selon des variables d'état. Une fonction définie dans le test l'emporte sur celle de la bibliothèque si elle est définie **après** le chargement du script.
</details>

**Pour aller plus loin** (facultatif) : déclare un serveur de métriques externe (InfluxDB ou Graphite, *Datacenter → Metric Server*) vers une VM de test et regarde ce que Proxmox y pousse : c'est ce que le module 21 collectera ; [API Viewer](https://pve.proxmox.com/pve-docs/api-viewer/), [Notifications](https://pve.proxmox.com/wiki/Notifications), [External Metric Server](https://pve.proxmox.com/wiki/External_Metric_Server).

---

### M09-E26 — Sécuriser le cluster  `LAB` `★★★`

> **Ticket SEC-1052** — *De : Sophie Laurent*
> Audit interne du cluster `hv-par1`, constats : (1) l'interface 8006 et SSH des nœuds sont joignables par toute machine du VLAN MGMT, passerelles comprises ; (2) les comptes humains n'ont qu'un mot de passe ; (3) le certificat présenté sur 8006 n'est pas émis par notre PKI, donc les outils désactivent la vérification ou embarquent une racine de plus ; (4) personne ne sait dire qui a arrêté la VM 120 hier à 16 h 12.
> Je veux un cluster cloisonné par son propre pare-feu, la double authentification pour les humains, des certificats de la PKI renouvelés seuls, et une réponse à la question (4) en moins de cinq minutes.

**Objectifs pédagogiques**
- Concevoir et activer le pare-feu de cluster Proxmox VE (niveaux datacenter et nœud, IPSet `management`, alias `local_network`, règles automatiques) sans se couper l'accès.
- Recenser **tous** les flux d'un cluster hyperconvergé (Corosync, API, SSH, migration, Ceph, VRRP, EVPN, ACME, sauvegarde).
- Mettre en place la double authentification TOTP et les clés de récupération.
- Faire émettre et renouveler les certificats de l'interface 8006 par la PKI interne, y compris pour le nom de la VIP.
- Retrouver qui a fait quoi : journaux d'accès et tâches.

**Prérequis** : M09-E16 (SDN EVPN), M09-E17 (droits), M09-E18 (VIP keepalived, rôles), M09-E25 (sonde) ; M06-E18 (ACME, rôle `certificats_acme`), M06-E19 (certificats SSH d'hôte), M04-E17 (filet anti-coupure).
**Durée indicative** : 4 h 30.

**Contexte technique**
- Accès d'administration légitimes vers les nœuds : `adm01` (10.10.10.10), VPN d'administration (10.255.1.0/24), `runner01` (10.10.20.15, OpenTofu de `hv-invites`). Aucun autre hôte de MGMT (passerelles comprises) n'a à joindre 8006 ni SSH.
- Réseaux internes du cluster : COROSYNC 10.10.32.51-53 et MGMT 10.10.10.51-53 (Corosync), STOR-PUB 10.10.30.71-73 (Ceph public, et migration à partir d'E27), STOR-CLU 10.10.31.71-73 (Ceph cluster) ; VRRP de la VIP 10.10.10.200 (VRID 110) entre les nœuds sur MGMT ; EVPN du SDN (BGP et VXLAN) entre les nœuds ; sauvegardes vers `pbs01` (10.20.10.10:8007, sortant).
- Le pare-feu Proxmox VE se configure dans `/etc/pve/firewall/cluster.fw` (commun) et `/etc/pve/nodes/<nœud>/host.fw` (par nœud). Il ajoute des règles automatiques pour le trafic du cluster, fondées sur l'alias `local_network` : lis la documentation pour savoir ce qu'elles ouvrent, et à qui.
- Certificat de l'interface 8006 : émis par `ca01` (racine « MédiSphère Root CA »), noms `hvNN.par1.medisphere.internal` **et** `hv.par1.medisphere.internal` (la VIP, utilisée par OpenTofu et la sonde), 30 jours au plus, renouvelé automatiquement, sans clé d'API DNS ni secret d'autorité déposés sur les nœuds. Deux outils sont candidats : le client ACME intégré de Proxmox VE (`pvenode acme`) et le rôle `certificats_acme` de M06-E18 (avec `pvenode cert set`). Étudie les deux et choisis.
- Double authentification : TOTP pour `root@pam` et pour chaque membre de `hv-admins` ; clés de récupération générées, rangées hors ligne (emplacement au registre des secrets, jamais la valeur). Les jetons d'API ne passent pas par la double authentification : c'est pour cela qu'ils sont limités.
- Rôle Ansible nouveau : `pve_pare_feu` (contenu de `cluster.fw` et des `host.fw`, filet anti-coupure).

> ⚠️ **Attention** : (1) « If you enable the firewall, traffic to all hosts will be blocked by default » : avant d'activer quoi que ce soit, ouvre une console de chaque nœud depuis `pve01` et garde une session SSH ouverte ; (2) active d'abord le pare-feu **sur un seul nœud** (les autres en `enable: 0` dans leur `host.fw`), avec une désactivation automatique programmée dans 10 minutes si tu ne la confirmes pas ; (3) un VRRP filtré donne **deux** maîtres et la VIP sur deux nœuds ; un Ceph filtré gèle les VMs ; vérifie ces deux points avant d'étendre aux autres nœuds ; (4) TOTP sur `root@pam` : génère les clés de récupération **avant** de te déconnecter, et teste-les ; la console de `pve01` reste la sortie de secours.

**Travail demandé**
1. **La matrice.** Dresse la liste des flux du cluster (source, destination, port, protocole, motif), à partir de la documentation (*Ports used by Proxmox VE*, Ceph *Network Configuration Reference*, SDN) et de l'observation (`ss -tulpn` sur un nœud, `conntrack -L` si installé). Compare avec ce que les règles automatiques ouvrent déjà, et décide ce que tu fais de l'alias `local_network`.
2. **Le pare-feu.** Écris le rôle `pve_pare_feu` : IPSet `management`, alias, groupes de sécurité si utile, règles du datacenter et des nœuds, politique d'entrée en `DROP` ; un filet anti-coupure qui désactive le pare-feu si la confirmation n'arrive pas. Applique sur `hv01` seul, vérifie chaque flux de ta matrice (quorum, Ceph, VIP sur un seul nœud, EVPN, migration, sauvegarde, 8006 depuis `adm01` et `runner01`), puis étends à `hv02` et `hv03`.
3. **La preuve négative.** Depuis `gw01` (ou `gw02`), tente 8006 et SSH sur les trois nœuds : refusés. Depuis `adm01` et `runner01` : acceptés. Ajoute ces tests à ta matrice documentée (`docs/virtualisation/matrice-flux-hv-par1.md`).
4. **TOTP.** Active TOTP pour toi (`<MOI>@pve`) et `root@pam`, génère les clés de récupération, teste une connexion avec chacun des trois facteurs (mot de passe, code, clé de récupération sur un compte de test). Explique ce que deviennent les jetons et les connexions SSH entre nœuds.
5. **Certificats.** Compare les deux outils candidats au regard des contraintes du contexte (noms à couvrir, défi ACME possible pour un nom flottant, fréquence de renouvellement avec des certificats de 30 jours, secrets sur les nœuds). Mets en œuvre ton choix **par le code** (rôles et playbooks de `plateforme/ansible`, variables du groupe des nœuds), avec ce qu'il faut dans `pare_feu.yml` et dans `pve_pare_feu`. Vérifie depuis `adm01` avec la seule racine MédiSphère, sur chaque nœud **et** sur la VIP. Passe ensuite la sonde de E25 et OpenTofu (`hv-invites`) sur cette racine.
6. **SSH.** Vérifie que l'authentification par mot de passe est refusée sur les nœuds, que `root` ne se connecte que par clé (les nœuds en ont besoin entre eux) et que les clés d'hôte sont signées (M06-E19). Applique par le rôle `pve_noeud`, sans casser les connexions entre nœuds (migration, réplication).
7. **Qui a fait quoi ?** Arrête puis redémarre la VM 120 depuis l'interface avec ton compte. Retrouve, en moins de cinq minutes et sans connaître l'heure exacte, le compte, l'adresse source, l'heure et le nœud, à partir des journaux (`/var/log/pveproxy/access.log`, tâches du cluster). Écris la procédure en tête de la matrice documentée.
8. **La bordure.** Clos l'écart inscrit au registre en M09-E05 : la règle « bastion (MGMT) vers tout le lab, PAR2 et LYO1 » de `pare_feu.yml` n'a pas de source. Maintenant que tu connais tous les flux sortants des nœuds, décide ce qui doit avoir sa propre ligne avant de restreindre cette règle, fais-le dans une seule MR, et prouve qu'aucun flux légitime des nœuds ne s'est perdu (sauvegarde, certificats, résolution de noms, heure, dépôts).

**Critères de réussite**
- [ ] Le pare-feu est actif au niveau du cluster et sur les trois nœuds, géré par le rôle `pve_pare_feu` ; l'IPSet `management` contient `adm01`, le VPN d'administration et `runner01`.
- [ ] Depuis `gw01`, 8006 et 22 des trois nœuds sont injoignables ; depuis `adm01` et `runner01`, joignables. Le cluster reste quorate, Ceph en `HEALTH_OK`, la VIP portée par un seul nœud.
- [ ] Les certificats présentés sur 8006 par chaque nœud et par la VIP sont émis par la PKI MédiSphère, valides pour leurs noms, pour 31 jours au plus, avec plus de 10 jours restants ; leur renouvellement est automatique.
- [ ] `root@pam` et chaque membre de `hv-admins` ont un facteur TOTP ; `PasswordAuthentication no` est effectif sur les nœuds.
- [ ] La matrice des flux du cluster et la procédure d'enquête sont sur `main` de `plateforme/medisphere`.
- [ ] Dans `pare_feu.yml`, la règle du bastion a une source ; chaque flux des nœuds qui traverse la bordure a sa ligne (motif, référence) ; une sauvegarde vers `pbs01` et un renouvellement de certificat passent toujours ; l'écart de M09-E05 est clos au registre.

**Vérification** : `lab/bin/check 09 26`

<details><summary>Indice 1</summary>

Par défaut, l'alias `local_network` vaut le réseau de l'adresse principale du nœud (celle de `/etc/hosts`) : tout MGMT. Les règles automatiques lui ouvrent l'interface, SSH et les consoles. On peut redéfinir cet alias dans `cluster.fw`. Les règles automatiques ne savent rien de Ceph, de VRRP ni de l'EVPN : c'est toi qui les ouvres, entre nœuds seulement.
</details>

<details><summary>Indice 2</summary>

Pour un défi HTTP-01, `ca01` se connecte au port 80 de l'adresse **résolue** du nom à valider. Pour `hv.par1.medisphere.internal`, c'est la VIP : un seul nœud la porte. Demande-toi ensuite combien de fois par mois chaque outil refait un défi, avec des certificats de 30 jours (lis quand `pve-daily-update` déclenche un renouvellement ACME, et comment step renouvelle).
</details>

<details><summary>Indice 3</summary>

`pvenode cert set` installe un certificat et sa clé pour `pveproxy` (fichiers `pveproxy-ssl.*` du nœud) et peut redémarrer le service. Le rôle `certificats_acme` sait appeler une commande de rechargement après chaque émission et chaque renouvellement. Côté pare-feu de cluster, une règle de protocole `vrrp` existe dans les macros/protocoles acceptés : vérifie la syntaxe dans la documentation avant de l'écrire.
</details>

**Pour aller plus loin** (facultatif) : passe un nœud sur le pare-feu nftables (`proxmox-firewall`, option `nftables: 1` dans `host.fw`) et compare le jeu de règles produit ; impose TOTP au niveau du realm `pve` ; [Firewall](https://pve.proxmox.com/wiki/Firewall), [User Management — TFA](https://pve.proxmox.com/wiki/User_Management), [Certificate Management](https://pve.proxmox.com/wiki/Certificate_Management), [Ceph network reference](https://docs.ceph.com/en/latest/rados/configuration/network-config-ref/).

---

### M09-E27 — Le réseau de migration  `LAB` `★★`

> **Ticket PLAT-1053** — *De : Karim Benali*
> Pendant la maintenance de jeudi, la migration à chaud de `app01` a duré quatre minutes et Corosync a journalisé des pertes de jetons sur le lien 1 : la migration passe par MGMT, comme l'interface et l'un des deux liens Corosync. Sur le vrai matériel, on aura un réseau dédié ; dans le lab, on a le VLAN 30 en MTU 9000.
> Je veux la migration sur le VLAN 30, une limite de débit qui protège Ceph, et des chiffres avant/après. Et dis-moi ce qu'on gagnerait à passer en `insecure`, et ce qu'on y perdrait.

**Objectifs pédagogiques**
- Comprendre ce qui circule pendant une migration à chaud (mémoire, pages modifiées, convergence) et pourquoi Corosync y est sensible.
- Configurer le réseau et le type de migration au niveau du datacenter, et une limite de débit, par le code.
- Mesurer, et relier les chiffres à la théorie (débit, taux de modification de la mémoire, MTU).

**Prérequis** : M09-E07, E11 (migration), M09-E10 (réseau Ceph 10.10.30.0/24, MTU 9000 de bout en bout), M09-E26 (pare-feu de cluster).
**Durée indicative** : 2 h 30.

**Contexte technique**
- VM de test 122 `migr01` : 2 vCPU, **4 Go**, disque sur `ceph-vm`. Charge mémoire : `stress-ng --vm 1 --vm-bytes 2G --vm-keep` (paquet Debian) dans la VM, qui réécrit sans cesse 2 Go.
- Réglages du datacenter : `migration` (type et réseau) et `bwlimit` (en Kio/s) dans `/etc/pve/datacenter.cfg`, modifiables par `pvesh set /cluster/options` ; ils se surchargent par migration (`qm migrate … --migration_network`, `--migration_type`, `--bwlimit`).
- Corosync expose des statistiques de ses liens (`corosync-cfgtool -s`, `corosync-cmapctl -m stats`) : latence moyenne et maximale par lien, jetons retransmis.
- Le pare-feu d'E26 doit laisser passer la migration sur son nouveau réseau.

**Travail demandé**
1. **Lecture.** Dans la documentation (*Migration* du chapitre *Qemu/KVM Virtual Machines*, *Cluster Network* du chapitre *Cluster Manager*), relève : ce que fait `type=secure` et par quel canal, ce que change `insecure` (ports, chiffrement), comment Proxmox choisit l'adresse de destination sur le réseau de migration, et pourquoi la documentation insiste pour séparer Corosync des réseaux à gros débit.
2. **Mesure de référence.** Avec la configuration actuelle, migre `migr01` à chaud, sans puis avec la charge mémoire. Pendant la seconde, relève les statistiques de latence des deux liens Corosync. Note durée totale, débit, temps d'arrêt annoncé (*downtime*) dans le journal de la tâche.
3. **Configuration.** Par le rôle `pve_cluster` : migration `secure` sur 10.10.30.0/24, et une limite `bwlimit` de migration que tu justifies (part du lien laissée à Ceph). Vérifie dans le journal d'une migration que l'adresse de destination est bien sur le VLAN 30.
4. **Nouvelle mesure.** Refais les deux migrations. Compare (tableau) : durée, débit, *downtime*, latence Corosync. Puis, **pour une seule migration** et en argument de commande, essaie `insecure` : que faut-il ouvrir dans le pare-feu, quel gain observes-tu ? Conclus.
5. **Charge qui ne converge pas.** Avec la limite de débit au plus bas que tu juges raisonnable et une charge mémoire plus forte, la migration se termine-t-elle ? Que fait QEMU (lis le journal), et quels paramètres existent pour l'aider ?
6. **Compte rendu.** `docs/virtualisation/tests/migration-hv-par1.md` : chiffres, choix retenus, décision sur `insecure` (et ce qui la ferait changer sur le matériel réel). Détruis `migr01`.

**Critères de réussite**
- [ ] `datacenter.cfg` fixe la migration en `secure` sur 10.10.30.0/24 et une limite de débit de migration, posées par le rôle `pve_cluster`.
- [ ] Une migration récente a envoyé son trafic sur une adresse du VLAN 30 (journal de tâche).
- [ ] Aucun lien Corosync n'est sur 10.10.30.0/24 ; les deux liens sont connectés sur chaque nœud.
- [ ] Le compte rendu avec le tableau avant/après est sur `main` ; la VM 122 n'existe plus.

**Vérification** : `lab/bin/check 09 27`

<details><summary>Indice 1</summary>

Une migration à chaud copie la mémoire, puis recopie ce qui a changé pendant la copie, et ainsi de suite : elle ne converge que si le débit dépasse nettement le rythme auquel la VM salit sa mémoire. Divise 2 Go réécrits en boucle par ton débit : tu sauras si la migration peut finir.
</details>

<details><summary>Indice 2</summary>

Le journal d'une tâche de migration se lit par `pvesh get /nodes/<nœud>/tasks/<UPID>/log` ou dans l'interface ; il annonce l'adresse dédiée utilisée. `bwlimit` s'exprime en Kio/s : 1 Gbit/s ≈ 122 070 Kio/s.
</details>

**Pour aller plus loin** (facultatif) : les paramètres de migration de QEMU (*auto-converge*, *postcopy*) et ce que Proxmox expose ; la migration de VMs avec disques locaux (`--with-local-disks`) et la limite `move` ; [Qemu/KVM — Migration](https://pve.proxmox.com/wiki/Qemu/KVM_Virtual_Machines#qm_migration), [Cluster Network](https://pve.proxmox.com/wiki/Cluster_Manager#pvecm_cluster_network), [`datacenter.cfg`](https://pve.proxmox.com/wiki/Manual:_datacenter.cfg).

---

### M09-E28 — Monter Ceph de Squid à Tentacle  `LAB` `★★★`

> **Ticket CHG-1054** — *De : Karim Benali* — *Copie : Claire Morel*
> Le Ceph du cluster est en Squid, comme le parc d'InfoGér qu'on reprend. Le Ceph de PAR1 (`ceph-par1`) est déjà en Tentacle, et Proxmox VE 9.2 installe Tentacle par défaut. On monte, maintenant que le cluster est petit et qu'on peut répéter.
> Règles : procédure officielle, un démon à la fois, `HEALTH_OK` (ou seulement l'avertissement attendu) entre chaque étape, les VMs HA tournent pendant toute l'opération, et un playbook qu'on pourra rejouer sur un autre cluster.

**Objectifs pédagogiques**
- Suivre une procédure officielle de montée de version majeure de Ceph sur Proxmox VE et comprendre l'ordre des démons.
- Distinguer les étapes réversibles des étapes irréversibles (`require-osd-release`).
- Automatiser une montée de version progressive avec des contrôles entre chaque étape.

**Prérequis** : M09-E10 (Ceph hyperconvergé Squid), M09-E19 (mises à jour progressives), M08 (exploitation de Ceph, drapeaux).
**Durée indicative** : 3 h.

**Contexte technique**
- Procédure de référence : [Ceph Squid to Tentacle](https://pve.proxmox.com/wiki/Ceph_Squid_to_Tentacle) (wiki Proxmox). Lis ses **prérequis** (versions minimales de Proxmox VE et des paquets Squid) avant tout.
- Dépôt Ceph des nœuds : `/etc/apt/sources.list.d/ceph.sources` (format deb822), composant `no-subscription`.
- Le cluster n'a pas de CephFS (pas de MDS) ; s'il en a un, l'étape MDS de la procédure s'applique.
- Charge pendant l'opération : les VMs HA 120 et 121 (E24) tournent sur `ceph-vm` ; lance la sonde de coupure d'E24 sur `fence01` pendant toute l'opération.
- Livrable : un playbook `playbooks/ceph-squid-vers-tentacle.yml` dans `plateforme/ansible`, rejouable (sans effet sur un cluster déjà en Tentacle), qui s'arrête au premier contrôle en échec.

> ⚠️ **Attention** : (1) il n'y a **pas** de retour arrière d'une version majeure de Ceph une fois les OSD redémarrés en Tentacle, et encore moins après `require-osd-release` ; dans le lab, le filet est un ensemble d'instantanés des trois VMs de nœuds pris **cluster arrêté** (VMs 2091-2093 arrêtées en même temps, puis instantané de chacune sur `pve01`), à supprimer une fois la montée validée ; (2) vérifie la place disponible sur les stockages de `pve01` avant ces instantanés ; (3) ne lance pas la montée pendant un job de sauvegarde ou de réplication.

**Travail demandé**
1. **Préalables.** Relève et consigne : version de Proxmox VE et des paquets Ceph sur chaque nœud, `ceph versions`, `ceph -s`, drapeaux posés, `ceph osd dump | grep require_osd_release`, `ceph mon dump | grep min_mon_release`. Liste les prérequis de la procédure qui ne sont pas remplis et remplis-les (mise à jour des nœuds selon RB-090/E19).
2. **Filet du lab.** Prends les instantanés décrits dans l'avertissement, redémarre le cluster, vérifie qu'il est sain.
3. **Le playbook.** Écris le playbook : contrôles préalables (versions, santé), dépôt changé sur chaque nœud, mise à jour des paquets, drapeau `noout`, redémarrage des moniteurs **un nœud à la fois** avec attente de santé, contrôle de `min_mon_release`, gestionnaires, OSD un nœud à la fois avec attente de la fin de la récupération, `require-osd-release`, retrait de `noout`, contrôle final. Chaque attente est bornée (délai maximal), chaque échec arrête tout.
4. **La montée.** Lance le playbook en mode vérification, puis pour de bon, étape par étape (`--step` ou étiquettes) la première fois. Pendant ce temps, observe `ceph -s` et la sonde de coupure. Note chaque avertissement apparu et ce qui l'a fait disparaître.
5. **Après.** `ceph versions` homogène, plus aucun démon en Squid, `HEALTH_OK`. Vérifie aussi l'utilisation `META` des OSD (point connu de la procédure). Supprime les instantanés du lab. Rejoue le playbook : aucun changement.
6. **Compte rendu.** Complète la fiche `docs/virtualisation/changements/CHG-1054-ceph-tentacle.md` (préalables, déroulé horodaté, interruption mesurée des VMs, incidents, retour arrière possible à chaque étape).

**Critères de réussite**
- [ ] Tous les démons Ceph (MON, MGR, OSD) des trois nœuds sont en 20.2.x ; `require_osd_release` vaut `tentacle` ; `min_mon_release` vaut 20.
- [ ] Le drapeau `noout` n'est plus posé ; Ceph est en `HEALTH_OK`.
- [ ] Les trois nœuds utilisent le dépôt `ceph-tentacle` ; aucun instantané de filet ne subsiste sur les VMs 2091-2093.
- [ ] Le playbook et la fiche CHG-1054 sont sur `main` ; la sonde de coupure n'a mesuré aucune interruption des VMs 120 et 121.

**Vérification** : `lab/bin/check 09 28`

<details><summary>Indice 1</summary>

Mettre à jour les paquets ne redémarre aucun démon Ceph : les anciens binaires continuent de tourner jusqu'au redémarrage de chaque unité. C'est ce qui permet de choisir l'ordre (MON, puis MGR, puis OSD). Les unités systemd de Ceph sur Proxmox VE sont regroupées par type (`ceph-mon.target`, `ceph-osd.target`…).
</details>

<details><summary>Indice 2</summary>

Dans un playbook, `serial: 1` traite un nœud à la fois ; un `until` sur la sortie JSON de `ceph status` (ou `ceph health`) avec `retries` et `delay` borne l'attente. Pour le seul avertissement attendu pendant l'opération, regarde quels codes de santé apparaissent quand `noout` est posé.
</details>

**Pour aller plus loin** (facultatif) : lis les notes de version de Tentacle 20.2 (plugin EC par défaut, modules mgr supprimés, mClock) et dis lesquelles touchent ce cluster ; compare avec la montée de `ceph-par1` par cephadm (M08) : qui orchestre, et qu'est-ce qui reste à ta charge dans chaque cas ; [Ceph Tentacle release notes](https://docs.ceph.com/en/latest/releases/tentacle/).

---

### M09-E29 — Reconstruire un nœud, restaurer le cluster  `LIBRE` `★★★`

> **Ticket PLAT-1055** — *De : Nadia Roussel*
> Exercice de reprise trimestriel : on considère `hv03` comme **perdu** (carte mère et disques). Je veux le voir reconstruit à l'identique (nom, adresses, rôle dans Ceph, HA, réplication, pare-feu, certificat) depuis le code et les sauvegardes, sans improvisation, et je veux le runbook qui permettra à l'astreinte de le refaire seule à 3 h du matin.
> Au passage : la VM `restau01` n'existait que sur le disque local de `hv03`. Et Lucas a supprimé hier par erreur le fichier de configuration d'une VM de test : on a de quoi le retrouver ?

**Objectifs pédagogiques**
- Savoir ce qui fait l'identité d'un nœud dans un cluster Proxmox VE (`pmxcfs`, Corosync, certificats, clés SSH, Ceph) et ce qui doit être sauvegardé hors du cluster.
- Retirer proprement un nœud perdu (cluster, Ceph, HA, réplication) puis le réintégrer sous le même nom.
- Restaurer ce qui n'existait que sur le nœud perdu, depuis PBS.
- Écrire un runbook de reconstruction jouable par un tiers.

**Prérequis** : M09-E03 (installation automatique), M09-E08 (ajout d'un nœud), M09-E10, E14, E15 (Ceph, réplication, PBS), M09-E24, E26 (chien de garde, pare-feu, certificats), M06-E28 (rôle `sauvegarde_pbs`), M09-E44 recommandé.
**Durée indicative** : 5 h.

**Contraintes**
- **Avant la perte** : chaque nœud sauvegarde chaque nuit vers PBS sa configuration de cluster (contenu de `/etc/pve`, base `config.db` de `pmxcfs` copiée de façon cohérente, configuration Corosync et réseau du nœud), dans l'espace de noms `par1/hv`, groupe `host/<nœud>`, chiffrée côté client avec la clé du cluster (Vault `critique`, E15), avec le jeton PBS du cluster d'E15. Pas de nouvel outil : le rôle `sauvegarde_pbs` de M06-E28, étendu (noms imposés conservés : script `/usr/local/sbin/wb-backup-socle.sh`, unités `wb-backup-socle.service` et `.timer`, secrets `/etc/wb-backup/pbs-<nœud>.env` et `.key` en `root:root 600`, alerte `ms-alerte@`). Une sauvegarde a réussi sur les trois nœuds avant de commencer.
- La VM 127 `restau01` (1 Go, disque sur le stockage local LVM-thin de `hv03`, hors HA) est sauvegardée par le job de cluster d'E15 avant la perte.
- **La perte** : arrêt brutal de la VM 2093 sur `pve01`, puis destruction de la VM et de ses disques **par le code** (état `hv`). Rien de `hv03` n'est récupéré à la main.
- **Pendant la perte** : les VMs HA continuent de tourner ; Ceph fonctionne en mode dégradé (2 hôtes sur 3) et tu sais dire ce que cela implique pour `size`/`min_size` ; tu retires du cluster et de Ceph tout ce qui désignait l'ancien `hv03`, et tu sais justifier chaque suppression.
- **La reconstruction** : même nom, mêmes adresses, même VMID, installation automatique, puis tout le reste par le code (rôles du cluster) ; réintégration au cluster, au Ceph (MON, MGR, OSD), aux règles HA, aux tâches de réplication, au pare-feu, à la VIP, au SDN ; certificat 8006 de la PKI. Aucune trace de l'ancien nœud ne doit subsister (clés d'hôte, entrées SSH connues, OSD fantômes).
- **Les restaurations** : `restau01` est restaurée depuis PBS sur `hv03` reconstruit (même VMID) ; le fichier de configuration d'une VM de test que tu supprimes volontairement est retrouvé dans la sauvegarde de configuration et remis en place sans restaurer toute la VM.
- Mesure : chaque étape est horodatée, le temps total de reconstruction est noté.
- Livrables dans `plateforme/medisphere` : `docs/virtualisation/runbooks/RB-091-reconstruire-un-noeud.md` (décision, préalables, retrait, réinstallation, réintégration, restaurations, vérifications, retour à la normale ; chaque commande destructive précédée de son contrôle), section datée dans `docs/virtualisation/tests/reprise-hv-par1.md` (feuille de temps, RTO par étape). Le runbook traite aussi, en une section, la **perte totale** du cluster : ce que la sauvegarde de configuration permet, ce qu'elle ne permet pas.

**Critères de réussite**
- [ ] Sur chaque nœud, la minuterie de sauvegarde de configuration est active et son dernier passage a réussi ; PBS contient un instantané `host/hvNN` de moins de 48 h pour chacun dans `par1/hv`, chiffré.
- [ ] La VM 2093 a été recréée (au moins deux créations dans le journal de `pve01`) ; `hv03` est en ligne, le cluster est quorate à trois nœuds, sans nœud fantôme.
- [ ] Ceph est en `HEALTH_OK` avec trois MON et six OSD actifs, aucun OSD fantôme ; `hv03` porte un MON et deux OSD.
- [ ] La VM 127 tourne sur `hv03` ; les tâches de réplication vers `hv03` ont réussi depuis la reconstruction.
- [ ] RB-091 et le compte rendu sont sur `main`.

**Vérification** : `lab/bin/check 09 29`

<details><summary>Indice 1</summary>

Proxmox VE embarque `proxmox-backup-client` : un nœud peut sauvegarder des fichiers (archive `.pxar`) dans un groupe de type `host`. `pmxcfs` stocke tout `/etc/pve` dans une base SQLite : une copie cohérente se fait avec l'outil de SQLite, pas avec `cp` sur une base ouverte. Lis la section *Recovery* du chapitre *Proxmox Cluster File System*.
</details>

<details><summary>Indice 2</summary>

Réutiliser le nom d'un nœud supprimé est possible, mais la documentation (*Remove a Cluster Node*) prévient : l'ancien nœud ne doit jamais revenir, et des restes (répertoire du nœud dans `/etc/pve/nodes/`, entrées SSH connues du cluster) doivent être nettoyés. Côté Ceph, un OSD perdu se retire de la carte CRUSH, des clés et de la carte des OSD ; un MON perdu se retire de la carte des moniteurs.
</details>

<details><summary>Indice 3</summary>

Ce qui est propre à un nœud dans `/etc/pve` (son `host.fw`, son certificat, ses fichiers sous `nodes/hv03/`) disparaît avec sa suppression : c'est le code qui doit le recréer, pas la sauvegarde. La sauvegarde de configuration sert à ce que le code ne sait pas recréer (fichiers d'invités, état du jour), et à la perte totale.
</details>

**Pour aller plus loin** (facultatif) : refais l'exercice en mesurant le temps sans le runbook, puis avec, par quelqu'un d'autre ; [Cluster Manager — Remove a Cluster Node](https://pve.proxmox.com/wiki/Cluster_Manager#_remove_a_cluster_node), [pmxcfs — Recovery](https://pve.proxmox.com/wiki/Proxmox_Cluster_File_System_(pmxcfs)), [Backup Client — namespaces](https://pbs.proxmox.com/docs/backup-client.html).

---

### M09-E30 — ADR : cluster Proxmox ou OpenStack ?  `RED` `★★`

> **Ticket PLAT-1056** — *De : Claire Morel*
> La direction a lu qu'on allait aussi monter OpenStack (module suivant) et demande pourquoi « deux clouds ». Julien voudrait créer ses environnements de recette lui-même, Sophie veut savoir où iront les données de santé, Nadia veut savoir ce qu'elle devra opérer la nuit.
> Écris l'ADR qui dit **quelles charges** vont sur le cluster Proxmox, lesquelles sur OpenStack, et ce qui fait passer une charge de l'un à l'autre.

**Objectifs pédagogiques**
- Comparer deux modèles d'infrastructure (virtualisation gérée par l'équipe, cloud en libre-service) sur des critères explicites.
- Décider par **usage** plutôt que par préférence technique, et dire ce qui rendrait la décision caduque.
- Rédiger une décision défendable avec ses conséquences négatives.

**Prérequis** : M09 paliers 1 à 3 ; lecture de l'introduction du module 10 et de PLAN §5.2 (modules 10, 14, 24) ; ADR-0080 (M08).
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/virtualisation/adr/ADR-0090-cluster-proxmox-ou-openstack.md` (gabarit MADR de M00-E33, deux pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Lister les **charges** à placer, avec leurs caractéristiques : services socle et d'infrastructure (DNS, PKI, forge, sauvegardes), bases de données de production de MédiAgenda, VMs héritées d'InfoGér (Legacy-RDV), environnements de recette éphémères des équipes de Julien, nœuds Kubernetes (module 14), postes de rebond, charges de test du workbook.
2. Comparer au moins trois options (tout sur Proxmox ; tout sur OpenStack ; partage par usage ; éventuellement OpenStack **sur** des VMs Proxmox) selon des critères explicites : libre-service et multi-locataire, quotas, API et IaC, HA d'une VM unique contre applications conçues pour la panne, compétences et charge d'astreinte, consommation de ressources du plan de contrôle, stockage (Ceph hyperconvergé contre `ceph-par1`), conformité HDS (traçabilité, cloisonnement), sortie de secours (réversibilité).
3. Trancher, avec un tableau « charge → plateforme → raison ».
4. Dire ce qui ferait **changer** la décision (seuils : nombre de VMs, d'équipes, de demandes par semaine ; incident ; compétence perdue).
5. Lister les conséquences négatives et les actions induites (rattachées à un module : M10, M14, M24, M28, F1).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en deux pages, et contient le tableau des charges.
- [ ] Au moins trois options réellement envisagées, avec des critères explicites, pas des impressions.
- [ ] Les conditions de remise en cause sont chiffrées ou observables.
- [ ] Les conséquences négatives sont écrites et rattachées à des actions.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Pose la question à l'envers : pour chaque charge, **qui** demande une VM, **combien de fois par semaine**, et qui est réveillé quand elle tombe ? Une plateforme en libre-service coûte cher à opérer ; elle ne se justifie que si les demandes sont fréquentes et viennent de plusieurs équipes.
</details>

<details><summary>Indice 2</summary>

La HA de Proxmox redémarre une VM unique ailleurs ; OpenStack, par défaut, ne le fait pas (une instance perdue est relancée par l'application ou par l'orchestrateur). Une charge « pet » et une charge « cattle » ne demandent pas la même plateforme.
</details>

**Pour aller plus loin** (facultatif) : le modèle de responsabilité partagée appliqué à un cloud privé (qui patche quoi, qui sauvegarde quoi) ; [Proxmox VE — Features](https://pve.proxmox.com/wiki/Main_Page), [OpenStack — Project navigator](https://www.openstack.org/software/project-navigator/).

---

### M09-E31 — Capacité et surallocation  `LIBRE` `★★★`

> **Ticket DEV-1057** — *De : Julien Petit* — *Copie : Claire Morel*
> Pour la recette de MédiAgenda, il me faudrait une vingtaine de VMs de 2 Go sur `hv-par1`. On m'a dit « le cluster a 36 Go, ça passe ». C'est vrai ?
> *Claire, en commentaire* : je veux un chiffre de capacité **honnête** du cluster, qui tienne compte de la perte d'un nœud, et une règle qui dise quand on refuse une demande. Et je ne veux plus d'un « ça passe » au doigt mouillé.

**Objectifs pédagogiques**
- Calculer la capacité utile d'un cluster hyperconvergé : réserve N+1, mémoire de l'hôte, de Ceph, du cache ZFS, de la HA.
- Comprendre les mécanismes de surallocation de la mémoire (ballon, KSM) et du processeur, et leurs risques.
- Outiller la décision : un calcul reproductible depuis l'API et une règle d'acceptation.

**Prérequis** : M09-E10 (Ceph, `osd_memory_target`), M09-E13 (HA), M09-E14 (ZFS), M09-E25 (sonde, identité de supervision).
**Durée indicative** : 3 h 30.

**Contraintes**
- Mesure d'abord, calcule ensuite : relève sur chaque nœud la mémoire réellement consommée par l'hôte, chaque démon Ceph, le cache ZFS (taille maximale effective et taille actuelle), et la marge que tu veux garder ; trouve dans la documentation les valeurs par défaut qui s'appliquent (cache ZFS selon le type d'installation, `osd_memory_target`, KSM et `ksmtuned`, ballon).
- Capacité « honnête » : ce qui reste pour les invités quand **un** nœud est perdu et que la HA a relancé ses VMs ailleurs, sans faire basculer les autres nœuds en échange (*swap*) ni déclencher l'OOM killer.
- Surallocation : décide, pour la mémoire et pour le processeur, si et comment tu suralloues (ballon avec plancher sur les VMs de recette, KSM, ratio vCPU/cœur), et pour quelles VMs jamais (bases de données, VMs HA de production). Démontre-le sur quatre VMs de test 123-126 (`charge01-04`, 2 Go, plancher de ballon à 1 Go, pool `recette`) en remplissant la mémoire d'un nœud : qui rend de la mémoire, quand, et ce que voit l'invité.
- Réglage du cache ZFS s'il le faut, par le rôle `pve_noeud`, justifié.
- Outil : `ms-capacite-cluster` dans `plateforme/outils` (mêmes conventions que les `ms-verif-*`, identité de supervision d'E25, tests bats sans réseau) qui calcule, depuis l'API, la mémoire allouée aux invités, la capacité N+1 et la marge restante ; il répond 0 si une demande (`--demande <N>x<Mio>`) entre dans la capacité N+1, 1 sinon, 2 en cas d'usage incorrect. La sonde d'E25 (ou cet outil appelé par elle) alerte quand la mémoire allouée aux VMs HA dépasse la capacité N+1.
- Livrable dans `plateforme/medisphere` : `docs/virtualisation/capacite-hv-par1.md` — mesures, calcul détaillé, politique de surallocation, règle d'acceptation d'une demande, réponse chiffrée à Julien (combien de VMs de 2 Go, à quelles conditions, et ce qu'on lui propose à la place sinon).
- Les VMs 123-126 sont détruites à la fin.

**Critères de réussite**
- [ ] `ms-capacite-cluster` est installée sur `adm01`, répond 0 pour une demande de 1×512 Mio et 1 pour une demande de 20×2048 Mio sur le cluster actuel ; ses tests bats sont sur `main` et passent.
- [ ] Le cache ZFS a une taille maximale explicite sur chaque nœud (ou la décision de ne pas le limiter est justifiée dans le document).
- [ ] `ksmtuned` est actif sur chaque nœud.
- [ ] Le document de capacité est sur `main` et contient le calcul N+1, la politique de surallocation et la réponse à Julien ; les VMs 123-126 n'existent plus.

**Vérification** : `lab/bin/check 09 31`

<details><summary>Indice 1</summary>

`/nodes/<nœud>/status` donne la mémoire totale et utilisée du nœud ; `/cluster/resources` donne, pour chaque VM, `maxmem` (alloué) et `mem` (consommé). La mémoire « consommée » d'une VM vue de l'hôte n'est pas celle que voit l'invité : un invité Linux remplit son cache de pages, l'hôte ne le sait pas.
</details>

<details><summary>Indice 2</summary>

Avec trois nœuds identiques et une réserve N+1, la règle la plus simple : la somme de la mémoire allouée aux invités ne dépasse pas ce que **deux** nœuds peuvent porter. Le ballon ne rend de la mémoire que si l'hôte en manque (seuil d'occupation) et si l'invité a le pilote : il ne crée pas de capacité, il la déplace dans le temps.
</details>

<details><summary>Indice 3</summary>

`arc_summary` et `/proc/spl/kstat/zfs/arcstats` (`c_max`, `size`) donnent l'état du cache ZFS ; `/sys/module/zfs/parameters/zfs_arc_max` vaut 0 quand c'est la valeur par défaut du module qui s'applique. KSM : `/sys/kernel/mm/ksm/` (`run`, `pages_sharing`) et `/etc/ksmtuned.conf`.
</details>

**Pour aller plus loin** (facultatif) : la répartition dynamique du CRS (`crs: ha=dynamic`) et la façon dont elle compte la mémoire ; [Qemu/KVM — Memory](https://pve.proxmox.com/wiki/Qemu/KVM_Virtual_Machines#qm_memory), [ZFS — Limit ZFS Memory Usage](https://pve.proxmox.com/wiki/ZFS_on_Linux#sysadmin_zfs_limit_memory_usage), [Ceph — memory target](https://docs.ceph.com/en/latest/rados/configuration/bluestore-config-ref/#automatic-cache-sizing).

---

### M09-E32 — Questions de production : cluster de virtualisation  `Q` `★★★`

> **Ticket PLAT-1058** — *De : Karim Benali*
> Avant de te mettre d'astreinte sur `hv-par1`, je veux t'entendre sur ces questions. Argumente, chiffre quand c'est possible, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement en production d'un cluster Proxmox VE hyperconvergé : quorum, fencing, stockage, migration, sécurité, mises à jour.
- Relier les choix du module à des risques concrets.

**Prérequis** : paliers 1 et 2, M09-E24 à E31.
**Durée indicative** : 1 h 30.

**Questions**

1. Le cluster a trois nœuds et deux liens Corosync. Le commutateur du lien 0 tombe. Que se passe-t-il ? Puis celui du lien 1 tombe aussi, sur `hv02` seulement. Décris l'état de chaque nœud, des VMs HA de `hv02` et de ses VMs non HA, minute par minute.
2. QCM — `hv02` est mis en pause (`qm suspend 2092` sur `pve01`) pendant 3 minutes, alors qu'il porte une VM HA dont le disque est sur `ceph-vm`. Le CRM relance cette VM sur `hv01`. Puis `hv02` reprend. Avec `softdog` :
   a) rien de grave : `softdog` redémarre `hv02` avant qu'il exécute la moindre instruction ;
   b) `hv02` peut exécuter du code (et la VM des écritures) pendant un court instant avant que `softdog` ne le redémarre ;
   c) `hv02` ne redémarre jamais car le chien de garde a été réarmé pendant la pause ;
   d) Ceph refuse toute écriture de l'ancienne VM car le verrou exclusif RBD a été pris par la nouvelle.
   Justifie, et dis ce que change le chien de garde émulé, puis ce que changerait un vrai chien de garde matériel ou un fencing par IPMI.
3. Pourquoi la documentation de Proxmox VE recommande-t-elle un QDevice avec un nombre **pair** de nœuds, et le déconseille-t-elle avec un nombre impair ? Que se passerait-il à 5 nœuds avec QDevice si le QDevice et deux nœuds tombaient ?
4. `pool ceph-vm` : `size 3`, `min_size 2`, trois nœuds, deux OSD par nœud. Un nœud est en maintenance (30 min, `noout` posé), et un OSD d'un autre nœud tombe. Que deviennent les PG et les écritures des VMs ? Qu'aurait changé `min_size 1` ? Pourquoi ne faut-il jamais le faire en production ?
5. Une VM HA est sur `zfs-local` avec réplication toutes les 15 minutes vers les deux autres nœuds. Son nœud est coupé. Que fait la HA ? Quelle perte de données (RPO) au pire ? Que se passe-t-il quand le nœud revient, côté réplication ?
6. QCM — `max_restart 1`, `max_relocate 1`. Une VM HA échoue à démarrer sur son nœud (disque introuvable sur le nœud), puis sur le nœud suivant. État final :
   a) `started` sur le troisième nœud ;
   b) `error`, il faut une intervention ;
   c) `stopped` ;
   d) `fence`.
   Justifie, et donne la commande (ou la suite de commandes) pour la sortir de cet état une fois la cause corrigée.
7. Tu dois redémarrer les trois nœuds pour un nouveau noyau. Compare : redémarrages successifs avec mode maintenance, `shutdown_policy=migrate`, et `disarm-ha` (Proxmox VE 9.2). Dans quel cas utiliserais-tu chacun ?
8. Migration `type=insecure` sur un VLAN dédié non routé. Quels risques concrets, dans un hébergement HDS ? Qu'est-ce qui pourrait la rendre acceptable ?
9. La sonde `ms-verif-cluster` lit l'API par un jeton `PVEAuditor`. Un attaquant vole ce jeton. Que peut-il apprendre ? Que ne peut-il pas faire ? Qu'est-ce qui rend ce vol plus grave qu'il n'y paraît (indices : configuration des VMs, `cloud-init`, notes) ?
10. QCM — Le pare-feu de cluster est actif. Un administrateur ajoute une règle qui bloque UDP 5405-5412 entre `hv01` et les autres sur MGMT. Effet immédiat :
    a) perte de quorum de `hv01` et auto-fencing ;
    b) aucun, le lien 0 (COROSYNC) porte le trafic ;
    c) perte de quorum de tout le cluster ;
    d) aucun, les règles automatiques du cluster passent avant les règles de l'administrateur.
    Justifie. Que regarderais-tu pour savoir si la règle a vraiment un effet ?
11. Pourquoi un certificat de 30 jours renouvelé par `pve-daily-update` (seuil de 30 jours) pose-t-il problème, et comment l'as-tu réglé en E26 ? Qu'arrive-t-il aux sessions de l'interface et aux clients d'API quand le certificat de `pveproxy` change ?
12. Ceph : pendant la montée de version d'E28, un moniteur Tentacle et deux Squid. Est-ce supporté ? Combien de temps peux-tu rester dans cet état ? Quelle étape est le vrai point de non-retour, et pourquoi ?
13. La capacité N+1 d'E31 dit 10 Go pour les invités. Julien te montre que la somme de `mem` des VMs ne fait que 4 Go et demande pourquoi tu refuses ses 20 VMs. Réponds-lui en trois phrases.
14. `pmxcfs` passe en lecture seule sur un nœud. Liste quatre causes possibles et ce que tu regardes pour chacune. Pourquoi une écriture dans `/etc/pve` ne peut-elle pas réussir sur un nœud sans quorum ?
15. Tu reconstruis `hv03` (E29) mais tu oublies de nettoyer `/etc/pve/priv/known_hosts`. Que se passe-t-il, quand, et pour quelles opérations ?
16. Dans deux ans, MédiSphère passe à 6 nœuds sur deux salles de PAR1. Quelles décisions de ce module tiennent, lesquelles sont à revoir (quorum, liens Corosync, domaines de défaillance Ceph, HA, réseau de migration) ?

Les réponses argumentées sont dans le corrigé.

---

### M09-E33 — Fiche de changement : mise à jour du cluster  `RED` `★★`

> **Ticket CHG-1059** — *De : Claire Morel* — *Copie : Nadia Roussel*
> Proxmox VE publie une version mineure tous les quelques mois, et des mises à jour de sécurité chaque semaine. Aujourd'hui, chaque mise à jour du cluster est « faite par celui qui y pense ». Je veux une fiche de changement **type** que le comité de changement validera une fois, et un runbook RB-092 qui dit exactement comment on met à jour `hv-par1`, mineure comme majeure, sans interruption des VMs HA.

**Objectifs pédagogiques**
- Distinguer changement standard (pré-approuvé), normal et urgent, et ce que chacun exige.
- Écrire une procédure de mise à jour progressive d'un cluster, avec ses critères d'arrêt et son retour arrière réel (pas théorique).
- Relier la procédure aux outils du module (mode maintenance, `disarm-ha`, sonde, playbooks).

**Prérequis** : M09-E19 (mises à jour progressives), M09-E20 (évacuation), M09-E22 (RB-090), M09-E25 (sonde), M09-E28 (montée de Ceph), M06-E08 (fiche CHG-708, modèle).
**Durée indicative** : 2 h 30.

**Travail demandé**
Dans `plateforme/medisphere`, par MR relue (joue Nadia avec la grille du corrigé) :
1. `docs/virtualisation/changements/CHG-1059-mise-a-jour-hv-par1.md` : fiche de changement **standard** pour les mises à jour **mineures** et de sécurité de Proxmox VE et de Ceph sur `hv-par1` : objet, périmètre (ce qui en est **exclu** et devient un changement normal : version majeure de Proxmox VE ou de Ceph, noyau avec changement de pilote, changement de configuration), conditions préalables avec leur preuve, fenêtre, déroulé (renvoi à RB-092), critères de réussite, critères d'arrêt, retour arrière, communication, compte rendu.
2. `docs/virtualisation/runbooks/RB-092-mettre-a-jour-hv-par1.md` (nouveau : E19 a écrit le playbook `hv-mise-a-jour.yml`, pas de runbook ; RB-092 dit quand et comment le lancer, et quoi faire quand il s'arrête) : préalables (sauvegardes de configuration d'E29, santé, place disque, lecture des notes de version et des « known issues », dépôts), ordre des nœuds et raison, traitement d'un nœud (maintenance, `apt full-upgrade` ou équivalent, noyau et redémarrage, contrôles, fin de maintenance), cas Ceph (`noout`, ordre des démons, renvoi au playbook d'E28 pour une majeure), contrôle final, retour arrière (paquets épinglés, noyau précédent au démarrage, ce qui n'est **pas** réversible), et une section « montée majeure » qui renvoie au guide officiel de la version (`pve8to9` pour la précédente) et à un changement normal.
3. Une **répétition** sur `hv-par1` de la fiche (même s'il n'y a qu'une mise à jour de sécurité disponible), compte rendu rempli.

**Critères de réussite**
- [ ] La fiche CHG-1059 distingue clairement ce qui est pré-approuvé de ce qui ne l'est pas, avec des critères d'arrêt observables (commande et résultat attendu).
- [ ] RB-092 couvre un nœud de bout en bout, l'ordre des nœuds, Ceph, le retour arrière réel, et la montée majeure.
- [ ] Le compte rendu de la répétition est rempli (heures, versions avant/après, incidents).
- [ ] Les deux documents sont sur `main`.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Un changement **standard** est pré-approuvé parce qu'il est fréquent, à faible risque, et **toujours** fait de la même façon : sa fiche décrit une procédure, pas un événement. Tout ce qui sort de la procédure (un avertissement inattendu, une version majeure dans la liste des paquets) fait sortir du standard.
</details>

<details><summary>Indice 2</summary>

`apt list --upgradable` avant de commencer dit **ce qui va** changer ; `pveversion -v` avant et après le prouve. Le noyau précédent reste installé : `proxmox-boot-tool kernel` permet d'en épingler un. Une mise à jour de paquet Ceph ne redémarre pas les démons.
</details>

**Pour aller plus loin** (facultatif) : un dépôt miroir local (Proxmox Offline Mirror) pour mettre à jour à version figée et répétable ; [Package Repositories](https://pve.proxmox.com/wiki/Package_Repositories), [Upgrade from 8 to 9](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9), [Proxmox Offline Mirror](https://pom.proxmox.com/).

---

### M09-E34 — Remplacer un nœud en temps limité  `CHRONO` `★★★`

> **Ticket CHG-1060** — *De : Nadia Roussel*
> Le fournisseur annonce une défaillance imminente du disque système de `hv02` (alerte SMART simulée). Remplacement planifié ce soir : on retire `hv02`, on « change le matériel », on le réintègre. Je veux savoir si notre runbook RB-091 tient la route **sous la pression du temps**, et si un remplacement **planifié** se passe mieux qu'une perte.
> Le dossier est prêt. Chrono en main.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** runbooks (RB-090, RB-091, RB-092), ton code et la documentation officielle.
- Durée cible : **1 h 45** entre l'ouverture du dossier (T0) et le cluster revenu à l'état nominal (T5).
- Tout passe par le code et les pipelines ; un geste manuel est permis pour **constater** ou pour les commandes de cluster et de Ceph prévues par ton runbook ; tout autre geste est noté dans la feuille de temps avec sa raison.
- Les VMs HA ne doivent subir **aucune** interruption : c'est un remplacement planifié, pas une panne.

**Prérequis** : M09-E29 (RB-091 écrit et testé), M09-E20 (évacuation), M09-E24 (chien de garde).
**Durée** : 1 h 45 chronométrées + 30 minutes de retour d'expérience.

**Dossier** : [`ressources/M09-E34/dossier-chrono.md`](../ressources/M09-E34/dossier-chrono.md) (le besoin, les exigences, la feuille de temps). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] À T5, toutes les exigences du dossier sont satisfaites (vérification ci-dessous).
- [ ] La feuille de temps est remplie (T0 à T5), avec les gestes manuels et leur raison ; le temps total est inférieur à 1 h 45 (sinon, améliore RB-091 et ton outillage, et refais l'exercice).
- [ ] Le retour d'expérience (une demi-page) est rédigé et RB-091 mis à jour par MR (section « remplacement planifié »).

**Vérification** : `lab/bin/check 09 34` (à lancer à T5).

**Pour aller plus loin** (facultatif) : refais l'exercice sur `hv01` (qui porte souvent la VIP et le maître HA) et compare ; demande-toi ce qu'il faudrait pour que le remplacement se fasse sans toi, entièrement par un pipeline.
