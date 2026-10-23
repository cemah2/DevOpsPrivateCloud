variable "noeud" {
  description = "Nom du nœud Proxmox de hp01 (inchangé : pbs01)."
  type        = string
  default     = "pbs01"
}

variable "stockage" {
  description = "Stockage des disques des VMs de PAR2 (répertoire plafonné sur le disque de hp01)."
  type        = string
  default     = "par2-vms"
}

variable "pont" {
  description = "Pont de PAR2 INFRA sur hp01."
  type        = string
  default     = "vmbr2"
}

variable "cle_ssh_admin" {
  description = "Clé publique SSH du compte admin des VMs (la clé privée de bris de glace est dans l'enveloppe)."
  type        = string
}

variable "absentes" {
  description = <<-EOT
    VMs du catalogue à NE PAS créer (noms). Sert à l'amorçage par étapes (S03 : seulement adm02, dns03,
    s3-02) sans « -target » permanent : S04 retire reg02 de la liste, S05 bao-par2, S06 k8s-par2-n01.
  EOT
  type        = list(string)
  default     = []
}
