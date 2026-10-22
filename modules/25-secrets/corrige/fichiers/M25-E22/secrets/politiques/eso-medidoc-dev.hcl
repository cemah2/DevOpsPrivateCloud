# politiques/eso-medidoc-dev.hcl — ESO dans l'espace medidoc-dev (MR !214 corrigée, M25-E22).
# Une politique et un rôle PAR ESPACE (fiche du module : eso-<espace>) : le SecretStore de
# medidoc-dev ne lit que les secrets de dev de MédiDoc.
path "kv/data/medidoc/dev/*" {
  capabilities = ["read"]
}
