# Cahier des charges — préproduction de MédiAgenda (DEV-679)

> **Ne lis ce fichier qu'au démarrage du chrono (T0).**

**Demandeur** : Julien Petit · **Relecture** : Karim Benali (MR), Sophie Laurent (sécurité)
**Échéance** : jeudi 9 h, environnement joignable

## Contexte

Répétition générale de la mise en production de MédiAgenda : deux frontaux d'API et une base de
données, à l'image de la future production. L'environnement vit le temps de la répétition, puis
il est détruit. Il se construit avec ce que l'équipe a déjà : Terragrunt (`terragrunt/live/`), les
composants `acces` et `vms`, le module `vm-debian` versionné.

## Exigences

| # | Exigence |
|---|---|
| X1 | Environnement Terragrunt nommé **`preprod-agenda`**, sous `terragrunt/live/`, avec les unités `acces` et `vms` ; leurs `terragrunt.hcl` sont **identiques** à ceux des autres environnements (tout ce qui varie est dans `env.hcl`). |
| X2 | Trois VMs : `m05-pp-api1` (VMID **2057**, 1 vCPU, 1 Go), `m05-pp-api2` (VMID **2058**, 1 vCPU, 1 Go), `m05-pp-bdd` (VMID **2059**, 2 vCPU, 2 Go). VNet `vsandbox`, DHCP. |
| X3 | `m05-pp-bdd` a, en plus de son disque système, un **disque de données de 10 Go sur `local-nvme`**, au format `raw` (base de données : pas de qcow2 sur le stockage rapide). Les frontaux n'en ont pas. |
| X4 | Étiquettes Proxmox de chaque VM : `env-m05`, `preprod-agenda`, et `app-api` pour les frontaux, `app-bdd` pour la base (Ansible en fera des groupes). |
| X5 | Si le composant `vms` doit évoluer pour X3 ou X4, l'évolution est **compatible** : la configuration des environnements existants n'a pas à changer, et leur plan n'en serait pas modifié. |
| X6 | Une clé SSH propre à l'environnement (unité `acces`) ; connexion réussie sur **chaque** VM avec cette seule clé. |
| X7 | Une sortie qui donne, pour chaque VM, son nom et son adresse IPv4 (Julien la recopiera dans son inventaire). |
| X8 | États dans `tofu-state` sous `envs/preprod-agenda/…`, **chiffrés** ; `.terraform.lock.hcl` versionnés. |
| X9 | `outils/analyse-securite.sh` et les hooks pre-commit passent sans exception ajoutée pour l'occasion. |
| X10 | MR depuis une branche `conf/…` : description avec le résumé du `terragrunt run --all plan`, la preuve de X6, ce qui n'a **pas** été testé. Pipeline vert. |
| X11 | Après la vérification : environnement détruit **par Terragrunt**, code conservé. |

## Hors périmètre

Configuration des VMs (PostgreSQL, API) : ce sera le travail d'Ansible. DNS : pas d'enregistrement
pour cet environnement jetable.
