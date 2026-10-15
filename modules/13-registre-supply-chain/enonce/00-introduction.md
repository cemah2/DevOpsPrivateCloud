# Module 13 — Introduction : le registre et la chaîne d'approvisionnement

## D'où vient cette image ?

Lundi, 9 h 10. Les quatre applications de MédiSphère tournent en conteneurs depuis le module 12. Leurs images vivent sur le registre de travail de `ctr01`, sans droits par équipe, sans analyse, sans signature ; les images de base viennent directement de Docker Hub, à chaque construction. Sophie Laurent a demandé un point avant la réunion de l'équipe.

> **De** : Sophie Laurent — RSSI
> **À** : Claire Morel, toi
> **Cc** : Karim Benali, Julien Petit, Nadia Roussel
> **Objet** : Chaîne d'approvisionnement logicielle — ce que l'auditeur va nous demander
>
> Bonjour,
>
> Vous avez tous lu le bulletin du CERT sur Trivy : le 19 mars, l'outil d'analyse de sécurité que la moitié de la profession utilise dans ses pipelines a été publié dans une version piégée qui volait les secrets des CI. Trois jours plus tard, des images Docker Hub piégées. Ce n'est ni la première (SolarWinds, Codecov, xz), ni la dernière. La question de l'auditeur HDS de l'an prochain est déjà écrite : « pour chaque conteneur qui traite des données de santé, montrez-moi **d'où il vient**, **ce qu'il contient**, **qui l'a construit** et **qui l'a autorisé** ».
>
> Aujourd'hui, nous ne savons répondre à aucune des quatre. Ce que je veux à la fin de ce chantier :
> 1. un **registre d'entreprise** : des projets, des droits par équipe, des comptes techniques à durée limitée, plus de mot de passe partagé ;
> 2. plus aucun tirage direct depuis Internet par nos serveurs et nos pipelines : des **caches** des registres publics, que nous contrôlons ;
> 3. chaque image analysée (vulnérabilités, mauvaises configurations), avec sa **nomenclature** (SBOM) conservée à côté d'elle ;
> 4. chaque image applicative **signée** par MédiSphère, par son empreinte, avec la preuve de **comment** elle a été construite ; et rien de non signé en production ;
> 5. les dépendances tenues à jour **automatiquement**, sans que cela devienne une porte d'entrée ;
> 6. pouvoir répondre en une heure à « sommes-nous touchés par la CVE de ce matin ? ».
>
> Les outils de sécurité sont des logiciels comme les autres : on les installe vérifiés, épinglés, et on sait les remplacer.
> Sophie

Claire répond dans la foulée : « **Harbor** sur une VM du socle, `reg01`. Karim pilote la revue, Julien prête `mediagenda/api` comme premier client. Le registre devient un service permanent : à partir du module 14, les nœuds Kubernetes ne tireront plus rien d'autre. »

---

## Ce que tu construis dans ce module

À la fin du module 13, MédiSphère a son registre **v1** (étiquette `registre-v1` de `plateforme/medisphere`) :

- **`reg01`** (VMID 1013, 10.10.20.18, socle) : **Harbor 2.15** installé par l'installateur **hors ligne** vérifié, Docker Engine 29 + Compose v5, configuré par le rôle Ansible `harbor`, publié en HTTPS sous **`https://registry.par1.medisphere.internal`** avec un certificat ACME de step-ca renouvelé seul ;
- les **objets de Harbor décrits par le code** (projets, membres, comptes robots, caches, politiques) dans un état OpenTofu `registre` du projet `plateforme/infra` ;
- des **caches** de Docker Hub, Quay, GHCR et registry.k8s.io, utilisés par `runner02` et, demain, par Kubernetes ;
- **Trivy**, **Syft**, **Grype** et **Cosign 3** installés vérifiés ; chaque image applicative analysée, accompagnée de sa SBOM, **signée par empreinte** et attestée (SBOM, provenance) ;
- une **chaîne de livraison** standard (`supply-chain.yml` de `plateforme/ci-templates`) appliquée à `mediagenda/api` ;
- **Renovate** auto-hébergé, qui propose chaque nuit les mises à jour des images de base et des dépendances ;
- aux paliers 3 et 4 : la réplication vers un second Harbor, les politiques bloquantes, la sauvegarde et la restauration, la supervision et la montée de version, l'ADR-0130, la réponse à une alerte CVE, les pannes et l'API de distribution OCI à la main.

