# `socle/` — VMs permanentes du socle MédiSphère

Configuration OpenTofu de l'état **`socle`** (`s3://tofu-state/socle/terraform.tfstate` sur `s3-01`).

| VM | VMID | Géré comment | Depuis |
|---|---|---|---|
| `s3-01` | 1006 | créée par le code (module `vm-debian`) | M05-E10, module en M05-E17 |
| `adm01`, `dns01`, `git01`, `runner01` | 1001, 1002, 1004, 1007 | importées (`imports.tf`), `prevent_destroy` | M05-E16 |
| `gw01` | 1000 | **hors OpenTofu**, surveillée par un bloc `check` (ADR-0051) | M05-E16 |

Règles : jamais de `tofu destroy` ici ; un plan qui **remplace** une VM s'arrête là
(on cherche pourquoi) ; l'intérieur des VMs est géré par `plateforme/ansible`.

Lancement : `cd socle && set -a && . ~/.config/workbook/pve-tofu.env && . ~/.config/workbook/s3-tofu.env && set +a && tofu plan`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | ~> 1.13.0 |
| proxmox | ~> 0.115.0 |

### Providers

| Name | Version |
| ---- | ------- |
| proxmox | ~> 0.115.0 |

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| s3\_01 | git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian | v1.1.0 |

### Resources

| Name | Type |
| ---- | ---- |
| [proxmox_virtual_environment_vm.socle](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cles\_ssh\_admin | Clés SSH PUBLIQUES injectées par cloud-init pour le compte admin. | `list(string)` | n/a | yes |
| noeud | Nom du nœud Proxmox qui héberge le socle (<NOEUD>, voir pvesh get /nodes). | `string` | n/a | yes |
| datastore\_donnees | Stockage des gros disques de données peu sollicités (PLAN.md §3.2). | `string` | `"hdd-bulk"` | no |
| datastore\_systeme | Stockage des disques système et des lecteurs cloud-init (PLAN.md §3.2). | `string` | `"local-nvme"` | no |
| dns | Résolveur et domaine de recherche du lab (dnsmasq de dns01 jusqu'au module 06). | ```object({ serveurs = list(string) domaine = string })``` | ```{ "domaine": "par1.medisphere.internal", "serveurs": [ "10.10.20.10" ] }``` | no |
| pool | Pool Proxmox de toutes les VMs du workbook (PLAN.md §4.3 bis). | `string` | `"lab"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| s3\_01 | Identité de s3-01 (lue par les vérifications et la documentation). |
| socle\_importe | VMs du socle importées (nom → VMID). |
<!-- END_TF_DOCS -->
