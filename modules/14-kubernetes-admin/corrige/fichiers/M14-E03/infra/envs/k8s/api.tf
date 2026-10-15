# api.tf — point d'accès de l'API de k8s-par1 (M14-E03, PLAT-1503). PLAN §4.10.
# La VIP 10.10.40.200 n'appartient à aucune VM : keepalived (VRID 140) la porte sur l'un des trois
# nœuds de contrôle, HAProxy y écoute en 8443 et répartit vers les kube-apiserver (6443).
# Dans NetBox : adresse de rôle « vip », sans interface (elle se déplace), comme lb (M07-E12).

locals {
  api_vip = "10.10.40.200"
  api_nom = "k8s-api.par1.medisphere.internal"
}

resource "netbox_ip_address" "api_vip" {
  ip_address  = "${local.api_vip}/24"
  status      = "active"
  role        = "vip"
  dns_name    = local.api_nom
  description = "VIP de l'API de k8s-par1 : keepalived VRID 140 + HAProxy 8443 sur k8s-cp01-03 (M14-E03)"
}

# Un nom de SERVICE : pas de PTR (l'adresse ne désigne pas une machine).
module "dns_api" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = netbox_ip_address.api_vip.dns_name
  ipv4 = local.api_vip
  ptr  = false
  ttl  = 300
}

output "api" {
  description = "Point d'accès de l'API Kubernetes."
  value = {
    vip      = local.api_vip
    fqdn     = local.api_nom
    endpoint = "https://${local.api_nom}:8443"
  }
}
