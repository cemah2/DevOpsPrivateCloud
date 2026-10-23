# plateforme/identite — tofu/flux.tf : CHANGEMENT de F2-S02 (PLAT-3202) + nouvelle variable.
# Les groupes d'équipe qui exigent l'OTP (prestataires, F2-S10) reçoivent le rôle de royaume
# second-facteur-obligatoire, comme plateforme-admins et securite (flux conditionnel du M24-E21).
# La liste vient de tofu/equipes.auto.tfvars.json, RENDU par plateforme/equipes.

variable "groupes_otp_equipes" {
  description = "Groupes d'équipe (plateforme/equipes) dont les membres doivent présenter un OTP."
  type        = list(string)
  default     = []
}

# Remplace le for_each du M24-E21 :
data "keycloak_group" "second_facteur" {
  for_each = toset(concat(["plateforme-admins", "securite"], var.groupes_otp_equipes))

  realm_id = "medisphere"
  name     = each.key
}

# ⚠️ Ordre : le groupe n'existe dans Keycloak qu'après une synchronisation des groupes de la fédération
# LDAP (mappeur groupes-ipa) qui suit son application dans FreeIPA. Si le plan échoue sur « group not
# found », lancer la synchronisation des groupes (console d'administration : User federation → la
# fédération ipa01 → Mappers → groupes-ipa → « Sync LDAP groups to Keycloak » ; ou la première connexion
# d'un membre, qui importe ses groupes) puis relancer le pipeline. RB-320 le rappelle dans l'ordre des étapes.
# keycloak_group_roles.second_facteur (for_each sur la source de données) : inchangé.
