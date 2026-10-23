# plateforme/identite — simulations/ghsv-idp/fournisseurs.tf (F7-S08, PLAT-3708)
#
# L'IdP du GHSV, SIMULÉ dans le royaume Keycloak « ghsv-idp » d'idp01. Ce royaume joue un système qui
# N'EST PAS le nôtre : sa racine OpenTofu, son état et son identité d'administration sont séparés de
# ceux de tofu/ (royaume medisphere). Le jour où le vrai IdP du GHSV est raccordé, ce dossier est
# détruit (tofu destroy) sans toucher à rien d'autre ; seul tofu/courtier-ghsv.tf change d'adresse.
#
# Identité : client « svc-tofu-ghsv-idp » du royaume master (compte de service, rôle create-realm
# SEULEMENT). Keycloak donne à celui qui crée un royaume les rôles d'administration de CE royaume
# (client ghsv-idp-realm de master) : rien sur medisphere ni sur master. Créé une fois à la main par
# <MOI>-admin (console, royaume master), secret rangé dans OpenBao (kv/plateforme/keycloak/
# svc-tofu-ghsv-idp), lu par outils/charger-acces.sh (KEYCLOAK_CLIENT_ID, KEYCLOAK_CLIENT_SECRET).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.10"
    }
  }

  # État séparé (clé distincte, même compartiment chiffré que tofu/) : un « destroy » ici ne voit
  # jamais le royaume medisphere.
  backend "s3" {
    bucket = "tofu-state"
    key    = "identite-ghsv-idp/terraform.tfstate"

    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_lockfile                = true
  }

  # Même chiffrement de l'état et des plans que tofu/chiffrement.tf (TF_ENCRYPTION) : l'état contient
  # le secret du client du courtier.
  encryption {
    method "aes_gcm" "etat" {
      keys = key_provider.pbkdf2.etat
    }
    state {
      method   = method.aes_gcm.etat
      enforced = true
    }
    plan {
      method   = method.aes_gcm.etat
      enforced = true
    }
  }
}

provider "keycloak" {
  url   = "https://sso.par1.medisphere.internal"
  realm = "master"
}
