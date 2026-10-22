# kms01 — politique « generation-racine » (M25-E25, utilisée au M25-E28). Dans les versions de
# référence, la génération d'un jeton racine passe par sys/generate-root-token, AUTHENTIFIÉ. Sans
# méthode d'authentification humaine sur kms01, il faut un jeton qui ne sait faire QUE lancer et
# alimenter cette génération : seul, il ne donne rien (il faut encore trois parts de kms01).
# Jeton orphelin et périodique (period 8760h), rangé dans le Vault « critique »
# (vault_kms01_jeton_generation), renouvelé à chaque usage et au plus tard tous les six mois
# (politique de rotation, M25-E33).
path "sys/generate-root-token/attempt" {
  capabilities = ["read", "update", "delete"]
}

path "sys/generate-root-token/update" {
  capabilities = ["update"]
}

# Renouveler ce jeton lui-même (bao token renew), sans la politique « default ».
path "auth/token/renew-self" {
  capabilities = ["update"]
}
