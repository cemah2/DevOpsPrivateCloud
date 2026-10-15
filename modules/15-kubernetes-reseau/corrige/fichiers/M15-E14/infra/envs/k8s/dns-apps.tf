# envs/k8s/dns-apps.tf — délégation de apps.par1.medisphere.internal dans par1 (M15-E14, PLAT-1614).
#
# par1 est pilotée par l'API (« contenu: api », M06-E14/E15) : la délégation y est écrite par
# OpenTofu, comme les A/PTR des VMs. La zone apps elle-même (création, NS, signature, réplication,
# autorisations RFC 2136) est faite par le rôle Ansible powerdns_auth (M15-E14).
# Fournisseur : mmianl/powerdns ~> 2.5.0 (même déclaration que envs/ceph, M08) ; clé d'API dans
# TF_VAR_pdns_api_key (~/.config/workbook/powerdns-api.env), variable éphémère.
#
# DS : relevé sur dns01 APRÈS la signature par le rôle, ligne SHA-256 (type de condensé 2) de
#   sudo -u pdns pdnsutil zone export-ds apps.par1.medisphere.internal
# (aussi affiché par la tâche « Rappeler le DS SHA-256 de chaque zone signée » du pipeline).
# ⚠️ Un DS faux = SERVFAIL sur toute la zone apps depuis les récurseurs (validation DNSSEC).
# Roulement de la clé de apps : procédure RB-064 (M06-E26), en remplaçant par1 par apps et
# « ancre des récurseurs » par « cette variable ».

variable "ds_apps" {
  description = "DS SHA-256 de apps.par1.medisphere.internal : « <keytag> 13 2 <empreinte hexadécimale> »."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{1,5} 13 2 [0-9A-Fa-f]{64}$", var.ds_apps))
    error_message = "ds_apps : « keytag 13 2 empreinte » attendu (ECDSA P-256, SHA-256)."
  }
}

locals {
  commentaire_apps = "gere-par=opentofu (plateforme/infra envs/k8s, M15-E14)"
}

resource "powerdns_record" "apps_ns" {
  zone     = "par1.medisphere.internal."
  name     = "apps.par1.medisphere.internal."
  type     = "NS"
  ttl      = 3600
  records  = ["dns01.par1.medisphere.internal.", "dns02.par1.medisphere.internal."]
  comments = [local.commentaire_apps]
}

resource "powerdns_record" "apps_ds" {
  zone     = "par1.medisphere.internal."
  name     = "apps.par1.medisphere.internal."
  type     = "DS"
  ttl      = 3600
  records  = [var.ds_apps]
  comments = [local.commentaire_apps]
}
