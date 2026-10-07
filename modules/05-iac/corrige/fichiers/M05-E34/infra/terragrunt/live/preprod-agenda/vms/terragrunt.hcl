# terragrunt.hcl — unité « vms » : les VMs de l'environnement (M05-E24).
# Copie identique dans chaque environnement : tout ce qui varie vient de ../env.hcl.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "proxmox" {
  path = "${dirname(find_in_parent_folders("root.hcl"))}/_commun/proxmox.hcl"
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/terragrunt/composants//vms"
}

# La clé publique de l'environnement vient de l'unité « acces ». Terragrunt la lit par
# « tofu output » sur l'état de cette unité, et ordonne les deux unités (acces, puis vms)
# dans « run --all apply » (et vms, puis acces, dans « run --all destroy »).
dependency "acces" {
  config_path = "../acces"

  # Tant que « acces » n'a jamais été appliquée, son état n'a pas de sortie : ces valeurs
  # factices permettent un validate ou un plan d'ensemble, JAMAIS un apply.
  mock_outputs = {
    cle_publique_openssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA0000000000000000000000000000000000000000000 maquette"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  environnement = local.env.locals.environnement
  vms           = local.env.locals.vms
  cle_ssh_env   = dependency.acces.outputs.cle_publique_openssh
}
