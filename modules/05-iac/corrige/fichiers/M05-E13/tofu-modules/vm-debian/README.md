# Module `vm-debian`

Une VM Debian 13 du lab MédiSphère, **clone complet** de l'image dorée courante (template
étiqueté `gold` + `debian13` + `current`, module 03), configurée par cloud-init et
étiquetée pour l'inventaire dynamique Ansible (`socle`, `role-<rôle>`, `env-<env>`).

## Utilisation

```hcl
module "s3_01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.0.0"

  nom             = "s3-01"
  vm_id           = 1006
  noeud           = var.noeud
  socle           = true
  role            = "s3"
  memoire_mo      = 2048
  disques_donnees = [{ taille_go = 100 }]
  reseau          = { vnet = "vinfra", ipv4 = "10.10.20.14/24", passerelle = "10.10.20.1" }
  cles_ssh        = var.cles_ssh_admin
  protection      = true # Proxmox refuse la suppression
  proteger        = true # OpenTofu refuse tout plan qui détruit la VM
}
```

## Choix et limites

- **Nouvelle image dorée** : le module ignore les changements de `clone` (`ignore_changes`).
  Une VM existante n'est donc **jamais** recréée parce que `current` a changé de template.
  Pour la reconstruire sur la nouvelle image : `tofu apply -replace='module.<nom>.proxmox_virtual_environment_vm.vm'`,
  après avoir vérifié ce qu'elle perd (données hors disques de données).
