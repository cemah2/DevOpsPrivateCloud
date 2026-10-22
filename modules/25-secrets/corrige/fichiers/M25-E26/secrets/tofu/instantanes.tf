# tofu/instantanes.tf — AppRole des instantanés de la grappe (M25-E26, SEC-2626).
# Essayé contre OpenBao 2.6.4 et 2.7.1 : apply, connexion, instantané, plan vide.
#
# - jeton BATCH de 10 min (15 au plus) : pas stocké côté serveur, pas renouvelable ; un instantané
#   prend quelques secondes ;
# - liés aux adresses des trois nœuds (secret_id ET jeton) : un secret_id volé ne sert pas ailleurs ;
# - secret_id sans expiration ni limite d'usage (la minuterie s'en sert chaque heure), compensé par
#   la liaison d'adresse, la politique minimale et la rotation trimestrielle (M25-E33) ; livré
#   enveloppé à partir de M25-E28.
resource "vault_approle_auth_backend_role" "openbao_instantanes" {
  backend   = vault_auth_backend.approle.path
  role_name = "openbao-instantanes"

  token_policies          = ["openbao-instantanes"]
  token_no_default_policy = true
  token_type              = "batch"
  token_ttl               = 600
  token_max_ttl           = 900
  token_bound_cidrs       = ["10.10.20.21/32", "10.10.20.22/32", "10.10.20.23/32"]
  secret_id_bound_cidrs   = ["10.10.20.21/32", "10.10.20.22/32", "10.10.20.23/32"]
  secret_id_ttl           = 0
  secret_id_num_uses      = 0
}
