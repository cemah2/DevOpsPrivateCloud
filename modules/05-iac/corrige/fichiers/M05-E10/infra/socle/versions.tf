# versions.tf — état « socle » de plateforme/infra (M05-E10).
#
# Même contrat de versions que envs/lab-m05 (M05-E03) : correctifs acceptés, jamais une
# nouvelle mineure du provider sans MR. Empreintes exactes dans .terraform.lock.hcl.
#
# Pas encore de bloc backend : en E10, l'état est LOCAL (socle/terraform.tfstate, ignoré par
# Git). Le stockage S3 qui doit l'héberger est justement ce que ce code construit.
# M05-E11 ajoute le backend "s3" et migre l'état vers s3-01.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.115.0"
    }
  }
}
