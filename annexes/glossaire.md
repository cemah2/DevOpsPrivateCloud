# Glossaire

> Termes du bloc A (modules 00 à 06), avec l'exercice qui les introduit ou les pratique en premier. Les termes anglais sont conservés quand c'est l'usage du métier. Pour les versions et les changements de comportement, voir [`versions-bloc-A.md`](versions-bloc-A.md). Complété à la fin de chaque bloc.

200 entrées.

[A](#a) · [B](#b) · [C](#c) · [D](#d) · [E](#e) · [F](#f) · [G](#g) · [H](#h) · [I](#i) · [J](#j) · [K](#k) · [L](#l) · [M](#m) · [N](#n) · [O](#o) · [P](#p) · [R](#r) · [S](#s) · [T](#t) · [U](#u) · [V](#v) · [W](#w) · [Y](#y) · [Z](#z)

## A

- **ACL (Proxmox)** — Association d'un rôle à un utilisateur, un groupe ou un jeton sur un chemin (`/pool/lab`, `/storage/…`). Les droits d'un jeton à privilèges séparés sont l'intersection des siens et de ceux de son utilisateur. → [M00-E08](../modules/00-lab/README.md)
- **ACME** — Protocole (RFC 8555) par lequel un client prouve qu'il contrôle un nom puis obtient et renouvelle seul un certificat. step-ca en est un serveur interne. → [M06-E18](../modules/06-services-socle/README.md)
- **Admin Mode (GitLab)** — Mode où un administrateur doit se réauthentifier avant d'accéder aux fonctions d'administration ; les jetons ont alors besoin de la portée `admin_mode`. → [M01-E31](../modules/01-git/README.md)
- **ADR (*Architecture Decision Record*)** — Court document qui consigne une décision d'architecture, son contexte, les options écartées et ses conséquences. Numérotés par module dans `docs/socle/adr/`. → [M00-E33](../modules/00-lab/README.md)
- **Agent QEMU** — Service (`qemu-guest-agent`) installé dans la VM qui permet à Proxmox de lire ses adresses, d'y exécuter des commandes (`qm guest exec`) et de geler ses systèmes de fichiers avant une sauvegarde. → [M00-E11](../modules/00-lab/README.md)
- **Agent SSH** — Processus (`ssh-agent`) qui garde en mémoire une clé privée déverrouillée, pour que les outils non interactifs (checks, Ansible) puissent l'utiliser sans redemander la phrase de passe. → [M00-E15](../modules/00-lab/README.md)
- **Ancre de confiance (*trust anchor*)** — Certificat (TLS) ou clé (DNSSEC) auquel on fait confiance a priori et à partir duquel on valide une chaîne. Pour `pve01`, une ancre conforme est construite en M02-E08. → [M02-E08](../modules/02-scripting/README.md)
- **Ancre négative (NTA)** — *Negative trust anchor* : déclaration qui demande à un résolveur validant de ne pas exiger de signatures DNSSEC pour une zone (ici `medisphere.internal`, non déléguée depuis la racine). → [M06-E07](../modules/06-services-socle/README.md)
- **AnsiballZ** — Mécanisme par lequel Ansible empaquette un module Python et ses dépendances dans un script autonome envoyé puis exécuté sur l'hôte géré. → [M04-E44](../modules/04-ansible/README.md)
- **Ansible** — Outil de gestion de configuration sans agent : depuis un nœud de contrôle, il se connecte en SSH aux hôtes d'un inventaire et y exécute des modules décrits dans des playbooks. → [M04-E02](../modules/04-ansible/README.md)
- **Ansible Vault** — Chiffrement de fichiers ou de variables d'un projet Ansible. Le workbook utilise deux identités (`lab`, `critique`) dont les mots de passe restent hors du dépôt. → [M04-E12](../modules/04-ansible/README.md)
- **ansible-lint** — Analyseur de code Ansible (style, bonnes pratiques, profils jusqu'à `production`), lancé en pre-commit et en CI. → [M04-E20](../modules/04-ansible/README.md)
- **Artefact (CI)** — Fichier produit par un job et conservé par GitLab (rapport, plan OpenTofu, paquet), téléchargeable ou transmis aux jobs suivants. → [M01-E24](../modules/01-git/README.md)
- **AWX** — Interface web et API d'exécution d'Ansible (projet amont d'Ansible Automation Platform), sans version depuis 2024 : traitée en fiche. → [M04-E32](../modules/04-ansible/README.md)
- **AXFR / IXFR** — Transferts de zone DNS, complet ou incrémental, d'un serveur primaire vers un secondaire ; ici signés par TSIG. → [M06-E24](../modules/06-services-socle/README.md)

## B

- **Backend (OpenTofu)** — Endroit où OpenTofu range l'état : fichier local par défaut, compartiment S3 sur `s3-01` dans le workbook. → [M05-E11](../modules/05-iac/README.md)
- **Bastion** — Point d'entrée unique et contrôlé vers un réseau d'administration ; ici `adm01`, puis avec des certificats SSH d'utilisateur. → [M00-E15](../modules/00-lab/README.md)
- **bats** — *Bash Automated Testing System* : cadre de tests pour scripts Bash (`@test`, `run`, assertions). → [M02-E14](../modules/02-scripting/README.md)
- **`become`** — Élévation de privilèges d'Ansible (par défaut `sudo`), déclarée au niveau du play ou de la tâche. → [M04-E04](../modules/04-ansible/README.md)
- **Bisect** — `git bisect` : recherche dichotomique du commit qui a introduit un défaut, automatisable avec `git bisect run`. → [M01-E44](../modules/01-git/README.md)
- **Blob, tree, commit** — Les trois types d'objets Git : contenu d'un fichier, répertoire, instantané daté avec parents et message. Adressés par leur empreinte. → [M01-E02](../modules/01-git/README.md)
- **`boot_command`** — Séquence de touches que Packer tape sur la console de la VM (API `sendkey`) pour lancer une installation automatisée. → [M03-E05](../modules/03-images/README.md)
- **Branche protégée** — Branche GitLab sur laquelle le push direct, la réécriture et la suppression sont restreints ; la fusion passe par une merge request. → [M01-E11](../modules/01-git/README.md)
- **Break & fix (`BF`)** — Type d'exercice : une panne est injectée par `lab/bin/break`, il faut la diagnostiquer et la réparer. `--annuler` restaure l'état sain. → [M00-E38](../modules/00-lab/README.md)
- **Bridge VLAN-aware** — Pont Linux qui transporte plusieurs VLANs étiquetés ; `vmbr1` en est un, sans port physique, pour isoler le lab. → [M00-E09](../modules/00-lab/README.md)
- **Builder (Packer)** — Composant qui crée la machine de construction et la convertit en image : `proxmox-iso` (depuis une ISO) ou `proxmox-clone` (depuis un template). → [M03-E03](../modules/03-images/README.md)
- **BUSL** — *Business Source License* : licence non libre adoptée par HashiCorp en 2023 pour Terraform, Packer et Vault ; origine du fork OpenTofu. → [M05-E09](../modules/05-iac/README.md)

## C

- **CA SSH** — Autorité qui signe des clés publiques SSH d'hôtes ou d'utilisateurs ; les clients lui font confiance (`@cert-authority`) au lieu de chaque empreinte. → [M06-E19](../modules/06-services-socle/README.md)
- **`cert-renewer`** — Unité systemd fournie par Smallstep (`cert-renewer@<id>`) qui renouvelle un certificat avant son échéance et recharge le service. → [M06-E18](../modules/06-services-socle/README.md)
- **Certificat SSH d'hôte** — Clé d'hôte signée par la CA SSH : le client vérifie l'identité du serveur sans accepter son empreinte à l'aveugle. → [M06-E19](../modules/06-services-socle/README.md)
- **Certificat SSH d'utilisateur** — Clé d'utilisateur signée pour un ou plusieurs comptes (*principals*) et une durée courte (16 h dans le workbook). → [M06-E20](../modules/06-services-socle/README.md)
- **Chaîne de certificats** — Suite certificat final → intermédiaire(s) → racine que le serveur présente (sauf la racine) et que le client valide. → [M06-E02](../modules/06-services-socle/README.md)
- **Checkov** — Analyseur de sécurité statique du code d'infrastructure (OpenTofu, Ansible…), à base de règles désactivables justifiées. → [M05-E25](../modules/05-iac/README.md)
- **Cherry-pick** — Report d'un commit existant sur une autre branche (rétroportage vers une branche de maintenance). → [M01-E19](../modules/01-git/README.md)
- **CHRONO** — Type d'exercice en temps limité, sans corrigé ni indice, dans les conditions d'un examen ou d'une astreinte. → [M00-E37](../modules/00-lab/README.md)
- **chrony** — Client et serveur NTP de Debian 13 ; `gw01` sert le temps au lab, avec NTS à partir du module 06. → [M00-E31](../modules/00-lab/README.md)
- **Clé de déploiement (*deploy key*)** — Clé SSH rattachée à un projet GitLab, en lecture (ou écriture), pour un automate qui n'a pas de compte. → [M01-E20](../modules/01-git/README.md)
- **Clone complet / clone lié** — Copie indépendante d'un disque, ou copie qui partage les blocs du template (rapide mais liée à lui). Le workbook réserve les clones liés aux VMs jetables. → [M00-E19](../modules/00-lab/README.md)
- **cloud-init** — Programme qui configure une instance au premier démarrage (utilisateur, clés, réseau, paquets) depuis une source de données. → [M00-E11](../modules/00-lab/README.md)
- **Colle (*glue record*)** — Enregistrement A d'un serveur de noms placé dans la zone parente quand ce serveur est lui-même dans la zone déléguée. → [M06-E06](../modules/06-services-socle/README.md)
- **Collection Ansible** — Unité de distribution de contenu Ansible (modules, plugins, rôles), installée à version fixée depuis Galaxy ou un dépôt interne (`medisphere.socle`). → [M04-E18](../modules/04-ansible/README.md)
- **commitlint** — Outil qui vérifie que les messages de commit respectent une convention (ici Conventional Commits), en local et en CI. → [M01-E14](../modules/01-git/README.md)
- **Conventional Commits** — Convention de messages (`feat:`, `fix:`, `feat!:`…) qui rend l'historique exploitable par les outils de version. → [M01-E14](../modules/01-git/README.md)
- **`count` / `for_each`** — Méta-arguments OpenTofu qui créent plusieurs instances d'une ressource, par nombre ou par clé (préférable : les adresses restent stables). → [M05-E07](../modules/05-iac/README.md)
- **CRL** — *Certificate Revocation List* : liste signée des certificats révoqués, publiée par la CA (en HTTP sur `ca01`). → [M06-E27](../modules/06-services-socle/README.md)
- **CSK / KSK / ZSK** — Clés DNSSEC : de signature de clés, de signature de zone, ou combinée (CSK), choix du workbook pour la zone `par1`. → [M06-E26](../modules/06-services-socle/README.md)

## D

- **Data tagging** — Moteur de templates d'ansible-core 2.19+, plus strict : conditions booléennes, pas de `{{ }}` dans `when`, indéfinis signalés. → [M04-E09](../modules/04-ansible/README.md)
- **Datastore (PBS)** — Espace de stockage dédupliqué de Proxmox Backup Server (`ds-lab` sur `pbs01`), découpé en espaces de noms. → [M00-E22](../modules/00-lab/README.md)
- **DDNS** — Mise à jour dynamique du DNS (RFC 2136), signée TSIG : Kea y publie les baux qu'il attribue. → [M06-E17](../modules/06-services-socle/README.md)
- **`delegate_to`** — Exécution d'une tâche Ansible sur un autre hôte que celui en cours (contrôleur, API), souvent avec `run_once`. → [M04-E23](../modules/04-ansible/README.md)
- **Délégation DNS** — Découpage de l'espace de noms : la zone parente désigne par des NS les serveurs qui font autorité sur une sous-zone. → [M06-E06](../modules/06-services-socle/README.md)
- **Dérive (*drift*)** — Écart entre l'état décrit par le code et la réalité, dû à une modification faite hors de l'outil ; détectée par `--check` (Ansible) ou `plan` (OpenTofu). → [M04-E29](../modules/04-ansible/README.md)
- **DHCP relais (*relay*)** — Agent qui transmet les requêtes DHCP d'un VLAN vers un serveur situé ailleurs ; ici dnsmasq sur `gw01`. → [M00-E14](../modules/00-lab/README.md)
- **dnsmasq** — Serveur DNS et DHCP léger, DNS provisoire du lab jusqu'au module 06 (`/etc/dnsmasq.d/medisphere.conf`). → [M00-E13](../modules/00-lab/README.md)
- **DNSSEC** — Extensions de sécurité du DNS : les réponses sont signées et un résolveur validant vérifie la chaîne jusqu'à une ancre. → [M06-E26](../modules/06-services-socle/README.md)
- **Durcissement (*hardening*)** — Réduction de la surface d'attaque d'un système (services, comptes, SSH, noyau, journaux) selon une référence écrite. → [M03-E13](../modules/03-images/README.md)

## E

- **Écriture conditionnelle** — Écriture S3 refusée si l'objet existe déjà (`If-None-Match`) : base du verrou d'état natif d'OpenTofu. → [M05-E12](../modules/05-iac/README.md)
- **Empreinte (*checksum*, *hash*)** — Condensé (SHA-256) qui prouve l'intégrité d'un fichier ; on vérifie l'empreinte publiée avant d'exécuter un binaire téléchargé. → [M00-E04](../modules/00-lab/README.md)
- **Espace de noms (PBS)** — *Namespace* : sous-arborescence d'un datastore qui isole les sauvegardes (`par1`, `par1/git01`) et porte ses propres droits. → [M00-E22](../modules/00-lab/README.md)
- **État (OpenTofu)** — Fichier JSON qui associe chaque ressource du code à l'objet réel et à ses attributs ; il contient des secrets, se verrouille, se chiffre et se sauvegarde. → [M05-E05](../modules/05-iac/README.md)
- **Étiquette Proxmox (*tag*)** — Mot-clé posé sur une VM (`socle`, `role-dns`, `env-m05`, `gold`, `current`) ; il alimente l'inventaire Ansible et les sources de données OpenTofu. → [M02-E21](../modules/02-scripting/README.md)
- **Exécuteur `shell` (GitLab Runner)** — Mode où le runner exécute les jobs directement sur sa machine, avec les outils installés ; Docker et Kubernetes viendront aux modules 12 et 19. → [M01-E23](../modules/01-git/README.md)

## F

- **Fact (Ansible)** — Information collectée sur un hôte (système, réseau, matériel) et lue par `ansible_facts['…']`. → [M04-E04](../modules/04-ansible/README.md)
- **Fast-forward** — Fusion qui se contente d'avancer la référence de branche, sans commit de fusion, quand l'historique est linéaire. → [M01-E07](../modules/01-git/README.md)
- **Forward zone (Recursor)** — Zone que le récurseur relaie vers des serveurs désignés (ici l'autoritaire local) au lieu de la résoudre depuis la racine. → [M06-E07](../modules/06-services-socle/README.md)
- **FQCN** — *Fully Qualified Collection Name* : nom complet d'un module Ansible (`ansible.builtin.apt`), imposé par les conventions du projet. → [M04-E02](../modules/04-ansible/README.md)

## G

- **Garbage collection (PBS)** — Tâche qui libère les blocs dédupliqués qui ne sont plus référencés après l'élagage des sauvegardes. → [M00-E22](../modules/00-lab/README.md)
- **genericcloud** — Variante des images cloud Debian avec cloud-init et un noyau allégé, base du template `tpl-debian13`. → [M00-E11](../modules/00-lab/README.md)
- **Gitaly** — Service de GitLab qui gère l'accès aux dépôts Git sur disque pour le reste de l'application. → [M01-E30](../modules/01-git/README.md)
- **GitLab Runner** — Agent qui récupère les jobs CI d'une instance GitLab et les exécute ; enregistré avec un jeton `glrt-`. → [M01-E23](../modules/01-git/README.md)
- **`gitlab-secrets.json`** — Fichier des clés de chiffrement de GitLab : sans lui, une sauvegarde ne peut pas être restaurée entièrement. → [M01-E28](../modules/01-git/README.md)
- **Gitleaks** — Détecteur de secrets dans un dépôt ou un diff (`gitleaks git`, `gitleaks dir`), en pre-commit et en CI. → [M01-E16](../modules/01-git/README.md)
- **Graphe de dépendances** — Ordre calculé par OpenTofu à partir des références entre ressources ; ce qui est indépendant est traité en parallèle. → [M05-E18](../modules/05-iac/README.md)
- **GraphQL** — Langage de requête d'API où le client choisit les champs renvoyés ; NetBox en propose une en plus de l'API REST. → [M06-E10](../modules/06-services-socle/README.md)
- **`group_vars` / `host_vars`** — Dossiers de variables Ansible par groupe et par hôte, rangés à côté de l'inventaire. → [M04-E03](../modules/04-ansible/README.md)

## H

- **Handler** — Tâche Ansible déclenchée par `notify` et exécutée une seule fois en fin de play (rechargement d'un service après changement). → [M04-E08](../modules/04-ansible/README.md)
- **HCL** — *HashiCorp Configuration Language* : syntaxe des fichiers Packer (`.pkr.hcl`) et OpenTofu (`.tf`). → [M03-E03](../modules/03-images/README.md)
- **Hook côté serveur** — Script exécuté par GitLab à la réception d'un push (`pre-receive`), qui peut le refuser ; incontournable, contrairement à pre-commit. → [M01-E26](../modules/01-git/README.md)
- **Hot-standby (Kea)** — Mode de haute disponibilité de Kea : un serveur actif, un serveur de secours qui reçoit les baux et prend le relais. → [M06-E25](../modules/06-services-socle/README.md)
- **HTTP-01** — Défi ACME : le client publie un jeton sur le port 80 du nom demandé, la CA vient le lire. → [M06-E18](../modules/06-services-socle/README.md)

## I

- **Idempotence** — Propriété d'une opération qu'on peut rejouer sans changer le résultat : la seconde exécution ne modifie rien. → [M04-E05](../modules/04-ansible/README.md)
- **Image dorée (*golden image*)** — Template construit par du code, durci, testé et versionné, qui contient tout ce qui est commun aux machines. → [M03-E01](../modules/03-images/README.md)
- **Import (OpenTofu)** — Rattachement d'un objet existant à une ressource du code, sans le recréer (bloc `import` ou `tofu import`). → [M05-E16](../modules/05-iac/README.md)
- **`include` (GitLab CI)** — Inclusion de fichiers de configuration CI d'un autre projet (`plateforme/ci-templates`) ou du même dépôt. → [M01-E24](../modules/01-git/README.md)
- **Index (Git)** — Zone de préparation entre l'arbre de travail et le prochain commit ; `restore`, `reset` et `checkout` copient entre ces trois arbres. → [M01-E08](../modules/01-git/README.md)
- **Instantané (*snapshot*)** — État figé d'une VM (disques, éventuellement mémoire) pour revenir en arrière ; ce n'est pas une sauvegarde. → [M00-E19](../modules/00-lab/README.md)
- **Intermédiaire (CA)** — Autorité signée par la racine, en ligne, qui signe les certificats finaux ; remplaçable sans toucher aux clients. → [M06-E02](../modules/06-services-socle/README.md)
- **Inventaire dynamique** — Inventaire Ansible construit à l'exécution depuis une API (Proxmox, puis NetBox) plutôt qu'écrit à la main. → [M04-E13](../modules/04-ansible/README.md)
- **IPAM** — *IP Address Management* : gestion des préfixes, plages et adresses ; ici dans NetBox. → [M06-E05](../modules/06-services-socle/README.md)
- **IPSet (Proxmox)** — Ensemble nommé d'adresses utilisé dans les règles du pare-feu Proxmox (`automation` pour `runner01`). → [M03-E15](../modules/03-images/README.md)

## J

- **Jeton d'accès personnel (GitLab)** — *Personal access token* (`glpat-`) à portées choisies (`read_api`, `api`) et expiration obligatoire. → [M01-E05](../modules/01-git/README.md)
- **Jeton d'API Proxmox** — Identifiant `utilisateur@realm!nom` et secret pour l'API, avec privilèges séparés ou non et date d'expiration. → [M00-E17](../modules/00-lab/README.md)
- **Jeton v2 (NetBox)** — Format de jeton de NetBox 4.5+ (`nbt_<clé>.<jeton>`) dont le secret n'est plus lisible après création. → [M06-E10](../modules/06-services-socle/README.md)
- **Jinja2** — Moteur de templates utilisé par Ansible pour les expressions `{{ }}` et les fichiers modèles. → [M04-E07](../modules/04-ansible/README.md)
- **jq** — Processeur JSON en ligne de commande : filtrer, transformer et extraire des réponses d'API. → [M02-E05](../modules/02-scripting/README.md)
- **JWK (provisioner)** — Provisioner step-ca à clé JSON chiffrée par mot de passe, pour l'émission manuelle de certificats (`admin`). → [M06-E02](../modules/06-services-socle/README.md)

## K

- **Kea** — Serveur DHCP d'ISC (successeur d'ISC DHCP) : configuration JSON, API de contrôle, DDNS, haute disponibilité. → [M06-E16](../modules/06-services-socle/README.md)
- **Kickstart** — Fichier de réponses de l'installeur Anaconda (famille RHEL) pour une installation sans intervention. → [M03-E06](../modules/03-images/README.md)

## L

- **`lifecycle`** — Bloc OpenTofu qui modifie le cycle de vie d'une ressource : `prevent_destroy`, `ignore_changes`, `create_before_destroy`. → [M05-E18](../modules/05-iac/README.md)
- **Lockfile des providers** — `.terraform.lock.hcl` : versions et empreintes exactes des providers, versionné avec le code. → [M05-E03](../modules/05-iac/README.md)
- **LVM-thin** — Volumes logiques à allocation fine, base des instantanés et clones liés rapides de Proxmox sur `local-nvme`. → [M00-E07](../modules/00-lab/README.md)

## M

- **`machine-id`** — Identifiant unique d'une installation (`/etc/machine-id`) ; doit être vidé avant de faire un template. → [M03-E07](../modules/03-images/README.md)
- **`medictl`** — CLI Python de l'équipe (Typer + proxmoxer) qui liste, crée et détruit les VMs jetables avec garde-fous. → [M02-E15](../modules/02-scripting/README.md)
- **Merge request (MR)** — Demande de fusion d'une branche dans une autre, support de la revue, des discussions et du pipeline. → [M01-E10](../modules/01-git/README.md)
- **Mode strict (Bash)** — `set -euo pipefail` : arrêt sur erreur, variable indéfinie ou échec dans un tube — avec de nombreuses exceptions à connaître. → [M02-E03](../modules/02-scripting/README.md)
- **Module (Ansible)** — Unité d'action d'Ansible (`apt`, `template`, `service`…) qui décrit un état et décide s'il y a quelque chose à faire. → [M04-E04](../modules/04-ansible/README.md)
- **Module (OpenTofu)** — Dossier de fichiers `.tf` réutilisable, avec variables et sorties, versionné et consommé par étiquette (`vm-debian`). → [M05-E13](../modules/05-iac/README.md)
- **Molecule** — Cadre de test de rôles Ansible : crée une instance jetable, applique le rôle, vérifie idempotence et résultat, détruit. → [M04-E24](../modules/04-ansible/README.md)
- **`moved` / `removed`** — Blocs OpenTofu pour renommer une ressource dans l'état sans la recréer, ou l'en retirer sans la détruire. → [M05-E17](../modules/05-iac/README.md)
- **MTU** — Taille maximale d'un paquet sur un lien ; une MTU incohérente (tunnel) laisse passer les petits échanges et bloque les gros. → [M00-E41](../modules/00-lab/README.md)

## N

- **NAT (masquerade)** — Traduction de l'adresse source du trafic sortant du lab vers l'adresse WAN de `gw01`. → [M00-E10](../modules/00-lab/README.md)
- **NetBox** — Application de modélisation du centre de données et d'IPAM, source de vérité du socle, pilotée par API. → [M06-E04](../modules/06-services-socle/README.md)
- **nftables** — Pare-feu du noyau Linux (tables, chaînes, ensembles), configuré dans `/etc/nftables.conf` sur `gw01`. → [M00-E10](../modules/00-lab/README.md)
- **NoCloud** — Source de données cloud-init lue sur un lecteur local (le lecteur `cloudinit` de Proxmox). → [M03-E04](../modules/03-images/README.md)
- **NOTIFY (DNS)** — Message par lequel un serveur primaire prévient ses secondaires qu'une zone a changé. → [M06-E24](../modules/06-services-socle/README.md)
- **NTS** — *Network Time Security* : authentification des réponses NTP par TLS, servie par chrony sur `gw01`. → [M06-E21](../modules/06-services-socle/README.md)
- **Nœud de contrôle** — Machine d'où Ansible s'exécute (`adm01`, puis `runner01`). → [M04-E02](../modules/04-ansible/README.md)

## O

- **Omnibus** — Paquet GitLab qui embarque tous ses composants (NGINX, Puma, Sidekiq, Gitaly, PostgreSQL, Redis), configurés par `gitlab.rb` et `gitlab-ctl reconfigure`. → [M01-E04](../modules/01-git/README.md)
- **OpenTofu** — Outil d'infrastructure déclarative, fork libre de Terraform (Linux Foundation) ; outil IaC du workbook. → [M05-E02](../modules/05-iac/README.md)
- **OpenVox** — Fork communautaire de Puppet, apparu après le passage de Puppet sous licence propriétaire. → [M04-E32](../modules/04-ansible/README.md)

## P

- **Packer** — Outil de HashiCorp qui construit des images machine à partir d'un fichier HCL (builders, provisioners, post-processors). → [M03-E02](../modules/03-images/README.md)
- **Packfile** — Fichier où Git compresse des objets en deltas ; `git gc` et `git maintenance` les entretiennent. → [M01-E45](../modules/01-git/README.md)
- **Paperkey** — Copie imprimable d'une clé de chiffrement de sauvegarde PBS, à conserver hors ligne. → [M00-E36](../modules/00-lab/README.md)
- **Pipeline** — Suite de jobs CI déclenchée par un push ou une MR ; un pipeline obligatoire réussi conditionne la fusion. → [M01-E24](../modules/01-git/README.md)
- **Plan (OpenTofu)** — Liste des actions qu'OpenTofu prévoit (créer, modifier, remplacer `-/+`, détruire) ; on relit le plan, puis on applique exactement celui-là. → [M05-E05](../modules/05-iac/README.md)
- **Play / playbook** — Un play applique des tâches à un groupe d'hôtes ; un playbook est un fichier YAML qui enchaîne des plays. → [M04-E05](../modules/04-ansible/README.md)
- **Pool Proxmox** — Regroupement de VMs et de stockages qui porte des droits ; toutes les VMs du workbook sont dans `lab`. → [M00-E08](../modules/00-lab/README.md)
- **PowerDNS Authoritative** — Serveur DNS faisant autorité, à backends (SQLite) et API REST ; écoute sur 5300, derrière le récurseur. → [M06-E06](../modules/06-services-socle/README.md)
- **PowerDNS Recursor** — Résolveur récursif validant DNSSEC, seul point d'entrée DNS des clients du lab (port 53). → [M06-E07](../modules/06-services-socle/README.md)
- **pre-commit** — Cadre qui exécute des contrôles versionnés avec le dépôt (lint, secrets, format) avant chaque commit. → [M01-E15](../modules/01-git/README.md)
- **Précédence des variables** — Ordre dans lequel Ansible retient une variable définie à plusieurs endroits (défauts de rôle, inventaire, play, `-e`…). → [M04-E06](../modules/04-ansible/README.md)
- **Preseed** — Fichier de réponses de l'installeur Debian pour une installation automatisée. → [M03-E05](../modules/03-images/README.md)
- **Provider** — Programme téléchargé par OpenTofu qui traduit la configuration en appels d'API (`bpg/proxmox`). → [M05-E03](../modules/05-iac/README.md)
- **Provisioner (Packer)** — Étape qui configure la machine de construction (scripts, fichiers) avant sa conversion en template. → [M03-E07](../modules/03-images/README.md)
- **Provisioner (step-ca)** — Méthode d'authentification des demandes de certificats : `admin` (JWK), `acme`, `sshpop`. → [M06-E02](../modules/06-services-socle/README.md)
- **Proxmox Backup Server (PBS)** — Serveur de sauvegarde dédupliquée et chiffrée de Proxmox ; `pbs01` sur le site PAR2. → [M00-E20](../modules/00-lab/README.md)
- **proxmoxer** — Bibliothèque Python cliente de l'API Proxmox, utilisée par `medictl`. → [M02-E08](../modules/02-scripting/README.md)
- **Pruning (rétention)** — Élagage des sauvegardes selon une politique (`keep-daily`, `keep-weekly`…). → [M00-E22](../modules/00-lab/README.md)
- **PTR / zone inverse** — Enregistrement qui associe une adresse à un nom, dans une zone `in-addr.arpa`. → [M00-E13](../modules/00-lab/README.md)

## R

- **Racine hors ligne** — Clé de l'autorité racine de la PKI conservée chiffrée hors de tout serveur en ligne ; elle ne signe que des intermédiaires. → [M06-E02](../modules/06-services-socle/README.md)
- **Rebase interactif** — `git rebase -i` : réécrire une suite de commits (réordonner, fusionner, reformuler) avant de la soumettre à revue. → [M01-E12](../modules/01-git/README.md)
- **Récurseur / résolveur récursif** — Serveur DNS qui interroge les serveurs faisant autorité pour le compte des clients et met en cache. → [M06-E07](../modules/06-services-socle/README.md)
- **Reflog** — Journal local des déplacements de références Git : le filet de sécurité pour retrouver un travail « perdu ». → [M01-E08](../modules/01-git/README.md)
- **Registre de paquets (GitLab)** — Dépôt de paquets intégré à un projet GitLab (PyPI pour `medictl`). → [M02-E25](../modules/02-scripting/README.md)
- **Règle 3-2-1** — Trois copies des données, sur deux supports, dont une hors site. → [M00-E04](../modules/00-lab/README.md)
- **`rerere`** — *Reuse recorded resolution* : Git mémorise la résolution d'un conflit et la rejoue quand il réapparaît. → [M01-E13](../modules/01-git/README.md)
- **REV (revue)** — Type d'exercice : relire une configuration ou un code fourni (souvent « de Lucas ») et en relever les défauts. → [M00-E26](../modules/00-lab/README.md)
- **Revert** — Commit qui annule les effets d'un commit précédent sans réécrire l'historique publié. → [M01-E08](../modules/01-git/README.md)
- **Rôle (Ansible)** — Regroupement réutilisable de tâches, handlers, templates et variables par défaut pour une fonction. → [M04-E10](../modules/04-ansible/README.md)
- **Rôle (Proxmox)** — Ensemble de privilèges (`VM.Allocate`, `Datastore.AllocateSpace`…) ; le workbook crée des rôles minimaux par outil. → [M00-E08](../modules/00-lab/README.md)
- **Rotation** — Remplacement planifié d'un secret, d'une clé ou d'une image par une nouvelle version, et retrait de l'ancienne. → [M04-E30](../modules/04-ansible/README.md)
- **ruff** — Analyseur et formateur Python très rapide, équivalent de ShellCheck et shfmt pour Python. → [M02-E07](../modules/02-scripting/README.md)
- **`run_once`** — Exécute une tâche Ansible une seule fois pour tout le groupe d'hôtes du play. → [M04-E23](../modules/04-ansible/README.md)
- **Runbook** — Procédure d'exploitation pas à pas, testée, pour un geste ou un incident (`RB-NNx`). → [M00-E25](../modules/00-lab/README.md)

## S

- **S3** — API de stockage objet (compartiments, objets, versions) d'AWS, devenue un standard ; servie ici par SeaweedFS. → [M05-E10](../modules/05-iac/README.md)
- **SDN (Proxmox)** — *Software-Defined Network* : zones et VNets déclarés au niveau du cluster Proxmox (`vinfra`, `vsandbox`…). → [M00-E28](../modules/00-lab/README.md)
- **SeaweedFS** — Stockage objet distribué libre (Apache 2.0) qui remplace MinIO sur `s3-01`. → [M05-E10](../modules/05-iac/README.md)
- **semantic-release** — Outil qui déduit la version suivante des messages de commit, pose l'étiquette et publie notes et release. → [M01-E25](../modules/01-git/README.md)
- **Semaphore UI** — Interface web légère d'exécution d'Ansible, évaluée au module 04 (non retenue). → [M04-E28](../modules/04-ansible/README.md)
- **SemVer** — *Semantic Versioning* : `MAJEUR.MINEUR.CORRECTIF`, le majeur signalant une rupture de compatibilité. → [M01-E25](../modules/01-git/README.md)
- **`sensitive`** — Marque OpenTofu qui masque une valeur à l'affichage, mais pas dans l'état. → [M05-E27](../modules/05-iac/README.md)
- **`serial`** — Taille des lots d'hôtes d'un play Ansible, pour des mises à jour progressives. → [M04-E25](../modules/04-ansible/README.md)
- **ShellCheck** — Analyseur statique de scripts shell qui signale les erreurs classiques (guillemets, `cd` non vérifié…). → [M02-E04](../modules/02-scripting/README.md)
- **shfmt** — Formateur de scripts shell, configuré par `.editorconfig`. → [M02-E04](../modules/02-scripting/README.md)
- **Signature de commit** — Signature (ici par clé SSH) d'un commit ou d'une étiquette, vérifiée par Git et affichée par GitLab. → [M01-E27](../modules/01-git/README.md)
- **SOA** — Enregistrement de tête d'une zone DNS : serveur primaire, contact, numéro de série, minuteries. → [M06-E06](../modules/06-services-socle/README.md)
- **Source de données (`data`)** — Lecture d'informations par OpenTofu (image dorée `current`, stockages) sans les gérer. → [M05-E08](../modules/05-iac/README.md)
- **Source de vérité** — Endroit unique où l'on décide d'une donnée (adresse, nom, rôle) ; les autres outils en dérivent. NetBox au module 06. → [M06-E05](../modules/06-services-socle/README.md)
- **Squash** — Fusion de plusieurs commits en un seul, à la fusion d'une MR ou pendant un rebase. → [M01-E09](../modules/01-git/README.md)
- **`sshpop`** — Provisioner step-ca qui authentifie une demande par un certificat SSH déjà valide (renouvellement). → [M06-E19](../modules/06-services-socle/README.md)
- **step-ca** — Autorité de certification de Smallstep : X.509 et SSH, ACME, provisioners ; installée sur `ca01`. → [M06-E02](../modules/06-services-socle/README.md)
- **Stratégie (Ansible)** — Mode d'enchaînement des tâches sur les hôtes : `linear` (par défaut) ou `free`. → [M04-E26](../modules/04-ansible/README.md)

## T

- **Task (Taskfile)** — Lanceur de tâches en YAML (`Taskfile.yml`), alternative lisible à Make. → [M02-E20](../modules/02-scripting/README.md)
- **Template Proxmox** — VM figée en modèle, qu'on ne démarre plus et dont on fait des clones. → [M00-E11](../modules/00-lab/README.md)
- **terraform-docs** — Générateur de documentation (variables, sorties) des modules OpenTofu/Terraform. → [M05-E20](../modules/05-iac/README.md)
- **Terragrunt** — Surcouche d'OpenTofu qui factorise backends, providers et environnements (`run --all`). → [M05-E24](../modules/05-iac/README.md)
- **tflint** — Analyseur statique du code OpenTofu/Terraform (erreurs, conventions, règles par provider). → [M05-E20](../modules/05-iac/README.md)
- **Timer systemd** — Unité qui déclenche un service à heure fixe ou à intervalle ; remplace cron dans le workbook. → [M02-E26](../modules/02-scripting/README.md)
- **`trap`** — Commande Bash qui exécute du code à la sortie ou sur un signal (nettoyage des fichiers temporaires). → [M02-E03](../modules/02-scripting/README.md)
- **Trivy** — Scanner de vulnérabilités et de mauvaises configurations ; épinglé par empreinte depuis sa compromission de 2026. → [M05-E25](../modules/05-iac/README.md)
- **TSIG** — Signature HMAC à clé partagée des échanges DNS (transferts de zone, mises à jour dynamiques). → [M06-E17](../modules/06-services-socle/README.md)
- **Typer** — Bibliothèque Python de CLI fondée sur les annotations de type, utilisée pour `medictl`. → [M02-E15](../modules/02-scripting/README.md)

## U

- **UPID** — Identifiant de tâche asynchrone de Proxmox, renvoyé par l'API et à suivre jusqu'à son statut final. → [M02-E11](../modules/02-scripting/README.md)
- **`use_lockfile`** — Option du backend S3 d'OpenTofu (1.10+) qui verrouille l'état par un objet `.tflock` créé par écriture conditionnelle. → [M05-E12](../modules/05-iac/README.md)
- **uv** — Gestionnaire de projets et d'environnements Python (`pyproject.toml`, `uv.lock`, `uv sync --locked`). → [M02-E07](../modules/02-scripting/README.md)

## V

- **Valkey** — Base clé-valeur en mémoire, fork libre de Redis ; utilisée par NetBox (cache, files de tâches). → [M06-E04](../modules/06-services-socle/README.md)
- **Variables CI protégées et masquées** — Variables GitLab exposées seulement aux branches protégées et masquées dans les journaux ; emplacement des secrets en CI. → [M01-E25](../modules/01-git/README.md)
- **Vendor-data** — Données cloud-init fournies par la plateforme, appliquées en plus du user-data de l'instance. → [M03-E11](../modules/03-images/README.md)
- **Verrou d'état** — Mécanisme qui empêche deux `apply` simultanés sur un même état. → [M05-E12](../modules/05-iac/README.md)
- **Versionnage (S3)** — Conservation de toutes les versions d'un objet d'un compartiment ; permet de restaurer un état écrasé. → [M05-E11](../modules/05-iac/README.md)
- **VLAN / sous-interface** — Réseau virtuel étiqueté (802.1Q) ; `gw01` porte une sous-interface `ens19.<VLAN>` par VLAN routé. → [M00-E10](../modules/00-lab/README.md)
- **VMID** — Identifiant numérique d'une VM Proxmox ; le workbook réserve des plages (1000-1099 socle, 2000-2999 modules, 5000-5999 sandbox, 9000-9099 templates). → [M00-E05](../modules/00-lab/README.md)
- **VNet** — Réseau virtuel du SDN Proxmox auquel on rattache une carte de VM (`vinfra` = VLAN 20, `vsandbox` = VLAN 99). → [M00-E28](../modules/00-lab/README.md)
- **vzdump** — Outil de sauvegarde de VM de Proxmox VE, qui écrit vers un stockage local ou vers PBS. → [M00-E22](../modules/00-lab/README.md)

## W

- **WireGuard** — VPN noyau à clés publiques ; tunnel inter-sites `wg0` et VPN d'administration `wg1` sur `gw01`. → [M00-E16](../modules/00-lab/README.md)
- **Workspace (OpenTofu)** — Plusieurs états pour une même configuration ; comparé aux répertoires par environnement. → [M05-E15](../modules/05-iac/README.md)
- **Worktree** — Arbre de travail supplémentaire attaché au même dépôt Git, pour travailler sur deux branches à la fois. → [M01-E18](../modules/01-git/README.md)

## Y

- **yq** — Processeur YAML en ligne de commande (version Go de mikefarah, pas le paquet Debian). → [M02-E06](../modules/02-scripting/README.md)

## Z

- **Zone (DNS)** — Portion de l'espace de noms gérée par un même ensemble de serveurs faisant autorité, avec son SOA et ses NS. → [M06-E06](../modules/06-services-socle/README.md)
- **Zone parente** — Zone qui contient la délégation d'une sous-zone ; `medisphere.internal` délègue `par1.medisphere.internal`. → [M06-E06](../modules/06-services-socle/README.md)
