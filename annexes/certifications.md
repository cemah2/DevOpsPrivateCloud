# Certifications et exercices du workbook

> Le workbook ne prépare pas à une certification : il forme au métier. Mais une bonne partie de ses exercices recouvre les domaines des examens du secteur. Ce fichier indique, **pour chaque certification**, les domaines officiels et les exercices qui les entraînent. Il est complété à la fin de chaque bloc.
>
> Domaines relevés le 7 octobre 2026 sur les pages officielles des éditeurs (liens en fin de section). Ils changent régulièrement : vérifie la version en vigueur avant de t'inscrire. Les correspondances sont **indicatives** : un exercice « couvre » un domaine quand il y fait pratiquer un geste de l'examen, pas quand il en parle. Les examens pratiques (LFCS, RHCSA, RHCE, CKA) demandent en plus de la **vitesse** : refais les exercices `CHRONO` et les `BF` sans indice.

État : **blocs A et B** (modules 00 à 11) renseignés ; blocs C à G et finaux à compléter. Domaines des certifications ajoutées au bloc B (COA, CCNA, Ceph) relevés le 8 octobre 2026.

## Vue d'ensemble

| Certification | Éditeur | Format | Couverture par le workbook | Où |
|---|---|---|---|---|
| LFCS — Linux Foundation Certified System Administrator | Linux Foundation | pratique, en ligne | large pour le réseau et le stockage (blocs A et B), conteneurs au bloc C | §1 |
| RHCSA — Red Hat Certified System Administrator (EX200, RHEL 10) | Red Hat | pratique | partielle : le workbook est surtout sur Debian, Rocky Linux 10 au M03 | §2 |
| RHCE — Red Hat Certified Engineer (EX294) | Red Hat | pratique (Ansible) | large pour Ansible (M04, M06), appliqué à grande échelle au bloc B | §3 |
| HashiCorp Terraform Associate (004) | HashiCorp | QCM | large pour les concepts, avec OpenTofu (M05) | §4 |
| GitLab Certified Git Associate / CI/CD Associate | GitLab | QCM (+ lab pratique pour CI/CD) | Git et forge (M01), CI de base (bloc A), CI avancée au M19 | §5 |
| COA — Certified OpenStack Administrator | OpenInfra Foundation | pratique, en ligne (3 h) | large (M10), sauf Swift | §6 |
| CCNA (200-301) | Cisco | QCM et simulations | partielle : les concepts L2/L3 et FHRP (M07), sur Linux et non sur IOS | §7 |
| Ceph : Red Hat Certified Specialist in Ceph Cloud Storage (EX260) | Red Hat | pratique | **examen retiré** ; programme couvert par M08 | §8 |
| Proxmox VE | Proxmox Server Solutions | formation avec attestation, sans examen | M00, M09 | §8 |
| CKA, CKAD, CKS | CNCF / Linux Foundation | pratique (Kubernetes) | à venir : blocs C à F | §9 |

---

## 1. LFCS — Linux Foundation Certified System Administrator

Examen pratique de 2 heures sur Ubuntu. Le module 00 **évalue** ces bases (E01, E02) plutôt qu'il ne les enseigne : le workbook s'adresse à un administrateur déjà confirmé. Les domaines ci-dessous sont ceux du programme en vigueur, avec leur poids.

