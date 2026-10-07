# main.tf — bac à sable de M05-E07 : count ou for_each ? (aucune VM, aucun provider externe)
#
# terraform_data est une ressource INTÉGRÉE à OpenTofu : elle n'appelle aucune API, elle
# garde seulement sa valeur « input » dans l'état. Parfaite pour observer ce que fait OpenTofu
# des ADRESSES d'instances, sans rien créer sur pve01.
#
# Copie ce dossier dans ~/m05/e07/compteur/ et lance tofu depuis la copie.

variable "serveurs" {
  description = "Serveurs d'application de MédiAgenda, dans l'ordre de leur mise en service."
  type        = list(string)
  default     = ["app01", "app02", "app03"]
}

resource "terraform_data" "serveur" {
  count = length(var.serveurs)

  input = {
    nom  = "m05-${var.serveurs[count.index]}"
    vmid = 2051 + count.index
  }
}

output "serveurs" {
  value = { for s in terraform_data.serveur : s.output.nom => s.output.vmid }
}
