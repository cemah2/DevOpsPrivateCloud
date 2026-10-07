# main.tf — bac à sable de M05-E07, version for_each (corrigé).
#
# Chaque instance est désignée par une CLÉ stable (app01…), plus par sa position dans une
# liste : retirer app02 ne touche ni app01 ni app03. Le VMID fait partie des données,
# il n'est plus calculé à partir d'un index.

variable "serveurs" {
  description = "Serveurs d'application de MédiAgenda : nom court => VMID."
  type        = map(number)
  default = {
    app01 = 2051
    app02 = 2052
    app03 = 2053
  }
}

resource "terraform_data" "serveur" {
  for_each = var.serveurs

  input = {
    nom  = "m05-${each.key}"
    vmid = each.value
  }
}

output "serveurs" {
  value = { for k, s in terraform_data.serveur : s.output.nom => s.output.vmid }
}