Le **palier 1** installe Harbor, crée les projets et les comptes, migre les images du registre de travail, met en place les caches et l'analyse de vulnérabilités. Le **palier 2** ajoute la SBOM, la signature, les attestations, la chaîne de livraison complète, les règles de stockage et Renovate, puis une revue.

## Architecture du module

```
  adm01 (1001) 10.10.10.10 — VLAN 10 : OpenTofu (état « registre »), Ansible, cosign/trivy/syft/grype, checks
       │
  ═════╪════════════════ gw01 / gw02 (VIP .1) — flux VLAN 40, 99 → reg01:443 ouverts au E02 ═════════════
       │
  VLAN 20 INFRA 10.10.20.0/24 ───────────────┬──────────────────────────┬─────────────────────┬──────────
       │                                     │ .17                      │ .15                 │ .11, .12
  ┌────┴───────────────────────────────────┐ │ runner02 (1012)          │ runner01 (1007)     │ ca01, git01
  │ reg01 (1013) 10.10.20.18               │ │ Docker 29, exécuteur     │ shell (OpenTofu,    │ ACME, GitLab
  │ registry.par1.medisphere.internal      │ │ docker : construction,   │ Ansible)            │
  │ (CNAME → reg01)                        │ │ scan, SBOM, signature,   └─────────────────────┘
  │ Docker 29 + Compose v5, harbor.service │ │ Renovate (planifié)
  │ ┌─ nginx (proxy) :80 → :443 ─────────┐ │ └──────────────────────────
  │ │ core · portal · registry · jobsvc  │ │
  │ │ registryctl · harbor-db (PG 18)    │ │      Internet (443) ◀── reg01 : caches dockerhub, quay,
  │ │ redis (Valkey) · trivy-adapter     │ │                         ghcr, k8s ; base Trivy
  │ │ harbor-log · (exporter : palier 3) │ │
  │ └────────────────────────────────────┘ │
  │ /data (200 Gio, hdd-bulk) : blobs,     │
  │ base, rapports Trivy, certificat       │
  └────────────────────────────────────────┘

  reg02 (2131, vsandbox, palier 3) : second Harbor (réplication, restauration), détruit en fin de module.
```

Points structurants :

- **Harbor est une application Compose.** Une dizaine de conteneurs (`docker compose`), générés par le script `prepare` à partir d'un seul fichier, `harbor.yml`. On ne modifie jamais les fichiers générés (`common/config/…`, `docker-compose.yml`) : on modifie `harbor.yml`, on relance `prepare`, on redémarre. Le rôle Ansible `harbor` fait exactement cela, et une unité systemd `harbor.service` lance la pile au démarrage, **après** le montage de `/data`.
- **Le registre est la frontière.** Tout ce qui entre (images publiques par les caches, images construites par la CI) et tout ce qui sort (vers `runner02`, puis vers Kubernetes) passe par Harbor, avec une identité : un humain par la base locale de Harbor (OIDC viendra au module 24), une machine par un **compte robot** à droits minimaux et à durée de vie limitée.
- **Une image se désigne par son empreinte.** Une étiquette (`v1.4.2`, `latest`) est un pointeur mobile ; l'empreinte (`sha256:…`) est le contenu. On analyse, on signe, on atteste et on déploie **des empreintes**.
- **Les preuves vivent à côté de l'image.** Signature Cosign, SBOM, provenance : ce sont des **artefacts OCI référents** (*referrers*, OCI 1.1) rattachés à l'empreinte de l'image, stockés dans Harbor, répliqués avec elle (palier 3).
- **Le lab n'utilise pas le journal de transparence public.** Les signatures sont faites avec une **clé** MédiSphère, sans envoi au Rekor public de Sigstore (qui publierait le nom et l'empreinte de nos images). La signature « sans clé » (*keyless*, Fulcio + Rekor) est expliquée, pas pratiquée.

