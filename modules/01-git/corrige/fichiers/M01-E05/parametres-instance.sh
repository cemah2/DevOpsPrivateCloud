#!/usr/bin/env bash
# parametres-instance.sh — paramètres de sécurité de l'instance GitLab par l'API (M01-E05).
# Équivalent de Admin → Settings → General (Sign-up restrictions, Visibility and access controls).
# Jeton : ~/.config/workbook/gitlab-admin.token (portée api, compte administrateur).
set -euo pipefail

API="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
JETON_FICHIER="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
# Le jeton est passé à curl par un en-tête lu sur l'entrée standard (-H @-) :
# il n'apparaît ni dans la liste des processus ni dans l'historique du shell.
api() {
  local methode="$1" chemin="$2"; shift 2
  printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_FICHIER")" |
    curl -sS --fail-with-body -H @- -X "$methode" "$API/$chemin" "$@"
}

api PUT application/settings \
  -d signup_enabled=false \
  -d 'restricted_visibility_levels[]=public' \
  -d default_project_visibility=private \
  -d default_group_visibility=private \
  -d default_snippet_visibility=private \
  | jq '{signup_enabled, restricted_visibility_levels, default_project_visibility, default_group_visibility}'
