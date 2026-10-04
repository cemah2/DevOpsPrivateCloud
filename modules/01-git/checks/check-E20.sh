# shellcheck shell=bash
# shellcheck disable=SC2016  # variables jq entre apostrophes
#
# check-E20.sh — M01-E20 : jetons et clés (personnels, de projet, de déploiement), registre des secrets
# Lancé depuis adm01. Lecture seule : requêtes GET sur l'API GitLab (jeton des checks, et jeton
# d'administration uniquement pour lire ses propres caractéristiques), fichiers locaux.

title "M01-E20 — Jetons et clés : personnels, de projet, de déploiement"
require_cmd curl jq

_m01_url="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
_m01_fc="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
_m01_fa="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
_m01_p="projects/formation%2Fgit-labo"
_m01_jq() { jq -e "$1" <<<"$2" >/dev/null 2>&1; }
# _m01_self FICHIER_JETON — caractéristiques du jeton contenu dans le fichier
_m01_self() {
  [[ -r "$1" ]] || return 1
  curl -sf --max-time "$WB_TIMEOUT" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(tr -d '[:space:]' < "$1")") \
    "$_m01_url/personal_access_tokens/self" 2>/dev/null
}
# _m01_exp_max JSON AAAA-MM-JJ — le jeton a une date d'expiration, au plus tard à cette date
_m01_exp_max() { jq -e --arg m "$2" '.expires_at != null and .expires_at <= $m' <<<"$1" >/dev/null 2>&1; }
_m01_dans() { date -d "+$1 days" +%F; }

# --- Fichiers de secrets sur adm01 --------------------------------------------------------------
check_output "le dossier .config/workbook est en mode 700" '^700$' stat -c %a "$HOME/.config/workbook"
for _m01_f in "$_m01_fc" "$_m01_fa"; do
  check_output "$(basename "$_m01_f") est en mode 600" '^600$' stat -c %a "$_m01_f"
done

# --- Jeton des checks -----------------------------------------------------------------------------
_m01_c="$(_m01_self "$_m01_fc")" || _m01_c="{}"
check_cmd "jeton des checks : actif, portée read_api seule" \
  _m01_jq '.active == true and .scopes == ["read_api"]' "$_m01_c"
check_cmd "jeton des checks : expire dans un an au plus" _m01_exp_max "$_m01_c" "$(_m01_dans 366)"

# --- Jeton d'administration ------------------------------------------------------------------------
_m01_a="$(_m01_self "$_m01_fa")" || _m01_a="{}"
check_cmd "jeton d'administration : actif, portée api" \
  _m01_jq '.active == true and (.scopes | index("api") != null)' "$_m01_a"
check_cmd "jeton d'administration : aucune portée superflue (sudo, write_repository, read_user…)" \
  _m01_jq '(.scopes - ["api", "admin_mode"]) == []' "$_m01_a"
check_cmd "jeton d'administration : expire dans 90 jours au plus" _m01_exp_max "$_m01_a" "$(_m01_dans 90)"

# --- Ta clé SSH déclarée dans GitLab --------------------------------------------------------------
_m01_cles="$(gitlab_api "user/keys" 2>/dev/null)" || _m01_cles="[]"
check_cmd "tes clés SSH d'authentification déclarées dans GitLab ont toutes une date d'expiration" \
  _m01_jq '[.[] | select((.usage_type // "auth_and_signing") != "signing")] as $a
           | ($a | length) > 0 and all($a[]; .expires_at != null)' "$_m01_cles"

# --- formation/git-labo : clé de déploiement et jeton de projet -------------------------------------
_m01_dk="$(gitlab_api "$_m01_p/deploy_keys" 2>/dev/null)" || _m01_dk="[]"
check_cmd "formation/git-labo : une clé de déploiement en lecture seule est déclarée" \
  _m01_jq 'any(.[]; .can_push == false)' "$_m01_dk"
check_cmd "formation/git-labo : aucune clé de déploiement n'a le droit d'écrire" \
  _m01_jq 'all(.[]; .can_push == false)' "$_m01_dk"
_m01_pat="$(gitlab_api "$_m01_p/access_tokens?state=inactive&per_page=100" 2>/dev/null)" || _m01_pat="[]"
check_cmd "formation/git-labo : un jeton de projet Reporter / read_repository a été testé puis révoqué" \
  _m01_jq 'any(.[]; .revoked == true and .access_level == 20 and .scopes == ["read_repository"])' "$_m01_pat"

# --- Registre des secrets (plateforme/medisphere) ------------------------------------------------------
_m01_reg="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/files/docs%2Fsocle%2Fregistre-secrets.md/raw?ref=main" 2>/dev/null)" || _m01_reg=""
check_cmd "docs/socle/registre-secrets.md est sur main de plateforme/medisphere" test -n "$_m01_reg"
check_cmd "le registre décrit le jeton des checks et le jeton d'administration" \
  bash -c 'grep -q "gitlab-checks" <<<"$1" && grep -q "gitlab-admin" <<<"$1"' _ "$_m01_reg"
check_cmd "le registre décrit la clé de déploiement et la procédure de rotation" \
  bash -c 'grep -Eqi "d[ée]ploiement" <<<"$1" && grep -Eqi "rotation" <<<"$1"' _ "$_m01_reg"
check_cmd "le registre ne contient aucune valeur de secret" \
  bash -c '! grep -Eq "gl(pat|dt|rt|ptt|ft)-[0-9A-Za-z_.-]{16,}|BEGIN [A-Z ]*PRIVATE KEY" <<<"$1"' _ "$_m01_reg"
