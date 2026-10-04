#!/usr/bin/env bash
# gitlab-rotation-jeton.sh — fait tourner un jeton d'accès personnel GitLab rangé dans un fichier.
#
# Usage : gitlab-rotation-jeton.sh FICHIER_JETON JOURS
#   ex. : gitlab-rotation-jeton.sh ~/.config/workbook/gitlab-admin.token 90
#
# Le jeton doit avoir la portée api (ou self_rotate) : il se fait tourner lui-même
# (POST /personal_access_tokens/self/rotate). GitLab révoque l'ancien jeton et renvoie le nouveau,
# avec les mêmes portées. Sans expires_at, le nouveau jeton expirerait dans 7 jours : on le précise.
# Le nouveau secret est écrit dans un fichier temporaire 600 du même dossier, puis renommé
# (opération atomique) : à aucun moment le fichier n'est vide ou lisible par d'autres.
# Le jeton des checks (read_api seule) ne peut pas se faire tourner lui-même : rotation dans
# l'interface, ou par POST /personal_access_tokens/<id>/rotate avec le jeton d'administration.
set -euo pipefail

URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
[[ $# -eq 2 && "$2" =~ ^[0-9]+$ ]] || { echo "Usage : $0 FICHIER_JETON JOURS" >&2; exit 2; }
fichier="$1"; jours="$2"
(( jours >= 1 && jours <= 365 )) || { echo "durée hors limites (1 à 365 jours)" >&2; exit 2; }
[[ -r "$fichier" ]] || { echo "fichier illisible : $fichier" >&2; exit 1; }

umask 077
tmp="$(mktemp "$(dirname "$fichier")/.rotation.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

expire="$(date -d "+$jours days" +%F)"
reponse="$(curl -sSf --max-time 30 -X POST \
  -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(tr -d '[:space:]' < "$fichier")") \
  "$URL/api/v4/personal_access_tokens/self/rotate?expires_at=$expire")" \
  || { echo "rotation refusée (jeton expiré, révoqué, ou sans portée api/self_rotate ?)" >&2; exit 1; }

jq -er .token <<<"$reponse" > "$tmp"
mv "$tmp" "$fichier"
trap - EXIT
jq -r '"Nouveau jeton « \(.name) » (id \(.id)), portées \(.scopes | join(",")), expire le \(.expires_at)"' <<<"$reponse"
