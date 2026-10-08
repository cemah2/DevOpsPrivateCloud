# variables.tf — ce que l'équipe CHOISIT. Ce que la plateforme impose (fournisseur OVN du
# répartiteur, groupes de sécurité minimaux, pas d'IP flottante sur les instances, étiquettes)
# n'est pas une variable.

variable "prefixe" {
  description = "Préfixe de toutes les ressources (ex. agenda-recette) : minuscules, chiffres, tirets."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.prefixe))
    error_message = "Le préfixe doit faire 3 à 31 caractères : minuscules, chiffres, tirets, en commençant par une lettre."
  }
}

variable "cidr" {
  description = "Plage du sous-réseau privé, /24 à /28, hors des réseaux du lab (10.10.0.0/16, 10.20.0.0/16, 10.255.0.0/16)."
  type        = string
  validation {
    condition = (
      can(cidrnetmask(var.cidr))
      && tonumber(split("/", var.cidr)[1]) >= 24 && tonumber(split("/", var.cidr)[1]) <= 28
      && !contains(["10.10", "10.20", "10.255"], join(".", slice(split(".", split("/", var.cidr)[0]), 0, 2)))
    )
    error_message = "Plage invalide, de taille hors /24-/28, ou en chevauchement avec les réseaux du lab."
  }
}

variable "nombre_instances" {
  description = "Nombre de serveurs d'application derrière le répartiteur (2 à 4)."
  type        = number
  default     = 2
  validation {
    condition     = var.nombre_instances >= 2 && var.nombre_instances <= 4
    error_message = "Entre 2 et 4 instances (sinon le répartiteur n'a pas de sens, ou le quota explose)."
  }
}

variable "gabarit" {
  description = "Gabarit des instances (m1.petit ou m1.moyen)."
  type        = string
  default     = "m1.petit"
  validation {
    condition     = contains(["m1.petit", "m1.moyen"], var.gabarit)
    error_message = "Gabarits autorisés en libre-service : m1.petit, m1.moyen."
  }
}

variable "image" {
  description = "Nom de l'image Glance (publique, maintenue par la plateforme)."
  type        = string
  default     = "debian-13"
}

variable "cle_publique_ssh" {
  description = "Clé publique SSH de l'équipe (paire de clés <prefixe>-cle)."
  type        = string
}

variable "volume_taille" {
  description = "Taille (Go) du volume de données attaché à la première instance."
  type        = number
  default     = 5
}

variable "point_de_montage" {
  description = "Point de montage du volume de données (XFS)."
  type        = string
  default     = "/srv/donnees"
}

variable "page_titre" {
  description = "Titre de la page servie (le nom d'hôte de l'instance y est ajouté)."
  type        = string
  default     = "MédiAgenda — recette"
}

variable "clients_http" {
  description = "Plages autorisées à joindre l'application sur le port 80 (le fournisseur OVN ne traduit pas l'adresse source : ce sont les CLIENTS que voient les instances)."
  type        = list(string)
  default     = ["10.10.10.0/24", "10.255.1.0/24"]
}

variable "cidr_admin" {
  description = "Plages autorisées en SSH sur l'accès d'administration (MGMT et VPN d'administration)."
  type        = list(string)
  default     = ["10.10.10.0/24", "10.255.1.0/24"]
}

variable "acces_admin" {
  description = "Crée temporairement une IP flottante d'administration sur la première instance (SSH depuis cidr_admin seulement). À remettre à false après usage."
  type        = bool
  default     = false
}

variable "reseau_externe" {
  description = "Réseau externe (IP flottantes, passerelle des routeurs)."
  type        = string
  default     = "ext-net"
}

variable "dns" {
  description = "Résolveurs annoncés par DHCP."
  type        = list(string)
  default     = ["10.10.20.10", "10.10.20.16"]
}

variable "etiquettes" {
  description = "Étiquettes Neutron/Nova ajoutées aux ressources (l'étiquette « libre-service » est toujours posée)."
  type        = list(string)
  default     = []
}
