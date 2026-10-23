# politiques/ci-plateforme-equipes.hcl — plateforme/secrets (F2-S02, PLAT-3202)
# Pipeline de plateforme/equipes (rôle JWT ci-plateforme-equipes : main et conf/* PROTÉGÉES).
# Il lit le jeton du compte de service GitLab svc-equipes, et RANGE les jetons qu'il crée dans GitLab.
# Écriture SEULE sur les jetons (create/update) : il ne relit jamais un jeton déjà rangé. Lecture des
# métadonnées : savoir si le secret existe (rotation).
# Risque accepté (ADR-0320) : les règles « + » couvrent les chemins de TOUTE équipe, y compris
# kv/mediagenda/ci/promotion ; le pipeline n'écrit que ce que dit equipes/*.yaml, relu en MR.

path "kv/data/plateforme/equipes/gitlab" {
  capabilities = ["read"]
}

path "kv/data/plateforme/argocd/depot-*" {
  capabilities = ["create", "update"]
}

path "kv/metadata/plateforme/argocd/depot-*" {
  capabilities = ["read"]
}

path "kv/data/+/ci/promotion" {
  capabilities = ["create", "update"]
}

path "kv/metadata/+/ci/promotion" {
  capabilities = ["read"]
}
