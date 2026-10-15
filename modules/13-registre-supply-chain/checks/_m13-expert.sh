# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# _m13-expert.sh — fonctions partagées par les checks du palier 4 du module 13 (check-E19 à check-E23).
# Sourcé par ces scripts, jamais lancé seul. Lecture seule : API Harbor (robot wb-checks), sonde des
# témoins en mode --lecture sur runner02 (aucun tirage, aucune poussée), lectures par SSH + « sudo -n »
# sur runner02 et reg01, cosign verify depuis adm01.
# S'appuie sur _m13-production.sh (préfixe _m13p_), chargé en tête.

# shellcheck source=_m13-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-production.sh"

_m13x_runner="${WB_M13_RUNNER:-runner02}"
_m13x_reg01="${WB_M13_REG01:-reg01}"

# _m13x_temoins — les témoins du palier 4 existent (sonde installée sur runner02).
_m13x_temoins() {
  remote "$_m13x_runner" "sudo -n test -x /usr/local/sbin/wb-sonde-registre -a -s /etc/workbook/sonde-registre/temoins.txt" >/dev/null 2>&1
}

# _m13x_sonde_lecture ETAPE — une étape de la sonde en mode lecture réussit.
_m13x_sonde_lecture() {
  remote "$_m13x_runner" "sudo -n /usr/local/sbin/wb-sonde-registre --lecture --etape $1" >/dev/null 2>&1
}

# _m13x_cosign_verify IMAGE FICHIER_CLÉ — cosign verify depuis adm01 avec le robot des checks (lecture).
_m13x_cosign_verify() {
  local d f="${WB_HARBOR_CHECKS_FILE:-$HOME/.config/workbook/harbor-checks.env}" rc=0 HARBOR_USER="" HARBOR_PASSWORD=""
  command -v cosign >/dev/null 2>&1 && [[ -r "$f" && -s "$2" ]] || return 1
  # shellcheck disable=SC1090
  source "$f"
  d="$(mktemp -d)" || return 1
  (umask 077 && printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$_M13P_REGISTRE_NOM" \
    "$(printf '%s:%s' "$HARBOR_USER" "$HARBOR_PASSWORD" | base64 -w0)" >"$d/config.json")
  DOCKER_CONFIG="$d" timeout 60 cosign verify --key "$2" --insecure-ignore-tlog=true "$1" >/dev/null 2>&1 || rc=1
  rm -rf -- "$d"
  return "$rc"
}

# _m13x_endpoint_cache_sain — l'endpoint amont du projet dockerhub est « healthy ».
_m13x_endpoint_cache_sain() {
  local id
  id="$(_m13p_api projects/dockerhub | jq -r '.registry_id // empty' 2>/dev/null)" || return 1
  [[ -n "$id" ]] && _m13p_api "registries/$id" | jq -e '.status == "healthy"' >/dev/null 2>&1
}

# _m13x_harbor_pannes_ok — identité des pannes présente et protégée (préparation du palier 4).
_m13x_harbor_pannes_ok() {
  local f="${WB_HARBOR_PANNES_FILE:-$HOME/.config/workbook/harbor-pannes.env}"
  [[ -r "$f" && "$(stat -c %a "$f")" == 600 ]] && grep -q '^HARBOR_USER=' "$f" && grep -q '^HARBOR_PASSWORD=' "$f"
}
