# Certifications et exercices du workbook

> Le workbook ne prépare pas à une certification : il forme au métier. Mais une bonne partie de ses exercices recouvre les domaines des examens du secteur. Ce fichier indique, **pour chaque certification**, les domaines officiels et les exercices qui les entraînent. Il est complété à la fin de chaque bloc.
>
> Domaines relevés le 7 octobre 2026 sur les pages officielles des éditeurs (liens en fin de section). Ils changent régulièrement : vérifie la version en vigueur avant de t'inscrire. Les correspondances sont **indicatives** : un exercice « couvre » un domaine quand il y fait pratiquer un geste de l'examen, pas quand il en parle. Les examens pratiques (LFCS, RHCSA, RHCE, CKA) demandent en plus de la **vitesse** : refais les exercices `CHRONO` et les `BF` sans indice.

État : **blocs A à G** (modules 00 à 29) renseignés. Les finaux F1 à F4 ne visent aucun domaine d'examen nouveau : ils remobilisent les exercices cités ici en conditions de production (reconstruction, accueil d'équipes, astreinte, changements). F5 à F7 ajoutent surtout des sujets **hors examens techniques** (continuité d'activité, système de management de la sécurité, protection des données, réponse à un appel d'offres), rattachés en culture aux certifications de personnes du domaine, et quelques gestes Kubernetes (§27). Domaines des certifications ajoutées au bloc B (COA, CCNA, Ceph) relevés le 8 octobre 2026 ; ceux des certifications Kubernetes (CKA, CKAD, CKS, KCNA, KCSA) le 15 octobre 2026 sur les programmes publiés par la CNCF ([cncf/curriculum](https://github.com/cncf/curriculum)) ; ceux des certifications des blocs D et E (PCA, OTCA, CAPA, CGOA) le 22 octobre 2026 sur les pages officielles de la CNCF et de la Linux Foundation ; ceux du HashiCorp Vault Associate (003) le 23 octobre 2026 sur la page officielle de HashiCorp ; ceux des certifications du bloc G (CBA, CNPA, CNPE, Confluent, EDB) le 23 octobre 2026 sur les pages officielles de la Linux Foundation, de Confluent et d'EDB.

## Vue d'ensemble

| Certification | Éditeur | Format | Couverture par le workbook | Où |
|---|---|---|---|---|
| LFCS — Linux Foundation Certified System Administrator | Linux Foundation | pratique, en ligne | large pour le réseau et le stockage (blocs A et B), moteurs de conteneurs (M12) | §1, §14 |
| RHCSA — Red Hat Certified System Administrator (EX200, RHEL 10) | Red Hat | pratique | partielle : le workbook est surtout sur Debian, Rocky Linux 10 au M03 | §2 |
| RHCE — Red Hat Certified Engineer (EX294) | Red Hat | pratique (Ansible) | large pour Ansible (M04, M06), appliqué à grande échelle au bloc B | §3 |
| HashiCorp Terraform Associate (004) | HashiCorp | QCM | large pour les concepts, avec OpenTofu (M05) | §4 |
| GitLab Certified Git Associate / CI/CD Associate | GitLab | QCM (+ lab pratique pour CI/CD) | Git et forge (M01), CI de base (bloc A), CI avancée et runners Kubernetes (M19) | §5 |
| COA — Certified OpenStack Administrator | OpenInfra Foundation | pratique, en ligne (3 h) | large (M10), sauf Swift | §6 |
| CCNA (200-301) | Cisco | QCM et simulations | partielle : les concepts L2/L3 et FHRP (M07), sur Linux et non sur IOS | §7 |
| Ceph : Red Hat Certified Specialist in Ceph Cloud Storage (EX260) | Red Hat | pratique | **examen retiré** ; programme couvert par M08 | §8 |
| Proxmox VE | Proxmox Server Solutions | formation avec attestation, sans examen | M00, M09 | §8 |
| CKA — Certified Kubernetes Administrator (programme v1.35) | CNCF / Linux Foundation | pratique, en ligne (2 h) | large : installation kubeadm, cycle de vie, réseau, stockage et dépannage (M14 à M17) ; autoscaling, priorités et quotas au M28 | §9, §23 |
| CKAD — Certified Kubernetes Application Developer (programme v1.37) | CNCF / Linux Foundation | pratique, en ligne (2 h) | large pour la conception, la configuration et le déploiement (M12, M14, M15, M17) ; Jobs, ressources et quotas complétés au bloc G | §10, §23 |
| CKS — Certified Kubernetes Security Specialist (programme v1.34) | CNCF / Linux Foundation | pratique, en ligne (2 h) ; CKA en cours de validité exigée | **large** : chaîne d'approvisionnement (M12, M13), RBAC, admission, audit, chiffrement (M14), politiques réseau (M15) ; OIDC et RBAC par groupes (M24), Secrets par coffre (M25), CIS, PSA, Kyverno, Falco, Tetragon, chiffrement et pare-feu des nœuds (M26) ; conteneurs isolés (gVisor, Kata) seulement discutés | §11, §21 |
| KCNA et KCSA — Kubernetes and Cloud Native (Security) Associate | CNCF / Linux Foundation | QCM en ligne | KCNA : largement couvert par le bloc C ; KCSA : largement couvert avec le bloc F | §12, §21 |
| DCA — Docker Certified Associate | Mirantis | QCM | partielle : M12, M13 ; Swarm et produits d'entreprise de Mirantis non couverts | §13 |
| PCA — Prometheus Certified Associate | CNCF / Linux Foundation | QCM en ligne (90 min) | large (M21), notions d'observabilité complétées par M22 et M23 | §15 |
| OTCA — OpenTelemetry Certified Associate | CNCF / Linux Foundation | QCM en ligne | large pour le Collector et les SDK (M23) | §16 |
| CAPA — Certified Argo Project Associate | CNCF / Linux Foundation | QCM en ligne | Argo CD et Argo Rollouts (M20) ; **Argo Workflows et Argo Events non couverts** (près de la moitié de l'examen) | §17 |
| CGOA — GitOps Certified Associate | CNCF / Linux Foundation | QCM en ligne | large (M20, avec Flux en comparaison) | §18 |
| CBA — Certified Backstage Associate | CNCF / Linux Foundation | QCM en ligne (90 min) | partielle : installation, configuration, catalogue, TechDocs, modèles (M28) ; développement de plugins en React peu pratiqué | §24 |
| CNPA — Certified Cloud Native Platform Engineering Associate | CNCF / Linux Foundation | QCM en ligne (120 min) | large pour les notions (blocs D à G, M28 en tête) ; indicateurs DORA et IA seulement évoqués | §25 |
| CNPE — Certified Cloud Native Platform Engineer | CNCF / Linux Foundation | pratique, en ligne (2 h) | partielle : GitOps, observabilité, politiques, multi-locataire (blocs D à G) ; API de plateforme par CRD maison et cadres d'automatisation (Crossplane) non pratiqués | §25 |
| CCDAK et CCAAK — Confluent Certified Developer / Administrator for Apache Kafka | Confluent | QCM en ligne (90 min) | **faible** : Kafka n'est qu'un essai (M27-E09, E10) | §26 |
| EDB : Essentials for CloudNativePG, Essentials / Advanced for PostgreSQL | EDB | examen associé à une formation EDB | partielle : CloudNativePG (M16, M27) ; l'administration de PostgreSQL elle-même n'est pas le sujet du workbook | §26 |
| HashiCorp Certified: Vault Associate (003) | HashiCorp | QCM en ligne | **équivalence seulement** : le workbook pratique **OpenBao** (fork MPL 2.0 de Vault), pas Vault ; concepts, CLI et API quasi identiques, mais l'examen porte sur Vault et ses fonctions Enterprise/HCP (M25 ; Vault 2.2 en comparaison au M25-E30) | §22 |
| ISO/IEC 27001 Lead Implementer / Lead Auditor ; continuité (ISO 22301, BCI, DRI) ; DPO | organismes de certification de personnes (PECB, BSI, AFNOR…), BCI, DRI, organismes agréés par la CNIL | selon l'organisme | **en culture seulement** : les scénarios des finaux F5 (PRA) et F6 (audit, incident, notifications) en font pratiquer les livrables, pas le programme | §27 |

---

## 1. LFCS — Linux Foundation Certified System Administrator

Examen pratique de 2 heures sur Ubuntu. Le module 00 **évalue** ces bases (E01, E02) plutôt qu'il ne les enseigne : le workbook s'adresse à un administrateur déjà confirmé. Les domaines ci-dessous sont ceux du programme en vigueur, avec leur poids.

| Domaine (poids) | Compétences de l'examen | Exercices du bloc A | Exercices du bloc B |
|---|---|---|---|
| **Operations Deployment** (25 %) | paramètres du noyau à chaud ; processus ; journaux ; tâches planifiées ; intégrité et disponibilité des ressources ; scripts de maintenance ; démarrage et services ; SELinux ; machines virtuelles ; moteurs de conteneurs | sysctl et routage : M00-E10, M03-E13 · services, journaux : M00-E06, M00-E40, M01-E30, M01-E37 · planification (timers systemd) : M00-E30, M02-E26, M02-E35, M02-E41 · mises à jour maîtrisées : M00-E34, M03-E13 · scripts : M02-E03, M02-E10 à E14, M02-E27 à E30, M02-E39, M02-E44 · démarrage : M00-E44, M03-E22, M03-E23 · SELinux : M03-E06, M03-E25 · VMs : M00-E11, M00-E12, M00-E18, M00-E19 · conteneurs : voir §14 (bloc C) | paramètres du noyau (`sysctl`, conntrack) : M07-E27, M07-E41 · KVM imbriqué (module et paramètre du noyau) : M09-E02 · VMs : M09-E07, M09-E11, M09-E23 · démarrage réseau et installation : M11-E03, M11-E04, M11-E05 · conteneurs vus en exploitation (Podman, Docker) : M08-E03, M10-E20 · journaux et services : M07-E22, M10-E20 · SELinux sur Rocky : M08-E02 |
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

| Thème | Exercices du bloc A | Exercices du bloc B | Exercices du bloc D |
|---|---|---|---|
| Git : dépôts, commits, branches, fusion, rebase, historique, annulation | M01-E02, M01-E07, M01-E08, M01-E12, M01-E13, M01-E18, M01-E19, M01-E44, M01-E46 | — | — |
| GitLab : groupes, projets, droits, branches protégées, merge requests et revue | M01-E05, M01-E06, M01-E10, M01-E11, M01-E20, M01-E21 | dépôt d'équipe en libre-service : M10-E31 | MR de promotion approuvées : M19-E17 ; montée de version de l'instance : M19-E26 |
| CI/CD : `.gitlab-ci.yml`, stages, jobs, runners, variables protégées, artefacts, `include` | M01-E23, M01-E24, M01-E25, M02-E24, M03-E15, M04-E27, M05-E26 | validation et détection de dérive : M08-E23, M11-E06 ; invariants et déploiement tracé : M10-E46 ; pipeline de provisioning : M11-E15 | modèle d'exécution : M19-E05, M19-E09 ; variables, artefacts, rapports : M19-E07, M19-E13 ; services de job : M19-E14 ; secrets (`CI_JOB_TOKEN`, jetons d'identité) : M19-E25, M19-E40 |
| CI/CD avancée : `rules`, `needs`, `workflow`, pipelines enfants et multi-projets, environnements, caches, composants CI/CD | — | — | `rules`, `needs`, `workflow` : M19-E06, M19-E21 · caches et environnements : M19-E07, M19-E23, M19-E38 · pipelines enfants et multi-projets : M19-E12 · composants et catalogue : M19-E10, M19-E11, M19-E32 · déploiement (agent pour Kubernetes) : M19-E18 |
| Runners : enregistrement, étiquettes, exécuteurs, Kubernetes, capacité | `shell` : M01-E23 | — | M19-E04, M19-E24, M19-E27, M19-E35, M19-E36, M19-E42, M19-E44 |
| Sécurité de la chaîne (SAST, détection de secrets, analyse de dépendances) | Gitleaks : M01-E16 | — | M19-E15, M19-E29 |
| Chronométré, sans corrigé | — | — | M19-E34, M19-E43 |

Le lab pratique de la CI/CD Associate se passe sur GitLab.com, avec les runners de l'instance : les runners auto-hébergés et l'exécuteur Kubernetes (M19-E04 à E05, E24, E27) vont au-delà. Les environnements protégés et les approbations de déploiement (édition Premium) ne sont pas pratiqués (ADR-0051).

Sources : [GitLab Certified Git Associate](https://university.gitlab.com/courses/gitlab-with-git-essentials-certification-exam), [GitLab Certified CI/CD Associate](https://about.gitlab.com/services/education/gitlab-cicd-associate/), [examen CI/CD Associate (GitLab University)](https://university.gitlab.com/courses/gitlab-ci-cd-certification-exam).

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

## 9. CKA — Certified Kubernetes Administrator

Examen pratique de 2 heures, en ligne et surveillé, sur des clusters fournis (ligne de commande seulement, documentation de kubernetes.io autorisée). Programme **v1.35** de la CNCF (le workbook est en 1.36 : les écarts entre les deux versions ne touchent pas les gestes de l'examen). Le module 14 en est le cœur : `k8s-par1` est construit par kubeadm, en haute disponibilité, puis exploité, monté de version et cassé. L'examen demande de la **vitesse** : refais M14-E34 (examen blanc) et les `BF` des modules 14 à 16 sans indice, et entraîne-toi à `kubectl` impératif (`create`, `expose`, `--dry-run=client -o yaml`), que le workbook utilise peu (tout y passe par le code).

| Domaine (poids) | Compétences de l'examen | Exercices du bloc C |
|---|---|---|
| **Storage** (10 %) | classes de stockage et provisionnement dynamique ; types de volumes, modes d'accès, politiques de récupération ; PV et PVC | classes et provisionnement dynamique : M16-E03, M16-E06, M16-E07, M16-E12 · types de volumes, modes d'accès, `reclaimPolicy` : M16-E02, M16-E03, M16-E11 · PV et PVC : M16-E03, M16-E08, M16-E10, M16-E29 · dépannage : M16-E22, M16-E35, M16-E36, M16-E37 |
| **Troubleshooting** (30 %) | clusters et nœuds ; composants du cluster ; consommation de ressources ; sorties des conteneurs ; services et réseau | nœuds : M14-E22, M14-E35, M14-E36 · composants : M14-E39 (API), M14-E40 (etcd), M14-E29 · ressources (`kubectl top`, metrics-server) : M14-E20 · journaux des conteneurs : M14-E20, M14-E38 · services et réseau : M14-E42 (DNS), M15-E35, M15-E36, M15-E37, M15-E42 · astreintes : M14-E43, M15-E43, M16-E43 |
| **Workloads and Scheduling** (15 %) | déploiements, mises à jour progressives et retours arrière ; ConfigMaps et Secrets ; autoscaling ; primitives d'auto-réparation ; admission et ordonnancement (limites, affinités) | déploiements et retours arrière : M14-E07, M14-E16 · ConfigMaps et Secrets : M14-E08 · auto-réparation (sondes, StatefulSets, DaemonSets, PDB) : M14-E08, M14-E15, M14-E16 · ordonnancement (affinités, taints, répartition, priorités) : M14-E14, M14-E36 · limites et admission : M14-E10, M14-E18 · **autoscaling** (HPA) : non pratiqué au bloc C (module 28) |
| **Cluster Architecture, Installation and Configuration** (25 %) | RBAC ; préparer l'infrastructure ; créer et gérer un cluster avec kubeadm ; cycle de vie ; plan de contrôle hautement disponible ; Helm et Kustomize pour installer des composants ; interfaces d'extension (CNI, CSI, CRI) ; CRD et opérateurs | RBAC : M14-E11, M14-E12, M14-E13, M14-E41 · préparer les nœuds : M14-E02 · kubeadm : M14-E04, M14-E05, M14-E17 · cycle de vie (montée de version, certificats, etcd) : M14-E24, M14-E25, M14-E26 · plan de contrôle HA : M14-E03, M14-E29 · Helm et Kustomize : M14-E20 (metrics-server par Helm), M17-E02, M17-E04, M17-E10, M17-E16 · CRI : M14-E02 ; CNI : M14-E05, M15-E09 ; CSI : M16-E04, M16-E44 · CRD et opérateurs : M15-E13 (cert-manager), M16-E13 (Rook), M16-E18 (CloudNativePG) |
| **Services and Networking** (20 %) | connectivité entre pods ; NetworkPolicy ; Services ClusterIP, NodePort, LoadBalancer et leurs points de terminaison ; Gateway API pour le trafic entrant ; contrôleurs et ressources Ingress ; CoreDNS | connectivité : M15-E02, M15-E05 · NetworkPolicy : M15-E06, M15-E17, M15-E28 · Services et EndpointSlices : M15-E03, M15-E10 · **Gateway API** : M15-E07, M15-E12, M15-E16 · Ingress : M15-E18 (migration d'Ingress vers la Gateway API ; ingress-nginx est retiré, l'examen garde les objets `Ingress`) · CoreDNS : M15-E04, M15-E36 |
| Chronométré, sans corrigé | — | M14-E34 (examen blanc d'administration), M15-E34, M16-E34, M17-E18 |

Source : [programme CKA v1.35 (CNCF)](https://github.com/cncf/curriculum) et [page de l'examen](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) (Linux Foundation).

## 10. CKAD — Certified Kubernetes Application Developer

Examen pratique de 2 heures, en ligne. Programme **v1.37**. Le point de vue est celui de l'équipe MédiAgenda : construire l'image, écrire les manifestes, configurer, exposer, déboguer. Le workbook le pratique côté plateforme ; ce qui manque surtout, c'est la vitesse d'écriture des manifestes à la main.

| Domaine (poids) | Compétences de l'examen | Exercices du bloc C |
|---|---|---|
| **Application Design and Build** (20 %) | construire et modifier des images ; choisir la bonne ressource (Deployment, DaemonSet, CronJob…) ; pods multi-conteneurs (init, sidecar) ; volumes persistants et éphémères | images : M12-E05, M12-E10, M12-E12 · ressources de charge : M14-E07, M14-E15 · conteneurs d'initialisation : M14-E15 · volumes : M16-E02, M16-E03, M16-E08 |
| **Application Deployment** (20 %) | stratégies de déploiement (bleu/vert, canari) ; Deployments et mises à jour progressives ; Helm pour déployer des paquets existants ; Kustomize | canari par poids de route : M15-E16 · mises à jour progressives : M14-E16 · Helm : M17-E02, M17-E06 · Kustomize : M17-E04, M17-E09 |
| **Application Observability and Maintenance** (15 %) | dépréciations d'API ; sondes et contrôles de santé ; outils CLI de surveillance ; journaux des conteneurs ; débogage | dépréciations (montée de version) : M14-E25, M14-E30 · sondes : M14-E08 · `kubectl top`, `events`, `logs`, `debug` : M14-E20 · débogage : M14-E37, M14-E38 |
| **Application Environment, Configuration and Security** (25 %) | ressources d'extension (CRD, opérateurs) ; authentification, autorisation, admission ; demandes, limites, quotas ; ConfigMaps ; Secrets ; ServiceAccounts ; sécurité applicative (`securityContext`, capacités) | CRD et opérateurs : M15-E13, M16-E18 · authentification, RBAC, admission : M14-E11, M14-E12, M14-E18 · demandes, limites, quotas : M14-E08, M14-E10, M16-E20 · ConfigMaps et Secrets : M14-E08, M17-E15 · ServiceAccounts : M14-E13 · `securityContext` et capacités : M14-E08, M14-E18, M12-E24 |
| **Services and Networking** (20 %) | NetworkPolicy ; accès aux applications par les Services ; règles Ingress | NetworkPolicy : M15-E06, M15-E17 · Services : M15-E03, M15-E35 · exposition : M15-E07 (Gateway API), M15-E18 (Ingress) |

Source : [programme CKAD v1.37 (CNCF)](https://github.com/cncf/curriculum).

## 11. CKS — Certified Kubernetes Security Specialist

Examen pratique de 2 heures, en ligne, qui exige une **CKA en cours de validité**. Programme **v1.34**. Le bloc C en couvre une bonne moitié : la chaîne d'approvisionnement (M12, M13), le contrôle d'accès, l'admission, l'audit et le chiffrement (M14), les politiques réseau et le chiffrement entre nœuds (M15). La sécurité à l'exécution (Falco, Tetragon), Kyverno, kube-bench et kubescape en profondeur, AppArmor dans Kubernetes et les conteneurs isolés (gVisor, Kata) arrivent au **module 26** (bloc F) : la colonne de droite dit ce qui restait après le bloc C ; les exercices du bloc F qui les couvrent sont au §21.

| Domaine (poids) | Exercices du bloc C | À venir (bloc F) |
|---|---|---|
| **Cluster Setup** (15 %) : NetworkPolicy au niveau du cluster ; référentiel CIS des composants ; Ingress en TLS ; métadonnées et points d'accès des nœuds ; vérifier les binaires avant déploiement | NetworkPolicy et politique de base du cluster : M15-E06, M15-E28 · TLS de l'entrée : M15-E12, M15-E33 · référentiel CIS (kube-bench, comparé entre distributions) : M18-E15 · binaires vérifiés (signature et empreinte) : M13-E05, M14-E02 | CIS appliqué à `k8s-par1` (M26) ; métadonnées des nœuds (sans objet dans un lab sans nuage public, à réviser) |
| **Cluster Hardening** (15 %) : RBAC minimal ; comptes de service (désactiver les jetons par défaut, droits minimaux) ; restreindre l'accès à l'API ; monter de version | RBAC : M14-E11, M14-E41 · comptes de service et jetons liés : M14-E13 · accès à l'API (VIP interne, certificats courts, bris de glace) : M14-E03, M14-E06, M14-E12 · montée de version : M14-E25 | OIDC pour Kubernetes (M24) |
| **System Hardening** (10 %) : réduire l'empreinte du système hôte ; identités à moindre privilège ; limiter l'accès réseau externe ; AppArmor, seccomp | OS minimal et immuable : M18-E05 (Talos), M18-E04 (profil CIS de RKE2) · moindre privilège : M13-E03 (robots), M14-E11 · sortie limitée : M15-E28 (`toFQDNs`), M15-E32 · seccomp, capacités, SELinux : M12-E24, M12-E25 | profils AppArmor et seccomp dans les pods (M26) |
| **Minimize Microservice Vulnerabilities** (20 %) : Pod Security Standards ; Secrets ; isolation (multi-locataire, conteneurs isolés) ; chiffrement de pod à pod (Cilium, Istio) | Pod Security Admission : M14-E18 · Secrets chiffrés au repos : M14-E28, M17-E15 · multi-équipes : M14-E33, M15-E28 · chiffrement entre nœuds (WireGuard de Cilium) : M15-E24 · espaces de noms utilisateur : M12-E26 | Vault et External Secrets (M25) ; gVisor ou Kata (M26) |
| **Supply Chain Security** (20 %) : image de base minimale ; connaître sa chaîne (SBOM, CI/CD, dépôts d'artefacts) ; sécuriser la chaîne (registres autorisés, signer et valider) ; analyse statique des charges et des images | images minimales : M12-E10, M12-E27 · SBOM et provenance : M13-E06, M13-E08 · chaîne de livraison : M13-E09 · registres autorisés : M14-E18 (ValidatingAdmissionPolicy `medisphere-images`), M14-E19 · signature exigée : M13-E07, M13-E14, M17-E08 · analyse statique : M12-E16 (Hadolint), M13-E05 (Trivy), M15-E21 et M16-E23 (kubeconform) | vérification de signature à l'admission (Kyverno, M26) |
| **Monitoring, Logging and Runtime Security** (20 %) : analyse comportementale ; menaces ; phases d'une attaque ; immuabilité des conteneurs à l'exécution ; journaux d'audit | journaux d'audit : M14-E27 · racine en lecture seule : M12-E24, M14-E08 | Falco, Tetragon, réponse à incident (M26, F6) |

Source : [programme CKS v1.34 (CNCF)](https://github.com/cncf/curriculum).

## 12. KCNA et KCSA

QCM en ligne, sans manipulation. **KCNA** (*Kubernetes and Cloud Native Associate*) vérifie les notions ; le bloc C les pratique toutes, au-delà de ce que demande l'examen. **KCSA** (*Kubernetes and Cloud Native Security Associate*) est le pendant théorique de la CKS : le bloc C en couvre la moitié, le bloc F le reste. Révise surtout le vocabulaire et l'écosystème de la CNCF, que le workbook n'aborde que par ce qu'il utilise. Les compléments du bloc F sont au §21.

| Domaine KCNA (poids) | Exercices du bloc C |
|---|---|
| **Kubernetes Fundamentals** (44 %) : concepts, administration, ordonnancement, conteneurs | M12-E03, M12-E04, M12-E09 · M14-E04 à M14-E09, M14-E14 |
| **Container Orchestration** (28 %) : réseau, sécurité, dépannage, stockage | M15-E02, M15-E03, M15-E06 · M14-E11, M14-E18 · M14-E20 · M16-E03, M16-E04 |
| **Cloud Native Application Delivery** (16 %) : livraison, débogage | M17-E02, M17-E04, M17-E10 · M14-E20 ; GitOps au module 20 |
| **Cloud Native Architecture** (12 %) : observabilité, écosystème, communauté | M15-E05 (Hubble), M18-E01 (panorama des distributions) ; observabilité au bloc E |

| Domaine KCSA (poids) | Exercices du bloc C | À venir |
|---|---|---|
| **Overview of Cloud Native Security** (14 %) : les 4C, isolation, dépôts d'artefacts et images, sécurité du code | M12-E24, M12-E26, M13-E01, M13-E14 | — |
| **Kubernetes Cluster Component Security** (22 %) : API server, contrôleurs, ordonnanceur, kubelet, runtime, kube-proxy, etcd, réseau, stockage | M14-E26 (certificats, `serverTLSBootstrap`), M14-E27, M14-E28, M14-E24, M15-E24, M16-E26 | — |
| **Kubernetes Security Fundamentals** (22 %) : Pod Security, authentification, Secrets, isolation, audit, NetworkPolicy | M14-E18, M14-E12, M14-E13, M14-E28, M14-E33, M14-E27, M15-E06 | — |
| **Kubernetes Threat Model** (16 %) : frontières de confiance, persistance, déni de service, code malveillant, attaquant sur le réseau, données sensibles, élévation de privilèges | M13-E24, M14-E45, M15-E45 (questions expert) | F6 (réponse à incident) |
| **Platform Security** (16 %) : chaîne d'approvisionnement, dépôt d'images, observabilité, maillage de services, PKI, connectivité, admission | M13-E09, M13-E14, M14-E26, M15-E33, M14-E18 | maillage de services (hors périmètre), M26 |
| **Compliance and Security Frameworks** (10 %) | M18-E15 (CIS comparé), M13-E17 (ADR de confiance) | M26, F6 (HDS, ISO 27001) |

Sources : [programmes KCNA et KCSA (CNCF)](https://github.com/cncf/curriculum).

## 13. Docker Certified Associate (DCA)

**Statut** : l'examen existe toujours, mais il n'appartient plus à Docker. Docker a cédé son activité d'entreprise à **Mirantis** en 2019, qui administre depuis la certification. QCM. Domaines relevés sur une source secondaire (juin 2026), à vérifier sur la page de Mirantis avant de t'inscrire. L'examen garde une large part de **Swarm** et des produits d'entreprise de Mirantis (MKE, MSR), que le workbook ne pratique pas : il a retenu Kubernetes pour l'orchestration. Avec le seul bloc C, c'est un examen à préparer en partie à côté.

| Domaine (poids) | Exercices du bloc C |
|---|---|
| **Orchestration** (25 %) : Swarm, services, piles, mise à l'échelle | non couvert (Swarm hors périmètre) ; Compose : M12-E08 ; orchestration par Kubernetes : M14 |
| **Image Creation, Management, and Registry** (20 %) | M12-E04, M12-E05, M12-E10, M12-E11, M12-E13, M12-E15, M12-E16 · registre d'entreprise : M13-E02, M13-E03, M13-E10 |
| **Installation and Configuration** (15 %) | M12-E02, M12-E20, M12-E26 |
| **Networking** (15 %) | M12-E07, M12-E37 |
| **Security** (15 %) | M12-E24, M12-E26, M13-E07, M13-E14 |
| **Storage and Volumes** (10 %) | M12-E07, M12-E29, M12-E36, M12-E39 |

Sources : [Mirantis, certifications](https://certification.mirantis.com/), [présentation de l'examen (KodeKloud, juin 2026, source secondaire)](https://kodekloud.com/blog/docker-certification/).

## 14. LFCS : compléments du bloc C

Le domaine *Operations Deployment* de la LFCS (§1) demande de savoir utiliser un **moteur de conteneurs** : lancer, inspecter, arrêter des conteneurs, gérer images, volumes et réseaux, et faire démarrer un conteneur avec le système. Le module 12 le couvre : M12-E03 (cycle de vie), M12-E04 (images), M12-E06 (Podman sans privilège), M12-E07 (volumes et réseaux), M12-E14 (Quadlet et systemd), M12-E18 (journaux, ressources, santé), M12-E35 à M12-E41 (pannes). Les certificats (*Essential Commands*) reviennent avec cert-manager : M15-E13, M15-E40. Swap, automontage, ACL et LDAP restent non pratiqués (LDAP au module 24).

## 15. PCA — Prometheus Certified Associate

QCM en ligne et surveillé de 90 minutes, sans manipulation. Le module 21 en couvre tout le programme, et au-delà (Thanos, Pyrra, supervision de la supervision, pannes) ; ce qui manque surtout pour l'examen, c'est la **lecture rapide de PromQL** et du format d'exposition : refais M21-E04, M21-E14 et M21-E45 sans indice, et lis les requêtes des alertes du chart kube-prometheus-stack.

| Domaine (poids) | Compétences de l'examen | Exercices des blocs D et E |
|---|---|---|
| **Observability Concepts** (18 %) | métriques, journaux et événements, traces et spans ; *push* et *pull* ; découverte de services ; SLO, SLA, SLI | M21-E01, M21-E09 · *pull* et découverte : M21-E03, M21-E07, M21-E08 · SLI et SLO : M21-E26, M21-E27 · journaux : M22-E04 · traces et spans : M23-E05, M23-E24 |
| **Prometheus Fundamentals** (20 %) | architecture ; configuration et collecte ; limites de Prometheus ; modèle de données et étiquettes ; format d'exposition | M21-E02, M21-E03, M21-E09 · collecte et relabeling : M21-E07, M21-E13 · limites (stockage local, haute disponibilité) : M21-E24, M21-E30 · stockage : M21-E44 |
| **PromQL** (28 %) | sélection ; taux et dérivées ; agrégations dans le temps et par dimensions ; opérateurs binaires ; histogrammes ; métriques d'horodatage | M21-E04, M21-E14, M21-E23, M21-E45 · histogrammes et quantiles : M21-E19, M21-E26 · métriques d'horodatage : non pratiquées en tant que telles (révision personnelle) |
| **Instrumentation and Exporters** (16 %) | bibliothèques clientes ; instrumentation ; exportateurs ; structure et nommage des métriques | ServiceMonitor et PodMonitor des applications : M21-E07 · exportateurs : M21-E08, M21-E10, M21-E11, M21-E12 · nommage et cardinalité : M21-E14 · exemplars depuis le code : M23-E08 |
| **Alerting & Dashboarding** (18 %) | tableaux de bord ; règles d'alerte ; Alertmanager ; quand, quoi et pourquoi alerter | Grafana : M21-E05, M21-E17, M21-E19 · règles : M21-E15, M21-E21, M21-E41 · Alertmanager (routes, silences, inhibitions) : M21-E06, M21-E16, M21-E36, M21-E40 · politique d'alerte : M21-E32 |
| Chronométré, sans corrigé | — | M21-E34, M21-E43 |

Source : [page officielle de la PCA](https://training.linuxfoundation.org/certification/prometheus-certified-associate/) (Linux Foundation).

## 16. OTCA — OpenTelemetry Certified Associate

QCM en ligne et surveillé. Le module 23 pratique les quatre domaines, avec un parti pris : instrumentation **dans le code** (SDK Python et Go) avant l'auto-instrumentation, Collector piloté par l'opérateur. L'examen interroge plus largement l'API (types de métriques, *baggage*, journaux par l'API de *logs bridge*) et les autres langages : révise la spécification à part.

| Domaine (poids) | Exercices du bloc E |
|---|---|
| **Fundamentals of Observability** (18 %) : signaux, corrélation, conventions sémantiques | M23-E01, M23-E08, M23-E13 ; métriques et journaux : M21, M22 |
| **The OpenTelemetry API and SDK** (46 %) : traceurs, spans, attributs de ressource, propagation du contexte, exportateurs, échantillonnage en tête, auto-instrumentation | SDK Python : M23-E04 · SDK Go : M23-E06 · auto-instrumentation par l'opérateur : M23-E07 · propagation W3C : M23-E06, M23-E20, M23-E24 · échantillonnage : M23-E09 · conventions de MédiSphère : M23-E25 |
| **The OpenTelemetry Collector** (26 %) : récepteurs, processeurs, exportateurs, pipelines, modes agent et passerelle, extensions | M23-E02, M23-E09 (échantillonnage en queue), M23-E10 (processeurs, masquage), M23-E11 (revue), M23-E16 (capacité, TLS, authentification) |
| **Maintaining and Debugging Observability Pipelines** (10 %) : métriques internes du Collector, pertes, file d'attente, diagnostic | M23-E19, M23-E20, M23-E21, M23-E22, M23-E23, M23-E24 |

Source : [annonce officielle de l'OTCA](https://training.linuxfoundation.org/blog/new-certification-opentelemetry-certified-associate-otca/) (Linux Foundation).

## 17. CAPA — Certified Argo Project Associate (partiel)

QCM en ligne et surveillé, sur les quatre projets Argo. Le workbook ne pratique que **Argo CD** et **Argo Rollouts** (M20) : **Argo Workflows** (36 %) et **Argo Events** (12 %) ne sont pas au programme (la CI de MédiSphère est GitLab CI, M19). Avec le seul bloc D, la CAPA se prépare donc pour moitié à côté.

| Domaine (poids) | Exercices du bloc D | Non couvert |
|---|---|---|
| **Argo Workflows** (36 %) | — | modèles, DAG, artefacts, planification, intégration CI/CD : à réviser entièrement |
| **Argo CD** (34 %) | installation et accès : M20-E02, M20-E03 · Applications, synchronisation, santé, dérive : M20-E04, M20-E05, M20-E06 · AppProjects, RBAC : M20-E07, M20-E24 · ApplicationSets : M20-E10, M20-E33 · vagues et hooks : M20-E11 · Helm, Kustomize, sources multiples : M20-E13 · notifications : M20-E19 · multi-cluster : M20-E26 · HA, sauvegarde, durcissement : M20-E25, M20-E27, M20-E28 · dépannage : M20-E35 à M20-E43 · architecture : M20-E44 | Dex et SSO (M24), extensions de l'interface, *Source Hydrator* |
| **Argo Rollouts** (18 %) | canary : M20-E15, M20-E16 · blue/green : M20-E17 · analyses (Job, `web`) : M20-E18 · analyses par Prometheus : M21-E18 · panne : M20-E40 | *Experiments*, autres fournisseurs de trafic (Istio, NGINX) |
| **Argo Events** (12 %) | — | sources, capteurs, déclencheurs : à réviser entièrement |

Source : [page officielle de la CAPA](https://www.cncf.io/training/certification/capa/) (CNCF).

## 18. CGOA — GitOps Certified Associate

QCM en ligne et surveillé, sur les principes d'OpenGitOps plutôt que sur un outil. Le module 20 les pratique avec Argo CD et compare Flux (M20-E23) ; le questionnaire M20-E09 reprend les quatre principes. Jenkins X, cité par l'examen, n'est pas abordé.

| Domaine (poids) | Exercices du bloc D |
|---|---|
| **GitOps Terminology** (20 %) : état désiré, réconciliation, dérive, source de vérité | M20-E01, M20-E05, M20-E09 |
| **GitOps Principles** (30 %) : déclaratif, versionné et immuable, tiré automatiquement, réconcilié en continu | M20-E05 (auto-réparation), M20-E06 (racine), M20-E12 (ce qui reste hors Git), M20-E30 (la CI sans droits), M20-E39 |
| **Related Practices** (16 %) : configuration et infrastructure *as code*, DevSecOps, CI/CD | CI et promotion par MR : M19-E17, M20-E14 · IaC : blocs A et B · sécurité : M20-E25 |
| **GitOps Patterns** (20 %) : *App of Apps*, environnements, promotion, déploiements progressifs, multi-cluster | M20-E06, M20-E10, M20-E14, M20-E16, M20-E17, M20-E26, M20-E29 |
| **Tooling** (14 %) : Argo CD, Flux, outils de rendu (Helm, Kustomize) | M20-E02, M20-E13, M20-E23 (Flux), M20-E31 (ADR comparatif) |

Source : [page officielle de la CGOA](https://www.cncf.io/training/certification/cgoa/) (CNCF).

## 19. Kubernetes : compléments des blocs D et E

Les certifications Kubernetes (§9 à §12) gagnent quelques exercices avec les blocs D et E :

| Certification | Domaine | Exercices des blocs D et E |
|---|---|---|
| **CKA** | Troubleshooting : consommation de ressources, journaux des conteneurs | M21-E20 (plan de contrôle, etcd, kubelet), M21-E23 (saturation), M22-E03, M22-E07 (audit de l'API), M22-E19 |
| **CKAD** | Application Deployment : stratégies bleu/vert et canari ; Helm et Kustomize | M20-E15, M20-E16, M20-E17 ; M20-E13 |
| **CKAD** | Application Observability and Maintenance : outils de surveillance, journaux, débogage | M21-E07, M22-E04, M22-E06, M23-E12 |
| **KCNA** | Cloud Native Application Delivery (GitOps, CI/CD) ; Cloud Native Architecture (observabilité) | M19-E06, M19-E17, M20-E09, M20-E10 ; M21-E09, M22-E04, M23-E05 |
| **CKS** | Supply Chain Security : connaître et sécuriser la chaîne CI/CD | M19-E15, M19-E24, M19-E25, M19-E29 |
| **CKS** | Monitoring, Logging and Runtime Security : journaux d'audit | M22-E07, M22-E16 |

## 20. À compléter aux blocs suivants

| Certification | Domaines officiels | Bloc concerné |
|---|---|---|
| **KCSA** (complément) | conformité (HDS, ISO 27001) | fait aux finaux : §27 |
| **LFCS** (compléments) | swap, automontage, ACL POSIX | non prévus (révision personnelle) |
| **Kyverno Certified Associate (KCA)** | non relevé au bloc F : le M26 n'utilise que les politiques CEL de Kyverno 1.19 (`ClusterPolicy` dépréciée), à vérifier contre le programme de l'examen si l'apprenant le vise | — |

## 21. Kubernetes, LFCS, RHCSA et RHCE : compléments du bloc F

Le bloc F termine la CKS (§11) et la KCSA (§12) et ajoute des gestes Linux d'identité et de durcissement aux certifications système. Les domaines sont ceux des programmes cités plus haut.

| Certification | Domaine | Exercices du bloc F |
|---|---|---|
| **CKS** | Cluster Setup : référentiel CIS ; NetworkPolicy ; métadonnées et points d'accès des nœuds | kube-bench (forcé sur `cis-1.12`, aucun référentiel pour 1.36) et kubescape : M26-E05, M26-E34 · NetworkPolicy par défaut générée, quarantaine : M26-E16, M26-E42 · kubelets à certificats vérifiés : M26-E25, M26-E41 · pare-feu d'hôte des nœuds : M26-E27, M26-E40 |
| **CKS** | Cluster Hardening : RBAC minimal ; accès à l'API ; comptes de service ; montée de version | authentification OIDC structurée et kubelogin : M24-E16, M24-E36 · RBAC par groupes de l'annuaire, revue des accès : M24-E10, M24-E17, M24-E30 · comptes de service sans jeton monté : M26-E21 · audience des jetons de compte de service (méthode `kubernetes` d'OpenBao) : M25-E12 · correctifs du cluster : M26-E30 |
| **CKS** | System Hardening : empreinte de l'hôte ; identités à moindre privilège ; accès réseau ; AppArmor et seccomp | rôle `durcissement` (SSH, PAM, sudo, noyau, services) : M26-E10, M26-E11, M26-E14 · AppArmor et SELinux, `appArmorProfile` dans les pods : M26-E13, M26-E21, M26-E39 · seccomp (`seccompDefault`, mutation par défaut) : M26-E16, M26-E25 · SSH par certificats courts, HBAC : M24-E19, M24-E20 |
| **CKS** | Minimize Microservice Vulnerabilities : Pod Security Standards ; Secrets ; isolation ; chiffrement de pod à pod | PSA `restricted` imposé, panne : M26-E06, M26-E36 · Secrets par coffre et ESO : M25-E12, M25-E13 · identifiants dynamiques : M25-E14 · comparaison SOPS, Sealed Secrets, CSI : M25-E18, M25-E19 · chiffrement d'etcd (`secretbox` gardé, KMS v2 étudié et écarté) : M25-E31 · WireGuard étendu aux nœuds : M26-E26 · gVisor et Kata : **discutés seulement** (M26-E31), à pratiquer à côté |
| **CKS** | Supply Chain Security : registres autorisés ; signer et valider ; analyse statique | admission Kyverno (registres, digest, limites) : M26-E07, M26-E16, M26-E18 · signatures Cosign exigées en recette et prod : M26-E15, M26-E35 · clé de signature dans le coffre (`transit`) : M25-E20 · politiques d'admission natives (VAP, MAP) : M26-E17 · analyse des manifestes et du Dockerfile : M26-E21, M26-E22 · vulnérabilités des images en service : M26-E30 |
| **CKS** | Monitoring, Logging and Runtime Security : analyse comportementale ; phases d'une attaque ; immuabilité ; audit | Falco : M26-E08, M26-E19, M26-E37 · Tetragon (observer, bloquer) : M26-E20, M26-E29 · réponse à incident : M26-E33, M26-E42, M26-E43 · `readOnlyRootFilesystem` : M26-E21 · politique d'audit revisitée et détections : M26-E28 · mécanismes (eBPF, LSM, chaîne d'admission) : M26-E44 |
| **KCSA** | Kubernetes Threat Model ; Platform Security ; Compliance and Security Frameworks | modèle de menace : M26-E02 · admission, PKI de services : M26-E07, M25-E16 · référentiels CIS, ANSSI, OpenSCAP : M26-E04, M26-E09, M26-E24 · registre des exceptions : M26-E23 · audit de conformité : M26-E34 · questions : M24-E45, M25-E45, M26-E45 |
| **KCSA** | Kubernetes Security Fundamentals : authentification, Secrets, audit | M24-E07, M24-E16, M25-E12, M25-E21, M26-E28 |
| **LFCS** | Users and Groups : comptes LDAP | inscription des VMs dans FreeIPA (SSSD, HBAC, sudo) : M24-E19, M24-E40 · annuaire en code, recherches LDAP : M24-E03, M24-E37 |
| **LFCS** | Operations Deployment : SELinux ; paramètres du noyau ; journaux | M26-E10, M26-E12 (auditd, AIDE), M26-E13, M26-E39 |
| **LFCS** | Networking : OpenSSH | ssh-audit et durcissement de sshd : M26-E03, M26-E11 · certificats SSH d'utilisateur : M24-E20 |
| **RHCSA** | Manage security (SELinux : contextes, booléens, `semanage`, `restorecon`) ; Manage users and groups | SELinux *enforcing* sur Rocky 10 : M26-E13, M26-E39 · `authselect`, PAM : M26-E11 · FreeIPA sur Rocky 10, Kerberos (`kinit`) : M24-E02, M24-E03 · `firewalld` d'`ipa01` : M24-E06 · clients SSSD : M24-E19 |
| **RHCE** | rôles et collections ; Ansible Vault ; variables par groupe | collection `freeipa.ansible_freeipa` : M24-E03 · rôle `durcissement` (exceptions, vagues `serial: 1`) : M26-E10, M26-E14 · Ansible lit ses secrets dans OpenBao (`community.hashi_vault`) : M25-E11 |

Restent hors du workbook : pour la CKS, les conteneurs isolés (gVisor, Kata) en pratique et Istio ; pour la LFCS, swap, automontage et ACL POSIX.

## 22. HashiCorp Certified: Vault Associate (003) — en équivalence

**À lire avant tout** : le workbook n'installe pas HashiCorp Vault en production, il installe **OpenBao** 2.7, le fork communautaire de Vault (Linux Foundation, licence MPL 2.0), choisi parce que Vault est sous licence BUSL (ADR-0250). Les concepts (barrière, seal, jetons, baux, politiques, méthodes, moteurs), la CLI (`bao` au lieu de `vault`) et l'API (`/v1/...`) sont presque identiques, et le fournisseur OpenTofu utilisé est `hashicorp/vault`. Mais l'examen porte sur **Vault** : ses fonctions Enterprise et HCP (espaces de noms, réplication, *performance standby*, Sentinel, HSM), son interface et ses évolutions depuis le fork ne sont pas pratiquées ; M25-E30 installe Vault 2.2 sur `bao-essai` pour comparer. Compte une préparation propre à Vault (parcours officiel de HashiCorp) en plus du module.

| Domaine officiel | Exercices du module 25 |
|---|---|
| **Authentication methods** | OIDC (Keycloak) : M25-E06 · AppRole et `secret_id` enveloppés : M25-E07, M25-E28 · JWT de GitLab (`bound_claims`) : M25-E10, M25-E36 · Kubernetes : M25-E12 |
| **Vault policies** | M25-E05, M25-E22 (revue), M25-E40 (panne « permission denied ») |
| **Vault tokens** | jetons, accesseurs, jetons périodiques : M25-E05 · jeton racine révoqué : M25-E08, M25-E28 · jeton du seal renouvelé : M25-E25, M25-E42 |
| **Vault leases** | baux, renouvellement, révocation : M25-E09, M25-E14, M25-E38 · rotation : M25-E15, M25-E33, M25-E34 |
| **Secrets engines** | KV v2 : M25-E04 · `database` (PostgreSQL dynamique) : M25-E14 · PKI : M25-E16, M25-E41 · `transit` : M25-E17, M25-E20 |
| **Encryption as a Service** | M25-E17, M25-E18 (SOPS par `transit`), M25-E20 (Cosign par `transit`) |
| **Vault architecture fundamentals** | barrière, seal Shamir, initialisation : M25-E03, M25-E09 · sous le capot (trousseau, Raft, baux) : M25-E44 · audit : M25-E21 |
| **Vault deployment architecture** | grappe Raft et VIP : M25-E24 · auto-descellement `transit` : M25-E25, M25-E35, M25-E42 · instantanés et restauration : M25-E26 · supervision, durcissement : M25-E27, M25-E28 · montée de version : M25-E29 · panne sans leader : M25-E39 |
| **Access management architecture** | modèle d'accès au coffre : M25-E05 · groupes externes tirés de l'annuaire : M25-E06, M25-E08 · ADR du coffre : M25-E31 |

Sources : [Vault Associate (003), revue des objectifs (HashiCorp)](https://developer.hashicorp.com/vault/tutorials/associate-cert-003/associate-review-003) ; [page de la certification](https://developer.hashicorp.com/certifications/vault-associate).

## 23. Kubernetes : compléments du bloc G

Le bloc G apporte à la CKA et à la CKAD ce qui leur manquait (autoscaling, priorités), et quelques gestes aux autres programmes Kubernetes. Les domaines sont ceux des programmes cités aux §9 à §12.

| Certification | Domaine | Exercices du bloc G |
|---|---|---|
| **CKA** | Workloads and Scheduling : autoscaling ; admission et ordonnancement | **HPA** `autoscaling/v2` (cible Rollout, `behavior`) : M28-E02 · KEDA (file, cron, Prometheus, zéro) : M28-E03, M28-E13 · VPA et redimensionnement en place : M28-E04 · boucle de l'HPA et métriques externes : M28-E24 · PriorityClass, préemption, quotas par locataire : M28-E14 · PDB et bascules sous drainage : M27-E02 |
| **CKA** | Troubleshooting : charges et ressources | autoscaling muet : M28-E19 · pods qui oscillent : M28-E20 · locataire qui sature le cluster : M28-E23 · écritures bloquées, consommateur arrêté : M27-E19, M27-E20 |
| **CKA** | Cluster Architecture : CRD et opérateurs | opérateurs RabbitMQ (Cluster Operator, Messaging Topology Operator) : M27-E03, M27-E04 · Strimzi : M27-E09 · Capsule et ses webhooks : M28-E05, M28-E24 · schémas des CRD pour la validation : M29-E02 |
| **CKAD** | Application Design and Build : choisir la ressource (Job, CronJob, StatefulSet) | Job de migration en hook : M27-E05 · CronJob d'export des définitions : M27-E15 · StatefulSet de Valkey : M27-E07 |
| **CKAD** | Application Environment, Configuration and Security : demandes, limites, quotas ; CRD | recommandations VPA : M28-E04 · quotas, LimitRange et priorités : M28-E14, M28-E23 · objets d'opérateurs (Pooler, `Database`, `Queue`, `ScaledObject`) : M27-E02, M27-E04, M28-E03 |
| **CKAD** | Application Observability and Maintenance : sondes et contrôles de santé ; débogage | sondes de CloudNativePG : M27-E24 · sonde `/pret` révélée par le chaos : M29-E23 · migrations qui ne cassent pas N−1 : M27-E06 |
| **KCNA** | Cloud Native Architecture : autoscaling, *serverless* ; Container Orchestration : ordonnancement | M28-E02, M28-E03 (mise à zéro), M28-E14 ; questionnaires M28-E01, M28-E18 |
| **CKS** | Minimize Microservice Vulnerabilities : isolation multi-locataire | M28-E05, M28-E15 (tentatives d'évasion d'un locataire), M28-E09 (vCluster) |
| **CKS** | Supply Chain Security : analyse statique des manifestes | kubeconform et conftest sur les manifestes rendus : M29-E02, M29-E03, M29-E10 |

## 24. CBA — Certified Backstage Associate

QCM en ligne de 90 minutes. Le module 28 construit et exploite un portail Backstage complet, mais du point de vue de la plateforme : le domaine le plus lourd de l'examen, **Customizing Backstage** (32 %), porte sur le développement de plugins (React, Material UI), que le module ne fait qu'effleurer en intégrant des plugins existants. Compte une préparation propre à ce domaine.

| Domaine (poids) | Exercices du module 28 |
|---|---|
| **Backstage Development Workflow** (24 %) : projet local, TypeScript, dépendances (Yarn), image de conteneur | application créée par `@backstage/create-app`, image construite par la CI : M28-E06 · montée de version : M28-E16 |
| **Backstage Infrastructure** (22 %) : cadre, configuration, déploiement en production, architecture client-serveur | `app-config`, chart, base CNPG `portail-db`, connexion OIDC : M28-E06 · production (mise à jour, sauvegarde, supervision) : M28-E16 · panne : M28-E22 |
| **Backstage Catalog** (22 %) : alimenter le catalogue, annotations, emplacements enregistrés à la main, ingestion automatique, dépannage de l'ingestion | découverte GitLab, organisation par LDAP, `catalog-info.yaml`, propriétaires : M28-E07 · annotations Kubernetes et TechDocs : M28-E10 · catalogue complet à la livraison : M28-E25 |
| **Customizing Backstage** (32 %) : plugins frontaux et dorsaux, personnalisation de plugins, code React, Material UI | plugins Kubernetes et TechDocs ajoutés à l'application : M28-E10 · modèles du *scaffolder* : M28-E08 · **développement de plugins non pratiqué** |

Source : [page de la certification CBA (Linux Foundation)](https://training.linuxfoundation.org/certification/certified-backstage-associate-cba/).

## 25. CNPA et CNPE — ingénierie de plateforme

Deux certifications de la CNCF sur l'ingénierie de plateforme. Le workbook entier en est une mise en pratique (livraison, observabilité, sécurité, libre-service) ; le bloc G en ferme la boucle avec le portail, les locataires et les tests.

**CNPA** (*Certified Cloud Native Platform Engineering Associate*) : QCM en ligne de 120 minutes.

| Domaine (poids) | Exercices du workbook |
|---|---|
| **Platform Engineering Core Fundamentals** (36 %) : gestion déclarative, environnements, architecture de plateforme, CI, CD et GitOps | M17, M19, M20 · ADR de la plateforme développeurs : M28-E17 |
| **Platform Observability, Security, and Conformance** (20 %) : observabilité, communication sécurisée, moteurs de politiques, sécurité de Kubernetes et des pipelines | M21-M23 · M24-M26 · politiques Rego en CI : M29-E03, M29-E10 |
| **Continuous Delivery & Platform Engineering** (16 %) : pipelines, réponse à incident, GitOps | M19, M20 · astreintes `BF` des modules 27 à 29 (M27-E23, M28-E23, M29-E23) |
| **Platform APIs and Provisioning Infrastructure** (12 %) : boucle de réconciliation, API de libre-service (CRD), provisionnement par Kubernetes, opérateurs | opérateurs RabbitMQ et Strimzi : M27-E03, M27-E09 · locataires en libre-service : M28-E05 · Crossplane en fiche ([`decouverte/crossplane.md`](decouverte/crossplane.md)) |
| **IDPs and Developer Experience** (8 %) : accès simplifié, catalogues, portails | M28-E06, M28-E07, M28-E08, M28-E12 (guide d'accueil) |
| **Measuring your Platform** (8 %) : efficacité, productivité, indicateurs DORA | DORA : M19-E28 · temps du chemin balisé mesuré : M28-E25 |

**CNPE** (*Certified Cloud Native Platform Engineer*) : examen **pratique** de 2 heures.

| Domaine (poids) | Exercices du workbook |
|---|---|
| **Platform Architecture and Infrastructure** (15 %) : bonnes pratiques réseau, stockage, calcul ; dimensionnement ; ressources multi-locataires | M15, M16 · VPA, quotas, priorités : M28-E04, M28-E14 · dimensionnement des données : M27-E16 |
| **GitOps and Continuous Delivery** (25 %) : GitOps, pipelines intégrés à Kubernetes, livraison progressive | M19, M20 (canary d'Argo Rollouts) · MédiNotif livré par ApplicationSet : M27-E04, M27-E08 |
| **Platform APIs and Self-Service Capabilities** (25 %) : CRD de services de plateforme, libre-service, opérateurs, cadres d'automatisation | opérateurs : M27-E03, M27-E09 · locataires : M28-E05 · modèle « nouveau service » par MR : M28-E08 · **CRD maison et Crossplane non pratiqués** |
| **Observability and Operations** (20 %) : supervision, alertes, journaux, traces ; indicateurs ; diagnostic | M21-M23 · supervision des données : M27-E14 · pannes des modules 27 à 29 |
| **Security and Policy Enforcement** (15 %) : communication sécurisée, RBAC, traces d'audit et conformité, moteurs de politiques, analyses en pipeline | M24-M26 · politiques Rego et composant `validation` : M29-E03, M29-E10 |

Sources : [CNPA (Linux Foundation)](https://training.linuxfoundation.org/certification/certified-cloud-native-platform-engineering-associate-cnpa/), [CNPE (Linux Foundation)](https://training.linuxfoundation.org/certification/certified-cloud-native-platform-engineer-cnpe/).

## 26. Données et messagerie : Kafka, PostgreSQL, RabbitMQ

- **Kafka** : Confluent propose le **CCDAK** (*Confluent Certified Developer for Apache Kafka*) et le **CCAAK** (*Confluent Certified Administrator for Apache Kafka*), QCM surveillés de 90 minutes. Le workbook n'en couvre qu'une petite part : Kafka y est un **essai** de deux exercices (KRaft, `KafkaNodePool`, *topics*, utilisateurs SCRAM, offsets et groupes de consommateurs : M27-E09, M27-E10), retiré ensuite (ADR-0270). Le CCAAK suppose l'exploitation durable d'une grappe, le CCDAK les API clientes (producteurs, consommateurs, Streams, Connect) : préparation propre indispensable. Source : [certifications Confluent](https://www.confluent.io/certification/).
- **PostgreSQL et CloudNativePG** : EDB publie un catalogue d'examens, dont **EDB Essentials for CloudNativePG** (version 1.25, examen inclus dans la formation EDB du même nom : architecture, installation, configuration, sécurité et supervision, sauvegarde et restauration, réplication et haute disponibilité, montées de version) et **EDB Essentials / Advanced for PostgreSQL**. Le premier recoupe M16 (installation, sauvegardes Barman Cloud, PITR) et M27 (rôles et bases déclaratifs, *pooler*, switchover, fencing, réplica de secours, supervision, mise à jour mineure : M27-E02, M27-E14, M27-E15, M27-E24) ; la version de l'examen (1.25) est antérieure à celle du workbook (1.30). Les seconds portent sur l'administration de PostgreSQL elle-même, que le workbook ne traite que par CloudNativePG et Patroni (M27-E13). Sources : [catalogue des examens EDB](https://enterprisedb.com/training/certification-exams), [fiche EDB Essentials for CloudNativePG](https://www.enterprisedb.com/sites/default/files/pdf/EDB_Essentials_for_CloudNativePG_Datasheet.pdf).
- **RabbitMQ** : aucune certification officielle relevée (l'éditeur propose des formations, pas d'examen).
- **Sans certification** : OPA et Rego (aucune certification officielle de la CNCF ni du projet), k6, Chaos Mesh, LitmusChaos, Terratest, Testinfra, Goss, KEDA, Capsule, vCluster : le module 29 et le module 28 les pratiquent sans grille d'examen.

## 27. Finaux F5 à F7 : continuité, conformité, incident et avant-vente

Les finaux F5 à F7 ne visent aucun examen technique nouveau. Ils touchent en revanche des métiers qui ont leurs propres certifications **de personnes** : le workbook n'en suit pas les programmes (ils varient d'un organisme à l'autre et n'ont pas été relevés), il en fait pratiquer les livrables sur un cas réel. Ces correspondances sont donc **de culture**, à ne pas prendre pour une préparation.

| Certification | Domaine (ou sujet) | Scénarios des finaux |
|---|---|---|
| **CKS** | Monitoring, Logging and Runtime Security : analyse comportementale ; phases d'une attaque ; immuabilité ; audit | détection Falco/Tetragon croisée avec l'audit de l'API, confinement sans détruire les preuves : F6-S11 · chronologie, portée, éradication : F6-S12 · capture d'un conteneur vivant (point de contrôle du kubelet) et ordre de collecte : F6-S10 |
| **CKS** | Cluster Hardening : RBAC minimal, comptes de service | revue des accès (comptes orphelins, techniques, bris de glace) : F6-S03 · liaison `cluster-admin` oubliée, panne : F6-S04 |
| **CKS** | Supply Chain Security : signer et valider ; analyse des images | images et signatures copiées vers le registre de PAR2 sans contourner la vérification : F5-S04 · délais de correction par criticité et exceptions à échéance : F6-S09 |
| **CKA** | Cluster Architecture, Installation and Configuration : kubeadm ; Storage : classes de stockage | cluster de secours `k8s-par2` construit par kubeadm depuis le même code que `k8s-par1`, StorageClass `local-path` : F5-S06 |
| **KCSA** | Compliance and Security Frameworks | référentiels HDS v2 et ISO/IEC 27001:2022, déclaration d'applicabilité : F6-S01 · preuves automatiques et inaltérables : F6-S02, F6-S08 · audit outillé (CIS, OpenSCAP, kube-bench) relié aux mesures : F6-S05 |
| **CNPA, CNPE** | traces d'audit et conformité ; libre-service | archive d'audit inaltérable : F6-S08 · client hébergé « en code » par le même mécanisme que les équipes : F7-S07 · engagements de service mesurés et rapport mensuel : F7-S10 |
| **ISO/IEC 27001 Lead Implementer** (culture) | mise en œuvre d'un SMSI | périmètre et SoA : F6-S01 · preuves : F6-S02 · plan de remédiation priorisé par le risque : F6-S07 · remédiation par le code : F6-S08, F6-S09 · état des preuves avant l'audit de suivi : F6-S14 |
| **ISO/IEC 27001 Lead Auditor** (culture ; audit selon ISO 19011) | conduite d'un audit, entretiens, rapport | audit à blanc et écarts cachés : F6-S04 · audit technique : F6-S05 · entretien d'audit : F6-S06 · rapport d'écarts (majeure, mineure, observation) : F6-S07 · audit de suivi : F6-S14 |
| **Continuité d'activité** (culture : ISO 22301 Lead Implementer, CBCI du BCI, CBCP du DRI) | analyse d'impact, stratégie de reprise, plan, exercice | BIA et objectifs RTO/RPO : F5-S01 · dépendances et ordre de redémarrage : F5-S02 · cellule de crise et runbook de bascule : F5-S07 · exercice réel chronométré : F5-S09 à F5-S12 · rapport d'exercice et calendrier des tests : F5-S13, F5-S14 |
| **DPO** (culture : certification des compétences du DPO selon le référentiel de la CNIL) | violation de données, rôles responsable de traitement / sous-traitant | décision de notification (CNIL, clients, personnes, signalement santé) et registre des violations : F6-S13 |

Le capstone F7 (réponse à un appel d'offres : CCTP, exigences chiffrées, architecture, coût complet, planning, soutenance) ne correspond à aucune certification relevée ; ses gestes techniques (fédération d'identité, tests de contrat, SLO, réversibilité, reprise sur PAR2) remobilisent les §9 à §12, §15 et §25.
