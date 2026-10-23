# tofu/equipes.tf — EXTRAIT (F2-S07, DEV-3207) : ce que le RENDU de l'équipe en code ne connaît pas
# (identifiants dynamiques d'une base d'équipe), déclaré à la main par la plateforme dans
# tofu/equipes-complements.auto.tfvars (écrit et relu ici, jamais rendu) :
#   chemins_creds_equipes        = { "data-traitements" = ["db-data/creds/data-traitement"] }
#   politiques_equipes_en_plus   = { "data" = ["data-analystes"] }

variable "chemins_creds_equipes" {
  description = "Chemins d'identifiants dynamiques lus par le SecretStore d'un espace d'équipe (eso-<espace>)."
  type        = map(list(string))
  default     = {}
}

variable "politiques_equipes_en_plus" {
  description = "Politiques ajoutées au groupe externe d'une équipe, en plus de <equipe>-equipe."
  type        = map(list(string))
  default     = {}
}

# Dans locals.espaces_equipes, remplacer « chemins_creds = [] » par :
#   chemins_creds = lookup(var.chemins_creds_equipes, "${nom}-${env}", [])

# Dans resource "vault_identity_group" "equipe", remplacer la ligne policies par :
#   policies = concat([vault_policy.equipe[each.key].name], lookup(var.politiques_equipes_en_plus, each.key, []))

resource "vault_policy" "data_analystes" {
  name   = "data-analystes"
  policy = file("${path.module}/../politiques/data-analystes.hcl")
}
