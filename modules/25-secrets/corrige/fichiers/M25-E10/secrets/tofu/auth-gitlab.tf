# tofu/auth-gitlab.tf — plateforme/secrets (M25-E10, SEC-2610)
# Méthode « jwt » montée en gitlab/ : OpenBao vérifie les jetons d'identité (id_tokens) que GitLab
# signe pour chaque job. Configurée par la DÉCOUVERTE OIDC de git01 (et non par une clé recopiée) :
# quand GitLab change de clé de signature, OpenBao lit la nouvelle sur /oauth/discovery/keys.
# Fournisseur hashicorp/vault ~> 5.13 utilisé contre l'API OpenBao (PLAN §4.12).

resource "vault_jwt_auth_backend" "gitlab" {
  path        = "gitlab"
  type        = "jwt"
  description = "Jetons d'identité des jobs GitLab (id_tokens) — M25-E10"

  oidc_discovery_url = "https://git01.par1.medisphere.internal"
  # Racine MédiSphère : seule autorité acceptée pour joindre git01 (pas le magasin système entier).
  oidc_discovery_ca_pem = file("${path.module}/../racine/medisphere-root-ca.crt")
  bound_issuer          = "https://git01.par1.medisphere.internal"
}

# Rôles des projets. Une entrée = un rôle ci-<groupe>-<projet> et sa politique du même nom.
#   refs        valeurs acceptées de la revendication « ref » (motifs glob)
#   ref_types   valeurs acceptées de « ref_type » (branch, tag)
#   environment valeur acceptée de « environment » (null : revendication non exigée)
locals {
  roles_ci = {
    "ci-mediagenda-api" = {
      projet      = "mediagenda/api"
      refs        = ["main", "v*"]
      ref_types   = ["branch", "tag"]
      environment = null
      politiques  = ["ci-mediagenda-api"]
    }
    # Le job promouvoir-<overlay> déclare environment: promotion/<overlay> (M19-E25).
    "ci-mediagenda-api-promotion" = {
      projet      = "mediagenda/api"
      refs        = ["main", "v*"]
      ref_types   = ["branch", "tag"]
      environment = "promotion/*"
      politiques  = ["ci-mediagenda-api-promotion"]
    }
    "ci-medidoc-medidoc" = {
      projet      = "medidoc/medidoc"
      refs        = ["main", "v*"]
      ref_types   = ["branch", "tag"]
      environment = null
      politiques  = ["ci-medidoc-medidoc"]
    }
    "ci-medidoc-medidoc-promotion" = {
      projet      = "medidoc/medidoc"
      refs        = ["main", "v*"]
      ref_types   = ["branch", "tag"]
      environment = "promotion/*"
      politiques  = ["ci-medidoc-medidoc-promotion"]
    }
    # Le pipeline de ce dépôt : plan sur main et conf/*, apply manuel sur main.
    "ci-plateforme-secrets" = {
      projet      = "plateforme/secrets"
      refs        = ["main", "conf/*"]
      ref_types   = ["branch"]
      environment = null
      politiques  = ["tofu-secrets"]
    }
  }
}

resource "vault_jwt_auth_backend_role" "ci" {
  for_each = local.roles_ci

  backend   = vault_jwt_auth_backend.gitlab.path
  role_name = each.key
  role_type = "jwt"

  # Audience fixée au M19-E25 : un jeton fait pour un autre service est refusé.
  bound_audiences = ["openbao.medisphere.internal"]

  # project_id (stable si le projet est renommé ou déplacé) plutôt que project_path ; ref_protected
  # est une CHAÎNE dans le jeton ("true"). Type « glob » pour accepter v* et conf/*. Plusieurs
  # valeurs pour une revendication : liste séparée par des virgules (le fournisseur la découpe).
  bound_claims_type = "glob"
  bound_claims = merge(
    {
      project_id    = tostring(var.projets_gitlab[each.value.projet])
      ref_protected = "true"
      ref           = join(",", each.value.refs)
      ref_type      = join(",", each.value.ref_types)
    },
    each.value.environment == null ? {} : { environment = each.value.environment },
  )

  # Une entité OpenBao par projet (et non par job) ; métadonnées recopiées dans le jeton, donc dans
  # chaque ligne d'audit (E21) : qui (projet, utilisateur), quoi (référence), quand (pipeline, job).
  user_claim = "project_path"
  claim_mappings = {
    project_path = "project_path"
    ref          = "ref"
    ref_type     = "ref_type"
    pipeline_id  = "pipeline_id"
    job_id       = "job_id"
    user_login   = "user_login"
  }

  # Jeton de SERVICE (révocable, avec accesseur : RB-250) de 10 minutes, non prolongeable au-delà.
  token_type             = "service"
  token_ttl              = 600
  token_max_ttl          = 600
  token_explicit_max_ttl = 600
  token_policies         = each.value.politiques
}

# Identifiants des projets GitLab (Paramètres > Général, ou API projects/<chemin encodé>).
variable "projets_gitlab" {
  description = "Chemin du projet GitLab → identifiant numérique (revendication project_id)"
  type        = map(number)
}
