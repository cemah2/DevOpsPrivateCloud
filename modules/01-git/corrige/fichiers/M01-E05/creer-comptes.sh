#!/usr/bin/env bash
# creer-comptes.sh — comptes des personnages, groupes et appartenances par l'API (M01-E05).
# Usage : creer-comptes.sh [personnages.tsv]
#   (défaut : modules/01-git/ressources/M01-E05/personnages.tsv du workbook)
# Idempotent : un compte, un groupe ou une appartenance déjà présents ne sont pas recréés.
# Jeton : ~/.config/workbook/gitlab-admin.token (portée api, compte administrateur <MOI>).
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
TSV="${1:-$RACINE/modules/01-git/ressources/M01-E05/personnages.tsv}"
API="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
JETON_FICHIER="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"

api() {
  local methode="$1" chemin="$2"; shift 2
  printf 'PRIVATE-TOKEN: %s\n' "$(<"$JETON_FICHIER")" |
    curl -sS --fail-with-body -H @- -X "$methode" "$API/$chemin" "$@"
}

niveau() {   # rôle -> niveau d'accès numérique de l'API
  case "$1" in
    Guest) echo 10 ;; Reporter) echo 20 ;; Developer) echo 30 ;;
    Maintainer) echo 40 ;; Owner) echo 50 ;; *) echo "rôle inconnu : $1" >&2; return 1 ;;
  esac
}

id_compte() { api GET "users?username=$1" | jq -r '.[0].id // empty'; }

# --- 1. Comptes -------------------------------------------------------------------------
while IFS=$'\t' read -r identifiant nom adresse _ _; do
  [[ -z "$identifiant" || "$identifiant" == \#* ]] && continue
  if [[ -n "$(id_compte "$identifiant")" ]]; then
    echo "compte $identifiant : déjà présent"; continue
  fi
  # Mot de passe aléatoire que personne ne connaît ; adresse confirmée d'office (pas de SMTP)
  api POST users \
    --data-urlencode "username=$identifiant" \
    --data-urlencode "name=$nom" \
    --data-urlencode "email=$adresse" \
    -d force_random_password=true -d skip_confirmation=true \
    | jq -r '"compte \(.username) : créé (id \(.id), \(.state))"'
done < "$TSV"

# --- 2. Groupes privés (le créateur, <MOI>, en devient Owner) ------------------------------
for g in plateforme formation; do
  if api GET "groups/$g" >/dev/null 2>&1; then
    echo "groupe $g : déjà présent"
  else
    api POST groups -d "name=$g" -d "path=$g" -d visibility=private \
      | jq -r '"groupe \(.full_path) : créé (\(.visibility))"'
  fi
done

# --- 3. Appartenances --------------------------------------------------------------------
ajouter() {   # ajouter GROUPE IDENTIFIANT RÔLE
  local g="$1" u="$2" r="$3" uid
  [[ "$r" == "-" ]] && return 0
  uid="$(id_compte "$u")"
  if api GET "groups/$g/members/$uid" >/dev/null 2>&1; then
    api PUT "groups/$g/members/$uid" -d "access_level=$(niveau "$r")" >/dev/null
  else
    api POST "groups/$g/members" -d "user_id=$uid" -d "access_level=$(niveau "$r")" >/dev/null
  fi
  echo "$g : $u = $r"
}
while IFS=$'\t' read -r identifiant _ _ role_plateforme role_formation; do
  [[ -z "$identifiant" || "$identifiant" == \#* ]] && continue
  ajouter plateforme "$identifiant" "$role_plateforme"
  ajouter formation  "$identifiant" "$role_formation"
done < "$TSV"
