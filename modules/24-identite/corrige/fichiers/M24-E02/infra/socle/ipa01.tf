# socle/ipa01.tf — plateforme/infra, état « socle » (M24-E02, ticket PLAT-2502).
#
# ipa01 : annuaire de MédiSphère (FreeIPA 4.13 : LDAP, Kerberos, HBAC, sudo, CA subordonnée).
# VMID 1031, 10.10.20.31 (PLAN §4.5), VLAN 20 INFRA, hôte PERMANENT du socle (socle v5).
# Rocky Linux 10 : FreeIPA serveur n'existe pas pour Debian. D'où le module vm-noeud (familles
# debian13 et rocky10, M08-E02) plutôt que vm-debian ; il enregistre la VM dans NetBox comme
# vm-debian (VM, interface, adresse imposée, IP primaire).
#
# Pas de DNS intégré à FreeIPA : PowerDNS reste la seule autorité de par1.medisphere.internal.
# Les enregistrements que FreeIPA attend (SRV, TXT, ipa-ca) sont donc publiés ICI, par la même
# API que tout le reste (M06-E13). La liste de référence est celle que donne, après installation :
#   [root@ipa01 ~]# ipa dns-update-system-records --dry-run
#
# Pré-requis NetBox : étiquette « role-annuaire » (script de modélisation de M06-E05 : à ajouter à
# son fichier de données si elle n'existe pas encore). Si 10.10.20.31 existe déjà dans NetBox
# (réservée par la modélisation de M06-E05), supprime-la ou importe-la avant l'apply (RB-060).

module "ipa01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=<VERSION-TOFU-MODULES>"

  nom         = "ipa01"
  vmid        = 1031
  noeud       = var.noeud
  famille     = "rocky10" # image dorée rocky10 « current » (M03) ; CPU x86-64-v3 imposé par la famille
  coeurs      = 2
  memoire_mo  = 4096 # 389-ds + Dogtag (Java) + KDC + httpd : 4 Go conseillés, moins = installation lente
  disque_go   = 40
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-annuaire"]
  description = "Annuaire FreeIPA 4.13 (LDAP, Kerberos PAR1.MEDISPHERE.INTERNAL, CA subordonnée), M24-E02."

  cartes = [
    { vnet = "vinfra", prefixe = "10.10.20.0/24", ipv4 = "10.10.20.31", passerelle = true },
  ]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = true # tout le lab s'authentifie contre lui : il démarre avec pve01
  protection     = true # pas de suppression par erreur (Proxmox refuse tant que le drapeau est posé)
  # Ordre de démarrage 3 (après gw01, les DNS, ca01 ; avant git01 et idp01), posé en root :
  #   root@pve01:~# qm set 1031 --startup order=3
}

module "dns_ipa01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"

  nom  = module.ipa01.fqdn
  ipv4 = module.ipa01.ipv4
  ttl  = 3600
}

locals {
  zone_par1 = "par1.medisphere.internal."
  ipa_cible = "${module.ipa01.fqdn}."
  # Services Kerberos et LDAP du domaine IPA (priorité 0, poids 100, port, cible).
  ipa_srv = {
    "_ldap._tcp"            = "0 100 389 ${local.ipa_cible}"
    "_kerberos._tcp"        = "0 100 88 ${local.ipa_cible}"
    "_kerberos._udp"        = "0 100 88 ${local.ipa_cible}"
    "_kerberos-master._tcp" = "0 100 88 ${local.ipa_cible}"
    "_kerberos-master._udp" = "0 100 88 ${local.ipa_cible}"
    "_kpasswd._tcp"         = "0 100 464 ${local.ipa_cible}"
    "_kpasswd._udp"         = "0 100 464 ${local.ipa_cible}"
  }
}

resource "powerdns_record" "ipa_srv" {
  for_each = local.ipa_srv

  zone     = local.zone_par1
  name     = "${each.key}.${local.zone_par1}"
  type     = "SRV"
  ttl      = 3600
  records  = [each.value]
  comments = ["gere-par=opentofu (plateforme/infra), FreeIPA sans DNS intégré (M24-E02)"]
}

# Nom du royaume Kerberos du domaine : les clients le trouvent ici (dns_lookup_realm).
resource "powerdns_record" "ipa_royaume" {
  zone     = local.zone_par1
  name     = "_kerberos.${local.zone_par1}"
  type     = "TXT"
  ttl      = 3600
  records  = ["\"PAR1.MEDISPHERE.INTERNAL\""]
  comments = ["gere-par=opentofu (plateforme/infra), FreeIPA sans DNS intégré (M24-E02)"]
}

# ipa-ca : nom écrit dans les certificats émis par la CA de FreeIPA (OCSP, CRL). Un A (et pas un
# CNAME) : c'est ce que crée FreeIPA quand il gère son DNS, et ce que vérifie ipa-healthcheck.
resource "powerdns_record" "ipa_ca" {
  zone     = local.zone_par1
  name     = "ipa-ca.${local.zone_par1}"
  type     = "A"
  ttl      = 3600
  records  = [module.ipa01.ipv4]
  comments = ["gere-par=opentofu (plateforme/infra), OCSP et CRL de la CA de FreeIPA (M24-E02)"]
}

output "ipa01" {
  description = "Identité de ipa01 (VMID, adresse, nom d'hôte) et noms publiés pour FreeIPA."
  value = {
    vmid = module.ipa01.vmid
    ipv4 = module.ipa01.ipv4
    fqdn = module.ipa01.fqdn
    srv  = sort(keys(local.ipa_srv))
  }
}
