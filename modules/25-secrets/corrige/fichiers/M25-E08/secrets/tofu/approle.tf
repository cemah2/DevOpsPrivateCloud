# tofu/approle.tf — rôles AppRole du palier 1 (M25-E07, importés en E08).
# Les secret_id ne sont PAS gérés ici : ils seraient écrits dans l'état. On les émet à la main
# (M25-E07), ou par enveloppement de réponse à partir de M25-E28.

# Vérifications du workbook (lab/bin/check, fonction bao_api) : métadonnées seulement.
# secret_id sans expiration (les checks servent jusqu'aux workbooks finaux), compensé par :
# liaison à adm01 (secret_id ET jeton), politique sans aucune valeur de secret, jeton « batch »
# de 10 minutes, rotation trimestrielle (politique de rotation, M25-E33).
# Pas de politique « default » : une machine n'a besoin ni de son cubbyhole, ni de lookup-self.
resource "vault_approle_auth_backend_role" "wb_checks" {
  backend   = vault_auth_backend.approle.path
  role_name = "wb-checks"

  token_policies          = ["wb-checks"]
  token_no_default_policy = true
  token_type              = "batch"
  token_ttl               = 600
  token_max_ttl           = 600
  token_bound_cidrs       = var.cidr_adm01
  secret_id_bound_cidrs   = var.cidr_adm01
  secret_id_ttl           = 0
  secret_id_num_uses      = 0
}

# medictl (plateforme/outils, minuterie de synchronisation NetBox sur adm01) : lit ses propres
# secrets d'accès, jeton de 5 minutes, même liaison à adm01.
resource "vault_approle_auth_backend_role" "medictl" {
  backend   = vault_auth_backend.approle.path
  role_name = "medictl"

  token_policies          = ["medictl"]
  token_no_default_policy = true
  token_type              = "batch"
  token_ttl               = 300
  token_max_ttl           = 300
  token_bound_cidrs       = var.cidr_adm01
  secret_id_bound_cidrs   = var.cidr_adm01
  secret_id_ttl           = 0
  secret_id_num_uses      = 0
}
