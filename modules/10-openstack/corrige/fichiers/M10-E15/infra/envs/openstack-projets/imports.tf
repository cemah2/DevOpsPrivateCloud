# Reprise des quotas posés à la main en M10-E13 (relu en MR, puis RETIRÉ une fois appliqué).
# Identifiant d'import des trois ressources de quota : <id du projet>/<région>.
# ⚠️ À vérifier sur ta version d'OpenTofu : l'identifiant référence une source de données, lue
# pendant le plan. Si OpenTofu le refuse (« value must be known »), remplace-le par les
# identifiants littéraux des projets (openstack project show -f value -c id …).

import {
  for_each = var.projets
  to       = openstack_compute_quotaset_v2.q[each.key]
  id       = "${data.openstack_identity_project_v3.p[each.key].id}/${var.region}"
}

import {
  for_each = var.projets
  to       = openstack_blockstorage_quotaset_v3.q[each.key]
  id       = "${data.openstack_identity_project_v3.p[each.key].id}/${var.region}"
}

import {
  for_each = var.projets
  to       = openstack_networking_quota_v2.q[each.key]
  id       = "${data.openstack_identity_project_v3.p[each.key].id}/${var.region}"
}