| Domaine (poids) | Compétences de l'examen | Exercices du bloc A | Exercices du bloc B |
|---|---|---|---|
| **Operations Deployment** (25 %) | paramètres du noyau à chaud ; processus ; journaux ; tâches planifiées ; intégrité et disponibilité des ressources ; scripts de maintenance ; démarrage et services ; SELinux ; machines virtuelles ; moteurs de conteneurs | sysctl et routage : M00-E10, M03-E13 · services, journaux : M00-E06, M00-E40, M01-E30, M01-E37 · planification (timers systemd) : M00-E30, M02-E26, M02-E35, M02-E41 · mises à jour maîtrisées : M00-E34, M03-E13 · scripts : M02-E03, M02-E10 à E14, M02-E27 à E30, M02-E39, M02-E44 · démarrage : M00-E44, M03-E22, M03-E23 · SELinux : M03-E06, M03-E25 · VMs : M00-E11, M00-E12, M00-E18, M00-E19 · conteneurs : *module 12* | paramètres du noyau (`sysctl`, conntrack) : M07-E27, M07-E41 · KVM imbriqué (module et paramètre du noyau) : M09-E02 · VMs : M09-E07, M09-E11, M09-E23 · démarrage réseau et installation : M11-E03, M11-E04, M11-E05 · conteneurs vus en exploitation (Podman, Docker) : M08-E03, M10-E20 · journaux et services : M07-E22, M10-E20 · SELinux sur Rocky : M08-E02 |
| **Networking** (25 %) | adressage IPv4/IPv6 et résolution de noms ; temps synchronisé ; diagnostic réseau ; OpenSSH serveur et client ; filtrage, redirection de ports, NAT ; routage statique ; ponts et agrégats ; reverse proxies et répartiteurs de charge | adressage et résolution : M00-E10, M00-E12, M00-E13, M03-E11, M06-E06 à E08 · temps : M00-E31, M00-E45, M06-E21 · diagnostic : M00-E38 à E43, M00-E47, M06-E35 · OpenSSH : M00-E15, M00-E27, M01-E40, M04-E11, M06-E19, M06-E20 · nftables, NAT : M00-E10, M00-E26, M00-E38, M04-E17, M06-E30 · routage statique, tunnels : M00-E16, M00-E21 · ponts : M00-E09, M00-E28 · agrégats, reverse proxies, répartiteurs : voir bloc B | adressage et cartographie : M07-E02 · diagnostic : M07-E20, M07-E38, M07-E41, M07-E44, M11-E23 · OpenSSH (commande forcée) : M07-E29 · filtrage, NAT, redirection de ports : M07-E13, M07-E26, M07-E30 · routage statique puis dynamique : M07-E06, M07-E07, M07-E14, M07-E19 · **ponts et agrégats** : M07-E04, M07-E05, M07-E17, M07-E40 · **reverse proxies et répartiteurs** : M07-E10, M07-E11, M07-E12, M07-E13, M07-E28, M07-E39 · tunnels : M07-E18 |
| **Storage** (20 %) | LVM ; système de fichiers virtuel ; création, gestion et dépannage des systèmes de fichiers ; systèmes de fichiers distants et périphériques bloc réseau ; swap ; automontage ; performances | LVM, LVM-thin, systèmes de fichiers : M00-E07, M00-E19, M00-E44 · performances : M00-E48 · partitionnement automatisé : M03-E05, M03-E06 · NFS, iSCSI, Ceph : voir bloc B · swap et automontage : non pratiqués (révision personnelle) | **systèmes de fichiers distants et périphériques bloc réseau** : M08-E06 (RBD), M08-E10 (CephFS), M08-E16 (NFS), M08-E17 (iSCSI), M08-E41 · ZFS et chiffrement LUKS : M08-E08, M08-E27 · montages persistants : M08-E06, M08-E10 · performances : M08-E28, M08-E42 · swap et automontage : toujours non pratiqués |
| **Essential Commands** (20 %) | opérations Git de base ; créer, configurer et dépanner des services ; performances ; contraintes propres aux applications ; espace disque ; certificats SSL | Git : M01-E02, M01-E07, M01-E08, M01-E12, M01-E13, M01-E18, M01-E19, M01-E41, M01-E44 · services en panne : M01-E37, M04-E40, M06-E39 · performances : M00-E48, M02-E40, M04-E26, M04-E41 · espace disque, nettoyage : M02-E37, M01-E45 · certificats : M01-E04, M06-E02, M06-E03, M06-E18, M06-E27, M06-E37 | services en panne : M07-E39, M10-E42, M11-E19 · espace disque (seuils de remplissage) : M08-E20, M08-E37 · certificats : M07-E12, M08-E11, M10-E27, M11-E13 |
| **Users and Groups** (10 %) | comptes et groupes locaux ; profils d'environnement ; limites de ressources ; ACL ; comptes LDAP | comptes locaux par le code : M04-E14 (rôle `base`), `sudo` : M00-E10, M02-E29 · environnement d'exécution (`PATH`, services, sudo) : M02-E35 · ACL POSIX, limites : non pratiquées · LDAP : *module 24* | — |

