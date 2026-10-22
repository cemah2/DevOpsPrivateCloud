# tofu/variables.tf — M25-E08.

# Le secret du client « openbao » de Keycloak n'est PAS une variable : il est lu dans le coffre
# lui-même (kv/plateforme/openbao/oidc, écrit en M25-E06) par une ressource éphémère, et poussé
# dans la méthode oidc par un argument en écriture seule. Ni le plan ni l'état ne le gardent.
# Incrémenter cette version pour POUSSER une nouvelle valeur (rotation du secret côté Keycloak,
# RB-244 et M25-E33) : un argument en écriture seule n'est jamais relu.
variable "openbao_oidc_version_secret" {
  description = "Version du secret du client Keycloak « openbao » poussé dans auth/oidc/config (à incrémenter à chaque rotation)."
  type        = number
  default     = 1
}

# Groupes du royaume medisphere (revendication « groups », noms courts, M24) → politiques d'OpenBao.
# Un groupe absent d'ici n'ouvre aucun droit : ses membres se connectent avec la seule politique
# « default » (direction, medidoc au palier 1).
variable "groupes_keycloak" {
  description = "Correspondance groupe Keycloak → politiques OpenBao (groupes externes)."
  type        = map(list(string))
  default = {
    "plateforme-admins" = ["plateforme-admin"]
    "plateforme"        = ["plateforme-lecture"]
    "support"           = ["plateforme-lecture"]
    "securite"          = ["securite-audit"]
    "mediagenda"        = ["mediagenda-dev"]
  }
}

# Adresse d'adm01 : seule origine admise des identités machines du palier 1 (checks, medictl).
variable "cidr_adm01" {
  description = "CIDR d'où les AppRole wb-checks et medictl peuvent se connecter (adm01)."
  type        = list(string)
  default     = ["10.10.10.10/32"]
}
