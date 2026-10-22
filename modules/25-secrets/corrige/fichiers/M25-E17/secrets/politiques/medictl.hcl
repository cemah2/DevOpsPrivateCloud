# politiques/medictl.hcl — AppRole « medictl » (outil d'exploitation de plateforme/outils, sur adm01)
# (M25-E07, en code en E08 ; chiffrement par transit en M25-E17, SEC-2617).
# Lire ses propres secrets d'accès ; chiffrer, déchiffrer et rechiffrer avec SA clé de transit.
# Jamais : lire ou régler la clé (transit/keys/…), la tourner, l'exporter, la sauvegarder.
path "kv/data/plateforme/medictl/*" {
  capabilities = ["read"]
}

# « update » = POST : chaque opération de transit est une écriture au sens de l'API.
path "transit/encrypt/medictl-donnees" {
  capabilities = ["update"]
}

path "transit/decrypt/medictl-donnees" {
  capabilities = ["update"]
}

# Rechiffrer (rewrap) un chiffré ancien avec la dernière version de la clé : le clair ne sort pas.
path "transit/rewrap/medictl-donnees" {
  capabilities = ["update"]
}
