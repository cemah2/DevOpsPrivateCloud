# acces-proxmox/royaume.tf — royaume OpenID Connect « medisphere » de pve01 (M24-E15, SEC-2515).
#
# Les personnes se connectent en <identifiant>@medisphere ; leurs groupes de l'annuaire (revendication
# « groups ») deviennent les groupes Proxmox « <groupe>-medisphere » (suffixe imposé par Proxmox VE
# pour éviter les collisions). root@pam reste le bris de glace, wb-admin@pve est désactivé (à la main,
# il n'est pas géré ici), les comptes d'automatisation wb-*@pve ne changent pas.
resource "proxmox_realm_openid" "medisphere" {
  realm      = "medisphere"
  issuer_url = "https://sso.par1.medisphere.internal/realms/medisphere"
  client_id  = "proxmox"
  # Secret en écriture seule : ni dans le plan, ni dans l'état. Proxmox ne le renvoie jamais.
  client_key_wo         = var.proxmox_oidc_secret
  client_key_wo_version = var.proxmox_oidc_secret_version

  # « username » = revendication preferred_username de l'ID token : lucas.martin@medisphere.
  # Ne change plus après la création (les identifiants des utilisateurs en dépendent) : se tromper
  # ici, c'est supprimer et recréer le royaume.
  username_claim = "username"
  autocreate     = true

  groups_claim = "groups"
  # Seuls les groupes DÉCLARÉS ci-dessous servent (un groupe inconnu de la revendication est ignoré).
  groups_autocreate = false
  # Les groupes de la personne sont REMPLACÉS à chaque connexion : un retrait dans l'annuaire se voit
  # à la connexion suivante (pas seulement les ajouts).
  groups_overwrite = true

  scopes         = "openid email profile"
  query_userinfo = true
  default        = false
  comment        = "SSO MédiSphère (Keycloak), M24-E15 — géré par plateforme/infra acces-proxmox/"
}

# Groupes déclarés AVANT toute connexion : une ACL ne vise qu'un groupe qui existe. Membres : remplis
# par Proxmox à la connexion (groups_overwrite) ; pour le fournisseur, « members » est en lecture
# seule (calculé) : aucune dérive au plan quand les personnes se connectent.
locals {
  groupes_annuaire = {
    "plateforme-admins" = "Administrateurs de la plateforme (annuaire)"
    "plateforme"        = "Équipe Plateforme (annuaire)"
    "securite"          = "Sécurité (annuaire)"
    "support"           = "Support et astreinte (annuaire)"
  }
}

resource "proxmox_virtual_environment_group" "annuaire" {
  for_each = local.groupes_annuaire
  group_id = "${each.key}-medisphere"
  comment  = "${each.value} — membres posés par le royaume medisphere, M24-E15"
}
