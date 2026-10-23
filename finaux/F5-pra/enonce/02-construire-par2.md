# Final F5 — Phase 2 : Construire PAR2

Cinq scénarios, dans l'ordre où un site de repli se construit : d'abord la machine et le réseau, puis ce qui y arrive en continu (les données), puis ce qui permet de s'en servir (la confiance et les secrets), puis ce qui fait tourner les applications, et enfin le papier qui permet à quelqu'un d'autre de tout déclencher.

Prérequis de la phase : S01 et S02 publiés ; l'ADR-0350 décidé par Claire. La phase dure environ **35 heures** : planifie-la en fenêtres, et ne laisse jamais `hp01` dans un état intermédiaire non documenté d'une fenêtre à l'autre.

> ⚠️ **Attention** : à partir d'ici, tu touches `hp01`, qui porte **toutes les sauvegardes du lab**. Avant chaque séance : la dernière tâche de sauvegarde de la nuit est verte, aucune sauvegarde n'est en cours (`proxmox-backup-manager task list`), et tu sais comment atteindre `hp01` si son réseau ne répond plus (console de l'iLO, M11 ; SSH par le LAN maison). Jamais de redémarrage de `hp01` pendant une fenêtre de sauvegarde.

---

### F5-S03 — L'hyperviseur et le réseau de PAR2  `LIBRE` `★★★`

> **Ticket CHG-3503** — *De : Karim Benali* — *Copie : Claire Morel, Sophie Laurent*
> On transforme `hp01` en hyperviseur **sans** qu'il cesse un instant d'être notre serveur de sauvegardes. Je veux un go/no-go écrit avant d'installer quoi que ce soit, une sauvegarde de la configuration de PBS rangée ailleurs que sur `hp01`, et un retour arrière que tu as lu à voix haute. Ensuite : le réseau du site, le VPN de secours (le jour où PAR1 brûle, le VPN de PAR1 brûle avec), et les trois premières VMs — le poste d'administration, le DNS, le stockage objet. L'état OpenTofu de PAR2 vit à PAR2 : débrouille-toi avec l'œuf et la poule.

**Objectifs pédagogiques**
- Mener un changement risqué sur un hôte critique : go/no-go, sauvegarde préalable vérifiée, retour arrière écrit, contrôle après.
- Construire le réseau d'un site de repli (pont, routage inter-sites, NAT, VPN de secours) sans toucher au réseau existant de l'hôte.
- Résoudre l'amorçage d'un état OpenTofu hébergé sur une ressource qu'il décrit.

**Prérequis** : F5-S02 ; M00 (PBS, `wg0`, `wg1`, M00-E31 pour le temps) ; M05 (OpenTofu, état S3, SeaweedFS) ; M06 (PowerDNS primaire et secondaire, TSIG) ; M07 (pare-feu de la bordure en code).
**Durée indicative** : 8 h, en deux fenêtres au moins (hyperviseur ; réseau et VMs).

**Contexte technique**
- `hp01` : PBS 4.2 installé par son ISO (Debian 13, noyau Proxmox), nom d'hôte `pbs01`, datastore `ds-lab`, adresse PAR2 10.20.10.10 sur `vmbr1` (pont sans port) ; tunnel `wg0` vers la bordure (M00-E21). Proxmox VE 9.2 s'installe sur un Debian 13 par le paquet `proxmox-ve` (page officielle « Install Proxmox VE on Debian 13 Trixie ») ; Proxmox documente aussi l'installation de PBS **sur** un PVE, mais **pas** l'inverse (PVE ajouté à un PBS installé par ISO) : même base Debian, même noyau, chemin non décrit officiellement. C'est pour cela que ce changement commence par un go/no-go. Le nœud Proxmox garde le nom **`pbs01`** ; son API est `https://10.20.10.10:8006`.
- Proxmox VE exige que le nom de l'hôte se résolve vers une adresse non locale (`/etc/hosts`) : on retient **10.20.10.10**.
- La bordure (`gw01`, `wg0`) accepte déjà `10.20.0.0/16` depuis PAR2 (M00-E21) ; c'est son **filtrage** (`group_vars/role_routeur/pare_feu.yml`) qui décide de ce qui passe. `hp01` émet vers PAR1 depuis 10.20.10.10 (routes posées par `wg0.conf`).
- Les VMs de PAR2 se synchronisent sur leur passerelle (convention du PLAN) ; `hp01` prend aujourd'hui l'heure de `gw01` par `wg0` (M00-E31).
- Il n'y a aucune image dorée sur `hp01` ; les images dorées de `pve01` (M03, `gold`/`debian13`/`current`) peuvent être sauvegardées dans PBS comme n'importe quelle VM.
- Le module `vm-noeud` de `plateforme/tofu-modules` refuse les VMID hors 2000-2999 et les VMs de moins de 1 Gio, et écrit dans NetBox (à PAR1) ; il se télécharge depuis `git01` (à PAR1).
- La zone `par2.medisphere.internal` et la zone inverse `20.10.in-addr.arpa` sont sur le primaire `dns01` (écrites par l'API, M06) ; les transferts sont signés par la clé TSIG `axfr-par1`. La zone parente `medisphere.internal` est générée par le rôle `powerdns_auth`.
- Noms globaux à créer dans `medisphere.internal` : `mediagenda`, `medidoc`, `rdv` → CNAME (TTL **60 s**) vers les noms de PAR1 (`mediagenda.apps.par1.medisphere.internal`, `medidoc-recette.apps.par1.medisphere.internal`, `rdv.par1.medisphere.internal`).
- Valeurs figées : voir l'introduction (pool `par2`, étiquette `site-par2`, stockage `par2-vms`, `vmbr2`, table `inet par2`, `wg1` 10.255.3.1/24 UDP 51823, VMID et adresses). État OpenTofu : compartiment **`tofu-par2`** de `s3-02`, clé **`envs/par2/terraform.tfstate`**.
- Les checks attendent une archive de la configuration de PBS **`/root/f5/pbs-config-<AAAAMMJJ>.tar.gz`** sur `hp01` **et** une copie dans `~/f5/` de `adm01`.

**Travail demandé**

Objectifs :
1. **Go/no-go et retour arrière** : un runbook **RB-353** (`docs/pra/runbooks/RB-353-hyperviseur-par2.md`) qui fixe les critères de go (sauvegardes de la nuit vertes, vérification d'un instantané, espace disque, mémoire, accès de secours), la sauvegarde de la configuration de PBS et sa vérification, l'installation, les contrôles d'après, et un **retour arrière** complet (désinstallation de Proxmox VE en laissant PBS et son noyau intacts). La fiche CHG-3503 porte la décision.
2. **L'hyperviseur** : Proxmox VE 9.2 à côté de PBS 4.2 sur `hp01`, PBS toujours fonctionnel (interface, tâches de sauvegarde de la nuit suivante, vérification), stockage `par2-vms` avec une **limite de taille technique** qui protège `ds-lab`, pool `par2`, un compte d'automatisation dédié à jeton (privilèges minimaux, pool `par2` et ce dont il a besoin), une image dorée Debian 13 disponible sur `hp01`.
3. **Le réseau du site** : `vmbr2` et sa passerelle, routage de PAR2 INFRA vers PAR1 par `wg0` et retour, sortie Internet de PAR2 INFRA par la table `inet par2` (sans accès au LAN maison), flux ouverts sur la bordure par MR (et reportés dans la matrice des flux), temps servi à PAR2 INFRA par `hp01`, qui ne doit pas perdre l'heure si PAR1 disparaît.
4. **Le VPN de secours** `wg1` sur `hp01`, qui n'ouvre que PAR2, essayé depuis ton poste.
5. **Les trois premières VMs**, décrites dans `plateforme/infra` `envs/par2` (OpenTofu) et configurées par Ansible (groupe `site_par2`) : `adm02`, `dns03` (secondaire de toutes les zones internes, récurseur pour PAR2 INFRA), `s3-02` (SeaweedFS, compartiment `tofu-par2` versionné et son identité dédiée). `envs/par2` ne doit dépendre d'aucun service de PAR1 pour un `plan` ou un `apply` (ni NetBox, ni `git01`, ni `s3-01`).
6. **L'amorçage** de l'état : `envs/par2` finit avec son état dans `tofu-par2` de `s3-02`, et RB-353 explique comment on le reconstruit si `s3-02` est perdu.
7. **Les noms** : enregistrements de PAR2 publiés, noms globaux en CNAME à TTL 60 s, servis aussi par `dns03`.

Contraintes :
- Ni le datastore `ds-lab`, ni `/etc/proxmox-backup`, ni `vmbr0`, `vmbr1`, `wg0` de `hp01` ne sont modifiés (sauf ajout réversible et écrit dans la fiche) ; aucune tâche de sauvegarde n'est déplacée ou désactivée.
- Toute modification réseau de `hp01` est faite avec un accès de secours **vérifié avant** (console iLO ou SSH par le LAN) et un retour arrière testé.
- Aucune VM de PAR2 hors du pool `par2` ; aucun secret dans Git.

**Critères de réussite**
- [ ] RB-353 et la fiche CHG-3503 (décision et contrôles d'après) sont publiés ; une archive `pbs-config-<date>.tar.gz` existe sur `hp01` (`/root/f5/`) et dans `~/f5/` de `adm01`.
- [ ] `hp01` répond comme hyperviseur Proxmox VE 9.2 **et** comme PBS : `ds-lab` est listé, la dernière sauvegarde planifiée après l'installation a réussi.
- [ ] Le stockage `par2-vms` existe avec une limite de taille qui ne laisse pas une VM remplir le système de fichiers de `ds-lab` ; le pool `par2` existe.
- [ ] `vmbr2` porte 10.20.20.1/24 ; la table `inet par2` existe et traduit la sortie de PAR2 INFRA ; `wg1` écoute en UDP 51823 avec 10.255.3.1/24.
- [ ] `adm02`, `dns03`, `s3-02` tournent dans le pool `par2` avec l'étiquette `site-par2`, et `adm01` s'y connecte en SSH.
- [ ] `dns03` sert les zones `medisphere.internal`, `par1.medisphere.internal`, `par2.medisphere.internal` avec le même numéro de série que `dns01` ; `mediagenda.medisphere.internal` est un CNAME de TTL 60 s.
- [ ] L'état de `envs/par2` est dans `s3://tofu-par2/envs/par2/terraform.tfstate` de `s3-02`, et un `tofu plan` lancé depuis `adm02` ne montre aucun changement.
- [ ] `hp01` sert l'heure à PAR2 INFRA et garde une source de temps qui ne passe pas par PAR1.

**Vérification** : `lab/bin/check F5 3`

<details><summary>Indice 1</summary>

Le go/no-go se prépare en **lecture** : quels paquets PVE et PBS partagent déjà, quel noyau tourne, quels dépôts sont configurés, quels services écoutent sur quels ports (8006 et 8007 ne se gênent pas, mais vérifie). APT sait **simuler** une installation : la simulation dit ce qui serait installé, mis à jour **et retiré**. Un paquet de PBS dans la liste des retraits est un no-go.
</details>

<details><summary>Indice 2</summary>

Un état OpenTofu ne peut pas vivre sur une machine qu'il doit créer. Deux temps : un état provisoire pour créer ce qui le portera, puis une migration de l'état (OpenTofu sait migrer un état d'un *backend* à l'autre à l'initialisation). Et le jour où `s3-02` est perdu : que contient un état, et qu'est-ce qui permet de le reconstruire (`import`) ?
</details>

<details><summary>Indice 3</summary>

Depuis Proxmox VE 8, utiliser un pont pour une carte de VM demande un droit sur ce pont dans l'arborescence SDN, même sans SDN configuré : cherche dans la documentation des permissions (`pveum`) quel chemin protège un pont « local ». Pour la limite de `par2-vms`, compare ce que permettent un sous-volume ZFS avec quota, un volume logique séparé, ou l'option de PVE qui refuse de créer un disque au-delà d'un seuil — et ce qui protège **vraiment** contre un disque qui grossit après sa création.
</details>

**Pour aller plus loin** (facultatif) : un second jeton Proxmox en lecture pour la supervision de PAR2 (pve-exporter de `mon01`, puis d'`adm02` en PRA) ; l'inventaire des VMs de PAR2 dans NetBox par la synchronisation Proxmox → NetBox du M06 (NetBox reste à PAR1 : ce n'est que de la documentation).

---

### F5-S04 — Les données partent à PAR2  `LIBRE` `★★★`

> **Ticket PLAT-3504** — *De : Julien Petit* — *Copie : Karim Benali, Sophie Laurent*
> Pour qu'on reprenne à PAR2, il faut que tout ce qui fait MédiAgenda y soit déjà : les journaux de la base, les sauvegardes, les documents de MédiDoc, le code, les images. Et je veux savoir **de combien** PAR2 est en retard sur PAR1, flux par flux, en permanence — pas le jour du sinistre. Sophie insiste sur un point : si quelqu'un efface quelque chose à PAR1, qu'est-ce qui se passe à PAR2 ? « On a une copie » ne doit plus jamais vouloir dire « on a une sauvegarde ».

**Objectifs pédagogiques**
- Mettre en place des réplications continues de nature différente (objets, dépôts Git, images signées) et leurs garde-fous.
- Mesurer et superviser le retard de réplication, le relier au RPO.
- Distinguer copie répliquée et sauvegarde, et en tirer des règles écrites.

**Prérequis** : F5-S03 ; M05 (SeaweedFS de `s3-01`), M08 et M16 (RGW, `medidoc-documents`), M13 et M19 (Harbor, Cosign, runner protégé), M25 (signature par `transit`), M21 (règles d'alerte, témoin de `mon01`).
**Durée indicative** : 7 h.

**Contexte technique**
- **Objets** : `s3-01` porte les sauvegardes et archives (`cnpg-k8s-par1`, `velero-k8s-par1`, `etcd-k8s-par1`, `openbao-instantanes`, `argocd-sauvegardes`, `identite-sauvegardes`, `mariadb-legacy-rdv`, `tofu-state`…) et d'autres compartiments sans utilité pour une reprise (`ci-cache`…). Sur `s3-01`, `weed server` fait tourner master, volume, filer et passerelle S3 dans un seul processus ; **seule la passerelle S3 écoute sur le réseau** (master, volume et filer n'écoutent qu'en `127.0.0.1`, rôle `seaweedfs` du M05).
- `weed filer.sync` (wiki SeaweedFS, « Filer Active Active cross cluster continuous synchronization ») : options `-a`, `-b`, `-a.path`, `-b.path`, `-isActivePassive`, `-a.filerProxy`, `-b.filerProxy`, `-a.security`, `-b.security`, `-a.debug`, `-b.debug`. Le processus doit joindre les filers **et** les serveurs de volumes des deux côtés, sauf avec `-a.filerProxy` / `-b.filerProxy` ; il reprend à son dernier point de contrôle après un arrêt. Les identités S3 (`s3.json`) ne sont **pas** des données du filer : elles ne se répliquent pas.
- **Documents de MédiDoc** : compartiment `medidoc-documents` du RGW de `ceph-par1` (`https://rgw.par1.medisphere.internal`, compte `medidoc-app`) ; il n'existe pas de RGW à PAR2.
- **Code** : GitLab CE `git01` ; les *push mirrors* (SSH ou HTTPS) sont disponibles dans l'édition gratuite ; miroirs attendus sur `adm02` dans `/srv/miroirs/<groupe>/<projet>.git` (dépôts nus), compte `miroir`.
- **Images** : Harbor `registry.par1.medisphere.internal`, projets `medisphere` (images signées, Cosign 3, clé `transit/cosign-medisphere`, clé publique `docs/registre/cosign.pub`), `charts`, caches publics ; `reg02` (VMID 1053, 10.20.20.18) est un `registry:3` ; le runner **`k8s-par1-protege`** (jobs `ref_protected`, espace `ci-jobs-protege`) est le seul à manipuler la clé de signature et à promouvoir.
- RPO de MédiAgenda : 15 min (S01, si tu ne l'as pas changé) ; la base de production archive sous le nom de serveur **`mediagenda-db-prod-day0`** dans `cnpg-k8s-par1`.
- Les checks attendent : un document **`docs/pra/mesures/retard-replication.md`** ; une unité systemd de `filer.sync` active sur `s3-02` (nom libre, contenant `filer-sync`) ; une minuterie systemd de copie MédiDoc active sur `s3-02` (nom libre, contenant `medidoc`) ; dans `reg02`, le dépôt `medisphere/mediagenda-api` avec le *digest* déployé en production et sa signature.

**Travail demandé**

Objectifs :
1. **Objets** : les compartiments **utiles à une reprise** de `s3-01` répliqués en continu vers `s3-02` par `filer.sync` en mode actif-passif, lancé sur `s3-02`, avec un chemin réseau et une protection des échanges que tu justifies ; les identités S3 de PAR2 (lecture des copies, écriture des futures archives de PAR2) déclarées sur `s3-02`.
2. **Documents** : `medidoc-documents` copié du RGW vers `s3-02` par une minuterie (`rclone`), avec une identité en **lecture seule** côté RGW.
3. **Code** : les projets nécessaires à une reconstruction et à un déploiement à PAR2 (à toi d'en dresser la liste, à partir de S02) poussés en miroir vers `adm02` ; le compte `miroir` limité à Git ; une clé de **lecture seule** pour les consommateurs de PAR2 (Argo CD de `k8s-par2`, S06).
4. **Images** : les images **déployées** (applications, et ce dont `k8s-par2` aura besoin) copiées vers `reg02` **avec leurs signatures** par un job planifié du runner protégé ; aucune image non signée ou dont la signature ne se vérifie pas n'est copiée.
5. **Retard** : pour chaque flux, une mesure du retard (âge du dernier WAL copié, horodatage du dernier commit miroir, âge de la dernière copie MédiDoc, dernière copie d'images) **exposée** et **alertée** quand elle dépasse l'objectif ; les valeurs mesurées sur au moins 24 h dans `docs/pra/mesures/retard-replication.md`.
6. **Copie ≠ sauvegarde** : démontre sur un compartiment d'essai ce que devient à PAR2 un objet supprimé à PAR1, et écris dans RB-354 (`docs/pra/runbooks/RB-354-replication-par2.md`) ce qui protège réellement contre une suppression (et ce qu'on fait des réplications le jour d'un PRA, puis du retour).

Contraintes :
- Pas de copie de données sans nécessité (minimisation : HDS, RGPD) : la liste des compartiments et des projets copiés est justifiée.
- Aucune identité de PAR2 ne peut **écrire** ou **supprimer** dans un compartiment de PAR1.
- La copie d'images ne contourne pas la vérification des signatures.
- Changements de PAR1 (rôle `seaweedfs` de `s3-01`, bordure, *push mirrors*, CI) par MR et fiche CHG-3504.

**Critères de réussite**
- [ ] Le WAL le plus récent de `mediagenda-db-prod-day0` présent dans `cnpg-k8s-par1` de `s3-02` a moins de 15 min (ou ton RPO).
- [ ] L'unité de `filer.sync` est active sur `s3-02` ; `s3-02` contient les compartiments de sauvegarde retenus et pas `ci-cache`.
- [ ] `medidoc-documents` existe sur `s3-02`, alimenté par une minuterie active dont la dernière exécution a réussi.
- [ ] Les miroirs de `adm02` existent pour les projets retenus, et leur branche `main` est celle de GitLab (ou en retard de moins d'une heure).
- [ ] `reg02` sert l'image de MédiAgenda déployée en production (même *digest*) et sa signature Cosign se vérifie avec `cosign.pub`.
- [ ] `retard-replication.md` et RB-354 sont publiés ; une alerte existe sur le retard de chaque flux.

**Vérification** : `lab/bin/check F5 4`

<details><summary>Indice 1</summary>

Le filer de `s3-01` n'écoute qu'en local : pour que `s3-02` le joigne, il faut soit le faire écouter sur son adresse (et alors filtrer, et chiffrer ou authentifier le gRPC du filer : regarde le fichier `security.toml` de SeaweedFS), soit… autre chose. Avec `-a.filerProxy`, seuls le port HTTP du filer et son port gRPC (HTTP + 10000) sont nécessaires. Un `filer.sync` par compartiment (une unité systemd « modèle », un chemin de départ par compartiment) se surveille et se relance plus finement qu'un seul processus pour tout.
</details>

<details><summary>Indice 2</summary>

`cosign copy` copie une image **et** ce qui lui est attaché (signatures, attestations, SBOM) ; vérifie que ta version de Cosign copie aussi les référents OCI (SBOM attachés au M13). Copier « tout Harbor » est inutile et lent : la liste des images à copier se lit dans ce qui est **déployé** (manifestes rendus des overlays de prod, valeurs des charts de la couche de base).
</details>

<details><summary>Indice 3</summary>

Le retard d'un flux se mesure **du côté de la destination** : l'âge du dernier objet arrivé, pas le statut du processus qui copie (il peut tourner et ne rien copier). Le *textfile collector* de node_exporter (M21, M26) sur `s3-02` et `adm02`, collecté par le témoin de `mon01`, suffit — tant que PAR1 existe. Et pendant un PRA ?
</details>

**Pour aller plus loin** (facultatif) : verrouillage d'objets (*Object Lock*) ou versionnage protégé sur les compartiments de sauvegarde de `s3-01` (le F6 y reviendra) ; synchronisation des sauvegardes PBS elles-mêmes vers un second datastore (tâche *sync* de PBS) ; comparaison des empreintes d'un échantillon d'objets entre `s3-01` et `s3-02` (détection de corruption silencieuse).

---

### F5-S05 — La confiance et les secrets hors de PAR1  `LIBRE` `★★★★`

> **Ticket PLAT-3505** — *De : Sophie Laurent* — *Copie : Claire Morel, Karim Benali*
> Le jour du sinistre, sans `ca01` et sans OpenBao, PAR2 ne peut ni présenter un certificat valide ni lire un secret. Je veux trois choses. Une autorité intermédiaire propre à PAR2, signée en cérémonie par notre racine, dont la clé n'a jamais existé à PAR1. Un coffre de secours qui sait redevenir notre coffre — et la preuve, en répétition, qu'on sait restaurer `kms01` à PAR2 **sans jamais toucher** à celui de PAR1. Et une « enveloppe de reprise » : la liste de tout ce qu'il faut avoir en main pour reprendre, qui la garde, où, comment on vérifie qu'elle est complète. Pas un secret dans Git, pas même dans le document qui décrit l'enveloppe.

**Objectifs pédagogiques**
- Étendre une PKI hors ligne à un second site par une cérémonie tracée, avec des contraintes adaptées.
- Restaurer un coffre auto-descellé et son service de descellement dans un bac à sable isolé, et mesurer l'opération.
- Organiser le séquestre des secrets de reprise (bris de glace) sans les écrire.

**Prérequis** : F5-S03 (réseau, `adm02`), F5-S04 (`openbao-instantanes` copié sur `s3-02`) ; M06 (racine hors ligne, `ceremonie-pki.sh`), M24 (bris de glace, RB-240), M25 (OpenBao, `kms01`, Shamir, instantanés, RB-252, restauration éprouvée sur `bao-restauration`).
**Durée indicative** : 7 h.

**Contexte technique**
- Racine « MédiSphère Root CA » : `~/pki-racine` sur `adm01`, signée par `ceremonie-pki.sh signer FICHIER.csr` (variable `DUREE_INTERMEDIAIRE`, 5 ans par défaut, `pathlen 0`) ; procès-verbal des cérémonies `docs/securite/identite/ceremonie-ca.md`.
- Nom de l'autorité : **« MédiSphère PAR2 Intermediate CA »**. Elle sera servie dans `k8s-par2` par un `ClusterIssuer` de type CA (S06) : sa clé vivra dans un Secret de `k8s-par2`. Les checks attendent son certificat (public) dans **`docs/pra/pki/medisphere-par2-intermediate-ca.crt`** de `plateforme/medisphere`.
- `kms01` : VMID 1024, 10.10.20.24, OpenBao mononœud, scellé par Shamir (5 parts, seuil 3), clé de transit `autodescellement-par1` ; seule sauvegarde : PBS (`par1/secrets`). Son certificat TLS (ACME, 30 jours) porte le nom `kms01.par1.medisphere.internal`. `vault01-03` se descellent avec un jeton **périodique de 168 h** sur `kms01` (politique `kms-autodescellement`).
- Copie restaurée à PAR2 : VMID **3501**, adresse **10.20.20.24**, sur `hp01`. `bao-par2` : VMID 1055, 10.20.20.21, **arrêté** hors PRA, rôle Ansible `openbao` (variables du M25 : `openbao_seal_transit_adresse`, `openbao_seal_transit_nom_tls`, `openbao_raft_rejoindre`…), instantanés de la grappe dans `openbao-instantanes` (copie sur `s3-02`), chiffrés par la clé `age` de restauration du M25.
- Les sauvegardes PBS des VMs de PAR1 sont chiffrées côté client : restaurer sur `hp01` exige la **clé de chiffrement** de PBS.
- Enveloppe de reprise, contenu minimal attendu par Claire : parts Shamir de `kms01`, clé de chiffrement PBS, phrase Kopia de Velero, comptes de bris de glace (dont `root@pam` de `hp01`), `admin.conf` de `k8s-par2` — complète-la à partir de S02.

**Travail demandé**

Objectifs :
1. **L'autorité de PAR2** : une CSR produite **à PAR2**, signée en cérémonie (deux personnes, procès-verbal), durée et contraintes justifiées ; la clé rangée pour pouvoir reconstruire `k8s-par2` depuis le code **sans PAR1** ; le certificat publié.
2. **Le coffre de secours** : `bao-par2` décrit dans `envs/par2` et configuré par Ansible pour devenir, en PRA, une copie du coffre de production restaurée depuis le dernier instantané et descellée par `kms01` restauré ; laissé **arrêté** en veille.
3. **La répétition** : restaure `kms01` depuis PBS en VMID 3501, adresse 10.20.20.24, **dans un bac à sable** (aucun chemin réseau vers PAR1, ni vers `s3-01`, ni vers `ca01`), descelle-le avec les parts de l'enveloppe, démarre `bao-par2`, restaure-y l'instantané, vérifie la lecture d'un secret ancien et l'absence d'un secret écrit après l'instantané (RPO du coffre), puis remets tout en veille : 3501 détruite, `bao-par2` arrêté, jetons d'essai révoqués. Mesure chaque étape.
4. **RB-355** (`docs/pra/runbooks/RB-355-coffre-de-secours.md`) : la procédure de la répétition et celle du PRA (ce qui change le jour J), avec les durées mesurées.
5. **L'enveloppe** : `docs/pra/enveloppe.md` — pour chaque élément, sa nature, son emplacement physique ou logique, ses gardiens, sa date de dernière vérification, la procédure de vérification **sans l'ouvrir** quand c'est possible, et ce qu'on fait s'il manque ; plus la liste de ce qui doit en sortir et y rentrer à chaque rotation.

Contraintes :
- ⚠️ Le `kms01` de PAR1 (1024) n'est **jamais** arrêté, modifié, restauré « en place » ni descellé de nouveau ; la copie 3501 n'a **jamais** de chemin réseau vers PAR1 ; elle n'est démarrée qu'avec sa carte réseau coupée tant que son adresse n'a pas changé.
- La clé de l'autorité de PAR2 n'apparaît jamais sur une machine de PAR1, ni en clair dans Git.
- Aucun secret dans `enveloppe.md` ni dans le procès-verbal (empreintes, numéros de série et identifiants de gardiens seulement).

**Critères de réussite**
- [ ] `docs/pra/pki/medisphere-par2-intermediate-ca.crt` est sur `main` : CN « MédiSphère PAR2 Intermediate CA », signé par la racine MédiSphère, autorité de certification avec `pathlen` 0, valide aujourd'hui.
- [ ] Le procès-verbal de la cérémonie est publié (empreinte du certificat, participants).
- [ ] `bao-par2` (1055) existe dans le pool `par2` et est **arrêté** ; la VM 3501 n'existe plus.
- [ ] `kms01` (1024) tourne sur `pve01` et répond « descellé ».
- [ ] `enveloppe.md` est publié, couvre au moins les éléments de Claire, ne contient aucun secret ; RB-355 et le compte rendu de répétition (`docs/pra/mesures/repetition-coffre-<AAAA-MM-JJ>.md`) donnent les durées et le RPO mesuré du coffre.

**Vérification** : `lab/bin/check F5 5`

<details><summary>Indice 1</summary>

Avant de démarrer 3501, regarde ce que la sauvegarde contient **comme comportement** : adresse fixe 10.10.20.24 et passerelle 10.10.20.1 (cloud-init), minuterie d'instantané vers `s3-01`, renouvellement ACME vers `ca01`, journaux vers Loki. Chacun de ces comportements, sur un réseau qui atteindrait PAR1, ferait de la copie une seconde production. Le premier démarrage se fait carte coupée ; on change l'adresse ; on rebranche dans un réseau qui ne mène nulle part ailleurs que là où on veut.
</details>

<details><summary>Indice 2</summary>

Le descellement automatique de `bao-par2` dépend de trois choses restaurées ensemble : la même clé de transit (elle est dans `kms01`), un jeton valide sur `kms01` (que contient l'instantané de `kms01`, et que vaut un jeton périodique dont le dernier renouvellement date de la sauvegarde ?), et un certificat TLS de `kms01` encore valide au nom attendu par `bao-par2`. RB-252 (M25) et les constats du banc `bao-restauration` répondent à une partie de ces questions.
</details>

<details><summary>Indice 3</summary>

Pour la PKI, compare deux emplacements pour la clé de l'autorité de PAR2 : un Secret de `k8s-par2` créé une fois à la main, ou un fichier chiffré dans un dépôt (Ansible Vault « critique » de `plateforme/ansible`, miroité sur `adm02`) recréé par l'amorçage. Puis demande-toi quel mot de passe déchiffre l'Ansible Vault « critique » quand OpenBao n'existe plus.
</details>

**Pour aller plus loin** (facultatif) : contraintes de noms (*name constraints*) sur l'autorité de PAR2 (seulement `apps.par2.medisphere.internal`, `par2.medisphere.internal` et les noms globaux) et leur effet sur les clients ; un *Seal* de secours sans `kms01` (migration du seal de `bao-par2` vers Shamir, comme au M25 dans l'autre sens) et ce que cela change à la sécurité ; vérification semestrielle de l'enveloppe en double contrôle.

---

### F5-S06 — Le cluster de secours `k8s-par2`  `LIBRE` `★★★★`

> **Ticket PLAT-3506** — *De : Julien Petit* — *Copie : Karim Benali, Nadia Roussel*
> Le jour J, je ne veux pas reconstruire un cluster : je veux en trouver un, à jour, qui n'attend qu'un signal. Même code que `k8s-par1` — si on a deux façons de faire un cluster, on en a une de trop. La base de production doit y être déjà, en réplica, prête à être promue proprement et à **revenir** proprement. Les applications y sont déclarées mais éteintes. Et pour que l'exercice prouve quelque chose : chaque réponse doit dire de quel site elle vient, et un témoin doit écrire chaque minute un rendez-vous dont on retrouvera (ou pas) la trace à PAR2.

**Objectifs pédagogiques**
- Construire un cluster de secours à partir du même code que le cluster principal, en isolant les différences de site.
- Mettre en place une topologie distribuée CloudNativePG (réplica continu, bascule et retour contrôlés par jetons).
- Concevoir l'état de veille d'un site tiède : objets présents, charges à zéro, secrets disponibles, livraison par miroirs.

**Prérequis** : F5-S03 à S05 ; M14 (kubeadm, rôles Ansible), M15 (Cilium, LB IPAM, Gateway API), M16 et M27 (CloudNativePG, plugin Barman Cloud, réplica de secours), M17 (Helmfile), M20 (Argo CD), M25 (ESO), F1 (amorçage, ordre de la couche de base).
**Durée indicative** : 10 h.

**Contexte technique**
- `k8s-par2-n01` : VMID 1054, 10.20.20.50, **5 Go** de mémoire, nœud unique (plan de contrôle **sans** *taint*). Point d'accès de l'API : `k8s-api.par2.medisphere.internal:6443` (pas de VIP). Cilium 1.20 avec remplacement de kube-proxy (comme `k8s-par1`), **L2 announcements** au lieu du BGP (`CiliumL2AnnouncementPolicy`, API `cilium.io/v2alpha1`, option Helm `l2announcements.enabled`) ; pool LB IPAM **`lb-par2`** 10.20.20.200-239 ; Gateway **`gw-par2`** (espace `passerelles`) en 10.20.20.200 pour `*.apps.par2.medisphere.internal`.
- Pas de Ceph à PAR2 : un stockage **local** au nœud. Pas d'observabilité complète (S01).
- Images : `reg02` pour les images MédiSphère (les références restent `registry.par1.medisphere.internal/…` dans les manifestes) ; Internet par `hp01` pour le reste.
- Base : `mediagenda-prod/mediagenda-db` (PAR1) archive dans `s3://cnpg-k8s-par1/` sous **`mediagenda-db-prod-day0`** (`ObjectStore` `cnpg-s3`) ; ce compartiment est copié sur `s3-02` (S04). Le `Cluster` de PAR2 s'appelle **`mediagenda-db-par2`** (espace `mediagenda-prod` de `k8s-par2`) et archive dans le compartiment **`cnpg-k8s-par2`** de `s3-02`. CloudNativePG 1.30, topologie distribuée : `spec.replica.primary`, `spec.replica.source`, `externalClusters` par le plugin `barman-cloud.cloudnative-pg.io` ; documentation : <https://cloudnative-pg.io/docs/1.30/replica_cluster>.
- Applications : MédiAgenda (`mediagenda/deploiement`, Rollout `mediagenda`, HPA en prod), MédiDoc (`medidoc-recette`), Legacy-RDV (`legacy/deploiement`, `legacy-rdv-prod`), MédiNotif (`medinotif/deploiement`, RabbitMQ). Les manifestes de MédiAgenda joignent la base par les Services `mediagenda-db-pooler-rw` et `mediagenda-db-rw`.
- Repère de site : en-tête **`X-MediSphere-Site: par1`** / **`par2`**, filtre `ResponseHeaderModifier` des HTTPRoute (Gateway API v1.6, canal standard).
- Témoin de RPO : CronJob **`temoin-rpo`** dans `mediagenda-prod` des deux clusters, **suspendu** sur le site passif ; chaque minute, `POST /api/v1/rendez-vous` avec `praticien: "PRA-TEMOIN"` et l'horodatage UTC de l'écriture (ISO 8601) dans `motif`. L'API refuse deux rendez-vous d'un même praticien à la même heure (409) : choisis `debut` en conséquence, loin de toute vraie plage de rendez-vous.
- Sonde utilisateur **`ms-sonde-pra`** sur `adm02` : unité systemd et minuterie **toutes les 15 s**, qui interroge les trois noms globaux et écrit `/var/lib/ms-sonde-pra/mesures.csv`, une ligne par cible : `horodatage_utc,cible,code_http,latence_ms,site` (`site` = valeur de `X-MediSphere-Site`). Les checks de l'exercice (S09 à S12) lisent ce fichier : le format est figé.
- Livraison à PAR2 : Argo CD de `k8s-par2` installé par Helmfile (environnement de site), lisant `ssh://miroir@adm02.par2.medisphere.internal/srv/miroirs/<groupe>/<projet>.git`.
- Les checks de `k8s-par2` utilisent un compte de service `wb-checks` (lecture, jamais les Secrets) dont le kubeconfig est **`~/.config/workbook/k8s-par2-checks.kubeconfig`** (variable `WB_F5_KUBECONFIG_PAR2`).

**Travail demandé**

Objectifs :
1. **Le cluster** : `k8s-par2-n01` décrit dans `envs/par2`, préparé par les **mêmes rôles Ansible** que `k8s-par1` (groupe `k8s_par2` dans `site_par2`), initialisé par kubeadm ; les différences avec `k8s-par1` rassemblées dans des fichiers de site (inventaire, valeurs Helmfile de l'environnement `par2`, composants propres au site), et listées dans RB-356 (`docs/pra/runbooks/RB-356-cluster-de-secours.md`).
2. **La couche de base** par Helmfile : réseau (L2, `lb-par2`, `gw-par2`), certificats (`ClusterIssuer` de l'autorité de PAR2, certificat de `gw-par2` couvrant les noms de PAR2 **et** les noms globaux), stockage local, CloudNativePG et son plugin, ESO, Argo CD.
3. **La base de secours** : `mediagenda-db-par2` en réplica continu de `mediagenda-db`, la base de production de PAR1 déclarée dans la même topologie (changement de prod : fiche CHG-3506), et la preuve que le réplica suit (retard mesuré). Aucune connexion réseau directe entre les deux clusters n'est requise.
4. **Les secrets** : les Secrets dont les applications de PAR2 ont besoin existent à PAR2 **en veille** ; écris (RB-356) d'où ils viennent en veille et en PRA, et ce qui change le jour J (dont les identifiants dynamiques de la base).
5. **Les applications** : MédiAgenda, MédiDoc, Legacy-RDV et MédiNotif déclarées à PAR2 par Argo CD depuis les miroirs, **à zéro réplica** (ou non synchronisées, si tu le justifies), avec les noms globaux et ceux de PAR2 dans leurs routes.
6. **Le repère, la sonde et le témoin** : l'en-tête de site sur les routes des **deux** sites ; la sonde `ms-sonde-pra` sur `adm02` (par Ansible) ; le CronJob `temoin-rpo` actif à PAR1, suspendu à PAR2 ; la requête qui donne le RPO (dernier témoin à PAR1 contre dernier témoin retrouvé à PAR2) écrite dans RB-356 et essayée.

Contraintes :
- Même code : aucun fichier copié-collé de `k8s-par1` pour en faire une variante ; une différence = une valeur ou un fichier de site.
- La production de PAR1 ne subit aucune interruption (sonde de continuité du F4 si tu l'as) ; le changement de topologie de `mediagenda-db` est préparé, relu, et a un retour arrière.
- Aucune charge applicative ne tourne à PAR2 en veille ; la mémoire du nœud reste sous 5 Go.

**Critères de réussite**
- [ ] `k8s-par2` a un nœud `Ready` (1.36), Cilium avec une `CiliumL2AnnouncementPolicy` et le pool `lb-par2` (10.20.20.200-239) ; `gw-par2` est programmée en 10.20.20.200.
- [ ] Le certificat présenté par `gw-par2` est émis par « MédiSphère PAR2 Intermediate CA » et couvre `mediagenda.medisphere.internal`.
- [ ] `mediagenda-db-par2` est sain, en réplica, avec `replica.primary: mediagenda-db` ; à PAR1, `mediagenda-db` déclare la même topologie.
- [ ] Les HTTPRoute de MédiAgenda posent `X-MediSphere-Site` (`par2` à PAR2) ; une requête à `mediagenda.apps.par1.medisphere.internal` renvoie `X-MediSphere-Site: par1`.
- [ ] À PAR2, aucun pod applicatif ne tourne dans `mediagenda-prod`, `medidoc-recette`, `legacy-rdv-prod`, `medinotif-prod` (hors base de secours) ; les ExternalSecrets de `mediagenda-prod` sont synchronisés.
- [ ] La sonde `ms-sonde-pra` tourne sur `adm02` : sa dernière mesure de `mediagenda.medisphere.internal` a moins de 2 min, en 2xx, `site` = `par1`.
- [ ] `temoin-rpo` est suspendu à PAR2 ; à PAR1, il est actif et sa dernière exécution réussie a moins de 5 min.
- [ ] Argo CD de `k8s-par2` ne connaît que des dépôts `ssh://miroir@adm02.par2.medisphere.internal/…` ; RB-356 est publié.

**Vérification** : `lab/bin/check F5 6`

<details><summary>Indice 1</summary>

Dans la topologie distribuée, **chaque** cluster connaît les **deux** archives dans ses `externalClusters`, sous les noms des clusters ; `replica.primary` dit qui est primaire (le même nom des deux côtés), `replica.source` dit d'où chacun lirait s'il était réplica. Côté PAR1, l'archive de PAR2 n'est lue qu'après une rétrogradation : déclare-la, ne l'ouvre pas encore au réseau. Lis aussi ce que la documentation dit d'une promotion **sans** jeton.
</details>

<details><summary>Indice 2</summary>

« Zéro réplica » n'est pas trivial avec un HPA (`minReplicas` ≥ 1) ni avec un Rollout dont l'overlay de prod fixe des bornes : un fichier de site peut retirer un *component* ou remplacer une valeur. Et un nom de Service ne se renomme pas : si la base s'appelle autrement à PAR2, un Service de plus portant l'ancien nom évite de toucher à la configuration de l'application.
</details>

<details><summary>Indice 3</summary>

Pour les secrets en veille : ESO garde le Secret qu'il a créé quand sa source ne répond plus (il n'efface pas sur erreur). La source de veille peut donc être différente de celle du PRA. Pour les identifiants **dynamiques** de la base (OpenBao, moteur `db-mediagenda`), demande-toi vers quelle adresse de PostgreSQL pointe la connexion du moteur dans l'instantané restauré à PAR2.
</details>

**Pour aller plus loin** (facultatif) : réplication en flux (*streaming*) en plus de l'archive par un Service exposé à travers `wg0` (RPO de quelques secondes au lieu de quelques minutes) et ce qu'elle coûte en sécurité ; une supervision minimale de PAR2 (Prometheus mononœud sur `adm02` qui sonde `gw-par2` et lit le retard du réplica).

---

### F5-S07 — Le runbook de bascule et la cellule de crise  `RED` `★★`

> **Ticket PLAT-3507** — *De : Nadia Roussel* — *Copie : Claire Morel, Julien Petit, Sophie Laurent*
> Le jour où ça arrive vraiment, ce ne sera peut-être pas toi qui seras là. Il me faut un runbook de bascule que je peux suivre à deux, une main sur le clavier, l'autre sur le téléphone ; et l'organisation de la cellule de crise : qui décide de déclencher, qui fait quoi, qui parle aux cabinets et à la direction, ce qu'on écrit et où, comment on sait que c'est fini. Claire veut un critère de déclenchement qu'on ne discute pas à chaud. Sophie veut que chaque étape laisse une preuve horodatée.

**Objectifs pédagogiques**
- Écrire un runbook de bascule exécutable sous stress : vagues, conditions de passage, points de non-retour, preuves.
- Organiser une cellule de crise : rôles, décisions, communication, main courante.
- Préparer la mesure d'un exercice (RTO, RPO) dès l'écriture.

**Prérequis** : F5-S01 à S06 ; gestion d'incident de F3 (main courante, messages d'état) si faite ; RB-240 (bris de glace).
**Durée indicative** : 3 h.

**Contexte technique**
- Le sinistre de l'exercice sera **INC-6109** ; la main courante de l'exercice : `docs/pra/journal/<AAAA-MM-JJ>.md`, une ligne par entrée `- HH:MM INC-6109 [type] texte` (types : ouverture, état, action, décision, mesure, clôture).
- Pendant un PRA, GitLab, Mailpit, Keycloak et la supervision de PAR1 n'existent plus ; les miroirs de `adm02` sont la seule copie du code et de la documentation à PAR2.
- Personnages : Claire Morel décide de déclencher ; Nadia Roussel pilote la cellule ; Sophie Laurent observe et relève les preuves (elle n'agit pas) ; Julien Petit valide la reprise de MédiAgenda ; Karim Benali fait la revue technique.

**Travail demandé**
1. Rédige `docs/pra/runbooks/RB-350-bascule-par2.md` : critères et autorité de déclenchement ; préalables vérifiables ; vagues de la reprise (de S02) avec, pour chacune, les gestes, la condition de passage observable, le temps de référence et la preuve à relever ; les **points de non-retour** (ce qui, une fois fait, impose le retour par RB-351) ; l'arrêt des réplications ; la bascule des noms ; la vérification de reprise (critère de S01) ; la mesure du RTO et du RPO (témoin) ; le mode dégradé ; ce qu'on fait si une vague échoue.
2. Rédige `docs/pra/cellule-de-crise.md` : rôles et suppléants, canaux de communication **qui ne dépendent pas de PAR1**, rythme des points de situation et modèles de messages (direction, cabinets, autorités si des données de santé sont en jeu), tenue de la main courante, décisions à tracer, fin de crise et passage au retour.
3. MR relue par Nadia et Julien, validée par Claire ; les deux documents sont aussi présents dans les miroirs de `adm02`.

**Critères de réussite**
- [ ] RB-350 est sur `main` avec le déclenchement, les vagues et leurs conditions de passage, les points de non-retour, la bascule des noms, la mesure du RTO et du RPO, et le renvoi au retour (RB-351).
- [ ] `cellule-de-crise.md` est sur `main` avec les rôles (décision, pilotage, observation, technique, communication), la main courante INC-6109, des canaux indépendants de PAR1 et des modèles de messages.
- [ ] Les deux documents sont lisibles depuis `adm02` (miroir de `plateforme/medisphere`).

**Vérification** : `lab/bin/check F5 7`

<details><summary>Indice 1</summary>

Un critère de déclenchement qu'on ne discute pas à chaud est **temporel et observable** : « PAR1 injoignable depuis PAR2 et depuis l'extérieur pendant N minutes, et aucune perspective de retour avant M heures selon l'équipe sur place ». N et M se déduisent du RTO : si le PRA prend 2 h et que le RTO est de 4 h, attendre 3 h avant de décider rend l'objectif impossible.
</details>

<details><summary>Indice 2</summary>

Le point de non-retour le plus important est la **promotion de la base à PAR2** : à partir de là, deux primaires peuvent exister si PAR1 revient. Le runbook doit dire comment on s'assure que PAR1 n'écrit plus (ou ce qu'on fait des écritures divergentes), et ce que change la présence ou l'absence d'un jeton de rétrogradation de PAR1.
</details>

**Pour aller plus loin** (facultatif) : une fiche « une page » plastifiée par rôle (ce que fait la personne dans les dix premières minutes) ; un arbre de décision pour les sinistres partiels (PAR1 dégradé mais pas perdu : bascule partielle ou non ?).