### Hôtes du module

| Hôte | VMID | Adresse | Ressources | Étiquettes | Rôles Ansible | Exercice |
|---|---|---|---|---|---|---|
| `reg01` | **1013** | 10.10.20.18 (VLAN 20), `reg01.par1.medisphere.internal` + CNAME `registry.par1.medisphere.internal` | 2 vCPU, 6 Go ; système 32 Gio `local-nvme` ; données 200 Gio `hdd-bulk` sur `/data` | `socle`, `role-registre` | `docker_engine` (M12), `certificats_acme` (M06), `harbor` | E02 |
| `reg02` | 2131 | `vsandbox` (DHCP) | 2 vCPU, 4 Go | `env-m13` | `docker_engine`, `harbor` | E13 (palier 3) |

`reg01` rejoint le **socle** (état OpenTofu `socle`, sauvegarde, supervision) : il ne se détruit plus. Socle v3 ≈ 37 Go avec `runner02` (M12) et `reg01`.

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01`/`gw02` |
|---|---|---|---|
| `adm01` (VLAN 10) → `reg01` (IHM, API, registre) | 443 | E02 | existant : MGMT joint tout le lab |
| VPN d'administration → `reg01` | 443 | E02 | existant : « VPN d'admin vers les interfaces web du socle » |
| `runner01`, `runner02`, `git01`, `ca01` → `reg01` | 80, 443 | E02 | même VLAN 20 : ne traverse pas la bordure |
| VLAN 40 (Kubernetes, M14) et VLAN 99 (`reg02`, VMs d'essai) → `reg01` | 443 | E02 | **à ouvrir** (matrice des flux) |
| `ca01` → `reg01` (défi ACME HTTP-01) | 80 | E02 | même VLAN 20 |
| `reg01` → Internet (caches, base Trivy, installateur) | 443 | E02, E04, E05 | existant (« lab vers Internet ») |

---

## Le chemin imposé

1. **OpenTofu, deux états.** La VM `reg01` est déclarée dans l'état **`socle`** de `plateforme/infra` (module `vm-debian`, étendu en E02 pour accepter un disque de données), avec ses noms DNS (A, PTR et le CNAME `registry`). Les **objets de Harbor** (projets, utilisateurs, membres, robots, caches, politiques) sont déclarés dans un état à part, **`registre`** (dossier `registre/` de `plateforme/infra`), avec le fournisseur `goharbor/harbor`. Détruire ou rejouer la configuration de Harbor ne touche jamais une VM, et inversement.
2. **Ansible** pour l'hôte : `reg01` entre dans l'inventaire par ses étiquettes NetBox (`socle`, `role-registre`) ; les rôles communs du socle, `docker_engine` (M12), `certificats_acme` (M06), puis le rôle **`harbor`** que tu écris en E02, par le playbook `playbooks/registre.yml`, appliqué par le pipeline protégé de `plateforme/ansible`.
3. **Les outils de la chaîne** (Cosign, Trivy, Syft, Grype) s'installent sur `adm01` par un rôle `outils_supply_chain` (E05), à partir de paquets **épinglés par empreinte** et dont la **signature** a été vérifiée une fois, à la main, au moment de l'épinglage. En CI, ils viennent d'**une image outillée** construite et signée par MédiSphère (E09), jamais d'une étiquette flottante.
4. **Secrets.** Mot de passe `admin` de Harbor et mot de passe de sa base : Ansible Vault **`critique`**. Clé privée Cosign et sa phrase de passe : Vault **`critique`** et variables de CI **protégées**. Secrets des robots : générés par OpenTofu (état chiffré, M05-E27), copiés dans des fichiers 600 de `~/.config/workbook/` et dans des variables de CI protégées et masquées. Rien en clair dans un dépôt ; tout est inscrit au registre des secrets (`docs/socle/registre-secrets.md`).
5. **Documentation** dans `plateforme/medisphere`, dossier **`docs/registre/`** : fiches, `cosign.pub`, configuration de signature, ADR-0130 (palier 3), runbooks **RB-130** et suivants. Journal de diagnostic et post-mortems : `docs/socle/journal/` et `docs/socle/post-mortems/`, comme à chaque module.

Une manipulation à la main n'est permise que pour **explorer** (une requête à l'API, un `docker pull`, un `trivy image` de découverte) ou quand l'énoncé la demande comme geste à connaître (vérifier une signature de distribution, la première installation de Cosign).

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Registre OCI.** Un service HTTP qui stocke des **blobs** (couches, configurations) adressés par leur empreinte et des **manifestes** qui les assemblent, selon la *Distribution Specification* de l'OCI (`/v2/<dépôt>/manifests/<référence>`, `/v2/<dépôt>/blobs/<empreinte>`). Un **index** (*manifest list*) regroupe les manifestes de plusieurs architectures. L'API à la main est l'objet de M13-E23.

**Harbor.** Un registre d'entreprise construit autour de CNCF Distribution : projets (espaces de noms avec membres et politiques), authentification (base locale, LDAP, OIDC), comptes **robots**, quotas, rétention, immuabilité des étiquettes, réplication, **caches** (*proxy cache*) de registres distants, analyse de vulnérabilités (Trivy intégré), génération de SBOM, gestion des signatures Cosign et Notation, journal d'audit. Projet CNCF diplômé.

**Compte robot.** Une identité technique de Harbor (`robot$<nom>` au niveau système, `robot$<projet>+<nom>` au niveau projet), avec des permissions explicites (ressource × action : `repository:pull`, `repository:push`, `artifact:read`…) et une **date d'expiration**. Un pipeline, un nœud, une vérification : un robot chacun.

**Cache de registre (*proxy cache*).** Un projet Harbor rattaché à un registre distant : au premier `pull` de `registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim`, Harbor tire l'image de Docker Hub, la sert et la garde ; les suivants sont servis localement (après une vérification de l'empreinte en amont tant que l'amont répond). On contrôle ce qui entre, on survit à une panne ou à une limite de débit de l'amont, on sait qui a tiré quoi.

**Vulnérabilités (CVE) et analyseurs.** Un analyseur lit les paquets d'une image (dpkg, pip, modules Go…), les compare à des bases d'avis (NVD, avis des distributions, GitHub Advisories) et produit une liste de CVE avec leur **sévérité** et l'existence ou non d'une **version corrigée**. Deux analyseurs ne donnent pas la même liste : bases, heuristiques et correspondances diffèrent (E06).

**SBOM.** *Software Bill of Materials* : l'inventaire des composants d'un logiciel (nom, version, licence, identifiant `purl`, empreintes), dans un format normalisé : **SPDX** (Linux Foundation, ISO/IEC 5962) ou **CycloneDX** (OWASP). Une SBOM conservée permet de répondre **plus tard** à « qui contient la bibliothèque X en version Y ? » sans réanalyser.

**Signature d'image (Cosign).** Cosign signe l'**empreinte du manifeste** d'une image avec une clé (ou une identité éphémère en mode *keyless*), et range la signature dans le registre, à côté de l'image. Depuis **Cosign 3**, la signature est un **bundle Sigstore** stocké comme artefact référent OCI 1.1 (plus l'étiquette `sha256-<empreinte>.sig` de Cosign 2). Vérifier, c'est prouver que l'empreinte qu'on va exécuter a été signée par la clé attendue.

**Attestation.** Une déclaration signée **à propos** d'une image, au format *in-toto* : « cette image contient ces composants » (SBOM), « cette image a été construite par ce pipeline, depuis ce commit, avec ces entrées » (**provenance**, format SLSA). La signature dit *qui* ; l'attestation dit *quoi* et *comment*.

**SLSA.** *Supply-chain Levels for Software Artifacts* : un cadre de niveaux d'exigence sur la construction (construction scriptée, provenance générée par la plateforme de construction, provenance infalsifiable, plateforme durcie). Il ne dit pas comment faire, il dit quoi prouver.

**Transparence (Rekor) et *keyless*.** Le *public good instance* de Sigstore offre une autorité de certification éphémère (Fulcio, liée à une identité OIDC) et un **journal de transparence** public (Rekor) où chaque signature est inscrite. C'est très bien pour un logiciel libre, inadapté à un registre privé de santé : on publierait l'existence et l'empreinte de chaque image.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Harbor **2.15.3** (installateur hors ligne, Trivy **0.74** embarqué, PostgreSQL 18 et Valkey intégrés) ; Docker Engine **29.8**, Compose **5.6** (rôle `docker_engine` du M12) ; Trivy **0.75.0** ; Syft **1.54.1** ; Grype **0.120.1** (base schéma v6) ; Cosign **3.1.3** ; Renovate **44** (renovate-runner v26.1.0) ; fournisseur OpenTofu `goharbor/harbor` **~> 3.12** |
| Changements de version | voir [`annexes/versions-bloc-C.md`](../../../annexes/versions-bloc-C.md), sections « Harbor 2.15 », « Trivy », « Cosign v3 », « Renovate » : Notary et ChartMuseum supprimés, Valkey, PostgreSQL 18, bundle Cosign v3 et référents OCI, `--tlog-upload` déprécié, Trivy 0.69.4-0.69.6 malveillantes |
| VM | `reg01`, VMID 1013, 2 vCPU, 6144 Mo, 10.10.20.18/24 (VNet `vinfra`), étiquettes `socle` + `role-registre` ; disque système 32 Gio `local-nvme` ; disque de données 200 Gio `hdd-bulk` (série `reg01-donnees`), système de fichiers XFS monté sur `/data`, **exclu** de la sauvegarde de la VM (les données de Harbor sont sauvegardées au niveau applicatif, M13-E15) |
| Noms | A et PTR `reg01.par1.medisphere.internal` ; CNAME **`registry.par1.medisphere.internal` → `reg01`** ; c'est **le seul nom** que les clients utilisent |
| Harbor sur l'hôte | installateur dans `/opt/harbor-dist/<version>/harbor/`, lien `/opt/harbor` vers la version active ; `harbor.yml` (600, root) ; unité `harbor.service` ; certificat et clé sources dans `/etc/harbor/tls/` (copiés par `prepare` dans `/data/secret/cert/`) ; journaux sous `/var/log/harbor/` |
| Certificat | step-ca ACME (rôle `certificats_acme`, id `harbor`), noms `registry.par1.medisphere.internal` et `reg01.par1.medisphere.internal`, 30 jours, renouvelé par `cert-renewer@harbor.timer`, puis recopié dans `/data/secret/cert/` et pris en compte par `nginx -s reload` dans le conteneur `nginx` |
| Comptes humains | base locale de Harbor : `admin` (bris de glace, mot de passe en Vault `critique`), `<MOI>`, `karim.benali`, `julien.petit`, `lucas.martin` |
| Projets | `medisphere` (privé, images applicatives `medisphere/mediagenda-api`, `medisphere/medidoc`, `medisphere/medinotif`, `medisphere/legacy-rdv`), `plateforme` (privé, outils), `bibliotheque` (privé, images de base reconstruites, M12-E27), `charts` (privé, M17) ; caches `dockerhub`, `quay`, `ghcr`, `k8s` (E04) |
| Robots | `robot$medisphere+ci` (poussée et tirage de `medisphere`), `robot$bibliotheque+ci` (idem pour `bibliotheque`), `robot$k8s-pull` (système, tirage seul, M14), `robot$wb-checks` (système, **lecture seule**, vérifications du workbook), `robot$renovate` (système, tirage de `bibliotheque` et `plateforme`, E11) |
| État OpenTofu | `plateforme/infra`, dossier **`registre/`**, clé `registre/terraform.tfstate` sur `s3-01`, chiffré (M05-E27) ; fournisseur `goharbor/harbor` ; appliqué par le pipeline de `plateforme/infra` avec les variables protégées et masquées `HARBOR_URL`, `HARBOR_USERNAME`, `HARBOR_PASSWORD` |
| Ansible | groupe `role_registre` ; `group_vars/role_registre/harbor.yml`, `vault-critique.yml` (`vault_harbor_admin_mdp`, `vault_harbor_db_mdp`) ; `host_vars/reg01/certificats.yml` ; rôle `harbor` ; playbook `playbooks/registre.yml` ; rôle `outils_supply_chain` (E05) appliqué à `adm01` |
| Fichiers sur `adm01` (`~/.config/workbook/`, 600) | `harbor-checks.env` (robot `wb-checks` : `HARBOR_USER=`, `HARBOR_PASSWORD=`, lu par les vérifications) ; `harbor-moi.env` (ton compte Harbor, mêmes variables) ; `registre-travail.env` (M12, jusqu'à la migration) |
| Variables de CI | groupes `mediagenda`, `medidoc`, `medinotif`, `legacy` : `HARBOR_ROBOT_USER` (protégée, **non développée** : le nom contient `$`, il ne peut pas être masqué), `HARBOR_ROBOT_TOKEN` (protégée, masquée), `COSIGN_PRIVATE_KEY` (type fichier, protégée), `COSIGN_PASSWORD` (protégée, masquée) |
| Documentation | `docs/registre/` de `plateforme/medisphere` : `cosign.pub`, `signing-config.json`, fiches d'exploitation, `comparaison-analyseurs.md` (E06), `chaine-livraison.md` (E09), RB-130 (installer et reconstruire Harbor, E02), RB-131 et suivants |
| Brouillons | `~/m13/eXX/` sur `adm01` (non versionnés, **sans secret**) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), aussi ton compte Harbor |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<VERSION-TOFU-MODULES>` | Étiquette de `plateforme/tofu-modules` qui contient `vm-debian` avec disques de données (E02) |
| `<EMPREINTE>` | Une empreinte `sha256:…` d'image, telle que l'affichent `skopeo inspect`, `docker buildx imagetools inspect` ou Harbor |

