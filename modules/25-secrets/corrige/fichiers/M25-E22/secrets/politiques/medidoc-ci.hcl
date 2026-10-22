# politiques/medidoc-ci.hcl — CI de medidoc/medidoc, job de déploiement (MR !214 corrigée, M25-E22).
# Exactement ce que lit le job, trouvé dans le journal d'audit (requête « quels secrets une
# identité a-t-elle lus », docs/securite/secrets/audit-openbao.md) sur un pipeline d'essai : pas de
# « path * » de débogage, jamais (capabilities-self et le message « permission denied » suffisent).
path "kv/data/medidoc/prod/deploiement" {
  capabilities = ["read"]
}
