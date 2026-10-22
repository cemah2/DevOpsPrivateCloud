# tofu/secrets-clients.tf — secrets des clients confidentiels IMPOSÉS par le code (M24-E29, SEC-2529).
#
# Le secret vient du Vault « critique » de plateforme/ansible (secrets/identite.yml :
# keycloak_secrets_clients.<client>, la même valeur que secrets-k8s.sh pousse dans le cluster).
# Il passe par une variable ÉPHÉMÈRE et l'argument en écriture seule client_secret_wo : ni le plan
# enregistré ni l'état ne le gardent. Keycloak n'est mis à jour que quand la VERSION change :
# une rotation = nouveau secret au Vault + version + 1 (RB-244).
variable "secrets_clients" {
  description = "Secrets des clients confidentiels (clé = clientId), lus dans le Vault par outils/charger-acces.sh."
  type        = map(string)
  sensitive   = true
  ephemeral   = true
}

variable "versions_secrets_clients" {
  description = "Version du secret poussé, par client : incrémenter à chaque rotation (RB-244)."
  type        = map(number)
  default = {
    grafana = 2 # 1 : secret imposé au M24-E12 ; 2 : rotation SEC-2529 (M24-E29)
  }
}
