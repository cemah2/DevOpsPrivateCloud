# Module 05 — Infrastructure as Code avec OpenTofu

| | |
|---|---|
| **Bloc** | A — Fondations automatisées |
| **Niveau** | Cœur |
| **Profil de lab** | Socle (+ `s3-01`, permanent, créé dans ce module ; VMs d'environnement 2050-2059) |
| **Prérequis** | Module 04 (rôles Ansible du socle, inventaire dynamique) ; module 03 (images dorées `current`) |
| **Durée indicative** | 40 à 50 heures |

## Contexte MédiSphère

Les machines sont configurées par du code, mais elles sont toujours **créées** à la main ou par des scripts impératifs. Personne ne peut dire, en lisant un dépôt, quelles VMs devraient exister, avec quelles ressources. Claire Morel veut que l'infrastructure du cloud privé soit **déclarée** : un dépôt `plateforme/infra` qui décrit l'état voulu, des plans relus en MR avant toute création, un état partagé et verrouillé, et des modules réutilisables versionnés dans `plateforme/tofu-modules`. L'équipe choisit **OpenTofu** (licence libre, verrou d'état S3 natif). Premier obstacle : l'état distant a besoin d'un stockage objet, et l'édition communautaire de MinIO, prévue au départ, vient d'être abandonnée par son éditeur. Sophie Laurent ajoute ses exigences : l'état contient des secrets, il doit être chiffré, et le code d'infrastructure doit être analysé comme du code applicatif.

## Objectifs

À la fin de ce module, tu sais :
- décrire une infrastructure Proxmox en OpenTofu avec le provider `bpg/proxmox` (variables, boucles, sources de données, cloud-init) ;
- comprendre et protéger l'état : backend S3, verrouillage, chiffrement, versionnage, sauvegarde ;
- concevoir, versionner et consommer des modules ;
- faire entrer l'existant sous IaC (import) et refactorer sans rien détruire (`moved`, `removed`) ;
- outiller le code (fmt, validate, tflint, terraform-docs, Checkov, Trivy) et le livrer par un pipeline plan/apply ;
- factoriser plusieurs environnements avec Terragrunt ;
- diagnostiquer les pannes d'IaC : dérive, verrou bloqué, backend inaccessible, droits, état désynchronisé ou perdu.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M05-E01 | Test de positionnement : Infrastructure as Code | Q | ★★ | 1 |
| M05-E02 | Installer OpenTofu et créer le projet `plateforme/infra` | LAB | ★ | 1 |
| M05-E03 | Compte Proxmox `wb-tofu`, provider épinglé, premier plan | LAB | ★★ | 1 |
| M05-E04 | Première VM déclarée | LAB | ★ | 1 |
| M05-E05 | Plan, apply, destroy et fichier d'état | LAB | ★ | 1 |
| M05-E06 | Variables, `locals`, sorties, types et validations | LAB | ★★ | 1 |
| M05-E07 | `count`, `for_each` et blocs dynamiques | LAB | ★★ | 1 |
| M05-E08 | Sources de données : trouver l'image dorée courante | LAB | ★★ | 1 |
| M05-E09 | Questions : OpenTofu, Terraform et l'état | Q | ★★ | 1 |
| M05-E10 | Construire `s3-01` : un stockage S3 pour le socle | LAB | ★★★ | 2 |
| M05-E11 | Backend S3 et migration de l'état | LAB | ★★ | 2 |
| M05-E12 | Verrouiller l'état partagé | LAB | ★★ | 2 |
| M05-E13 | Écrire un module `vm-debian` réutilisable | LAB | ★★ | 2 |
| M05-E14 | Versionner les modules dans `plateforme/tofu-modules` | LAB | ★★ | 2 |
| M05-E15 | Environnements : workspaces ou répertoires ? | LAB | ★★ | 2 |
| M05-E16 | Importer le socle existant sans le recréer | LAB | ★★★ | 2 |
| M05-E17 | Refactorer sans détruire : `moved` et `removed` | LAB | ★★★ | 2 |
| M05-E18 | Dépendances et cycle de vie des ressources | LAB | ★★ | 2 |
| M05-E19 | cloud-init généré et snippets gérés par le code | LAB | ★★ | 2 |
| M05-E20 | Qualité du code : fmt, validate, tflint, terraform-docs | LAB | ★★ | 2 |
| M05-E21 | Revue de la MR OpenTofu d'un stagiaire | REV | ★★ | 2 |
| M05-E22 | Lire un plan comme un relecteur | Q | ★★ | 2 |
| M05-E23 | De OpenTofu à Ansible : inventaire et configuration après création | LAB | ★★ | 2 |
| M05-E24 | Terragrunt : factoriser backends, providers et environnements | LAB | ★★★ | 3 |
| M05-E25 | Analyse de sécurité du code : Checkov et Trivy | LAB | ★★ | 3 |
| M05-E26 | Pipeline IaC : plan en MR, apply protégé | LAB | ★★★ | 3 |
| M05-E27 | Secrets et chiffrement de l'état | LAB | ★★★ | 3 |
| M05-E28 | Détecter la dérive de l'infrastructure | LIBRE | ★★ | 3 |
| M05-E29 | Sauvegarder et restaurer l'état | LAB | ★★ | 3 |
| M05-E30 | ADR : le stockage S3 du socle après l'abandon de MinIO | RED | ★★ | 3 |
| M05-E31 | Mettre à jour les providers sans surprise | LAB | ★★ | 3 |
| M05-E32 | Questions de production : état, équipes et rayon d'impact | Q | ★★★ | 3 |
| M05-E33 | Runbook : verrou d'état bloqué | RED | ★★ | 3 |
| M05-E34 | Un environnement complet en temps limité | CHRONO | ★★★ | 3 |
| M05-E35 | Panne : le plan veut recréer une VM du socle | BF | ★★★ | 4 |
| M05-E36 | Panne : « Error acquiring the state lock » | BF | ★★ | 4 |
| M05-E37 | Panne : le backend d'état est inaccessible | BF | ★★ | 4 |
| M05-E38 | Panne : l'apply échoue sur un refus de droits | BF | ★★ | 4 |
| M05-E39 | Panne : la VM est créée mais injoignable | BF | ★★★ | 4 |
| M05-E40 | Panne : l'état ne correspond plus à la réalité | BF | ★★ | 4 |
| M05-E41 | Panne : le plan est cassé du jour au lendemain | BF | ★★★ | 4 |
| M05-E42 | Panne : l'état a disparu | BF | ★★★ | 4 |
| M05-E43 | Astreinte : l'IaC en panne | BF | ★★★★ | 4 |
| M05-E44 | Sous le capot : graphe, providers et état | LAB | ★★★ | 4 |
| M05-E45 | Questions expert : OpenTofu | Q | ★★★ | 4 |
| M05-E46 | Mini-projet : l'infrastructure MédiSphère déclarée | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 5 questionnaires · 1 revue · 2 rédactions · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Adresse | Rôle | Exercice |
|---|---|---|---|---|
| `s3-01` | 1006 | 10.10.20.14 (VLAN 20 INFRA) | Stockage objet S3 SeaweedFS (état OpenTofu, artefacts) | E10 |

VMs d'environnement du module : 2050-2059 (pool `lab`, VNet `vsandbox`).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 05 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 05 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
