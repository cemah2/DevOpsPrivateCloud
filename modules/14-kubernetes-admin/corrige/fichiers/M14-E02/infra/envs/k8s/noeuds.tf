# noeuds.tf — les nœuds du cluster k8s-par1 (M14-E02, PLAT-1502). PLAN §4.10.
#
# Une seule règle, partagée avec l'inventaire Ansible (group_vars/k8s_par1/kubernetes.yml) :
#   suffixe = dernier octet de l'adresse : 51-53 (plan de contrôle), 61-64 (travailleurs)
#   VMID    = 2090 + suffixe pour le plan de contrôle (2141-2143),
#             2083 + suffixe pour les travailleurs (2144-2147)
#   adresse = 10.10.40.<suffixe>/24 (VLAN 40, VNet vk8s, passerelle 10.10.40.1)
#   MAC     = bc:24:11:40:00:<suffixe>
# On écrit le VMID en clair dans la table plutôt que de le calculer : il se lit et se cherche.

locals {
  plan_controle = {
    k8s-cp01 = { vmid = 2141, suffixe = 51 }
    k8s-cp02 = { vmid = 2142, suffixe = 52 }
    k8s-cp03 = { vmid = 2143, suffixe = 53 }
  }
  travailleurs = merge(
    {
      k8s-w01 = { vmid = 2144, suffixe = 61 }
      k8s-w02 = { vmid = 2145, suffixe = 62 }
      k8s-w03 = { vmid = 2146, suffixe = 63 }
    },
    # k8s-w04 : ajout puis retrait d'un nœud (M14-E17), détruit en fin de module.
    var.avec_k8s_w04 ? { k8s-w04 = { vmid = 2147, suffixe = 64 } } : {}
  )

  # Gabarits : 2 vCPU / 4 Go / 40 Gio (contrôle), 4 vCPU / 8 Go / 60 Gio (travailleurs).
  noeuds = merge(
    { for nom, n in local.plan_controle : nom => merge(n, {
      coeurs         = 2
      memoire_mo     = 4096
      disque_go      = 40
      etiquette_role = "role-k8s-cp"
      description    = "k8s-par1 : plan de contrôle (etcd empilé, keepalived + HAProxy de la VIP d'API). plateforme/k8s."
    }) },
    { for nom, n in local.travailleurs : nom => merge(n, {
      coeurs         = 4
      memoire_mo     = 8192
      disque_go      = 60
      etiquette_role = "role-k8s-worker"
      description    = "k8s-par1 : travailleur. plateforme/k8s."
    }) },
  )
}

module "noeud" {
  # vm-noeud v2.3.0 (M08-E02, complété en M10-E02 : MAC imposée). Mets l'étiquette publiée par
  # ta MR sur plateforme/tofu-modules si la numérotation diffère.
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.3.0"
  for_each = local.noeuds

  nom         = each.key
  vmid        = each.value.vmid
  noeud       = var.noeud
  famille     = "debian13"
  description = each.value.description
  etiquettes  = ["env-k8s", each.value.etiquette_role]

  # null = CPU de la famille (x86-64-v2-AES) : pas de virtualisation imbriquée dans ce cluster.
  type_cpu   = null
  coeurs     = each.value.coeurs
  memoire_mo = each.value.memoire_mo
  disque_go  = each.value.disque_go
  stockage   = "local-nvme"

  # Une seule carte au palier 1 (VLAN 40). M16 ajoute une carte VLAN 30 aux travailleurs.
  cartes = [
    { vnet = "vk8s", prefixe = "10.10.40.0/24", ipv4 = "10.10.40.${each.value.suffixe}",
    mac = format("bc:24:11:40:00:%d", each.value.suffixe), passerelle = true },
  ]
  resolveurs = ["10.10.20.10", "10.10.20.16"]

  cle_ssh_admin = var.cle_ssh_admin
  # Cluster « arrêtable » (PLAN §4.10) : pas de démarrage avec pve01. Procédure d'arrêt et de
  # démarrage dans modules/14-kubernetes-admin/enonce/00-introduction.md (règles du module).
  demarrage_auto = false
}

output "noeuds" {
  description = "Nœuds de k8s-par1 : VMID, adresse, nom, MAC."
  value = { for nom, m in module.noeud : nom => {
    vmid = m.vmid
    ipv4 = m.ipv4
    fqdn = m.fqdn
    macs = m.macs
  } }
}
