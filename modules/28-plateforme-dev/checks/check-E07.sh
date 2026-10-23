# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M28-E07 : Le catalogue : services, équipes et propriétaires
# Lecture seule : API du catalogue (jeton des checks) ; document (GitLab, GET).

# shellcheck source=_m28-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-operationnel.sh"

title "M28-E07 — Le catalogue : services, équipes et propriétaires"
require_cmd jq curl

# --- 1. Organisation (LDAP) -------------------------------------------------------------------------------------
for _m28o_e07_g in mediagenda medidoc plateforme; do
  check_cmd "Group $_m28o_e07_g présent, venu de l'annuaire (LDAP)" _m28o_eq group "$_m28o_e07_g" \
    '(.metadata.annotations["backstage.io/managed-by-location"] // "") | startswith("ldap")'
done
check_cmd "User julien.petit présent et membre de group:default/mediagenda" _m28o_eq user julien.petit \
  '[.relations[]? | select(.type == "memberOf") | .targetRef] | index("group:default/mediagenda") != null'
check_cmd "aucun Group ne vient d'un dépôt (tous de l'annuaire)" _m28o_origine_ldap group
check_cmd "aucun User ne vient d'un dépôt (tous de l'annuaire)" _m28o_origine_ldap user

# --- 2. Systèmes et composants (découverte GitLab) ------------------------------------------------------------------
for _m28o_e07_s in mediagenda:mediagenda medidoc:medidoc medinotif:mediagenda plateforme:plateforme; do
  check_cmd "System ${_m28o_e07_s%%:*} présent, possédé par group:default/${_m28o_e07_s##*:}" _m28o_eq system "${_m28o_e07_s%%:*}" \
    '[.relations[]? | select(.type == "ownedBy") | .targetRef] | index($o) != null' --arg o "group:default/${_m28o_e07_s##*:}"
done
for _m28o_e07_c in mediagenda-api:mediagenda:mediagenda medidoc:medidoc:medidoc medinotif-worker:medinotif:mediagenda portail:plateforme:plateforme; do
  IFS=: read -r _m28o_e07_n _m28o_e07_sys _m28o_e07_eq <<<"$_m28o_e07_c"
  check_cmd "Component $_m28o_e07_n découvert dans GitLab, système $_m28o_e07_sys, propriétaire groupe $_m28o_e07_eq" _m28o_eq component "$_m28o_e07_n" \
    '((.metadata.annotations["backstage.io/managed-by-location"] // "") | test("git01\\.par1\\.medisphere\\.internal"))
     and ([.relations[]? | select(.type == "partOf") | .targetRef] | index("system:default/" + $s) != null)
     and ([.relations[]? | select(.type == "ownedBy") | .targetRef] | index("group:default/" + $e) != null)' \
    --arg s "$_m28o_e07_sys" --arg e "$_m28o_e07_eq"
done
check_cmd "le propriétaire de mediagenda-api existe vraiment (entité Group résolue)" _m28o_eq group mediagenda \
  '[.relations[]? | select(.type == "ownerOf") | .targetRef] | index("component:default/mediagenda-api") != null'

check_cmd "plateforme/medisphere : docs/plateforme-dev/catalogue.md (sources, règles, comptes)" \
  _m28d_doc docs/plateforme-dev/catalogue.md 'svc-portail' 'rules|règle' 'LDAP|annuaire'
