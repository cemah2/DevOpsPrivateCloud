# politiques/ci-mediagenda-api-promotion.hcl — plateforme/secrets (M25-E10, SEC-2610)
# Le seul job de mediagenda/api qui ouvre la MR de promotion dans mediagenda/deploiement : jeton de
# projet « ci-promotion » (portée api, limité à ce dépôt). Rien d'autre.
path "kv/data/mediagenda/ci/promotion" {
  capabilities = ["read"]
}
