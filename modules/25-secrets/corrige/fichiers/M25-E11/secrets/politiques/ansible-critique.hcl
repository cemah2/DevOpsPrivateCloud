# politiques/ansible-critique.hcl — plateforme/secrets (M25-E11, PLAT-2611)
# Mot de passe de l'identité « critique », et secrets lus par les playbooks par lookup
# (community.hashi_vault). Reçue par : le rôle JWT ci-plateforme-ansible-critique (main,
# environnement lab/socle) ; les administrateurs l'ont par plateforme-admin.
path "kv/data/plateforme/ansible-vault/critique" {
  capabilities = ["read"]
}

# Secrets servis directement aux playbooks (un sous-chemin par composant, ajoutés un à un).
path "kv/data/plateforme/mailpit/*" {
  capabilities = ["read"]
}
