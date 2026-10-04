# shellcheck shell=bash
# _m01-palier4.sh — fonctions partagées par les checks M01-E36 à M01-E47 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) ; toute commande
# qui peut échouer hors des fonctions check_* est protégée.

_M01_FQDN_GIT="git01.par1.medisphere.internal"
_M01_P_MED="projects/plateforme%2Fmedisphere"

# _m01_api_ok "chemin" 'filtre jq' — 0 si la réponse de l'API (jeton des checks) satisfait le filtre.
_m01_api_ok() {
  local r
  r="$(gitlab_api "$1" 2>/dev/null)" || return 1
  jq -e "$2" >/dev/null 2>&1 <<<"$r"
}

# _m01_api_existe "chemin" — 0 si la ressource existe (HTTP 2xx).
_m01_api_existe() { gitlab_api "$1" >/dev/null 2>&1; }

# _m01_ssh_bienvenue — « ssh -T git@forge » accueille l'utilisateur (sans connexion multiplexée).
_m01_ssh_bienvenue() {
  local out
  out="$(ssh -o BatchMode=yes -o ControlPath=none -o ConnectTimeout="${WB_TIMEOUT:-5}" -T "git@$_M01_FQDN_GIT" 2>&1)" || true
  grep -q 'Welcome to GitLab' <<<"$out"
}

# _m01_sans_rebond HÔTE — la configuration SSH locale n'impose ni ProxyJump ni ProxyCommand.
_m01_sans_rebond() {
  ssh -G "$1" 2>/dev/null | awk '
    (tolower($1) == "proxyjump" || tolower($1) == "proxycommand") && tolower($2) != "none" { trouve = 1 }
    END { exit trouve }'
}

# _m01_sujets_presents DÉPÔT PLAGE "sujet"... — chaque sujet de commit apparaît dans la plage.
_m01_sujets_presents() {
  local d="$1" plage="$2" s sujets
  shift 2
  sujets="$(git -C "$d" log --format=%s "$plage" 2>/dev/null)" || return 1
  for s in "$@"; do
    grep -qxF -- "$s" <<<"$sujets" || return 1
  done
}

# _m01_depot_absent_ok DÉPÔT — pour l'astreinte (M01-E43) : un dépôt d'exercice jamais fabriqué
# n'est pas une erreur. Renvoie 0 (et affiche un [--]) si on doit sauter les contrôles.
_m01_depot_absent_ok() {
  if [[ ! -e "$1" && -n "${_m01_astreinte:-}" ]]; then
    skip "$(basename "$1") : contrôles" "dépôt d'exercice non fabriqué par cette astreinte"
    return 0
  fi
  return 1
}
