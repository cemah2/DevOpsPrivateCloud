# tofu/variables.tf — M24-E08.

# Mot de passe du compte système svc-keycloak de l'annuaire (annuaire/vault-critique.yml, M24-E03).
# ÉPHÉMÈRE : jamais écrit dans un plan enregistré ni dans l'état ; il n'alimente que l'argument en
# écriture seule bind_credential_wo. Fourni par l'environnement :
#   TF_VAR_svc_keycloak_mot_de_passe  (outils/charger-acces.sh sur adm01 ; variable protégée et
#                                      masquée en CI, rappelée à l'apply : un plan ne la garde pas)
variable "svc_keycloak_mot_de_passe" {
  description = "Mot de passe de uid=svc-keycloak,cn=sysaccounts,cn=etc (liaison LDAPS de la fédération)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

# Incrémenter pour POUSSER un nouveau mot de passe vers Keycloak (rotation, RB-244) : un argument
# en écriture seule n'est jamais relu, OpenTofu ne voit un changement que par cette version.
variable "svc_keycloak_version_mot_de_passe" {
  description = "Version du mot de passe de svc-keycloak poussé dans la fédération (à incrémenter à chaque rotation)."
  type        = number
  default     = 1
}
