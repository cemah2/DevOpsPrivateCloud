<!-- docs/kubernetes/equipes/medidoc.md (M14-E33) : sections MISES À JOUR en M20-E33 (DEV-2133). -->

## Environnements

| Environnement | Espace | Nom publié | Stockage (RGW `ceph-par1`) | Application Argo CD | Synchronisation |
|---|---|---|---|---|---|
| dev | `medidoc-dev` | `medidoc-dev.apps.par1.medisphere.internal` | `medidoc-documents` (compte `medidoc-app`) | `medidoc-dev` | automatique (`prune`, `selfHeal`) |
| recette | `medidoc-recette` | `medidoc-recette.apps.par1.medisphere.internal` | `medidoc-recette-documents` (compte `medidoc-recette`) | `medidoc-recette` | automatique |
| prod | à venir | — | — | — | manuelle, fenêtre `deny` du vendredi (E29) déjà posée |

## Dépôts et droits

- Code : `medidoc/medidoc` (pipeline M19-E33) ; déploiement : `medidoc/deploiement` (base + `overlays/dev`, `overlays/recette`), MR relues par les Maintainers de l'équipe.
- Argo CD : projet `medidoc`, ApplicationSet `medidoc` (`plateforme/gitops`) ; rôle de projet `equipe` (groupe `medisphere:medidoc-devs`, actif avec le SSO au M24) : lire tout le projet, synchroniser dev et recette.
- Secrets : `harbor-pull`, `medidoc-s3` par `secrets-k8s.sh` (Vault `critique`, `secrets/medidoc-<env>.yml`), jamais dans un dépôt.
