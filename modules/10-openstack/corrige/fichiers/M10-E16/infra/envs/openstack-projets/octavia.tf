# Quotas Octavia des projets d'équipe (M10-E16), ajoutés à envs/openstack-projets.
# Posés d'abord en CLI (openstack loadbalancer quota set), puis importés (bloc ci-dessous,
# retiré après application). Suppression sans effet côté OpenStack (no-op).

variable "repartiteurs" {
  description = "Nombre de répartiteurs de charge autorisés par projet (docs/cloud/capacite.md)."
  type        = map(number)
  default = {
    "mediagenda-dev"  = 2
    "mediagenda-prod" = 2
  }
}

resource "openstack_lb_quota_v2" "q" {
  for_each       = var.repartiteurs
  project_id     = data.openstack_identity_project_v3.p[each.key].id
  loadbalancer   = each.value
  listener       = each.value * 2
  pool           = each.value * 2
  member         = each.value * 10
  health_monitor = each.value * 2
  # Le fournisseur OVN ne fait pas de L7 : rien à autoriser.
  l7_policy = 0
  l7_rule   = 0
}

import {
  for_each = var.repartiteurs
  to       = openstack_lb_quota_v2.q[each.key]
  id       = "${data.openstack_identity_project_v3.p[each.key].id}/${var.region}"
}
