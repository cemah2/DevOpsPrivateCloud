# Accueillir une équipe en GitOps

| | |
|---|---|
| Ticket | DEV-2133 (MédiDoc, M20-E33) |
| Complète | `docs/kubernetes/accueil-equipe.md` (M14-E33) |
| Dernière revue | <DATE> |

## Qui fait quoi

| Élément | Où | Qui (MR relue par) |
|---|---|---|
| Espace, étiquettes (`medisphere.internal/equipe`, Pod Security, exposition), quota, LimitRange, refus réseau par défaut, compte `default` | `plateforme/k8s` `espaces/<équipe>-<env>/` | Plateforme |
| Cloison `isolement-<équipe>-<env>`, politiques d'entrée et de sortie de l'application | `plateforme/k8s` `composants/reseau/politiques/`, `applications/<équipe>-<env>/` | Plateforme + RSSI |
| Secrets (`harbor-pull`, identifiants S3…) | Vault `critique` `secrets/<équipe>-<env>.yml`, `outils/secrets-k8s.sh appliquer <équipe>-<env>` | Plateforme |
| Compte et compartiment de stockage objet par environnement | RGW (IAM, méthode du M08-E12) | Plateforme |
| AppProject `<équipe>` (sources, destinations, listes noires, rôle `equipe`, fenêtres) | `plateforme/gitops` `projets/` | Plateforme |
| ApplicationSet `<équipe>` (un élément par environnement) | `plateforme/gitops` `applications/` | Plateforme |
| Manifestes de l'application (base, overlays, images par digest) | dépôt `<équipe>/deploiement` | **Équipe** (Maintainers de l'équipe) |
| Promotion d'un environnement à l'autre | MR sur `<équipe>/deploiement` | **Équipe**, production : Plateforme |

## Étapes (ordre)

1. Fiche d'équipe (`docs/kubernetes/equipes/<équipe>.md`) : environnements, enveloppe, référent, dépôts.
2. Stockage et secrets : compte et compartiment par environnement, entrées du Vault.
3. MR `plateforme/k8s` : `espaces/<équipe>-<env>/`, politiques ; `task appliquer` ; `secrets-k8s.sh appliquer <équipe>-<env>`.
4. MR `plateforme/gitops` : AppProject (destinations), ApplicationSet (élément de liste).
5. L'équipe : overlay `<env>` dans son dépôt (MR), image par digest.
6. Contrôles : `argocd app get <équipe>-<env>` `Synced`/`Healthy` ; `/readyz` par le nom publié ; `kubectl auth can-i` des personnes de l'équipe ; recherche de `kind: Secret` dans le dépôt de l'équipe (aucun).

## Reprendre un environnement déjà déployé à la main

- L'Application générée doit avoir **le même nom** que celle qui gérait l'environnement (s'il y en avait une) : l'ApplicationSet la reprend sans la recréer.
- `ServerSideApply=true` : Argo CD devient co-propriétaire des champs ; aucune ressource n'est recréée tant que le rendu est identique à l'existant (`argocd app diff` vide **avant** la première synchronisation).
- Les anciens gestionnaires de champs (`kubectl`) se retirent ensuite (`outils/nettoyer-gestionnaires.sh`, M20-E30).

## Pièges vécus (MédiDoc)

- Le `ConfigMap` de la racine MédiSphère n'était pas dans la base de l'équipe (créé à la main en M15-E34) : la recette ne démarrait pas (volume introuvable). Ajouté à l'overlay par un générateur.
- La cloison `isolement-<équipe>-<env>` sépare **aussi** dev et recette de la même équipe : voulu (règle 1 de la segmentation).
- Le Secret `medidoc-s3` apparaît en « ressource orpheline » sans la liste `ignore` de l'AppProject.
