#!/usr/bin/env bash
# rotation-canari.sh — réponse à une fuite de CANARI_JETON (M19-E40, RB-198), depuis adm01.
#   1. rotation du jeton d'accès de projet « canari-lecture » (l'ancien est révoqué par GitLab) ;
#   2. mise à jour de la variable CANARI_JETON (masquée, protégée) ;
#   3. effacement (journal + artefacts) des jobs passés en arguments.
# La valeur du jeton ne passe jamais sur la ligne de commande ni à l'écran.
# Usage : rotation-canari.sh [ID_JOB…]     (variables : GITLAB_URL, GITLAB_TOKEN_FILE, PROJET)
set -euo pipefail

GITLAB_URL="${GITLAB_URL:-https://git01.par1.medisphere.internal}"
GITLAB_TOKEN_FILE="${GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
PROJET="${PROJET:-formation/ci-pannes}"
NOM_JETON=canari-lecture

api() {
  local m="$1" p="$2"
  shift 2
  curl -sS --fail --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(tr -d '[:space:]' <"$GITLAB_TOKEN_FILE")") \
    "$GITLAB_URL/api/v4/$p" "$@"
}

P="$(jq -rn --arg s "$PROJET" '$s|@uri')"
tid="$(api GET "projects/$P/access_tokens?state=active&per_page=100" |
  jq -r --arg n "$NOM_JETON" '[.[] | select(.name == $n and .active)] | max_by(.id) | .id // empty')"
[[ -n "$tid" ]] || { echo "jeton actif « $NOM_JETON » introuvable dans $PROJET" >&2; exit 1; }

echo "Rotation du jeton $NOM_JETON (id $tid)…"
rep="$(api POST "projects/$P/access_tokens/$tid/rotate" --data-urlencode "expires_at=$(date -d '+90 days' +%F)")"
nouveau="$(jq -r '.token // empty' <<<"$rep")"
nid="$(jq -r '.id // empty' <<<"$rep")"
unset rep
[[ -n "$nouveau" ]] || { echo "rotation refusée" >&2; exit 1; }
# La valeur passe par l'entrée standard de curl (« value@- »), jamais par ses arguments (visibles par ps).
printf '%s' "$nouveau" | api PUT "projects/$P/variables/CANARI_JETON" --data-urlencode "value@-" \
  --data-urlencode "masked=true" --data-urlencode "protected=true" --data-urlencode "description=" |
  jq -r '"CANARI_JETON : masquée=\(.masked) protégée=\(.protected)"'
unset nouveau
api GET "projects/$P/access_tokens/$tid" | jq -r '"ancien jeton \(.id) : actif=\(.active) révoqué=\(.revoked)"'
echo "nouveau jeton : id $nid"

for job in "$@"; do
  [[ "$job" =~ ^[0-9]+$ ]] || { echo "identifiant de job invalide : $job" >&2; continue; }
  api POST "projects/$P/jobs/$job/erase" | jq -r '"job \(.id) effacé le \(.erased_at)"'
done
