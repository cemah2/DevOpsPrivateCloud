# Certifications et exercices du workbook

> Le workbook ne prépare pas à une certification : il forme au métier. Mais une bonne partie de ses exercices recouvre les domaines des examens du secteur. Ce fichier indique, **pour chaque certification**, les domaines officiels et les exercices qui les entraînent. Il est complété à la fin de chaque bloc.
>
> Domaines relevés le 7 octobre 2026 sur les pages officielles des éditeurs (liens en fin de section). Ils changent régulièrement : vérifie la version en vigueur avant de t'inscrire. Les correspondances sont **indicatives** : un exercice « couvre » un domaine quand il y fait pratiquer un geste de l'examen, pas quand il en parle. Les examens pratiques (LFCS, RHCSA, RHCE, CKA) demandent en plus de la **vitesse** : refais les exercices `CHRONO` et les `BF` sans indice.

État : **bloc A** (modules 00 à 06) renseigné ; blocs B à G et finaux à compléter.

## Vue d'ensemble

| Certification | Éditeur | Format | Couverture par le workbook | Où |
|---|---|---|---|---|
| LFCS — Linux Foundation Certified System Administrator | Linux Foundation | pratique, en ligne | partielle (bloc A), complétée aux blocs B et C | §1 |
| RHCSA — Red Hat Certified System Administrator (EX200, RHEL 10) | Red Hat | pratique | partielle : le workbook est surtout sur Debian, Rocky Linux 10 au M03 | §2 |
| RHCE — Red Hat Certified Engineer (EX294) | Red Hat | pratique (Ansible) | large pour Ansible (M04, M06) | §3 |
| HashiCorp Terraform Associate (004) | HashiCorp | QCM | large pour les concepts, avec OpenTofu (M05) | §4 |
| GitLab Certified Git Associate / CI/CD Associate | GitLab | QCM (+ lab pratique pour CI/CD) | Git et forge (M01), CI de base (bloc A), CI avancée au M19 | §5 |
| CKA, CKAD, CKS | CNCF / Linux Foundation | pratique (Kubernetes) | à venir : blocs C à F | §6 |
| COA (OpenStack), autres | OpenInfra Foundation… | pratique | à venir : bloc B (module 10) | §6 |

---

## 1. LFCS — Linux Foundation Certified System Administrator

Examen pratique de 2 heures sur Ubuntu. Le module 00 **évalue** ces bases (E01, E02) plutôt qu'il ne les enseigne : le workbook s'adresse à un administrateur déjà confirmé. Les domaines ci-dessous sont ceux du programme en vigueur, avec leur poids.

| Domaine (poids) | Compétences de l'examen | Exercices du bloc A |
|---|---|---|
| **Operations Deployment** (25 %) | paramètres du noyau à chaud ; processus ; journaux ; tâches planifiées ; intégrité et disponibilité des ressources ; scripts de maintenance ; démarrage et services ; SELinux ; machines virtuelles ; moteurs de conteneurs | sysctl et routage : M00-E10, M03-E13 · services, journaux : M00-E06, M00-E40, M01-E30, M01-E37 · planification (timers systemd) : M00-E30, M02-E26, M02-E35, M02-E41 · mises à jour maîtrisées : M00-E34, M03-E13 · scripts : M02-E03, M02-E10 à E14, M02-E27 à E30, M02-E39, M02-E44 · démarrage : M00-E44, M03-E22, M03-E23 · SELinux : M03-E06, M03-E25 · VMs : M00-E11, M00-E12, M00-E18, M00-E19 · conteneurs : *module 12* |
| **Networking** (25 %) | adressage IPv4/IPv6 et résolution de noms ; temps synchronisé ; diagnostic réseau ; OpenSSH serveur et client ; filtrage, redirection de ports, NAT ; routage statique ; ponts et agrégats ; reverse proxies et répartiteurs de charge | adressage et résolution : M00-E10, M00-E12, M00-E13, M03-E11, M06-E06 à E08 · temps : M00-E31, M00-E45, M06-E21 · diagnostic : M00-E38 à E43, M00-E47, M06-E35 · OpenSSH : M00-E15, M00-E27, M01-E40, M04-E11, M06-E19, M06-E20 · nftables, NAT : M00-E10, M00-E26, M00-E38, M04-E17, M06-E30 · routage statique, tunnels : M00-E16, M00-E21 · ponts : M00-E09, M00-E28 · agrégats, reverse proxies, répartiteurs : *module 07* |
| **Storage** (20 %) | LVM ; système de fichiers virtuel ; création, gestion et dépannage des systèmes de fichiers ; systèmes de fichiers distants et périphériques bloc réseau ; swap ; automontage ; performances | LVM, LVM-thin, systèmes de fichiers : M00-E07, M00-E19, M00-E44 · performances : M00-E48 · partitionnement automatisé : M03-E05, M03-E06 · NFS, iSCSI, Ceph : *module 08* · swap et automontage : non pratiqués (révision personnelle) |
| **Essential Commands** (20 %) | opérations Git de base ; créer, configurer et dépanner des services ; performances ; contraintes propres aux applications ; espace disque ; certificats SSL | Git : M01-E02, M01-E07, M01-E08, M01-E12, M01-E13, M01-E18, M01-E19, M01-E41, M01-E44 · services en panne : M01-E37, M04-E40, M06-E39 · performances : M00-E48, M02-E40, M04-E26, M04-E41 · espace disque, nettoyage : M02-E37, M01-E45 · certificats : M01-E04, M06-E02, M06-E03, M06-E18, M06-E27, M06-E37 |
| **Users and Groups** (10 %) | comptes et groupes locaux ; profils d'environnement ; limites de ressources ; ACL ; comptes LDAP | comptes locaux par le code : M04-E14 (rôle `base`), `sudo` : M00-E10, M02-E29 · environnement d'exécution (`PATH`, services, sudo) : M02-E35 · ACL POSIX, limites : non pratiquées · LDAP : *module 24* |