### Variables de `lab/lab.env`

Les deux variables du module existent déjà dans `lab/lab.env.example` (section « Bloc C ») ; leurs valeurs par défaut conviennent :

```
WB_HARBOR_URL="https://registry.par1.medisphere.internal"
WB_HARBOR_CHECKS_FILE="$HOME/.config/workbook/harbor-checks.env"
```

Les vérifications utilisent aussi `WB_MOI`, `WB_SRC`, `WB_DEPOT`, `WB_PVE_HOST`, `WB_STORAGE_NVME`, `WB_STORAGE_BULK` et les jetons en lecture de GitLab et de NetBox. À partir de M13-E03, la fonction `harbor_api` de `lab/lib/check-lib.sh` lit l'API de Harbor avec le robot `wb-checks`.

---

## Règles du module

1. **Une image se désigne par son empreinte.** On signe, on atteste, on vérifie et on déploie `…@sha256:…`. Une signature posée sur une étiquette signe ce que l'étiquette désignait **à l'instant** où Cosign l'a résolue ; une étiquette se déplace.
2. **Aucun outil de sécurité non vérifié.** Chaque binaire ou paquet (Harbor, Cosign, Trivy, Syft, Grype) est téléchargé, vérifié par sa **signature** (bundle Sigstore) **et** son empreinte SHA-256, puis épinglé par empreinte dans le code. Jamais Trivy **0.69.4**, ni les images `aquasec/trivy:0.69.5` / `0.69.6`. Jamais de `curl … | sh`. Jamais d'étiquette `latest` d'un outil en CI.
3. **Pas de journal de transparence public.** Aucune commande `cosign` ne doit écrire dans le Rekor public : signature avec la configuration de signature MédiSphère (sans journal), vérification avec `--insecure-ignore-tlog=true`. Un `cosign sign` lancé sans ces réglages envoie le nom et l'empreinte de l'image chez Sigstore.
   > ⚠️ **Attention** : avec une clé et sans configuration de signature, Cosign 3 envoie la signature au journal public **sans rien demander** (comportement relevé avec Cosign 3.1.3). Une signature envoyée par erreur ne se retire pas : l'entrée du journal est publique et définitive. Vérifie la présence de `--signing-config` dans **chaque** commande `cosign sign` ou `cosign attest`, et préfère les scripts relus aux commandes tapées.
