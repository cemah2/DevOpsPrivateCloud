# tofu/eso-espaces.tf — plateforme/secrets (M25-E13, PLAT-2613)
# Un rôle k8s-par1 et une politique par espace applicatif : compte de service « eso » de l'espace,
# audience openbao.medisphere.internal, lecture de kv/<application>/<environnement>/* seulement.
# chemins_creds : chemins d'identifiants dynamiques (M25-E14), vides au M25-E13.
locals {
  espaces_eso = {
    "mediagenda-dev"     = { application = "mediagenda", environnement = "dev", chemins_creds = [] }
    "mediagenda-recette" = { application = "mediagenda", environnement = "recette", chemins_creds = [] }
    "mediagenda-prod"    = { application = "mediagenda", environnement = "prod", chemins_creds = [] }
    "medidoc-dev"        = { application = "medidoc", environnement = "dev", chemins_creds = [] }
    "medidoc-recette"    = { application = "medidoc", environnement = "recette", chemins_creds = [] }
  }
}

resource "vault_policy" "eso_espace" {
  for_each = local.espaces_eso
  name     = "eso-${each.key}"
  policy   = templatefile("${path.module}/../politiques/eso-espace.hcl.tftpl", each.value)
}

resource "vault_kubernetes_auth_backend_role" "eso_espace" {
  for_each = local.espaces_eso

  backend                          = vault_auth_backend.k8s_par1.path
  role_name                        = "eso-${each.key}"
  bound_service_account_names      = ["eso"]
  bound_service_account_namespaces = [each.key]
  audience                         = "openbao.medisphere.internal"
  alias_name_source                = "serviceaccount_name"
  token_type                       = "service"
  token_ttl                        = 900
  token_max_ttl                    = 900
  token_policies                   = [vault_policy.eso_espace[each.key].name]
}
