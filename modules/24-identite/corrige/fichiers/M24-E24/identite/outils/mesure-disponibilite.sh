#!/usr/bin/env bash
# =============================================================================
# outils/mesure-disponibilite.sh — plateforme/identite (M24-E24, PLAT-2524 ; resservi en E29 et E33).
# Mesure ce que voit un CLIENT pendant une bascule ou un redémarrage de Keycloak : chaque seconde,
# (1) la découverte OIDC du royaume (publique), (2) un jeton client_credentials du client wb-checks
# (lecture seule, ~/.config/workbook/keycloak-checks.env, M24-E05). Une ligne par essai, puis, à
# l'arrêt (Ctrl-C ou durée atteinte), le bilan : essais, échecs, plus longue série d'échecs.
#
# Usage : outils/mesure-disponibilite.sh [DURÉE_S=600] [FICHIER_JOURNAL=mesure-<horodatage>.log]
# Aucun secret affiché ni passé en argument (curl -K <(...)).
# =============================================================================
set -Eeuo pipefail

duree="${1:-600}"
journal="${2:-mesure-$(date +%Y%m%dT%H%M%S).log}"
base="${WB_KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
royaume="${WB_KEYCLOAK_ROYAUME:-medisphere}"
fichier="${WB_KEYCLOAK_CHECKS_FILE:-$HOME/.config/workbook/keycloak-checks.env}"

[[ "$duree" =~ ^[0-9]+$ ]] || { echo "durée en secondes attendue" >&2; exit 2; }
[[ -r "$fichier" ]] || { echo "identifiants illisibles : $fichier" >&2; exit 2; }
[[ "$(stat -c %a "$fichier")" == 600 ]] || { echo "$fichier doit être en 600" >&2; exit 2; }
for outil in curl jq; do command -v "$outil" >/dev/null || { echo "$outil requis" >&2; exit 2; }; done

KEYCLOAK_CLIENT_ID=""
KEYCLOAK_CLIENT_SECRET=""
# shellcheck source=/dev/null
source "$fichier"

essais=0
echecs=0
serie=0
pire=0
debut_serie=""
pire_debut=""

bilan() {
  printf '\n# bilan : %d essais, %d échecs (%d %%), plus longue série d échecs : %d s (début %s)\n' \
    "$essais" "$echecs" "$(( essais > 0 ? 100 * echecs / essais : 0 ))" "$pire" "${pire_debut:--}" | tee -a "$journal"
}
trap 'bilan; exit 0' INT TERM

printf '# mesure-disponibilite : %s, royaume %s, %s s, journal %s\n' "$base" "$royaume" "$duree" "$journal" | tee "$journal"
printf '# heure        découverte jeton  durée_ms\n' | tee -a "$journal"
fin=$(( $(date +%s) + duree ))
while (( $(date +%s) < fin )); do
  t0=$(date +%s%3N)
  heure="$(date +%H:%M:%S)"
  d="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$base/realms/$royaume/.well-known/openid-configuration" || true)"
  j="$(curl -s --max-time 3 -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
        -d grant_type=client_credentials "$base/realms/$royaume/protocol/openid-connect/token" \
        | jq -r 'if .access_token then "ok" else (.error // "erreur") end' 2>/dev/null || true)"
  [[ -n "$j" ]] || j="injoignable"
  ms=$(( $(date +%s%3N) - t0 ))
  essais=$(( essais + 1 ))
  if [[ "$d" == 200 && "$j" == ok ]]; then
    etat=OK
    serie=0
  else
    etat=ÉCHEC
    echecs=$(( echecs + 1 ))
    (( serie == 0 )) && debut_serie="$heure"
    serie=$(( serie + 1 ))
    if (( serie > pire )); then pire=$serie; pire_debut="$debut_serie"; fi
  fi
  printf '%s  %-9s  %-5s  %-6s %s\n' "$heure" "$d" "$j" "$ms" "$etat" | tee -a "$journal"
  reste=$(( 1000 - ms ))
  (( reste > 0 )) && sleep "$(printf '0.%03d' "$reste")"
done
bilan
