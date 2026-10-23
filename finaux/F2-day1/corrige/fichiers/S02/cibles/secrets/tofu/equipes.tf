# plateforme/secrets — tofu/equipes.tf (F2-S02, PLAT-3202, ADR-0320)
# Les équipes décrites dans plateforme/equipes : la VALEUR de var.equipes_en_code vient de
# tofu/equipes.auto.tfvars.json, RENDU par plateforme/equipes (ne pas l'écrire à la main). Ce fichier-ci,
# lui, est écrit et relu une fois : il dit ce qu'une équipe reçoit dans le coffre.
#
# Par équipe <e> :
#   - politique <e>-equipe (gabarit politiques/equipe.hcl.tftpl) : écriture de kv/<e>/<env>/* pour les
#     environnements de secrets.ecriture, liste des environnements ; jamais kv/<e>/ci/* (jetons de la CI),
#     jamais destroy ni suppression des métadonnées ;
#   - groupe EXTERNE <e> (alias = nom du groupe dans la revendication « groups » de Keycloak), comme les
#     groupes du M25-E06 : ses membres viennent de l'annuaire à chaque connexion OIDC ;
# Par espace <e>-<env> : politique eso-<e>-<env> et rôle k8s-par1 du même nom (modèle M25-E13 :
#   compte « eso » de l'espace, audience openbao.medisphere.internal, kv/<e>/<env>/* en lecture) ;
# Par service <s> : rôles JWT ci-<groupe>-<s> (robot Harbor de publication) et ci-<groupe>-<s>-promotion
#   (jeton de groupe ci-promotion, rangé par le job gitlab:equipes), noms attendus par les composants
#   securite et promotion (rôle déduit de CI_PROJECT_PATH, M25-E10).
#
# Pourquoi project_path (et non project_id comme au M25-E10) pour les services d'équipe : le projet est
# créé PAR L'ÉQUIPE (modèle nouveau-service, F2-S04) après ce rendu ; son identifiant n'est pas connu au
# moment de la MR. Le chemin d'un projet ne peut être repris que par quelqu'un qui peut créer un projet
# dans le groupe de l'équipe (ses Maintainers, svc-equipes, svc-portail) : risque accepté, ADR-0320.

variable "equipes_en_code" {
  description = "Équipes de plateforme/equipes (rendu : tofu/equipes.auto.tfvars.json)."
  type = map(object({
    groupe_gitlab  = string
    environnements = list(string)
    ecriture       = list(string)
    services       = list(string)
  }))
  default = {}
}

locals {
  espaces_equipes = merge({}, [
    for nom, e in var.equipes_en_code : {
      for env in e.environnements : "${nom}-${env}" => { application = nom, environnement = env, chemins_creds = [] }
    }
  ]...)

  services_equipes = merge({}, [
    for nom, e in var.equipes_en_code : {
      for s in e.services : "${e.groupe_gitlab}-${s}" => { equipe = nom, projet = "${e.groupe_gitlab}/${s}" }
    }
  ]...)
}

# --- Personnes de l'équipe (OIDC) -------------------------------------------------------------------
resource "vault_policy" "equipe" {
  for_each = var.equipes_en_code

  name = "${each.key}-equipe"
  policy = templatefile("${path.module}/../politiques/equipe.hcl.tftpl", {
    equipe   = each.key
    ecriture = each.value.ecriture
  })
}

resource "vault_identity_group" "equipe" {
  for_each = var.equipes_en_code

  name     = each.key
  type     = "external"
  policies = [vault_policy.equipe[each.key].name]
  metadata = { source = "keycloak-medisphere", origine = "plateforme-equipes" }
}

resource "vault_identity_group_alias" "equipe" {
  for_each = var.equipes_en_code

  name           = each.key
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.equipe[each.key].id
}

# --- ESO : un rôle par espace d'équipe --------------------------------------------------------------
resource "vault_policy" "eso_equipe" {
  for_each = local.espaces_equipes

  name   = "eso-${each.key}"
  policy = templatefile("${path.module}/../politiques/eso-espace.hcl.tftpl", each.value)
}

resource "vault_kubernetes_auth_backend_role" "eso_equipe" {
  for_each = local.espaces_equipes

  backend                          = vault_auth_backend.k8s_par1.path
  role_name                        = "eso-${each.key}"
  bound_service_account_names      = ["eso"]
  bound_service_account_namespaces = [each.key]
  audience                         = "openbao.medisphere.internal"
  alias_name_source                = "serviceaccount_name"
  token_type                       = "service"
  token_ttl                        = 900
  token_max_ttl                    = 900
  token_policies                   = [vault_policy.eso_equipe[each.key].name]
}

# --- CI des services d'équipe -------------------------------------------------------------------------
resource "vault_policy" "ci_service" {
  for_each = local.services_equipes

  name   = "ci-${each.key}"
  policy = templatefile("${path.module}/../politiques/ci-service.hcl.tftpl", each.value)
}

resource "vault_policy" "ci_service_promotion" {
  for_each = local.services_equipes

  name   = "ci-${each.key}-promotion"
  policy = templatefile("${path.module}/../politiques/ci-service-promotion.hcl.tftpl", each.value)
}

resource "vault_jwt_auth_backend_role" "ci_service" {
  for_each = local.services_equipes

  backend         = vault_jwt_auth_backend.gitlab.path
  role_name       = "ci-${each.key}"
  role_type       = "jwt"
  bound_audiences = ["openbao.medisphere.internal"]

  bound_claims_type = "glob"
  bound_claims = {
    project_path  = each.value.projet
    ref_protected = "true"
    ref           = "main,v*"
    ref_type      = "branch,tag"
  }
  user_claim     = "project_path"
  claim_mappings = { project_path = "project_path", ref = "ref", pipeline_id = "pipeline_id", job_id = "job_id", user_login = "user_login" }

  token_type             = "service"
  token_ttl              = 600
  token_max_ttl          = 600
  token_explicit_max_ttl = 600
  token_policies         = [vault_policy.ci_service[each.key].name]
}

resource "vault_jwt_auth_backend_role" "ci_service_promotion" {
  for_each = local.services_equipes

  backend         = vault_jwt_auth_backend.gitlab.path
  role_name       = "ci-${each.key}-promotion"
  role_type       = "jwt"
  bound_audiences = ["openbao.medisphere.internal"]

  bound_claims_type = "glob"
  bound_claims = {
    project_path  = each.value.projet
    ref_protected = "true"
    ref           = "main,v*"
    ref_type      = "branch,tag"
    # Seul le job promouvoir-<overlay> déclare cet environnement (composant promotion, M19-E25).
    environment = "promotion/*"
  }
  user_claim     = "project_path"
  claim_mappings = { project_path = "project_path", ref = "ref", pipeline_id = "pipeline_id", job_id = "job_id", user_login = "user_login" }

  token_type             = "service"
  token_ttl              = 600
  token_max_ttl          = 600
  token_explicit_max_ttl = 600
  token_policies         = [vault_policy.ci_service_promotion[each.key].name]
}
