# tofu/fournisseurs.tf — configuration d'OpenBao en code (M25-E08, PLAT-2608). Projet plateforme/secrets.
#
# Aucun fournisseur « openbao » n'est publié : on utilise hashicorp/vault (licence MPL 2.0, le
# fournisseur n'est pas sous BUSL) contre l'API d'OpenBao, compatible pour ce que nous gérons ici
# (montages, méthodes oidc et approle, rôles, politiques, groupes d'identité). Chaque ressource
# ajoutée aux paliers suivants est essayée contre OpenBao avant d'être fusionnée (plan, apply, plan
# vide) : une ressource qui vise une fonction propre à Vault Enterprise (espaces de noms, Sentinel
# « egp/rgp », réplication) n'a rien à faire ici.
# Correctifs acceptés, jamais une nouvelle mineure sans MR ; empreintes dans .terraform.lock.hcl.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.13"
    }
  }

  # État distant sur s3-01, comme plateforme/infra (M05-E11) et plateforme/identite (M24-E08).
  # Il ne contient pas les secrets que nous protégeons (valeurs KV jamais gérées ici, secret du
  # client OIDC en écriture seule), mais il décrit tout le contrôle d'accès : chiffré quand même.
  backend "s3" {
    bucket = "tofu-state"
    key    = "secrets/terraform.tfstate"

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

# Authentification (M25-E08) : le jeton de la PERSONNE qui applique, obtenu par
# « bao login -method=oidc » (groupe plateforme-admins, OTP) et rangé par la CLI dans
# ~/.vault-token, que le fournisseur lit tout seul. Jamais de jeton dans le code ni dans une variable.
# Le fournisseur crée à partir de ce jeton un jeton ENFANT de 20 minutes (max_lease_ttl_seconds) pour
# la durée de l'exécution, révoqué à la fin : il faut auth/token/create dans plateforme-admin.
# Au M25-E10, le pipeline s'authentifie par son jeton d'identité GitLab (méthode jwt « gitlab »).
# Le certificat est vérifié avec le magasin du système (racine MédiSphère installée sur adm01 et
# runner01) : jamais skip_tls_verify.
provider "vault" {
  address               = "https://openbao.par1.medisphere.internal:8200"
  max_lease_ttl_seconds = 1200
}
