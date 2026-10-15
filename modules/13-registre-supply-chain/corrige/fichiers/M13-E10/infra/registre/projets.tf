# registre/projets.tf — projets « hébergés » de Harbor (M13-E03 ; SBOM à la poussée : M13-E06 ;
# quotas : M13-E10).
# Caches : caches.tf (M13-E04).
# Privés : tirage authentifié (robot k8s-pull, robots CI, humains membres).
# vulnerability_scanning = analyse à la poussée (défaut du fournisseur : true, écrit explicitement).
# Les politiques (signature exigée, vulnérabilités bloquantes) arrivent au palier 3 (M13-E14) ;
# quotas, rétention et immuabilité en M13-E10.
locals {
  # Quotas (Gio) : somme des projets + caches (caches.tf) = 160 Gio pour un /data de 200 Gio :
  # marge pour la base PostgreSQL, les rapports Trivy, les envois en cours et le ramasse-miettes
  # (qui a besoin de place pour travailler). Un quota se relève par MR (docs/registre/stockage.md).
  projets = {
    medisphere   = { description = "Images applicatives (MédiAgenda, MédiDoc, MédiNotif, Legacy-RDV)", quota_gio = 40 }
    plateforme   = { description = "Outils de la plateforme (image outillée de la CI, M13-E09)", quota_gio = 15 }
    bibliotheque = { description = "Images de base reconstruites par MédiSphère (M12-E27)", quota_gio = 15 }
    charts       = { description = "Charts Helm en OCI (M17)", quota_gio = 5 }
  }
}

resource "harbor_project" "projet" {
  for_each               = local.projets
  name                   = each.key
  public                 = false
  vulnerability_scanning = true
  storage_quota          = each.value.quota_gio
  # M13-E06 : SBOM générée par Harbor (Trivy) à chaque poussée, dans les projets d'images
  # exécutées. Second inventaire, indépendant de celui de la CI (Syft, attesté et signé, M13-E08) :
  # la SBOM de référence reste celle de la CI (signée) ; celle de Harbor sert de contrôle croisé.
  auto_sbom_generation = contains(["medisphere", "plateforme", "bibliotheque"], each.key)
}

# Membres de medisphere. Rôles du fournisseur : projectadmin, maintainer, developer, guest, limitedguest.
locals {
  membres_medisphere = {
    (var.moi)      = "projectadmin"
    "karim.benali" = "projectadmin"
    "julien.petit" = "developer" # pousse et tire ; ne règle pas le projet
    "lucas.martin" = "guest"     # lit et tire ; ne pousse pas
  }
}

resource "harbor_project_member_user" "medisphere" {
  for_each   = local.membres_medisphere
  project_id = harbor_project.projet["medisphere"].id
  user_name  = harbor_user.personne[each.key].username
  role       = each.value
}

# Tu administres aussi les autres projets (Karim en mainteneur).
resource "harbor_project_member_user" "plateforme_admin" {
  for_each   = toset(["plateforme", "bibliotheque", "charts"])
  project_id = harbor_project.projet[each.key].id
  user_name  = harbor_user.personne[var.moi].username
  role       = "projectadmin"
}

resource "harbor_project_member_user" "plateforme_karim" {
  for_each   = toset(["plateforme", "bibliotheque", "charts"])
  project_id = harbor_project.projet[each.key].id
  user_name  = harbor_user.personne["karim.benali"].username
  role       = "maintainer"
}
