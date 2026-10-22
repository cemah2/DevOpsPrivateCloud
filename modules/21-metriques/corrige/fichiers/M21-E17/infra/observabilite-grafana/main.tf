# observabilite-grafana/main.tf — dossiers, équipes et permissions de Grafana (M21-E17, PLAT-2217).

# Dossiers : UID FIXE (= clé de l'équipe), pour que les liens /dashboards/f/<uid> et les règles des
# checks ne changent jamais. Le titre est celui de l'annotation grafana_folder des ConfigMaps :
# le provisionnement (foldersFromFilesStructure) réutilise un dossier existant de même titre.
# prevent_destroy_if_not_empty : un « tofu destroy » ne vide pas un dossier qui contient des
# tableaux (provisionnés ou non).
resource "grafana_folder" "equipe" {
  for_each = var.equipes

  uid                          = each.key
  title                        = each.value.titre_dossier
  prevent_destroy_if_not_empty = true
}

resource "grafana_team" "equipe" {
  for_each = var.equipes

  name    = each.key
  email   = "${each.key}@medisphere.internal"
  members = each.value.membres
  admins  = each.value.admins
}

# Compte de service des vérifications du workbook (rôle Viewer, créé au M21-E05) : il doit VOIR
# tous les dossiers, sinon les checks ne trouvent pas les tableaux des équipes.
data "grafana_service_account" "wb_checks" {
  name = "wb-checks"
}

# Permissions. grafana_folder_permission REMPLACE toutes les permissions du dossier par celles
# déclarées ici (y compris celles par défaut de Grafana : Viewer et Editor de base) :
#   - chaque équipe voit son dossier ;
#   - l'équipe plateforme voit tous les dossiers (astreinte) ;
#   - le rôle Viewer de base ne voit que « Plateforme » ;
#   - le compte de service wb-checks (vérifications) voit tout ;
#   - personne n'a « Edit » : les tableaux sont provisionnés, et un dossier provisionné ne reçoit
#     pas de tableau créé à la main.
resource "grafana_folder_permission" "equipe" {
  for_each = var.equipes

  folder_uid = grafana_folder.equipe[each.key].uid

  permissions {
    team_id    = grafana_team.equipe[each.key].id
    permission = "View"
  }

  dynamic "permissions" {
    for_each = each.key == "plateforme" ? [] : [1]
    content {
      team_id    = grafana_team.equipe["plateforme"].id
      permission = "View"
    }
  }

  permissions {
    user_id    = data.grafana_service_account.wb_checks.id
    permission = "View"
  }

  dynamic "permissions" {
    for_each = each.key == "plateforme" ? [1] : []
    content {
      role       = "Viewer"
      permission = "View"
    }
  }
}