Source : [page officielle LFCS](https://training.linuxfoundation.org/certification/linux-foundation-certified-sysadmin-lfcs/) (domaines et compétences ; programme publié par la Linux Foundation).

## 2. RHCSA — Red Hat Certified System Administrator (EX200)

Examen pratique sur **RHEL 10**. Le workbook utilise Debian 13 par défaut ; la famille RHEL apparaît avec **Rocky Linux 10** (M03-E06, M03-E25) et le restera ponctuellement. Les gestes sont transposables, les outils diffèrent (`dnf`, `firewalld`, `nmcli`, SELinux) : la colonne de droite signale ce qu'il faut réviser spécifiquement sur RHEL.

| Domaine officiel | Exercices du bloc A | À réviser sur RHEL | Exercices du bloc B |
|---|---|---|---|
| Understand and use essential tools | M00-E01, M00-E02 (positionnement), M02-E03, M02-E12, M02-E44 | `man`, archives, redirections : supposés acquis | — |
| Manage software | M03-E06 (kickstart, dépôts), M03-E25 (mises à jour automatiques Rocky) ; Debian : M00-E06, M00-E34 | `dnf`, modules et flux d'applications, Flatpak | dépôts signés et paquets sur Rocky 10 : M08-E02 ; kickstart : M11-E05 |
| Create simple shell scripts | M02-E03, M02-E10, M02-E13, M02-E39 | — | M08-E24 (sonde), M11-E08 |
| Operate running systems | M00-E44, M03-E04, M03-E22, M03-E23, M02-E30 | cibles systemd, `rd.break`/récupération du mot de passe root, `tuned` | M08-E02 (Rocky 10 par le code) |
| Configure local storage | M00-E07, M00-E19 | partitions GPT, LVM classique, Stratis | — |
| Create and configure file systems | M00-E07 | XFS, montages persistants par UUID, NFS, autofs | montages réseau persistants : M08-E06, M08-E10, M08-E16 |
| Deploy, configure, and maintain systems | M00-E31, M02-E26, M03-E05, M03-E06, M03-E13 | `chronyd`, `cron`/`at`, cible par défaut | installation automatisée : M11-E05, M11-E15 |
| Manage basic networking | M00-E10, M00-E12, M03-E11 | `nmcli`, NetworkManager | `nmcli` sur Rocky 10 : M08-E02 |
| Manage users and groups | M04-E14 | `useradd`, politiques de mot de passe (`chage`) | — |
| Manage security | M00-E27, M03-E06, M03-E13, M06-E19 | `firewalld`, contextes et booléens SELinux, `restorecon`, `semanage` | SELinux, firewalld : M08-E02, M11-E05 |

Source : [EX200, page officielle Red Hat](https://www.redhat.com/en/services/training/ex200-red-hat-certified-system-administrator-rhcsa-exam).

## 3. RHCE — Red Hat Certified Engineer (EX294, Ansible)

Examen pratique d'automatisation avec Ansible (page officielle relevée : objectifs fondés sur RHEL 9 ; vérifie si une version RHEL 10 est publiée). Le module 04 couvre l'essentiel ; le module 06 l'applique à des services réels. L'examen utilise **Ansible Automation Platform** et ses outils (`ansible-navigator`, environnements d'exécution) : le workbook travaille avec `ansible-core` dans un environnement `uv`, révise ces outils à part.

| Domaine officiel | Exercices du bloc A | Exercices du bloc B |
|---|---|---|
| Perform all tasks expected of an RHCSA | voir §2 | voir §2 |
| Understand core components of Ansible (inventaires, modules, variables, faits, boucles, conditions, plays, handlers, plugins) | M04-E01, M04-E03 à E09, M04-E14, M04-E45 | M07-E03 (inventaire Proxmox par étiquettes), M08-E02, M10-E03 |
| Configure Ansible (`ansible.cfg`, inventaires statiques et dynamiques) | M04-E02, M04-E03, M04-E13, M06-E12 | M07-E03, M08-E02 (source d'inventaire NetBox dédiée), M10-E03 (`ansible.cfg` du projet Kolla) |
| Configure Ansible managed nodes ; SSH keys ; privilege escalation | M04-E03, M04-E04, M04-E11, M04-E35 | M09-E03 (connexion root aux nœuds), M10-E02 |
| Deploy files to managed nodes | M04-E05, M04-E07, M04-E08 | M07-E12, M10-E20 (surcharges de configuration) |
| Run playbooks (simulation, limites, tags) | M04-E05, M04-E19, M04-E25 | M07-E25, M09-E19 (`serial`, un nœud à la fois) |
| Perform basic source control operations using Git | M01-E02 à E13 | — |
| Be familiar with Visual Studio Code | non couvert (le workbook n'impose pas d'éditeur) | — |
| Create Ansible plays and playbooks (gestion d'erreurs, conditions, boucles, handlers) | M04-E05 à E08, M04-E14, M04-E15, M04-E23, M04-E25 | M07-E16, M07-E24, M09-E18, M11-E15 |
| Use roles and Ansible Content Collections | M04-E10, M04-E11, M04-E16, M04-E17, M04-E18, M04-E24, M06-E02, M06-E04, M06-E06, M06-E16 | rôles `frr`, `keepalived`, `haproxy`, `conntrackd` (Molecule) : M07-E06, M07-E08, M07-E10, M07-E27 ; `ceph_noeud` : M08-E02 ; `pve_noeud` : M09-E03 ; `pxe` : M11-E02 |
| Automate standard RHCSA tasks using Ansible modules (paquets, services, pare-feu, stockage, fichiers, utilisateurs, tâches planifiées) | M04-E10, M04-E11, M04-E14, M04-E17, M06-E21, M06-E28 | M08-E02, M09-E03, M11-E02 |
| Manage content (templates Jinja2, Ansible Vault) | M04-E07, M04-E12, M04-E30, M04-E38 | gabarits Jinja2 : M07-E25, M11-E06 ; Vault : M07-E18, M10-E03 |
| Chronométré, sans corrigé | M04-E34 (`CHRONO`), M04-E43 (astreinte) | M07-E34, M08-E34, M09-E34, M10-E34 |

Source : [EX294, page officielle Red Hat](https://www.redhat.com/en/services/training/ex294-red-hat-certified-engineer-rhce-exam-red-hat-enterprise-linux).

## 4. HashiCorp Terraform Associate (004)

QCM sur **Terraform**. Le workbook utilise **OpenTofu** (fork libre de Terraform 1.5, voir M05, introduction) : langage, commandes, état et providers sont communs pour l'essentiel, et les exercices du module 05 préparent donc aux objectifs 1 à 7. Attention aux écarts : l'examen interroge sur **HCP Terraform** (objectif 8), absent du workbook, et ignore ce qui est propre à OpenTofu (chiffrement de l'état côté client, méta-argument `enabled`, extension `.tofu`). Commandes : remplace `tofu` par `terraform`.

| Objectif officiel | Exercices du bloc A | Exercices du bloc B |
|---|---|---|
| 1. Infrastructure as Code (IaC) with Terraform | M05-E01, M05-E09, M05-E30 | M07-E03, M09-E18 |
| 2. Terraform fundamentals (providers, versions, état) | M05-E03, M05-E05, M05-E31, M05-E44 | M10-E15 (provider OpenStack) |
| 3. Core Terraform workflow (`init`, `validate`, `plan`, `apply`, `destroy`, `fmt`) | M05-E02 à E05, M05-E20, M05-E22 | M07-E03, M08-E02, M09-E03 |
| 4. Terraform configuration (`resource`/`data`, références, variables et sorties, types, expressions, dépendances, conditions, données sensibles) | M05-E06, M05-E07, M05-E08, M05-E18, M05-E19, M05-E27 | M10-E15, M10-E31 |
| 5. Terraform modules (sources, portée, versions) | M05-E13, M05-E14 | `vm-noeud` : M08-E02 ; `openstack-env-app` : M10-E31 |
| 6. Terraform state management (backend local, verrou, backend distant, dérive) | M05-E05, M05-E11, M05-E12, M05-E28, M05-E36, M05-E40, M05-E42 | un état par environnement : M07-E03, M08-E02, M09-E03, M10-E02 |
| 7. Maintain infrastructure with Terraform (import, inspection de l'état, journaux détaillés) | M05-E16, M05-E17, M05-E35, M05-E44 (`TF_LOG`) | M07-E46 (destruction et reconstruction de la maquette) |
| 8. HCP Terraform | non couvert ; l'équivalent auto-hébergé (pipeline plan/apply, verrou, workspaces) est M05-E15, M05-E24, M05-E26 | — |

Les secrets dans Vault (sous-objectif 4h) seront pratiqués au module 25.

Source : [Terraform Associate (004), objectifs officiels](https://developer.hashicorp.com/terraform/tutorials/certification-004/associate-review-004).

## 5. GitLab Certified Git Associate et CI/CD Associate

GitLab ne publie pas de programme détaillé en accès libre (pages de GitLab University réservées aux inscrits) : les thèmes ci-dessous sont ceux des descriptions officielles. La CI/CD Associate comprend en plus un **lab pratique** noté par les équipes de GitLab.

| Thème | Exercices du bloc A | Exercices du bloc B |
|---|---|---|
| Git : dépôts, commits, branches, fusion, rebase, historique, annulation | M01-E02, M01-E07, M01-E08, M01-E12, M01-E13, M01-E18, M01-E19, M01-E44, M01-E46 | — |
| GitLab : groupes, projets, droits, branches protégées, merge requests et revue | M01-E05, M01-E06, M01-E10, M01-E11, M01-E20, M01-E21 | dépôt d'équipe en libre-service : M10-E31 |
| CI/CD : `.gitlab-ci.yml`, stages, jobs, runners, variables protégées, artefacts, `include` | M01-E23, M01-E24, M01-E25, M02-E24, M03-E15, M04-E27, M05-E26 | validation et détection de dérive : M08-E23, M11-E06 ; invariants et déploiement tracé : M10-E46 ; pipeline de provisioning : M11-E15 |
| CI/CD avancée : `rules`, `needs`, environnements, caches, runners Kubernetes | *module 19* | — |

Sources : [GitLab Certified Git Associate](https://university.gitlab.com/courses/gitlab-with-git-essentials-certification-exam), [GitLab Certified CI/CD Associate](https://about.gitlab.com/services/education/gitlab-cicd-associate/).

## 6. COA — Certified OpenStack Administrator

Examen pratique de 3 heures, en ligne et surveillé, proposé par l'**OpenInfra Foundation** (sa seule certification) : ligne de commande `openstack` et Horizon sur un cloud fourni. La page officielle ne précise pas la série d'OpenStack de l'examen (vérifie-la avant de t'inscrire) ; le workbook utilise 2026.1. L'examen ne demande **pas** de déployer OpenStack : tout ce que fait Kolla-Ansible (M10-E02 à E04, E20, E24, E28, E29) va au-delà. Un écart important : l'objet de l'examen est **Swift**, celui du workbook est le S3 de Ceph (RGW, M08) ; révise le client `swift` / `openstack container` à part.

| Domaine (poids) | Compétences de l'examen | Exercices du bloc B |
|---|---|---|
| **OpenStack APIs** | Horizon ; client en ligne de commande | M10-E05, M10-E17 (Horizon), tous les `LAB` du module (CLI) |
| **Identity management** (15 %) | domaines, projets, utilisateurs, rôles ; `member` et `admin` ; politiques et règles d'accès ; fichiers RC | M10-E05, M10-E13, M10-E23 (politiques, rôle `reader`), M10-E04 (`admin-openrc.sh`, `clouds.yaml`), M10-E39 |
| **Compute** (35 %) | gabarits ; cycle de vie des instances ; clés SSH ; IP flottante ; groupes de sécurité ; consoles (noVNC) ; instantanés d'instance ; quotas | M10-E07 (gabarits, clés, console), M10-E08, M10-E13 (quotas, gabarits privés), M10-E19, M10-E35 · instantanés d'**instance** : non pratiqués (ceux des volumes le sont, M10-E11) |
| **Object Storage** (5 %) | conteneurs Swift, envoi de fichiers, droits | non couvert (stockage objet par RGW S3 : M08-E11, M08-E12) |
| **Block Storage** (10 %) | volumes, attachement, montage dans l'instance, quotas, sauvegarde et restauration, instantanés | M10-E10, M10-E11, M10-E13, M10-E38 |
| **Networking** (30 %) | réseaux, sous-réseaux, routeurs ; réseau externe ; réseaux et routeurs de projet ; quotas réseau ; interfaces des instances ; groupes de sécurité ; IP flottantes | M10-E08, M10-E12, M10-E13, M10-E16, M10-E36, M10-E44 |
| **Image management** (5 %) | envoi d'images, gestion, visibilité, métadonnées et propriétés, formats et backends | M10-E06 (propriétés, sommes), M10-E10 (backend Ceph, format `raw`), M10-E41 |
| Chronométré, sans corrigé | — | M10-E34 (environnement complet en temps limité), M10-E43 (astreinte) |

Source : [exigences officielles du COA](https://openstack.org/coa/requirements) et [page de l'examen](https://openstack.org/coa) (OpenInfra Foundation).

## 7. CCNA (200-301) — Cisco

QCM et simulations sur **Cisco IOS**. Programme **v1.1** en vigueur jusqu'en février 2027 (Network Fundamentals 20 %, Network Access 20 %, IP Connectivity 25 %, IP Services 10 %, Security Fundamentals 15 %, Automation and Programmability 10 %) ; la **v2.0** est passable à partir du 3 février 2027 (Network Infrastructure and Connectivity 25 %, Switching and Network Access 25 %, IP Routing 20 %, Network Services and Security 20 %, AI, and Network Operations and Management 10 %). Le workbook pratique les **mêmes concepts** sur Linux (pont, bonds, Open vSwitch, FRR, keepalived, nftables) : utile pour comprendre, insuffisant pour l'examen, qui interroge la syntaxe IOS, le Spanning Tree, le Wi-Fi et HSRP. BGP n'est au programme d'aucune des deux versions.

| Thème (commun aux deux versions) | Exercices du bloc B |
|---|---|
| Adressage, sous-réseaux, MTU | M07-E01, M07-E02, M07-E15, M07-E38 |
| Commutation : VLAN, trunks, EtherChannel/LACP | M07-E04, M07-E05, M07-E17, M07-E40 |
| Routage : table, statique, OSPF, FHRP (VRRP) | M07-E06, M07-E08, M07-E25, M07-E44 |
| Services : NAT, relais DHCP | M07-E26, M11-E02 |
| Sécurité : filtrage, VPN | M07-E18, M07-E30 |
| Automatisation de la configuration réseau | M07-E16, M07-E24 |

Sources : [CCNA v1.1, sujets officiels](https://learningcontent.cisco.com/documents/marketing/exam-topics/200-301-CCNA-v1.1.pdf), [CCNA v2.0, sujets officiels](https://learningcontent.cisco.com/documents/marketing/exam-topics/200-301_CCNA_v2.0_Exam_Topics_PDF.pdf) (Cisco).

## 8. Ceph et Proxmox VE

**Ceph.** Red Hat a **retiré** l'examen *Red Hat Certified Specialist in Ceph Cloud Storage* (EX260) ; aucune autre certification Ceph d'un éditeur reconnu n'est en vigueur à la date du relevé. Son programme (fondé sur Red Hat Ceph Storage, cours CL260) reste une bonne grille : le module 08 en couvre l'essentiel avec Ceph amont (cephadm).

| Objectif de l'ancien EX260 | Exercices du bloc B |
|---|---|
| Installer et configurer un cluster | M08-E02, M08-E03, M08-E04, M09-E10 |
| Bloc (RBD) | M08-E06, M08-E39 |
| Objet (RADOS Gateway) | M08-E11, M08-E12, M08-E40 |
| Fichier (CephFS) | M08-E10, M08-E41 |
| Carte CRUSH, cartes du cluster | M08-E14, M08-E15, M08-E36, M08-E44 |
| Gérer et mettre à jour le cluster | M08-E07, M08-E18, M08-E19, M08-E20, M08-E26, M09-E28 |
| Régler les performances | M08-E28, M08-E29, M08-E42 |
| Dépanner | M08-E35 à E43 |
| Intégration avec OpenStack | M10-E10, M10-E11 |

Source : [EX260 (retiré), page Red Hat](https://www.redhat.com/en/services/training/retired-ex260-red-hat-certified-specialist-in-ceph-cloud-storage-exam).

**Proxmox VE.** Proxmox Server Solutions ne propose pas d'examen : ses formations officielles (*Proxmox VE Deployment and Management*, *Proxmox VE Clustering and Shared Storage*) délivrent un certificat de fin de formation. Le module 00 recouvre en partie la première, le module 09 la seconde (cluster, quorum, HA, Ceph hyperconvergé, réplication, sauvegarde : M09-E04 à M09-E15). Source : [FAQ des formations Proxmox](https://proxmox.com/en/training/faqs).

## 9. À compléter aux blocs suivants

| Certification | Domaines officiels | Bloc concerné |
|---|---|---|
| **CKA** (programme v1.35) | Cluster Architecture, Installation & Configuration · Workloads & Scheduling · Services & Networking · Storage · Troubleshooting | C (14-18), à relever au démarrage du bloc C sur [cncf/curriculum](https://github.com/cncf/curriculum) |
| **CKAD** | à relever | C, D |
| **CKS** | à relever | F (26) |
| **LFCS** (compléments) | conteneurs, swap, automontage, ACL, LDAP | C (12), F (24) |
| **Vault Associate**, **Prometheus Certified Associate**, **Certified Argo Project Associate**… | à relever si pertinents | D, E, F |
