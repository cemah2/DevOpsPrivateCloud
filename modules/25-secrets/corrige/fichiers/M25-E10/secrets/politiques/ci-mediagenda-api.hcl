# politiques/ci-mediagenda-api.hcl — plateforme/secrets (M25-E10, SEC-2610)
# Jobs des références PROTÉGÉES de mediagenda/api (rôle JWT ci-mediagenda-api du montage gitlab/).
# Lecture seule, chemins exacts : jamais de joker sur kv/, jamais le jeton de promotion (réservé au
# rôle ci-mediagenda-api-promotion, donc au seul job qui déclare l'environnement promotion/*).

# Robot Harbor de publication (robot$medisphere+ci), partagé par les projets applicatifs.
path "kv/data/plateforme/harbor/robot-ci" {
  capabilities = ["read"]
}

# Jeton de projet de semantic-release (composant release).
path "kv/data/mediagenda/ci/release" {
  capabilities = ["read"]
}
