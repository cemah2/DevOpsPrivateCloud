# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E05.sh — M01-E05 : administration de GitLab (comptes, groupes, jetons, paramètres).
# Lancé depuis adm01. Lecture seule : API GitLab avec le jeton des checks (read_api, compte
# administrateur <MOI> ; + admin_mode une fois l'Admin Mode activé en M01-E31, sinon
# application/settings est refusé), fichiers de ~/.config/workbook, et git01 par l'alias SSH.

title "M01-E05 — Premiers pas d'administration GitLab"
require_cmd curl jq git

_m01_tok="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
_m01_adm="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
_m01_max365="$(date -d '+366 days' +%F)"
_m01_max90="$(date -d '+91 days' +%F)"

# _m01_jq "description" 'filtre jq' "json" [args jq...] — OK si le filtre renvoie true
_m01_jq() {
  local desc="$1" filtre="$2" json="$3"; shift 3
  check_cmd "$desc" jq -e "$@" "$filtre" <<<"${json:-null}"
}

# --- 1. Fichiers de jetons -----------------------------------------------------------------
title "1/5 Jetons sur adm01"
check_output "dossier ~/.config/workbook en 700" '^700$' stat -c %a "$HOME/.config/workbook"
check_output "jeton des checks : fichier en 600" '^600$' stat -c %a "$_m01_tok"
check_output "jeton d'administration : fichier en 600" '^600$' stat -c %a "$_m01_adm"

# --- 2. Ton compte et tes jetons -------------------------------------------------------------
title "2/5 Compte <MOI> et jetons"
check_cmd "WB_MOI renseigné dans lab/lab.env" test -n "${WB_MOI:-}"
_m01_user="$(gitlab_api user 2>/dev/null || true)"
check_cmd "le jeton des checks est accepté par GitLab" test -n "$_m01_user"
_m01_jq "le jeton des checks appartient au compte WB_MOI (${WB_MOI:-?})" '.username == $u' "$_m01_user" \
  --arg u "${WB_MOI:-}"
_m01_jq "ce compte est administrateur" '.is_admin == true' "$_m01_user"
_m01_jq "adresse du compte = <MOI>@medisphere.internal = git config user.email" \
  '.email == ($u + "@medisphere.internal") and .email == $g' "$_m01_user" \
  --arg u "${WB_MOI:-}" --arg g "$(git config --global --get user.email 2>/dev/null)"
_m01_self="$(gitlab_api personal_access_tokens/self 2>/dev/null || true)"
_m01_jq "jeton des checks : portée read_api seule (plus admin_mode après M01-E31)" \
  '(.scopes | sort) == ["read_api"] or (.scopes | sort) == ["admin_mode", "read_api"]' "$_m01_self"
_m01_jq "jeton des checks : expiration dans moins d'un an" \
  '.expires_at != null and .expires_at <= $m' "$_m01_self" --arg m "$_m01_max365"
_m01_uid="$(jq -r '.id // empty' <<<"${_m01_user:-null}" 2>/dev/null)"
_m01_toks="$(gitlab_api "personal_access_tokens?user_id=${_m01_uid:-0}&state=active&search=workbook-admin&per_page=100" 2>/dev/null || true)"
_m01_jq "jeton actif « workbook-admin » de portée api, expirant dans moins de 90 jours" \
  'any(.[]; (.scopes | any(. == "api")) and .expires_at != null and .expires_at <= $m)' \
  "$_m01_toks" --arg m "$_m01_max90"

# --- 3. Comptes des personnages --------------------------------------------------------------
title "3/5 Comptes des personnages"
for _m01_p in claire.morel karim.benali sophie.laurent julien.petit nadia.roussel lucas.martin; do
  _m01_jq "compte $_m01_p présent et actif" 'length == 1 and .[0].state == "active"' \
    "$(gitlab_api "users?username=$_m01_p" 2>/dev/null || true)"
done

# --- 4. Groupes et rôles ----------------------------------------------------------------------
title "4/5 Groupes plateforme et formation"
for _m01_g in plateforme formation; do
  _m01_jq "groupe $_m01_g présent et privé" '.visibility == "private"' \
    "$(gitlab_api "groups/$_m01_g" 2>/dev/null || true)"
done
_m01_mp="$(gitlab_api "groups/plateforme/members?per_page=100" 2>/dev/null || true)"
_m01_mf="$(gitlab_api "groups/formation/members?per_page=100" 2>/dev/null || true)"
# role GROUPE_JSON IDENTIFIANT NIVEAU NOM_GROUPE
_m01_role() {
  _m01_jq "$4 : $2 a le rôle attendu (niveau $3)" \
    'any(.[]; .username == $u and .access_level == ($n | tonumber))' "$1" --arg u "$2" --arg n "$3"
}
_m01_role "$_m01_mp" karim.benali 40 plateforme
_m01_role "$_m01_mp" lucas.martin 30 plateforme
for _m01_p in claire.morel sophie.laurent nadia.roussel julien.petit; do
  _m01_role "$_m01_mp" "$_m01_p" 20 plateforme
done
_m01_jq "plateforme : ${WB_MOI:-<MOI>} est Owner" \
  'any(.[]; .username == $u and .access_level == 50)' "$_m01_mp" --arg u "${WB_MOI:-}"
_m01_role "$_m01_mf" karim.benali 40 formation
_m01_role "$_m01_mf" lucas.martin 30 formation
_m01_jq "formation : ni Claire, ni Sophie, ni Nadia, ni Julien ne sont membres" \
  'all(.[]; .username as $x | ["claire.morel","sophie.laurent","nadia.roussel","julien.petit"] | index($x) | not)' \
  "$_m01_mf"

# --- 5. Paramètres de l'instance ----------------------------------------------------------------
title "5/5 Paramètres de l'instance"
_m01_set="$(gitlab_api application/settings 2>/dev/null || true)"
if [[ -n "$_m01_set" ]]; then
  _m01_jq "inscriptions désactivées" '.signup_enabled == false' "$_m01_set"
  _m01_jq "visibilité Public interdite" '(.restricted_visibility_levels // []) | any(. == "public")' "$_m01_set"
  _m01_jq "nouveaux projets privés par défaut" '.default_project_visibility == "private"' "$_m01_set"
  _m01_jq "nouveaux groupes privés par défaut" '.default_group_visibility == "private"' "$_m01_set"
else
  # Repli si l'API des paramètres n'est pas lisible avec ce jeton : lecture directe en base.
  check_ssh_output "inscriptions désactivées (lecture en base)" git01 '^f$' \
    'cd /tmp && sudo -n gitlab-psql -d gitlabhq_production -tAc "SELECT signup_enabled FROM application_settings ORDER BY id DESC LIMIT 1"'
  skip "visibilités par défaut et restreintes" "API application/settings illisible avec le jeton des checks"
fi
check_ssh "git01 : le mot de passe initial de root n'est plus sur le disque" git01 \
  '! sudo -n test -e /etc/gitlab/initial_root_password'
