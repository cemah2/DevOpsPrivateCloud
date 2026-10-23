# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# _m28-operationnel.sh — fonctions du palier 2 du module 28 (check-E06 à check-E12). Charge aussi les
# fonctions du palier 1 (_m28d_). Sourcé, jamais lancé seul. Lecture seule. Préfixe _m28o_.

# shellcheck source=_m28-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-decouverte.sh"

# --- Catalogue du portail (jeton d'accès externe des checks, plugin catalog en lecture) --------------

# _m28o_entite KIND NOM [ESPACE=default] — JSON de l'entité, « null » si absente ou injoignable.
_m28o_entite() {
  local s
  s="$(backstage_api "catalog/entities/by-name/$1/${3:-default}/$2" 2>/dev/null)" || s=""
  if jq -e '.metadata.name' >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# _m28o_eq KIND NOM 'filtre jq' [options jq…] — l'entité existe et satisfait le filtre.
_m28o_eq() {
  local k="$1" n="$2" f="$3"
  shift 3
  _m28o_entite "$k" "$n" | jq -e "$@" "$f" >/dev/null 2>&1
}

# _m28o_entites 'filtre de catalogue' — tableau JSON des entités (ex. kind=group), « [] » si erreur.
_m28o_entites() {
  local s
  s="$(backstage_api "catalog/entities?filter=$(_m28d_enc "$1")" 2>/dev/null)" || s=""
  if jq -e 'type == "array"' >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo '[]'; fi
}

# _m28o_origine_ldap KIND — le catalogue a RÉPONDU, contient au moins une entité de ce type, et
# TOUTES viennent du fournisseur LDAP (aucune d'un dépôt).
_m28o_origine_ldap() {
  local s
  s="$(backstage_api "catalog/entities?filter=$(_m28d_enc "kind=$1")" 2>/dev/null)" || return 1
  jq -e 'type == "array" and length > 0 and
         all(.[]; (.metadata.annotations["backstage.io/managed-by-location"] // "") | startswith("ldap"))' \
    >/dev/null 2>&1 <<<"$s"
}

# _m28o_code_http URL [en-tête d'autorisation : jeton des checks si « jeton »] — code HTTP de la réponse.
_m28o_code_http() {
  local f="${WB_BACKSTAGE_TOKEN_FILE:-$HOME/.config/workbook/backstage-checks.token}"
  if [[ "${2:-}" == "jeton" ]]; then
    [[ -r "$f" ]] || { echo 000; return 0; }
    curl -s -o /dev/null -w '%{http_code}' --max-time "${WB_TIMEOUT:-5}" \
      -K <(printf 'header = "Authorization: Bearer %s"\n' "$(<"$f")") "$1" 2>/dev/null || echo 000
  else
    curl -s -o /dev/null -w '%{http_code}' --max-time "${WB_TIMEOUT:-5}" "$1" 2>/dev/null || echo 000
  fi
}

# --- Stockage objet (identité de LECTURE de portail-techdocs) ------------------------------------------

# _m28o_s3_objet COMPARTIMENT CLÉ — l'objet existe (head-object).
# Le fichier (600) contient AWS_ACCESS_KEY_ID=… et AWS_SECRET_ACCESS_KEY=… ; il est LU (pas sourcé) et
# les clés passent par l'environnement de « aws » seulement (jamais en argument, visible par ps).
_m28o_s3_objet() {
  local b="$1" k="$2" id secret
  [[ -r "$_m28d_s3_techdocs" ]] || return 1
  id="$(sed -n 's/^[[:space:]]*\(export[[:space:]]\+\)\?AWS_ACCESS_KEY_ID=["'"'"']\?\([^"'"'"']*\)["'"'"']\?[[:space:]]*$/\2/p' "$_m28d_s3_techdocs" | head -n 1)"
  secret="$(sed -n 's/^[[:space:]]*\(export[[:space:]]\+\)\?AWS_SECRET_ACCESS_KEY=["'"'"']\?\([^"'"'"']*\)["'"'"']\?[[:space:]]*$/\2/p' "$_m28d_s3_techdocs" | head -n 1)"
  [[ -n "$id" && -n "$secret" ]] || return 1
  AWS_ACCESS_KEY_ID="$id" AWS_SECRET_ACCESS_KEY="$secret" \
    aws --endpoint-url "$_m28d_s3" --output json s3api head-object --bucket "$b" --key "$k" </dev/null >/dev/null 2>&1
}

# --- GitLab -------------------------------------------------------------------------------------------

# _m28o_mr_portail PROJET MOTIF — une MR (ouverte ou fusionnée) dont le titre contient MOTIF, ouverte par
# svc-portail.
_m28o_mr_portail() {
  gitlab_api "projects/$(_m28d_enc "$1")/merge_requests?state=all&search=$(_m28d_enc "$2")&in=title&per_page=20" 2>/dev/null |
    jq -e '[.[] | select(.author.username == "svc-portail")] | length >= 1' >/dev/null 2>&1
}
