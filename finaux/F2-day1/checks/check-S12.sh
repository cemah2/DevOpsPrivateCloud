# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S12.sh — F2-S12 « Le départ d'AxiomDev » : personnes désactivées dans l'annuaire et retirées de
# leurs groupes, comptes GitLab bloqués sans jeton actif ni appartenance, aucune session Keycloak,
# espace mediagenda-axiomdev retiré, aucune liaison RBAC restante, preuve publiée
# (docs/accueil/departs/axiomdev.md). Lecture seule.

# shellcheck source=_f2-equipes.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-equipes.sh"

title "F2-S12 — Le départ d'AxiomDev"
require_cmd jq curl kubectl ldapsearch

_s12_g="$_f2b_groupe_axiom"
_s12_re="^oidc:($_s12_g$(printf '|%s' "${_f2b_axiom_personnes[@]//./\\.}"))\$"

for _s12_u in "${_f2b_axiom_personnes[@]}"; do
  check_cmd "annuaire : $_s12_u désactivée (nsAccountLock), pas supprimée" _f2b_desactivee "$_s12_u"
  _s12_sans_groupe() { ! _f2b_groupes_ipa "$1" | grep -Evx 'ipausers' | grep -q .; }
  check_cmd "annuaire : $_s12_u retirée de tous ses groupes" _s12_sans_groupe "$_s12_u"

  _s12_gu="$(_f2b_gitlab_utilisateur "$_s12_u")"
  if [[ -z "$_s12_gu" ]]; then
    check_cmd "GitLab : compte $_s12_u conservé (bloqué, pas supprimé)" false
  else
    _s12_id="$(jq -r .id <<<"$_s12_gu")"
    check_cmd "GitLab : $_s12_u bloqué" jq -e '.state | test("blocked|deactivated|banned")' <<<"$_s12_gu"
    _s12_jetons() {
      local r
      r="$(gitlab_api "personal_access_tokens?user_id=$1&state=active&per_page=100" 2>/dev/null)" || return 2
      jq -e 'length == 0' <<<"$r" >/dev/null 2>&1
    }
    _s12_rc=0
    _s12_jetons "$_s12_id" || _s12_rc=$?
    if ((_s12_rc == 2)); then
      skip "GitLab : jetons personnels de $_s12_u" "liste des jetons illisible avec le jeton des checks"
    else
      check_cmd "GitLab : aucun jeton personnel actif pour $_s12_u" test "$_s12_rc" -eq 0
    fi
    _s12_cles() { gitlab_api "users/$1/keys" 2>/dev/null | jq -e 'length == 0' >/dev/null 2>&1; }
    check_cmd "GitLab : aucune clé SSH enregistrée pour $_s12_u" _s12_cles "$_s12_id"
  fi

  _s12_kc="$(keycloak_api "users?username=$(_f2b_enc "$_s12_u")&exact=true" 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null)" || _s12_kc=""
  if [[ -z "$_s12_kc" ]]; then
    skip "Keycloak : sessions de $_s12_u" "personne inconnue de Keycloak (jamais connectée) ou API illisible"
  else
    _s12_sessions() { keycloak_api "users/$1/sessions" 2>/dev/null | jq -e 'length == 0' >/dev/null 2>&1; }
    check_cmd "Keycloak : aucune session ouverte pour $_s12_u" _s12_sessions "$_s12_kc"
  fi
done

check_output "annuaire : groupe $_s12_g vide ou retiré" '^0$' \
  bash -c 'grep -c "^member: " <<<"$1" || true' _ "$(_f2b_ldap "(&(objectClass=ipausergroup)(cn=$_s12_g))" member)"
_s12_espace_absent() {
  local out
  out="$(kube get namespace "$_f2b_ns_axiom" -o name 2>&1)" && return 1
  grep -q 'NotFound\|not found' <<<"$out"
}
check_cmd "espace $_f2b_ns_axiom retiré du cluster" _s12_espace_absent
check_output "Kubernetes : aucune liaison RBAC restante pour AxiomDev" '^0$' _f2b_liaisons_hors "" "$_s12_re"
check_cmd "preuve du départ : docs/accueil/departs/axiomdev.md (annuaire, GitLab, Keycloak, SSH, espace)" \
  _f2b_doc_sections "$_f2b_doc_dir"/departs/axiomdev.md 4 'nsAccountLock|d[ée]sactiv' 'GitLab' 'Keycloak|session' 'SSH|16 h' "$_f2b_ns_axiom"