4. **Le compte `admin` de Harbor est un compte de bris de glace.** Il sert à OpenTofu (état `registre`, par le pipeline) et aux réparations. Toi, tu travailles avec `<MOI>` ; les machines avec un robot. Aucun mot de passe en argument de commande : fichier 600, entrée standard (`--password-stdin`), ou variable masquée.
5. **Harbor est un état partagé.** Supprimer un projet, un dépôt ou une étiquette, lancer le ramasse-miettes, changer une règle de rétention : c'est **irréversible** pour les images concernées, et d'autres (CI, Kubernetes à partir du M14) en dépendent.
   > ⚠️ **Attention** : avant toute suppression ou toute nouvelle règle de rétention, lance une **simulation** (*dry run*) quand Harbor la propose, et vérifie la liste de ce qui partirait.
6. **On ne modifie jamais les fichiers générés par `prepare`** sur `reg01` (`/opt/harbor/common/`, `/opt/harbor/docker-compose.yml`) : ils sont réécrits au prochain passage du rôle. Toute modification passe par `harbor.yml` (le gabarit du rôle).
7. **Pas de vérification TLS désactivée** : ni `--insecure`, ni `--tls-verify=false`, ni `--allow-insecure-registry`, ni `insecure = true` (le fournisseur OpenTofu `goharbor/harbor` a `insecure = true` **par défaut** : écris `insecure = false`). Le certificat de Harbor est émis par la PKI MédiSphère, que tous les hôtes du lab connaissent.
8. **Mémoire.** Ce module demande le socle v3 (≈ 37 Go avec `runner02` et `reg01`) ; `reg02` ajoute 4 Go au palier 3. Arrête les VMs du module 12 si elles tournent encore (`ctr02`, `ctr03`, `legacy01`), sauf `ctr01` jusqu'à la migration des images (E03).

