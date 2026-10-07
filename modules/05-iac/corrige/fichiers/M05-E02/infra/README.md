# plateforme/infra — l'infrastructure du lab MédiSphère, déclarée

Ce dépôt décrit **ce qui doit exister** sur l'hyperviseur `pve01` (VMs, disques, réseaux
utilisés) avec [OpenTofu](https://opentofu.org/). On ne crée plus une VM durable à la main ni
par script : on modifie ce code, on relit le **plan** en merge request, puis on l'applique.

## Arborescence

| Dossier | Contenu | Depuis |
|---|---|---|
| `envs/lab-m05/` | Environnement d'exercices du module 05 (VMs 2050-2059, VNet `vsandbox`) | M05-E03 |
| `socle/` | VMs permanentes du socle : `s3-01` créée par le code, les autres importées | M05-E10, E16 |
| `terragrunt/` | Factorisation des backends et providers | M05-E24 |

Chaque dossier racine (`envs/…`, `socle/`) est une **configuration** OpenTofu indépendante,
avec son propre état.

## Prérequis sur le poste

- OpenTofu **1.13.x** (dépôt APT officiel, série épinglée) : `tofu version`.
- Accès à l'API Proxmox : `~/.config/workbook/pve-tofu.env` (jeton `wb-tofu@pve!tofu`,
  jamais dans ce dépôt), chargé avant chaque commande :
  `set -a; . ~/.config/workbook/pve-tofu.env; set +a`.
- `pre-commit install` après le clone.

## Travailler

```
cd envs/lab-m05
tofu init          # providers aux versions de .terraform.lock.hcl
tofu plan          # TOUJOURS lu en entier avant un apply
tofu apply         # après fusion de la MR, depuis main à jour
```

Règles : voir `CONTRIBUTING.md`. Les secrets ne passent jamais par une variable OpenTofu
versionnée ; `terraform.tfvars` est versionné parce qu'il ne contient rien de secret.
