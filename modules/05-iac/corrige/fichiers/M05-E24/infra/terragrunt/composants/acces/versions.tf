# versions.tf — composant « acces » (M05-E24).
# Un composant est une configuration racine SANS backend ni provider : Terragrunt les génère
# (live/root.hcl). Il garde ses contraintes de versions : le .terraform.lock.hcl est écrit
# par « tofu init » dans le dossier de l'unité (live/<env>/acces/) et y est versionné.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    tls = {
      source  = "hashicorp/tls" # = registry.opentofu.org/hashicorp/tls
      version = "~> 4.4.0"
    }
  }
}
