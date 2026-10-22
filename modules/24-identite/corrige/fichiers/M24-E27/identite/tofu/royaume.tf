# tofu/royaume.tf — le royaume medisphere (créé à la main en M24-E05, importé en M24-E08,
# durci en M24-E27, SEC-2527).
#
# Chaque valeur décidée est ÉCRITE, même quand elle vaut la valeur par défaut de Keycloak : le
# fournisseur ne réécrit pas un attribut absent du code, et une valeur par défaut peut changer à
# la prochaine version (E33). La justification de chaque valeur est dans le corrigé de M24-E27 et
# dans ADR-0240.
resource "keycloak_realm" "medisphere" {
  realm        = "medisphere"
  display_name = "MédiSphère"
  enabled      = true

  registration_allowed     = false
  login_with_email_allowed = true
  ssl_required             = "external"
  # Pas de « se souvenir de moi » : la session SSO ne doit pas survivre à la fermeture du navigateur.
  remember_me = false
  # Les personnes n'ont pas de mot de passe dans Keycloak (fédération) : la réinitialisation se fait
  # dans l'annuaire, pas par un lien envoyé par Keycloak.
  reset_password_allowed = false

  default_signature_algorithm = "RS256"

  # --- Jetons et sessions (M24-E27) ---------------------------------------------------------------
  # Jeton d'accès court : un jeton volé ne vaut que 5 minutes ; les services le rafraîchissent.
  access_token_lifespan = "5m"
  # Code d'autorisation : une minute (défaut), usage unique.
  access_code_lifespan = "1m"
  # Session SSO : 30 minutes d'inactivité, 10 h au plus (une journée de travail). La 26.8 plafonne
  # en plus l'expiration des jetons de rafraîchissement par l'inactivité de session.
  sso_session_idle_timeout = "30m"
  sso_session_max_lifespan = "10h"
  # Sessions des clients alignées sur la session SSO (0 = hériter de la session SSO).
  client_session_idle_timeout = "0s"
  client_session_max_lifespan = "0s"
  # Rotation des jetons de rafraîchissement : chaque rafraîchissement en délivre un NOUVEAU et
  # invalide l'ancien ; une seconde présentation de l'ancien est refusée (vol détecté).
  revoke_refresh_token    = true
  refresh_token_max_reuse = 0

  # --- Mots de passe des comptes LOCAUX (le royaume n'en a pas : fédération READ_ONLY ; la règle
  # empêche qu'on en crée un faible par erreur). Celle de l'annuaire est dans annuaire/politiques.yml.
  password_policy = "length(12) and maxLength(128) and notUsername and notEmail and passwordHistory(6)"

  security_defenses {
    headers {
      # Valeurs de Keycloak 26.7 relues et ASSUMÉES : la console et les pages de connexion utilisent
      # des iframes de la même origine (vérification de session) : SAMEORIGIN, pas DENY.
      x_frame_options                     = "SAMEORIGIN"
      content_security_policy             = "frame-src 'self'; frame-ancestors 'self'; object-src 'none';"
      content_security_policy_report_only = ""
      x_content_type_options              = "nosniff"
      x_robots_tag                        = "none"
      strict_transport_security           = "max-age=31536000; includeSubDomains"
      referrer_policy                     = "no-referrer"
    }

    # Force brute : Keycloak doit verrouiller AVANT l'annuaire (6 échecs → compte verrouillé dans
    # FreeIPA, donc partout : SSH, sudo, tous les services). Verrouillage TEMPORAIRE seulement :
    # un verrouillage permanent désactiverait la personne dans Keycloak, à la main de quiconque
    # connaît son identifiant (déni de service), et sans lien avec l'annuaire (source de vérité).
    brute_force_detection {
      permanent_lockout                = false
      max_login_failures               = 5
      wait_increment_seconds           = 60
      max_failure_wait_seconds         = 900
      failure_reset_time_seconds       = 43200
      quick_login_check_milli_seconds  = 1000
      minimum_quick_login_wait_seconds = 60
    }
  }
}