Source : [page officielle LFCS](https://training.linuxfoundation.org/certification/linux-foundation-certified-sysadmin-lfcs/) (domaines et compétences ; programme publié par la Linux Foundation).

## 2. RHCSA — Red Hat Certified System Administrator (EX200)

Examen pratique sur **RHEL 10**. Le workbook utilise Debian 13 par défaut ; la famille RHEL apparaît avec **Rocky Linux 10** (M03-E06, M03-E25) et le restera ponctuellement. Les gestes sont transposables, les outils diffèrent (`dnf`, `firewalld`, `nmcli`, SELinux) : la colonne de droite signale ce qu'il faut réviser spécifiquement sur RHEL.

| Domaine officiel | Exercices du bloc A | À réviser sur RHEL |
|---|---|---|
| Understand and use essential tools | M00-E01, M00-E02 (positionnement), M02-E03, M02-E12, M02-E44 | `man`, archives, redirections : supposés acquis |
| Manage software | M03-E06 (kickstart, dépôts), M03-E25 (mises à jour automatiques Rocky) ; Debian : M00-E06, M00-E34 | `dnf`, modules et flux d'applications, Flatpak |
| Create simple shell scripts | M02-E03, M02-E10, M02-E13, M02-E39 | — |
| Operate running systems | M00-E44, M03-E04, M03-E22, M03-E23, M02-E30 | cibles systemd, `rd.break`/récupération du mot de passe root, `tuned` |
| Configure local storage | M00-E07, M00-E19 | partitions GPT, LVM classique, Stratis |
| Create and configure file systems | M00-E07 | XFS, montages persistants par UUID, NFS, autofs |
| Deploy, configure, and maintain systems | M00-E31, M02-E26, M03-E05, M03-E06, M03-E13 | `chronyd`, `cron`/`at`, cible par défaut |
| Manage basic networking | M00-E10, M00-E12, M03-E11 | `nmcli`, NetworkManager |
| Manage users and groups | M04-E14 | `useradd`, politiques de mot de passe (`chage`) |
| Manage security | M00-E27, M03-E06, M03-E13, M06-E19 | `firewalld`, contextes et booléens SELinux, `restorecon`, `semanage` |

Source : [EX200, page officielle Red Hat](https://www.redhat.com/en/services/training/ex200-red-hat-certified-system-administrator-rhcsa-exam).

## 3. RHCE — Red Hat Certified Engineer (EX294, Ansible)

Examen pratique d'automatisation avec Ansible (page officielle relevée : objectifs fondés sur RHEL 9 ; vérifie si une version RHEL 10 est publiée). Le module 04 couvre l'essentiel ; le module 06 l'applique à des services réels. L'examen utilise **Ansible Automation Platform** et ses outils (`ansible-navigator`, environnements d'exécution) : le workbook travaille avec `ansible-core` dans un environnement `uv`, révise ces outils à part.

| Domaine officiel | Exercices du bloc A |
|---|---|
| Perform all tasks expected of an RHCSA | voir §2 |
| Understand core components of Ansible (inventaires, modules, variables, faits, boucles, conditions, plays, handlers, plugins) | M04-E01, M04-E03 à E09, M04-E14, M04-E45 |
| Configure Ansible (`ansible.cfg`, inventaires statiques et dynamiques) | M04-E02, M04-E03, M04-E13, M06-E12 |
| Configure Ansible managed nodes ; SSH keys ; privilege escalation | M04-E03, M04-E04, M04-E11, M04-E35 |
| Deploy files to managed nodes | M04-E05, M04-E07, M04-E08 |
| Run playbooks (simulation, limites, tags) | M04-E05, M04-E19, M04-E25 |
| Perform basic source control operations using Git | M01-E02 à E13 |
| Be familiar with Visual Studio Code | non couvert (le workbook n'impose pas d'éditeur) |
| Create Ansible plays and playbooks (gestion d'erreurs, conditions, boucles, handlers) | M04-E05 à E08, M04-E14, M04-E15, M04-E23, M04-E25 |
| Use roles and Ansible Content Collections | M04-E10, M04-E11, M04-E16, M04-E17, M04-E18, M04-E24, M06-E02, M06-E04, M06-E06, M06-E16 |
| Automate standard RHCSA tasks using Ansible modules (paquets, services, pare-feu, stockage, fichiers, utilisateurs, tâches planifiées) | M04-E10, M04-E11, M04-E14, M04-E17, M06-E21, M06-E28 |
| Manage content (templates Jinja2, Ansible Vault) | M04-E07, M04-E12, M04-E30, M04-E38 |
| Chronométré, sans corrigé | M04-E34 (`CHRONO`), M04-E43 (astreinte) |

Source : [EX294, page officielle Red Hat](https://www.redhat.com/en/services/training/ex294-red-hat-certified-engineer-rhce-exam-red-hat-enterprise-linux).

## 4. HashiCorp Terraform Associate (004)

QCM sur **Terraform**. Le workbook utilise **OpenTofu** (fork libre de Terraform 1.5, voir M05, introduction) : langage, commandes, état et providers sont communs pour l'essentiel, et les exercices du module 05 préparent donc aux objectifs 1 à 7. Attention aux écarts : l'examen interroge sur **HCP Terraform** (objectif 8), absent du workbook, et ignore ce qui est propre à OpenTofu (chiffrement de l'état côté client, méta-argument `enabled`, extension `.tofu`). Commandes : remplace `tofu` par `terraform`.

| Objectif officiel | Exercices du bloc A |
|---|---|
| 1. Infrastructure as Code (IaC) with Terraform | M05-E01, M05-E09, M05-E30 |
| 2. Terraform fundamentals (providers, versions, état) | M05-E03, M05-E05, M05-E31, M05-E44 |
| 3. Core Terraform workflow (`init`, `validate`, `plan`, `apply`, `destroy`, `fmt`) | M05-E02 à E05, M05-E20, M05-E22 |
| 4. Terraform configuration (`resource`/`data`, références, variables et sorties, types, expressions, dépendances, conditions, données sensibles) | M05-E06, M05-E07, M05-E08, M05-E18, M05-E19, M05-E27 |
| 5. Terraform modules (sources, portée, versions) | M05-E13, M05-E14 |
| 6. Terraform state management (backend local, verrou, backend distant, dérive) | M05-E05, M05-E11, M05-E12, M05-E28, M05-E36, M05-E40, M05-E42 |
| 7. Maintain infrastructure with Terraform (import, inspection de l'état, journaux détaillés) | M05-E16, M05-E17, M05-E35, M05-E44 (`TF_LOG`) |
| 8. HCP Terraform | non couvert ; l'équivalent auto-hébergé (pipeline plan/apply, verrou, workspaces) est M05-E15, M05-E24, M05-E26 |

Les secrets dans Vault (sous-objectif 4h) seront pratiqués au module 25.

Source : [Terraform Associate (004), objectifs officiels](https://developer.hashicorp.com/terraform/tutorials/certification-004/associate-review-004).

## 5. GitLab Certified Git Associate et CI/CD Associate

GitLab ne publie pas de programme détaillé en accès libre (pages de GitLab University réservées aux inscrits) : les thèmes ci-dessous sont ceux des descriptions officielles. La CI/CD Associate comprend en plus un **lab pratique** noté par les équipes de GitLab.

| Thème | Exercices du bloc A |
|---|---|
| Git : dépôts, commits, branches, fusion, rebase, historique, annulation | M01-E02, M01-E07, M01-E08, M01-E12, M01-E13, M01-E18, M01-E19, M01-E44, M01-E46 |
| GitLab : groupes, projets, droits, branches protégées, merge requests et revue | M01-E05, M01-E06, M01-E10, M01-E11, M01-E20, M01-E21 |
| CI/CD : `.gitlab-ci.yml`, stages, jobs, runners, variables protégées, artefacts, `include` | M01-E23, M01-E24, M01-E25, M02-E24, M03-E15, M04-E27, M05-E26 |
| CI/CD avancée : `rules`, `needs`, environnements, caches, runners Kubernetes | *module 19* |

Sources : [GitLab Certified Git Associate](https://university.gitlab.com/courses/gitlab-with-git-essentials-certification-exam), [GitLab Certified CI/CD Associate](https://about.gitlab.com/services/education/gitlab-cicd-associate/).

## 6. À compléter aux blocs suivants

| Certification | Domaines officiels | Bloc concerné |
|---|---|---|
| **CKA** (programme v1.35) | Cluster Architecture, Installation & Configuration · Workloads & Scheduling · Services & Networking · Storage · Troubleshooting | C (14-18), à relever au démarrage du bloc C sur [cncf/curriculum](https://github.com/cncf/curriculum) |
| **CKAD** | à relever | C, D |
| **CKS** | à relever | F (26) |
| **COA** (Certified OpenStack Administrator) | à relever | B (10) |
| **LFCS** (compléments) | agrégats, reverse proxies, NFS/iSCSI, conteneurs | B (07, 08), C (12) |
| **Vault Associate**, **Prometheus Certified Associate**, **Certified Argo Project Associate**… | à relever si pertinents | D, E, F |