---

## Préparer `adm01`

Vérifie l'état d'entrée :

```
admin@adm01:~$ lab/bin/check 12 46
admin@adm01:~$ ssh runner02 'sudo docker version --format "{{.Server.Version}}"; docker compose version'
admin@adm01:~$ curl -sf https://ctr01.par1.medisphere.internal:5000/v2/ -o /dev/null -w '%{http_code}\n'
```

Le premier contrôle (mini-projet du module 12) doit être vert. Le deuxième affiche Docker 29.8.x et Compose 5.x. Le troisième répond `401` (le registre de travail demande une authentification) : il te faut encore `ctr01` et son registre jusqu'à la fin de M13-E03. Si tu l'as détruite au M12-E46, recrée-la par le code (état `m12-conteneurs`) avec son registre, ou prévois de reconstruire les images par leurs pipelines après E03.

Installe les outils de lecture dont le module se sert (paquets Debian 13) :

```
admin@adm01:~$ sudo apt install skopeo jq
admin@adm01:~$ skopeo --version
```

Cosign, Trivy, Syft et Grype ne viennent **pas** des dépôts Debian (trop anciens, et Cosign 2.5 de Debian ne produit pas le format de Cosign 3) : ils s'installent vérifiés en E02 (Cosign, à la main) puis par le rôle `outils_supply_chain` (E05, E06).

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 13 <XX>`. Elles sont en lecture seule : configuration Proxmox lue sur `pve01`, état de `reg01` et `runner02` en SSH (`sudo -n` pour lire), DNS, TLS, NetBox, GitLab en lecture, API de Harbor avec le robot `wb-checks` (à partir de E03), `skopeo inspect` et `cosign verify` avec ce même robot (dans un dossier d'authentification temporaire, effacé à la fin).
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M13-EXX/` : `infra/` reproduit l'arborescence de `plateforme/infra` (dont `registre/`), `tofu-modules/` celle de `plateforme/tofu-modules`, `ansible/` celle de `plateforme/ansible`, `ci-templates/` celle de `plateforme/ci-templates`, `mediagenda-api/` celle de `mediagenda/api`, `renovate/` et `renovate-config/` celles des projets Renovate, `medisphere/` celle de la documentation, `outils/` des scripts à poser dans `plateforme/outils`. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09 ─ E10 ─ E11 ─ E12
                   │                              ▲
                   └──── (les caches servent E09 et E11 : images des jobs, base Renovate)
