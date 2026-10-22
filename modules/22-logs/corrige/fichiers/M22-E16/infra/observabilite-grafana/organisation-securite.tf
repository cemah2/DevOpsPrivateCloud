# plateforme/infra/observabilite-grafana/organisation-securite.tf — M22-E16 (SEC-2316)
#
# Grafana OSS n'a pas de permissions par source de données (fonction Enterprise) : on cloisonne par
# ORGANISATION. Le locataire « audit » n'est interrogeable que depuis l'organisation « Sécurité ».
# Les sources des autres locataires restent dans l'organisation principale (org_id 1), provisionnées
# comme en M22-E02. La source « Loki — audit » est RETIRÉE de ce provisionnement (sinon elle revient).
#
# Fournisseur grafana/grafana ~> 4.50 (4.51.x de référence), déjà déclaré dans l'état observabilite-grafana (M21-E17).
# Chaque membre doit exister dans Grafana (comptes locaux du M21) : crée celui de Sophie Laurent s'il manque.

locals {
  # Comptes locaux de Grafana (M21), désignés par leur adresse ; SSO au M24.
  securite_admins  = ["sophie.laurent@medisphere.internal"]
  securite_viewers = ["nadia.roussel@medisphere.internal", "karim.benali@medisphere.internal", "claire.morel@medisphere.internal"]
}

resource "grafana_organization" "securite" {
  name         = "Sécurité"
  admin_user   = "admin"
  create_users = false # les comptes existent déjà (M21) ; on ne crée personne ici
  admins       = local.securite_admins
  viewers      = local.securite_viewers
}

resource "grafana_data_source" "loki_audit" {
  org_id = grafana_organization.securite.org_id
  type   = "loki"
  name   = "Loki — audit"
  uid    = "loki-audit"
  url    = "http://loki.journaux.svc.cluster.local:3100"

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
