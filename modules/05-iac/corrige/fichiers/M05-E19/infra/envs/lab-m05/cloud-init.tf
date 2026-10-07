# cloud-init.tf — user-data de la VM jetable, généré et déposé par OpenTofu (M05-E19).

locals {
  user_data_jetable = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    nom        = "m05-jetable"
    domaine    = local.domaine
    cles       = var.cles_ssh_admin
    paquets    = ["curl", "jq"]
    generation = var.generation_jetable
  })
}

resource "proxmox_virtual_environment_file" "user_data_jetable" {
  node_name    = var.noeud
  datastore_id = "tofu-snippets"
  content_type = "snippets"

  source_raw {
    data = local.user_data_jetable
    # L'empreinte du contenu est dans le NOM : un contenu nouveau = un fichier nouveau = un
    # identifiant nouveau pour la VM (user_data_file_id force alors son remplacement). Avec
    # un nom fixe, le fichier changerait sous une VM qui a déjà démarré : cloud-init ne le
    # relirait jamais, et la VM ne correspondrait plus au code sans que le plan le montre.
    file_name = "m05-jetable-${substr(sha256(local.user_data_jetable), 0, 12)}.yaml"
  }

  lifecycle {
    # Le nouveau fichier existe AVANT que l'ancien ne disparaisse : si la recréation de la VM
    # échoue, l'ancienne VM garde un snippet valide et peut encore démarrer.
    create_before_destroy = true
  }
}

output "user_data_jetable" {
  description = "Snippet cloud-init de la VM jetable (identifiant Proxmox)."
  value       = proxmox_virtual_environment_file.user_data_jetable.id
}
