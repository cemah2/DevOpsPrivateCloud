# plateforme/infra/observabilite-grafana/organisation-securite.tf — M22-E16 (SEC-2316)
#
# Grafana OSS n'a pas de permissions par source de données (fonction Enterprise) : on cloisonne par
# ORGANISATION. Le locataire « audit » n'est interrogeable que depuis l'organisation « Sécurité ».
# Les sources des autres locataires restent dans l'organisation principale (org_id 1), provisionnées
# comme en M22-E02. La source « Loki — audit » est RETIRÉE de ce provisionnement (sinon elle revient).
#
# Fournisseur grafana/grafana ~> 4.50 (4.50.0, dernière version publiée sur les registres d'OpenTofu et de Terraform au 22/10/2026), déjà déclaré dans l'état observabilite-grafana (M21-E17).
# Chaque membre doit exister dans Grafana (comptes locaux du M21) : crée celui de Sophie Laurent s'il manque.

# ⚠️ Authentification : grafana_organization utilise les API d'ADMINISTRATION DU SERVEUR de Grafana.
# Elles refusent les jetons de compte de service (rattachés à UNE organisation, comme le jeton « tofu »
# du M21) : il faut l'authentification basique d'un administrateur du serveur. On utilise le compte
# « admin » (bris de glace, M21-E05 : usage noté dans docs/kubernetes/journal/), par un second
# fournisseur, seulement pour ces deux ressources. Le mot de passe ne va ni dans le code ni dans l'état
# en clair : TF_VAR_grafana_admin_basique="admin:$(…)" lu depuis Vault critique (secrets/grafana.yml)
# au moment du plan. Le compte « admin » est le admin_user de l'organisation : il en reste membre, ce
# qui permet de créer ensuite la source DANS cette organisation (en-tête X-Grafana-Org-Id posé par le
# fournisseur à partir de org_id).
variable "grafana_admin_basique" {
  description = "« admin:<mot de passe> » de l'administrateur du serveur Grafana (TF_VAR_grafana_admin_basique, jamais dans un fichier du dépôt)."
  type        = string
  sensitive   = true
}

provider "grafana" {
  alias = "admin_serveur"
  url   = var.grafana_url
  auth  = var.grafana_admin_basique
}

locals {
  # Comptes locaux de Grafana (M21), désignés par leur adresse ; SSO au M24.
  securite_admins  = ["sophie.laurent@medisphere.internal"]
  securite_viewers = ["nadia.roussel@medisphere.internal", "karim.benali@medisphere.internal", "claire.morel@medisphere.internal"]
}

resource "grafana_organization" "securite" {
  provider     = grafana.admin_serveur
  name         = "Sécurité"
  admin_user   = "admin"
  create_users = false # les comptes existent déjà (M21) ; on ne crée personne ici
  admins       = local.securite_admins
  viewers      = local.securite_viewers
}

resource "grafana_data_source" "loki_audit" {
  provider = grafana.admin_serveur
  org_id   = grafana_organization.securite.org_id
  type     = "loki"
  name     = "Loki — audit"
  uid      = "loki-audit"
  url      = "http://loki.journaux.svc.cluster.local:3100"

  json_data_encoded = jsonencode({
    maxLines = 1000
    timeout  = 120
  })

  # Valeur du locataire : en-tête X-Scope-OrgID (stocké chiffré par Grafana, jamais affiché)
  http_headers = {
    "X-Scope-OrgID" = "audit"
  }
}

output "organisation_securite_id" {
  value = grafana_organization.securite.org_id
}
