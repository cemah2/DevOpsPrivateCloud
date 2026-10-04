# shellcheck shell=bash
#
# check-E31.sh — M01-E31 « Durcir GitLab »
# Lancé depuis adm01. Lecture seule. Les réglages d'instance se lisent par l'API
# d'administration : avec Admin Mode actif, le jeton des checks doit avoir la
# portée admin_mode en plus de read_api.

title "M01-E31 — Durcir GitLab"
require_cmd jq curl

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }
_m01_S="$(_m01_get application/settings)"

check_cmd "réglages d'instance lisibles par le jeton des checks (Admin Mode : portée admin_mode)" \
  jq -e 'has("signup_enabled")' <<<"$_m01_S"
_m01_regle() {   # _m01_regle "description" 'expression jq'
  check_cmd "$1" jq -e "$2" <<<"$_m01_S"
}
_m01_regle "inscriptions fermées"                                    '.signup_enabled == false'
_m01_regle "2FA obligatoire pour tous les comptes"                   '.require_two_factor_authentication == true'
_m01_regle "Admin Mode activé"                                       '.admin_mode == true'
_m01_regle "visibilité « public » interdite aux non-administrateurs" '(.restricted_visibility_levels // []) | index("public")'
_m01_regle "Git en HTTPS : pas d'authentification par mot de passe"  '.password_authentication_enabled_for_git == false'
_m01_regle "sessions bornées : pas de « se souvenir de moi », 12 h au plus" \
  '.remember_me_enabled == false and .session_expire_delay <= 720'
_m01_regle "clés SSH : DSA interdit, RSA de 3072 bits au moins" \
  '.dsa_key_restriction == -1 and (.rsa_key_restriction == -1 or .rsa_key_restriction >= 3072)'
_m01_regle "runners : jetons d'enregistrement (ancien flux) désactivés"  '.allow_runner_registration_token == false'
_m01_regle "pas de statistiques d'usage envoyées à l'éditeur (Service Ping)" '.usage_ping_enabled == false'
_m01_regle "pas d'avatars chargés depuis un service externe (Gravatar)"   '.gravatar_enabled == false'

check_cmd "aucun projet public" jq -e 'length == 0' <<<"$(_m01_get 'projects?visibility=public&per_page=1')"
check_cmd "aucun groupe public" jq -e 'length == 0' <<<"$(_m01_get 'groups?all_available=true&visibility=public&per_page=1')"
check_cmd "le compte root a la 2FA active" \
  jq -e '.[0].two_factor_enabled == true' <<<"$(_m01_get 'users?username=root')"
check_cmd "ton compte ($WB_MOI) a la 2FA active" \
  jq -e '.[0].two_factor_enabled == true' <<<"$(_m01_get "users?username=${WB_MOI:-inconnu}")"

check_cmd "plateforme/medisphere : rapport docs/socle/securite/durcissement-gitlab.md" \
  test -n "$(_m01_get "projects/plateforme%2Fmedisphere/repository/files/docs%2Fsocle%2Fsecurite%2Fdurcissement-gitlab.md/raw?ref=main")"
check_cmd "plateforme/medisphere : application reproductible versionnée sous forge/durcissement/" \
  jq -e 'length > 0' <<<"$(_m01_get "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=forge%2Fdurcissement&per_page=50")"
