# registre/caches.tf — caches des registres publics (M13-E04, PLAT-1404).
#
# Un point d'accès (harbor_registry) par registre amont, un projet cache par point d'accès.
# provider_name : noms du FOURNISSEUR, traduits en types Harbor (docker-hub, quay, github-ghcr,
# docker-registry). Les caches sont PUBLICS (tirage anonyme) : contenu public par nature ; l'accès
# réseau est limité par la bordure (VLAN autorisés vers reg01:443) ; chaque tirage reste journalisé.
# Quota par cache : un cache plein refuse les nouvelles images, il ne déborde pas sur medisphere.

variable "dockerhub_utilisateur" {
  description = "Compte Docker Hub (facultatif) : relève la limite de tirage anonyme. Vide = anonyme."
  type        = string
  default     = ""
}

variable "dockerhub_jeton" {
  description = "Jeton d'accès Docker Hub en LECTURE (TF_VAR_dockerhub_jeton, variable CI masquée)."
  type        = string
  default     = ""
  sensitive   = true
}

locals {
  caches = {
    dockerhub = { fournisseur = "docker-hub", url = "https://hub.docker.com", quota_gio = 40, description = "Docker Hub" }
    quay      = { fournisseur = "quay", url = "https://quay.io", quota_gio = 10, description = "Quay.io" }
    ghcr      = { fournisseur = "github", url = "https://ghcr.io", quota_gio = 20, description = "GitHub Container Registry" }
    k8s       = { fournisseur = "docker-registry", url = "https://registry.k8s.io", quota_gio = 15, description = "registry.k8s.io (images de Kubernetes, M14)" }
  }
}

resource "harbor_registry" "amont" {
  for_each      = local.caches
  name          = each.key
  provider_name = each.value.fournisseur
  endpoint_url  = each.value.url
  description   = "${each.value.description} — amont du cache ${each.key} (M13-E04)"
  insecure      = false
  access_id     = each.key == "dockerhub" && var.dockerhub_utilisateur != "" ? var.dockerhub_utilisateur : null
  access_secret = each.key == "dockerhub" && var.dockerhub_jeton != "" ? var.dockerhub_jeton : null
}

resource "harbor_project" "cache" {
  for_each      = local.caches
  name          = each.key
  public        = true
  registry_id   = harbor_registry.amont[each.key].registry_id
  storage_quota = each.value.quota_gio
  # Les images publiques sont analysées par l'analyse planifiée de tout le registre (M13-E05),
  # pas à chaque tirage (le cache se remplit au fil de l'eau, sans « poussée »).
  vulnerability_scanning = false
  # Harbor 2.15.1+ : servir l'image du cache si elle a disparu de l'amont. Laissé à false : une
  # image retirée en amont l'est souvent pour une raison (version piégée, licence) — corrigé E04.
  proxy_cache_local_on_not_found = false
}