```

1. **E01** — à froid, avant de toucher au clavier.
2. **E02 → E05** (palier 1) — dans l'ordre : chaque exercice construit sur le précédent.
3. **E06 → E08** — la SBOM, la signature, les attestations, à la main, pour comprendre ce que la chaîne de E09 automatise.
4. **E09** — la chaîne complète ; **E10** juste après (rétention et immuabilité protègent ce que E09 publie).
5. **E11** — Renovate, quand les images de base passent par les caches.
6. **E12** — la revue, en dernier : elle demande d'avoir pratiqué.

Durée indicative : palier 1, 8 à 11 heures ; palier 2, 10 à 14 heures.

## Pour aller plus loin

- Harbor : installation (<https://goharbor.io/docs/2.15.0/install-config/>), projets et robots (<https://goharbor.io/docs/2.15.0/working-with-projects/>), caches (<https://goharbor.io/docs/2.15.0/administration/configure-proxy-cache/>), API (`https://registry.par1.medisphere.internal/devcenter-api-2.0`).
- OCI : *Distribution Specification* et *Image Specification* (<https://github.com/opencontainers/distribution-spec>, <https://github.com/opencontainers/image-spec>), notamment la section *Referrers API*.
- Sigstore et Cosign : <https://docs.sigstore.dev/>, en particulier « Signing containers » et « Verifying signatures » ; billet « Cosign 3.0 available » (<https://blog.sigstore.dev/cosign-3-0-available/>).
- SLSA : <https://slsa.dev/spec/v1.1/> ; in-toto : <https://in-toto.io/>.
- SPDX : <https://spdx.dev/> ; CycloneDX : <https://cyclonedx.org/>.
- Trivy : <https://trivy.dev/latest/docs/> et l'avis de sécurité de mars 2026 (<https://www.aquasec.com/blog/trivy-supply-chain-attack-what-you-need-to-know>).
- Renovate auto-hébergé : <https://docs.renovatebot.com/examples/self-hosting/> et <https://gitlab.com/renovate-bot/renovate-runner>.
- Lectures d'incidents : *xz-utils backdoor* (CVE-2024-3094, mars 2024), rapport de la CISA sur SolarWinds (2021), compromission de Codecov (avril 2021).
