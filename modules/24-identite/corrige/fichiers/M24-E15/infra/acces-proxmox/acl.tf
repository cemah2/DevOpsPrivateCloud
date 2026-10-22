# acces-proxmox/acl.tf — droits des groupes de l'annuaire sur pve01 (M24-E15). Matrice :
# docs/securite/identite/modele-autorisation.md (M24-E10). Rôles intégrés de Proxmox VE seulement.
locals {
  acl = {
    "plateforme-admins-racine" = { groupe = "plateforme-admins", chemin = "/", role = "PVEAdmin" }
    "plateforme-racine"        = { groupe = "plateforme", chemin = "/", role = "PVEAuditor" }
    "securite-racine"          = { groupe = "securite", chemin = "/", role = "PVEAuditor" }
    "support-pool-lab"         = { groupe = "support", chemin = "/pool/lab", role = "PVEAuditor" }
  }
}

# PVEAdmin et non Administrator : tout sauf la gestion des droits et des royaumes (Permissions.Modify,
# Realm.Allocate) et quelques privilèges système ; changer les accès reste un geste root@pam par ce
# dépôt, relu en MR.
resource "proxmox_acl" "groupe" {
  for_each  = local.acl
  group_id  = proxmox_virtual_environment_group.annuaire[each.value.groupe].group_id
  path      = each.value.chemin
  role_id   = each.value.role
  propagate = true
}
