locals {
  octets = split(".", var.ipv4)
  # Zones inverses du lab (PLAN.md §4.8) : 10.10.0.0/16 et 10.20.0.0/16.
  zone_inverse = "${local.octets[1]}.${local.octets[0]}.in-addr.arpa."
  nom_ptr      = "${join(".", reverse(local.octets))}.in-addr.arpa."
  # Marque de propriété lue par la synchronisation NetBox → PowerDNS (M06-E15) et par les humains.
  commentaire = "gere-par=opentofu (plateforme/infra)"
}

check "zone_inverse_geree" {
  assert {
    condition     = contains(["10.10.in-addr.arpa.", "20.10.in-addr.arpa."], local.zone_inverse)
    error_message = "Adresse ${var.ipv4} hors des zones inverses gérées (10.10/16, 10.20/16)."
  }
}

resource "powerdns_record" "a" {
  zone     = var.zone
  name     = "${var.nom}."
  type     = "A"
  ttl      = var.ttl
  records  = [var.ipv4]
  comments = [local.commentaire]
}

resource "powerdns_record" "ptr" {
  count    = var.ptr ? 1 : 0
  zone     = local.zone_inverse
  name     = local.nom_ptr
  type     = "PTR"
  ttl      = var.ttl
  records  = ["${var.nom}."]
  comments = [local.commentaire]
}
