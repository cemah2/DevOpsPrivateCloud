# registre/replication.tf — réplication en poussée vers reg02 (M13-E13, PLAT-1431).
# Ajouté à la configuration « registre » de reg01 (M13-E03). Retiré en M13-E25 (avant la VM reg02).
#
# Le robot utilisé est celui de reg02 (état « registre-reg02 », sortie robot_replication) ; son secret
# arrive ici par TF_VAR_reg02_robot_secret (variable CI protégée et masquée, valeur en Vault critique).
# Le certificat de reg02 est émis par la PKI MédiSphère : on la donne à l'endpoint (ca_certificate,
# Harbor 2.15) plutôt que de désactiver la vérification (insecure = false, écrit explicitement).

variable "reg02_robot_secret" {
  description = "Secret du robot de réplication de reg02 (TF_VAR_reg02_robot_secret)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "racine_medisphere_pem" {
  description = "Racine MédiSphère (PEM). Défaut : le fichier du magasin système du runner."
  type        = string
  default     = ""
}

locals {
  reg02_actif = var.reg02_robot_secret != ""
  racine_pem  = var.racine_medisphere_pem != "" ? var.racine_medisphere_pem : file("/usr/local/share/ca-certificates/medisphere-root-ca.crt")
}

resource "harbor_registry" "reg02" {
  count          = local.reg02_actif ? 1 : 0
  name           = "reg02"
  provider_name  = "harbor"
  endpoint_url   = "https://reg02.par1.medisphere.internal"
  description    = "Harbor de test du module 13 (cible de réplication, TEMPORAIRE) — M13-E13"
  access_id      = "robot$replication"
  access_secret  = var.reg02_robot_secret
  insecure       = false
  ca_certificate = local.racine_pem
}

resource "harbor_replication" "medisphere_vers_reg02" {
  count       = local.reg02_actif ? 1 : 0
  name        = "medisphere-vers-reg02"
  description = "Versions publiées de medisphere vers reg02, avec leurs accessoires (signatures, attestations) — M13-E13"
  action      = "push"
  registry_id = harbor_registry.reg02[0].registry_id
  # Cron de Harbor : six champs (secondes en tête) — chaque nuit à 03:15, après la sauvegarde applicative (01:40) et le début de « lab-nuit » (02:30, sauvegarde des VM).
  schedule = "0 15 3 * * *"
  # Même espace de noms à destination (medisphere), aucune mise à plat.
  dest_namespace         = "medisphere"
  dest_namespace_replace = 0
  # Une version réécrite à la source ne doit pas l'être à destination (immuabilité v* sur reg02 aussi) :
  # override = true ne s'applique qu'aux artefacts qui DIFFÈRENT, ce qui ne devrait jamais arriver
  # pour une version ; on le garde pour que les accessoires ajoutés plus tard (attestations) suivent.
  override = true
  # Suppressions NON propagées : une suppression par erreur sur reg01 ne vide pas la copie.
  deletion                  = false
  copy_by_chunk             = false
  single_active_replication = true
  speed                     = -1
  enabled                   = true

  filters {
    name = "medisphere/**"
  }
  filters {
    tag = "v*"
  }
  filters {
    resource = "artifact"
  }
}
