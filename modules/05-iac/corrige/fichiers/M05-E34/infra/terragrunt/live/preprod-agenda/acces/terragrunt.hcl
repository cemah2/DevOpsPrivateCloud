# terragrunt.hcl — unité « acces » : la paire de clés SSH propre à l'environnement (M05-E24).
# Copie identique dans chaque environnement : tout ce qui varie vient de ../env.hcl.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  # « // » : Terragrunt copie tout le dossier composants/ et se place dans acces/.
  source = "${get_repo_root()}/terragrunt/composants//acces"
}

inputs = {
  environnement = local.env.locals.environnement
}
