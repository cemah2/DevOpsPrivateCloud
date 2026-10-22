# politiques/ansible-lab.hcl — plateforme/secrets (M25-E11, PLAT-2611)
# Mot de passe de l'identité Ansible Vault « lab » : rien d'autre. Une politique protège un CHEMIN,
# jamais une clé d'un secret : « critique » est donc rangé à un autre chemin.
# Reçue par : le rôle JWT ci-plateforme-ansible (jobs protégés de plateforme/ansible) et le groupe
# externe OIDC « plateforme » (Lucas compris).
path "kv/data/plateforme/ansible-vault/lab" {
  capabilities = ["read"]
}
