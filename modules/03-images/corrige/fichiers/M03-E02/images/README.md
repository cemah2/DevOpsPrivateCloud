# plateforme/images — images dorées MédiSphère

Construction, test, versionnage et publication des templates Proxmox du lab avec Packer.

| VMID | Nom | Construit par |
|---|---|---|
| 9001 | `tpl-debian13-base` | `debian13-base/` (ISO + preseed) |
| 9002 | `tpl-rocky10-base` | `rocky10-base/` (ISO + kickstart) |
| 9010-9029 | `deb13-gold-AAAAMMJJ-N` | `debian13-gold/` (clone de 9001) |
| 9030-9049 | `rocky10-gold-AAAAMMJJ-N` | `rocky10-gold/` (clone de 9002) |
| 9090-9099 | essais | — |

Les consommateurs (Ansible, OpenTofu) choisissent un template par ses étiquettes Proxmox :
`gold` + `debian13` (ou `rocky10`) + `current`. Jamais par son VMID ni par son nom.

## Prérequis sur le poste de construction

- Packer 1.16 (dépôt APT HashiCorp), plugin `github.com/hashicorp/proxmox` ~> 1.2.4 (`packer init`).
- Autorité de `pve01` approuvée par le magasin système (`/usr/local/share/ca-certificates/`).
- Accès : `~/.config/workbook/pve-packer.env` (600), jeton `wb-packer@pve!packer` — voir le registre des secrets.
- Flux : VNet `vsandbox` → poste de construction, TCP 8100-8199 (serveur HTTP de Packer).

## Construire

```
outils/construire.sh debian13-base
```

## Contribuer

Voir `CONTRIBUTING.md`. `pre-commit install` après le clonage : `packer fmt` et
`packer validate -syntax-only` tournent à chaque commit.

Licence de Packer : BUSL 1.1 (usage interne autorisé).
