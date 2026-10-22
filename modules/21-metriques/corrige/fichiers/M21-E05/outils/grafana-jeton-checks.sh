#!/usr/bin/env bash
# grafana-jeton-checks.sh — compte de service « wb-checks » (Viewer) de Grafana et son jeton pour les
# vérifications du workbook (M21-E05). Idempotent pour le compte ; chaque lancement crée un NOUVEAU
# jeton (rotation) et remplace le fichier. Les anciens jetons se révoquent dans l'interface
# (Administration > Users and access > Service accounts > wb-checks) ou par l'API.
# Identifiants d'administration : lus dans un fichier 600 (jamais en argument : visibles par ps).
#   GRAFANA_ADMIN_FILE (défaut ~/.config/workbook/grafana-admin.env) contient
#   GRAFANA_USER=… et GRAFANA_PASSWORD=…  (ton compte personnel Admin, pas « admin » si possible)
# Usage : grafana-jeton-checks.sh [JOURS=90]
set -euo pipefail

url="${WB_GRAFANA_URL:-https://grafana.apps.par1.medisphere.internal}"
f_admin="${GRAFANA_ADMIN_FILE:-$HOME/.config/workbook/grafana-admin.env}"
f_jeton="${WB_GRAFANA_TOKEN_FILE:-$HOME/.config/workbook/grafana-checks.token}"
jours="${1:-90}"
[[ "$jours" =~ ^[0-9]+$ ]] || { echo "JOURS : un entier." >&2; exit 2; }
[[ -r "$f_admin" ]] || { echo "Identifiants illisibles : $f_admin" >&2; exit 2; }
[[ "$(stat -c %a "$f_admin")" == "600" ]] || { echo "$f_admin doit être en 600." >&2; exit 2; }
GRAFANA_USER="" GRAFANA_PASSWORD=""
# shellcheck disable=SC1090
source "$f_admin"

api() {  # api MÉTHODE CHEMIN [CORPS_JSON]
  curl -fsS --max-time 10 -X "$1" -K <(printf 'user = "%s:%s"\n' "$GRAFANA_USER" "$GRAFANA_PASSWORD") \
    -H 'Content-Type: application/json' -H 'Accept: application/json' ${3:+--data "$3"} "$url/api/$2"
}

id="$(api GET 'serviceaccounts/search?query=wb-checks' | jq -r '.serviceAccounts[] | select(.name == "wb-checks") | .id' | head -n 1)"
if [[ -z "$id" ]]; then
  id="$(api POST serviceaccounts '{"name":"wb-checks","role":"Viewer","isDisabled":false}' | jq -r .id)"
  echo "Compte de service wb-checks créé (id $id, rôle Viewer)."
else
  role="$(api GET "serviceaccounts/$id" | jq -r .role)"
  [[ "$role" == "Viewer" ]] || { echo "wb-checks existe avec le rôle $role : remets-le en Viewer." >&2; exit 1; }
  echo "Compte de service wb-checks déjà présent (id $id, rôle Viewer)."
fi

corps="$(jq -nc --arg n "checks-$(date +%Y%m%d-%H%M%S)" --argjson s "$(( jours * 86400 ))" '{name: $n, secondsToLive: $s}')"
umask 077
api POST "serviceaccounts/$id/tokens" "$corps" | jq -r .key > "$f_jeton.tmp"
[[ -s "$f_jeton.tmp" ]] || { rm -f "$f_jeton.tmp"; echo "Jeton vide : rien n'est remplacé." >&2; exit 1; }
mv -f "$f_jeton.tmp" "$f_jeton"
chmod 600 "$f_jeton"
echo "Jeton écrit dans $f_jeton (expire dans $jours jours)."
