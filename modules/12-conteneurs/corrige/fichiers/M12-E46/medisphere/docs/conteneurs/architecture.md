# Conteneurs MédiSphère v1 — architecture

> État livré par l'étiquette `conteneurs-v1` de `plateforme/medisphere` (M12-E46). Décisions : ADR-0120 (moteurs). Règles : `normes.md`. Exploitation : runbooks RB-120 à RB-125, `supervision.md`.

## Vue d'ensemble

```
 Développeur ──MR──▶ GitLab (git01) ──pipeline──▶ runner02 (10.10.20.17, exécuteur docker, sans privilège)
                                                    │  Hadolint → construction sans démon (BuildKit sans privilège)
                                                    │  → test de fumée → poussée (compte ci)
                                                    ▼
                                   registre de travail ctr01:5000 (registry:3, TLS step-ca, htpasswd)
                                                    │  tirage (compte plateforme)
                                                    ▼
             ctr02 (Podman 5.4, compte app UID 1001, Quadlet) : pile de recette apps-recette
               MédiAgenda :8000 ─ PostgreSQL 18, Valkey 8, migrations
               MédiDoc :8080 ─ SeaweedFS de recette (S3)
               Legacy-RDV :8081 ─ MariaDB 11.8, volumes pièces jointes et sessions
               MédiNotif :9100 (métriques) ─ RabbitMQ 4
```

## Hôtes

| Hôte | VMID | Rôle | Cycle de vie |
|---|---|---|---|
| `runner02` | 1012 | GitLab Runner, exécuteur `docker`, étiquettes `docker`, `socle` ; constructions sans privilège | **socle** (état OpenTofu `socle`, PBS, supervision) |
| `ctr01` | 2121 | Docker 29, registre de travail (port 5000) | environnement M12 ; gardée jusqu'à la fin de M13-E03 si décidé (voir `recette-v1.md`) |
| `ctr02` | 2122 | Podman sans privilège, pile de recette | détruite après la recette |
| `ctr03` | 2123 | Podman 5.8, SELinux | détruite après la recette |
| `legacy01` | 2124 | Legacy-RDV « à l'ancienne » (référence de comparaison) | détruite après la recette |

## Chaîne de construction

- Gabarit `plateforme/ci-templates/image.yml` : Hadolint (règles `.hadolint.yaml` du projet), construction sans démon privilégié, cache exporté vers le registre, test de fumée, poussée par le compte `ci` (variables protégées et masquées), étiquettes `X.Y.Z` posées depuis les étiquettes Git, multi-architecture pour MédiAgenda (`linux/amd64`, `linux/arm64`).
- Pas de signature ni d'analyse de vulnérabilités au M12 : Cosign, Trivy et SBOM arrivent avec Harbor (M13).

## Pile de recette

- Rôle Ansible `pile_recette` (`plateforme/ansible`), fichiers Quadlet du compte `app`, réseau `apps-recette`, volumes nommés, secrets Podman alimentés par Ansible Vault (`lab`).
- Chaque conteneur : utilisateur non root (image), aucune capacité ajoutée, `NoNewPrivileges`, racine en lecture seule quand l'application le permet, limites mémoire et processus, sonde de santé (sauf MédiDoc, image sans shell : sonde externe), redémarrage par systemd, retour au démarrage par `[Install]` et le *linger* de `app`.
- MédiAgenda suit l'étiquette mobile `recette` (`AutoUpdate=registry`, `podman auto-update`, retour arrière sur échec de santé, M12-E30).

## Flux (extrait de la matrice du socle)

| Source | Destination | Port | Usage |
|---|---|---|---|
| `runner02` (10.10.20.17) | Internet | 443 | images de base, dépendances |
| `runner02` | `ctr01` (VLAN 99) | 5000 | poussée des images |
| `ctr02` (VLAN 99) | `ctr01` | 5000 | tirage (même VLAN, sans traverser la bordure) |
| `ctr01` | `ca01` (10.10.20.11) | 443 | ACME du certificat du registre |
| MGMT (`adm01`) | `ctr01`-`ctr03`, `runner02` | 22, 5000, 8000-8081, 9100 | administration, vérifications |

## Ce qui n'est pas redondant (assumé pour la v1)

Un seul registre (pas de réplication, pas de sauvegarde des images : elles se reconstruisent par la CI), une seule machine de recette, un seul runner à exécuteur `docker`, un seul hyperviseur physique.

## Ce qui change avec les modules suivants

| Module | Changement |
|---|---|
| M13 | Harbor (`reg01`) remplace le registre de travail : projets, robots, immuabilité, signature Cosign, Trivy, caches de Docker Hub ; `ctr01` détruite après la migration des images |
| M14 | Les mêmes images tournent sur `k8s-par1` ; `/sante` devient la sonde de vivacité, `/pret` la sonde de disponibilité |
| M19 | La CI des images passe sur des runners Kubernetes ; `runner02` reste pour les cas particuliers |
