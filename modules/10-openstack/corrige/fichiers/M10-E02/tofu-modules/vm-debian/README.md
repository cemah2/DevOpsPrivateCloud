# Module `vm-debian` (v2.2)

VM Debian 13 du lab MédiSphère : clone **complet** de l'image dorée `current` (M03), configurée par
cloud-init, **enregistrée dans NetBox avant d'exister** (M06-E13).

## Ce qui change en v2 (rupture)

- L'adresse IPv4 ne vient plus d'une variable : elle est **allouée** par NetBox dans une plage
  (`plage_adresses`), ou **imposée** (`ipv4_imposee`) pour les hôtes du socle dont l'adresse est fixée
  par PLAN.md §4.5. La passerelle se déduit du préfixe (`.1`).
- L'appelant doit configurer le fournisseur `e-breuninger/netbox` (`~> 5.8.0`) en plus de `bpg/proxmox`.
- Variables retirées : `ipv4`, `passerelle`. Variables ajoutées : `reseau_prefixe`, `plage_adresses`,
  `ipv4_imposee`, `netbox_cluster`, `domaine`.

## Ce qui change en v2.2 (M10-E02, ajout rétrocompatible)

Version **mineure** : un appelant de v2.1 qui ne renseigne aucune des nouvelles variables obtient
exactement la même VM et le même plan (aucun changement).

| Variable | Défaut | Rôle |
|---|---|---|
| `type_cpu` | `x86-64-v2-AES` | `host` pour un hyperviseur imbriqué (calculs OpenStack) ou pour Rocky 10 |
| `mac_adresse` | `null` | MAC de la carte principale (sinon tirée par Proxmox) |
| `mtu` | `null` | MTU annoncée à l'invité sur la carte principale (virtio) |
| `interface_principale` | `eth0` | nom de la carte principale dans NetBox |
| `cartes_supplementaires` | `[]` | cartes `net1`… : `vnet`, `interface` (nom NetBox), `mac_adresse`, `mtu`, `ipv4_imposee` + `prefixe` (facultatifs, ensemble) |

Règles :
- une carte supplémentaire adressée n'a **pas** de passerelle : la route par défaut reste sur la carte principale ;
- les cartes **sans adresse** viennent **après** toutes les cartes adressées. Proxmox associe `ipconfigN` à `netN` par leur numéro ; le module produit un bloc `ip_config` par carte adressée, dans l'ordre : une carte sans adresse au milieu décalerait la configuration des suivantes. Une validation le refuse au `plan` ;
- une carte sans adresse n'a pas d'`ipconfigN` : cloud-init ne la configure pas, et l'invité lui donne son nom « prévisible » (`ens21` pour `net3` sur une machine i440fx). Un rôle Ansible peut la renommer (M10-E02) ;
- le pare-feu de Proxmox est désactivé sur toutes les cartes (`firewall = false`, défaut du fournisseur, écrit explicitement) : une carte qui porte des adresses MAC de VMs imbriquées ou de routeurs virtuels (OVN) ne doit pas être filtrée par MAC ;
- NetBox reçoit une interface par carte (nom, MTU) et l'adresse des cartes adressées, **sans** nom DNS (le nom désigne l'adresse principale). Les adresses MAC ne sont pas écrites dans NetBox par le module (NetBox 4.2+ les modélise comme objets séparés) : la synchronisation Proxmox → NetBox (M06-E11) s'en charge si tu l'as étendue.

Exemple (calcul OpenStack) :

```hcl
module "oscmp01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v2.2.0"

  nom                  = "oscmp01"
  vmid                 = 2102
  type_cpu             = "host"
  vnet                 = "vosapi"
  mac_adresse          = "bc:24:11:50:00:52"
  interface_principale = "ens18"
  reseau_prefixe       = "10.10.50.0/24"
  ipv4_imposee         = "10.10.50.52"
  cartes_supplementaires = [
    { vnet = "vostun", interface = "ens19", mac_adresse = "bc:24:11:51:00:52", mtu = 9000, ipv4_imposee = "10.10.51.52", prefixe = "10.10.51.0/24" },
    { vnet = "vstopub", interface = "ens20", mac_adresse = "bc:24:11:30:00:52", mtu = 9000, ipv4_imposee = "10.10.30.62", prefixe = "10.10.30.0/24" },
  ]
  # …
}
```

Sortie ajoutée : `macs` (liste des MAC, dans l'ordre des cartes).

## Ce que le module écrit dans NetBox, et ce qu'il laisse

| Objet / champ | Écrit par le module | Remarque |
|---|---|---|
| VM (nom, cluster, statut, vCPU, mémoire, disque, étiquettes, commentaire) | oui | intention |
| interface `eth0`, adresse IP (`dns_name` = nom complet), IP primaire | oui | rendue au `destroy` |
| champ personnalisé `vmid` | **non** (`ignore_changes`) | écrit par la synchronisation Proxmox → NetBox (M06-E11), Proxmox fait foi |
| disques virtuels, adresse MAC | non | |

Le DNS (A et PTR) n'est **pas** dans ce module : module `enregistrement-dns` (M06-E14).

## Exemple

```hcl
module "ipam01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v2.0.0"

  nom            = "m06-ipam01"
  vmid           = 2063
  noeud          = var.noeud
  vnet           = "vsandbox"
  etiquettes     = ["env-m06"]
  reseau_prefixe = "10.10.99.0/24"
  plage_adresses = "10.10.99.10"   # plage « statique » .10-.49
  cle_ssh_admin  = var.cle_ssh_admin
}
```

Hôte du socle : `ipv4_imposee = "10.10.20.16"` à la place de `plage_adresses`.

## Entrées principales

| Nom | Type | Défaut | Rôle |
|---|---|---|---|
| `nom` | string | — | nom Proxmox, NetBox et d'hôte |
| `vmid` | number | — | 1000-1099 (socle) ou 2000-2999 |
| `noeud` | string | — | nœud Proxmox |
| `vnet` | string | — | VNet de la carte réseau |
| `etiquettes` | list(string) | — | étiquettes Proxmox et NetBox (doivent exister dans NetBox) |
| `cle_ssh_admin` | string | — | clé publique injectée pour `admin` |
| `reseau_prefixe` | string | — | préfixe du VLAN (masque, passerelle) |
| `plage_adresses` | string | `null` | adresse contenue dans la plage d'allocation |
| `ipv4_imposee` | string | `null` | adresse imposée (hôte du socle) |
| `coeurs`, `memoire_mo`, `disque_go` | number | 1, 1024, 10 | ressources |
| `stockage`, `pool`, `domaine`, `resolveurs` | | `local-nvme`, `lab`, `par1.medisphere.internal`, `[10.10.20.10]` | |
| `demarrage_auto` | bool | `true` | démarrage avec l'hyperviseur (l'ordre de démarrage se pose en root : `qm set <VMID> --startup order=<N>`) |

## Sorties

`vmid`, `nom`, `ipv4` (sans masque), `ipv4_cidr`, `fqdn`, `netbox_vm_id`.

## Compatibilité

Fournisseur NetBox 5.8 : NetBox 4.3 à 4.6.5 validés par l'éditeur ; au-delà, avertissement non bloquant
au `plan` (« version non supportée ») — à lire à chaque montée de version de NetBox.
