# locals.tf — valeurs calculées une fois, utilisées partout (M05-E06).
locals {
  domaine    = "par1.medisphere.internal"
  resolveurs = ["10.10.20.10"] # dns01 (PLAN §4.5)

  # Proxmox trie les étiquettes : on les trie aussi, et on retire les doublons.
  etiquettes = sort(distinct(concat(["env-${var.environnement}"], var.etiquettes_supplementaires)))

  description = "VM d'environnement ${var.environnement}. Gérée par OpenTofu (plateforme/infra, envs/lab-${var.environnement}) : ne pas modifier à la main."
}