- **Deux protections pour le socle** : `proteger = true` pose `prevent_destroy` (OpenTofu
  refuse tout plan qui détruit ou remplace la VM ; une variable n'est acceptée là que depuis
  OpenTofu 1.12, d'où `required_version >= 1.12.0`) et `protection = true` pose le drapeau
  Proxmox (refus de suppression même hors d'OpenTofu). Aucune des deux ne protège une VM
  dont l'appel de module est supprimé ou renommé sans bloc `moved` : la relecture du plan
  reste indispensable.
- **Rang de démarrage** : Proxmox exige `Sys.Modify` sur `/` pour régler `startup`, que le
  jeton d'OpenTofu n'a pas. `ordre_demarrage` reste donc `null` avec `wb-tofu` : le rang se
  pose une fois en root (`qm set <vmid> --startup order=N`) et le module l'ignore ensuite.
- **Snippets cloud-init** : `user_data_file_id` remplace `utilisateur`/`cles_ssh` ; le
  changer recrée la VM (attribut à remplacement forcé du provider).
- Disques de données : `scsi1`, `scsi2`… dans l'ordre de la liste ; dans la VM :
  `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsiN`. Retirer un disque du milieu
  de la liste renumérote les suivants : ajoute toujours en fin de liste.

## Tests

`tofu init && tofu test` dans ce dossier : tests unitaires avec un provider simulé
(aucun accès à Proxmox).

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.12.0 |
| proxmox | >= 0.115.0, < 1.0.0 |

### Providers

| Name | Version |
| ---- | ------- |
| proxmox | >= 0.115.0, < 1.0.0 |

### Resources

| Name | Type |
| ---- | ---- |
| [proxmox_virtual_environment_vm.vm](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [proxmox_virtual_environment_vms.image](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/data-sources/virtual_environment_vms) | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| noeud | Nom du nœud Proxmox qui héberge la VM. | `string` | n/a | yes |
| nom | Nom de la VM et nom d'hôte (court, sans domaine), ex. s3-01. | `string` | n/a | yes |
| reseau | Carte réseau : VNet SDN, adresse IPv4 en notation CIDR (ou « dhcp ») et passerelle (obligatoire en statique). | ```object({ vnet = string ipv4 = optional(string, "dhcp") passerelle = optional(string) })``` | n/a | yes |
| vm\_id | VMID Proxmox, dans une plage du PLAN : 1000-1099 (socle), 2000-2999 (environnements), 5000-5999 (sandbox). | `number` | n/a | yes |
| arret\_force | À la destruction, couper la VM (stop) au lieu d'un arrêt propre (shutdown) : pour les VMs jetables. | `bool` | `false` | no |
| cles\_ssh | Clés SSH PUBLIQUES du compte. Ignorées si user\_data\_file\_id est fourni (le snippet crée alors les comptes). | `list(string)` | `[]` | no |
| coeurs | Nombre de vCPU. | `number` | `2` | no |
| datastore\_systeme | Stockage du disque système et du lecteur cloud-init. | `string` | `"local-nvme"` | no |
| demarrage\_auto | Démarrer la VM avec l'hôte (onboot). | `bool` | `true` | no |
| description | Description affichée dans Proxmox (Notes). Une mention « gérée par OpenTofu » est ajoutée. | `string` | `""` | no |
| disque\_systeme\_go | Taille du disque système en Go (au moins celle de l'image : un disque ne rétrécit pas). | `number` | `20` | no |
| disque\_systeme\_ssd | Présenter le disque système comme un SSD à l'invité (TRIM) : vrai sur local-nvme, comme l'image. | `bool` | `true` | no |
| disques\_donnees | Disques de données supplémentaires, branchés sur scsi1, scsi2… dans l'ordre de la liste. | ```list(object({ taille_go = number datastore = optional(string, "hdd-bulk") format = optional(string, "qcow2") ssd = optional(bool, false) sauvegarde = optional(bool, true) }))``` | `[]` | no |
| dns | Résolveurs et domaine de recherche poussés par cloud-init. | ```object({ serveurs = list(string) domaine = string })``` | ```{ "domaine": "par1.medisphere.internal", "serveurs": [ "10.10.20.10" ] }``` | no |
| environnement | Environnement d'exercice (ajoute l'étiquette env-<environnement>), ex. m05. null pour le socle. | `string` | `null` | no |
| etiquettes | Étiquettes Proxmox supplémentaires. | `list(string)` | `[]` | no |
| image | Image source. Par défaut, le template doré courant de la famille (étiquettes gold + <famille> + current, M03). Fixer vm\_id pour cloner un template précis (essai d'une image candidate, reconstruction à l'identique). | ```object({ famille = optional(string, "debian13") vm_id = optional(number) })``` | `{}` | no |
| memoire\_mo | Mémoire en Mo. | `number` | `2048` | no |
| ordre\_demarrage | Rang dans l'ordre de démarrage de Proxmox (null : non ordonné), posé à la CRÉATION seulement. Proxmox exige Sys.Modify sur « / » pour régler « startup » (réglage de l'hôte) : le jeton wb-tofu ne l'a pas, laisse null et pose le rang en root (qm set VMID --startup order=N). Les changements ultérieurs du rang sont ignorés par le module. | `number` | `null` | no |
| pool | Pool Proxmox de la VM. | `string` | `"lab"` | no |
| protection | Drapeau « protection » de Proxmox : refuse la suppression de la VM et de ses disques, même par l'API. À true pour le socle. | `bool` | `false` | no |
| proteger | Interdire à OpenTofu tout plan qui détruit ou remplace la VM (lifecycle.prevent\_destroy, variable acceptée depuis OpenTofu 1.12). À true pour le socle, avec protection. | `bool` | `false` | no |
| role | Rôle de la VM (ajoute l'étiquette role-<role>, groupe Ansible role\_<role>), ex. s3. null si aucun. | `string` | `null` | no |
| socle | VM permanente du socle : ajoute l'étiquette « socle » (inventaire Ansible). | `bool` | `false` | no |
| type\_cpu | Type de CPU émulé. Celui de l'image dorée Debian (M03) ; Rocky 10 exige x86-64-v3 ou host. | `string` | `"x86-64-v2-AES"` | no |
| user\_data\_file\_id | Snippet cloud-init user-data (ex. hdd-bulk:snippets/x.yaml, M05-E19). Remplace utilisateur et cles\_ssh. Le changer RECRÉE la VM. | `string` | `null` | no |
| utilisateur | Compte créé par cloud-init (sudo sans mot de passe dans l'image dorée). | `string` | `"admin"` | no |
| vendor\_data\_file\_id | Snippet cloud-init vendor-data facultatif. Le changer RECRÉE la VM. | `string` | `null` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| etiquettes | Étiquettes Proxmox posées (elles alimentent l'inventaire dynamique Ansible). |
| fqdn | Nom complet attendu dans le DNS du lab. |
| image\_source | VMID du template cloné à la création (ou à la dernière lecture du template courant). |
| ipv4 | Adresse IPv4 : celle de la configuration si statique, sinon la première adresse non locale remontée par l'agent QEMU (null tant que l'agent ne répond pas). |
| nom | Nom de la VM (nom d'hôte court). |
| vm\_id | VMID de la VM. |
<!-- END_TF_DOCS -->
