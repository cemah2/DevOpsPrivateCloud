# politiques/cosign-signature.hcl — signer avec la clé MédiSphère (M25-E20, SEC-2620).
# Donnée par le rôle JWT « ci-signature » (méthode gitlab) aux seuls jobs des références protégées,
# des groupes qui publient des images et des charts, sur le runner protégé.
# Chemins relevés dans le journal d'audit pendant un « cosign sign » réel : Cosign lit la clé (pour
# la clé publique et la dernière version), puis signe l'empreinte SHA-256.
path "transit/keys/cosign-medisphere" {
  capabilities = ["read"]
}

path "transit/sign/cosign-medisphere/sha2-256" {
  capabilities = ["update"]
}

# Le rôle ci-signature retire la politique « default » (token_no_default_policy) : le job doit
# pouvoir révoquer son propre jeton à la fin (« bao token revoke -self »), droit que donnait default.
path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# Ceinture et bretelles : même si une autre politique attachée un jour à ce jeton l'accordait, un job
# de signature ne règle jamais la clé (exportable passerait à vrai, sans retour) ni ne l'exporte.
path "transit/keys/cosign-medisphere/*" {
  capabilities = ["deny"]
}

path "transit/export/*" {
  capabilities = ["deny"]
}

path "transit/backup/*" {
  capabilities = ["deny"]
}
