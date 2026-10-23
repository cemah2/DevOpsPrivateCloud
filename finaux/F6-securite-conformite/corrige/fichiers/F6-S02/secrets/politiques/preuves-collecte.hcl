# politiques/preuves-collecte.hcl — collecte et signature des preuves de conformité (F6-S02, PLAT-3602).
# Donnée par le rôle JWT « ci-preuves » (pipelines planifiés de plateforme/outils sur runner01).

# Signature du manifeste d'un lot (Cosign « hashivault:// » : lecture de la clé, puis signature de
# l'empreinte SHA-256 ; chemins relevés dans l'audit pendant un « cosign sign-blob », comme au M25-E20).
path "transit/keys/preuves-conformite" {
  capabilities = ["read"]
}
path "transit/sign/preuves-conformite/sha2-256" {
  capabilities = ["update"]
}

# Identités de LECTURE des collecteurs, clés S3 (écriture du lot, lecture pour la vérification),
# kubeconfig du compte de service en lecture, clé SSH du compte « preuves » des passerelles.
path "kv/data/plateforme/preuves/*" {
  capabilities = ["read"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# Jamais : régler, exporter ou sauvegarder la clé ; écrire dans le coffre.
path "transit/keys/preuves-conformite/*" {
  capabilities = ["deny"]
}
path "transit/export/*" {
  capabilities = ["deny"]
}
path "transit/backup/*" {
  capabilities = ["deny"]
}
