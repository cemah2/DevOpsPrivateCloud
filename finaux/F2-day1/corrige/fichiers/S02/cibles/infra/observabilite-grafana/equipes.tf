# plateforme/infra — observabilite-grafana/equipes.tf (F2-S02, PLAT-3202)
# Les équipes de plateforme/equipes reçoivent un dossier (UID = nom de l'équipe) et une équipe Grafana,
# comme plateforme, mediagenda et medidoc depuis le M21-E17. La VALEUR vient de
# equipes.auto.tfvars.json, RENDU par plateforme/equipes ; la variable « equipes » (écrite à la main,
# M21-E17 et M24-E12) reste la source des équipes historiques.
#
# Changement à faire UNE FOIS dans main.tf et utilisateurs.tf : remplacer chaque « var.equipes » par
# « local.toutes_equipes » (grafana_folder, grafana_team, grafana_folder_permission, equipes_effectives).
# Les permissions de dossier (main.tf, M21-E17) s'appliquent donc telles quelles : l'équipe voit son
# dossier, la plateforme voit tout, wb-checks voit tout, personne n'édite (tableaux provisionnés).

variable "equipes_en_code" {
  description = "Équipes de plateforme/equipes (rendu : equipes.auto.tfvars.json) : dossier, membres, administrateurs."
  type = map(object({
    titre_dossier = string
    membres       = list(string)
    admins        = list(string)
  }))
  default = {}
  validation {
    condition     = alltrue([for k in keys(var.equipes_en_code) : can(regex("^[a-z0-9-]+$", k))])
    error_message = "Clé d'équipe en minuscules : elle sert aussi d'UID au dossier."
  }
}

locals {
  # Une équipe historique et une équipe en code ne peuvent pas porter le même nom (rendre.py refuse les
  # noms réservés) ; si cela arrivait, la description historique l'emporterait (ordre de merge).
  toutes_equipes = merge(var.equipes_en_code, var.equipes)
}
