# root.hcl — configuration commune de toutes les unités Terragrunt de plateforme/infra
# (M05-E24, chiffrement de l'état ajouté en M05-E27).
#
# Terragrunt 1.x : le fichier racine s'appelle root.hcl (un terragrunt.hcl à la racine est
# déprécié) ; chaque unité (un dossier avec un terragrunt.hcl) l'inclut par
#   include "root" { path = find_in_parent_folders("root.hcl") }
#
# Ce fichier remplace ce que chaque dossier de envs/ et socle/ répétait (M05-E11) :
#   - le backend S3 de s3-01, avec une CLÉ D'ÉTAT DÉDUITE DU CHEMIN de l'unité : deux unités
#     ne peuvent plus partager un état par erreur de copier-coller ;
#   - les entrées communes (nœud, pool, DNS, clé d'administration).
# Le bloc provider « proxmox » est généré par _commun/proxmox.hcl, inclus seulement par les
# unités qui parlent à Proxmox.
#
# Aucun secret ici : PROXMOX_VE_*, AWS_* et TF_ENCRYPTION (fournisseur de clé « etat ») viennent
# de l'environnement (outils/charger-acces.sh sur adm01, outils/ci-preparer.sh en pipeline).

locals {
  commun = read_terragrunt_config(find_in_parent_folders("commun.hcl"))
}

remote_state {
  backend = "s3"

  # Terragrunt écrit backend.tf dans la copie de travail de l'unité (.terragrunt-cache) :
  # le composant n'a pas de bloc backend à lui. « overwrite_terragrunt » : le fichier n'est
  # réécrit que s'il a été généré par Terragrunt (un backend.tf écrit à la main bloque).
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = "tofu-state"
    # live/dev-agenda/vms → envs/dev-agenda/vms/terraform.tfstate
    key = "envs/${path_relative_to_include()}/terraform.tfstate"

    # Mêmes réglages que les backends écrits à la main en M05-E11 (SeaweedFS n'est pas AWS).
    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_lockfile                = true
  }
}

# Chiffrement de l'état et des plans (M05-E27) : le bloc « encryption » de toutes les unités est
# COPIÉ de socle/chiffrement.tf, la référence du dépôt. Une rotation de phrase (fallback) faite
# dans ce fichier s'applique donc aussi aux environnements Terragrunt, sans rien oublier.
generate "chiffrement" {
  path      = "chiffrement.tf"
  if_exists = "overwrite_terragrunt"
  contents  = file("${get_repo_root()}/socle/chiffrement.tf")
}

# Entrées passées à TOUTES les unités (TF_VAR_…). Une unité ne reçoit que celles que son
# composant déclare : les autres sont ignorées sans erreur.
inputs = {
  noeud          = local.commun.locals.noeud
  pool           = local.commun.locals.pool
  dns            = local.commun.locals.dns
  cles_ssh_admin = local.commun.locals.cles_ssh_admin
}
