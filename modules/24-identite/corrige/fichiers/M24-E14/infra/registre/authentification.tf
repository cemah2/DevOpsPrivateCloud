# registre/authentification.tf — mode d'authentification de Harbor : OIDC par Keycloak (M24-E14, PLAT-2514).
#
# Harbor refuse de changer auth_mode tant qu'il existe un utilisateur local NON SUPPRIMÉ autre que
# l'administrateur par défaut (controller/config/controller.go : authModeCanBeModified). D'où l'ordre
# des MR : 1) membres de groupes OIDC en plus des utilisateurs ; 2) suppression des utilisateurs et de
# leurs appartenances ; 3) ce fichier. « admin » reste un compte LOCAL, qui se connecte encore par le
# formulaire : c'est le bris de glace (RB-240). Les robots ne dépendent pas du mode d'authentification.
#
# Le secret du client ne va ni dans le code, ni dans le plan, ni dans l'état : variable ÉPHÉMÈRE,
# argument en ÉCRITURE SEULE. Incrémenter harbor_oidc_secret_version pour pousser un nouveau secret
# (rotation, M24-E29, RB-244).
resource "harbor_config_auth" "oidc" {
  auth_mode         = "oidc_auth"
  primary_auth_mode = true

  oidc_name                     = "SSO MédiSphère"
  oidc_endpoint                 = "https://sso.par1.medisphere.internal/realms/medisphere"
  oidc_client_id                = "harbor"
  oidc_client_secret_wo         = var.harbor_oidc_secret
  oidc_client_secret_wo_version = var.harbor_oidc_secret_version
  # « offline_access » n'est pas demandé : Harbor rafraîchit avec le jeton de rafraîchissement normal.
  oidc_scope = "openid,profile,email"

  # Le certificat de sso est vérifié avec la racine MédiSphère, ajoutée au magasin des conteneurs de
  # Harbor par le rôle Ansible harbor (storage_service.ca_bundle, M24-E14). JAMAIS false.
  oidc_verify_cert = true

  # Identifiant Harbor de la personne = son identifiant de l'annuaire (pas son nom affiché).
  oidc_user_claim = "preferred_username"
  # Pas d'écran d'inscription : le nom est imposé par l'IdP, la personne ne peut pas en choisir un autre.
  oidc_auto_onboard = true
  oidc_groups_claim = "groups"
  # Administrateurs système de Harbor : les membres de ce groupe de l'annuaire, et personne d'autre
  # (hors « admin » local, bris de glace).
  oidc_admin_group = "plateforme-admins"
  # Seuls les groupes de personnes de l'annuaire deviennent des groupes Harbor (expression régulière).
  oidc_group_filter = "^(plateforme-admins|plateforme|mediagenda|medidoc|securite|support|direction)$"
}
