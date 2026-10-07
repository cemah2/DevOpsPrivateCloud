# versions.tf — état « socle » de plateforme/infra (M05-E10, backend ajouté en M05-E11).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.115.0"
    }
  }

  # État distant sur s3-01 (SeaweedFS). Rien de secret ici : les identifiants viennent de
  # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (~/.config/workbook/s3-tofu.env, identité
  # S3 « tofu-etat »), la CA provisoire du magasin système valide le certificat de s3-01.
  # Le bloc backend est lu à « tofu init », avant tout le reste : il n'accepte que des
  # valeurs connues à ce moment (littéraux, et depuis OpenTofu 1.8 variables et locals
  # « statiques »), jamais une ressource ni une source de données. Ici : des littéraux.
  backend "s3" {
    bucket = "tofu-state"
    key    = "socle/terraform.tfstate"

    # SeaweedFS n'est pas AWS : région factice, et rien à demander aux services
    # STS / IAM / métadonnées EC2 qui n'existent pas ici.
    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true # https://s3-01…:8333/tofu-state/… (pas de DNS par compartiment)
    skip_credentials_validation = true # pas d'appel STS GetCallerIdentity
    skip_region_validation      = true # « us-east-1 » n'a pas de sens pour SeaweedFS
    skip_requesting_account_id  = true # pas d'API IAM/STS pour trouver un numéro de compte
    skip_metadata_api_check     = true # pas de service de métadonnées EC2 (169.254.169.254)

    # Verrou natif : un objet socle/terraform.tfstate.tflock écrit avec If-None-Match: *
    # (M05-E12). Pas de table DynamoDB.
    use_lockfile = true
  }
}
