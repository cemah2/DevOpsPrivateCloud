# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes ($n est une variable jq)
#
# check-E15.sh — M06-E15 : Le DNS généré depuis la source de vérité
# À lancer depuis adm01. Lecture seule (API NetBox et PowerDNS en GET, dig).

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E15 — Le DNS généré depuis la source de vérité"
require_cmd curl jq dig

_m06o_checks="${WB_NETBOX_TOKEN_FILE:-$_M06O_CFG/netbox-checks.token}"
_m06o_ip_netbox() {
  _m06o_nb "$_m06o_checks" "virtualization/virtual-machines/?name=$1" \
    | jq -r '.results[0].primary_ip4.address // empty' | cut -d/ -f1
}

# Pour chaque VM du socle : l'IP primaire de NetBox, résolue en A et en PTR.
for _m06o_h in $_M06O_SOCLE; do
  _m06o_ipnb="$(_m06o_ip_netbox "$_m06o_h" 2>/dev/null || true)"
  if [[ -z "$_m06o_ipnb" ]]; then
    check_cmd "$_m06o_h : IP primaire dans NetBox" false
    continue
  fi
  check_output "$_m06o_h : A = IP primaire NetBox ($_m06o_ipnb)" "^${_m06o_ipnb//./\\.}\$" \
    _m06o_dig "$_m06o_h.$_M06O_ZONE"
  check_output "$_m06o_h : PTR de $_m06o_ipnb → $_m06o_h" "^${_m06o_h}\.par1\.medisphere\.internal\.\$" \
    dig +short +time=3 @10.10.20.10 -x "$_m06o_ipnb"
done

# Propriété : des rrsets marqués par un compte d'outil ; aucun A du socle sans propriétaire.
_m06o_zone="$(_m06o_pdns "zones/$_M06O_ZONE." || true)"
check_cmd "des rrsets de par1 portent la marque d'un outil (commentaire avec compte)" \
  jq -e '[.rrsets[] | select(.type == "A") | .comments[]? | select((.account // "") != "")] | length >= 3' <<<"$_m06o_zone"
for _m06o_h in $_M06O_SOCLE; do
  check_cmd "$_m06o_h : son A a un propriétaire (adopté par l'outil, plus écrit à la main)" \
    jq -e --arg n "$_m06o_h.$_M06O_ZONE." \
      '[.rrsets[] | select(.name == $n and .type == "A" and ((.comments // []) | length) == 0)] | length == 0' <<<"$_m06o_zone"
done

_m06o_planifie() {
  systemctl list-timers --all --no-legend 2>/dev/null | grep -qi 'dns' && return 0
  gitlab_api "$_M06O_PROJET_OUTILS/pipeline_schedules" 2>/dev/null \
    | jq -e 'map(select(.active and (.description | test("dns"; "i")))) | length > 0' >/dev/null 2>&1
}
check_cmd "exécution planifiée de la génération DNS (minuterie sur adm01 ou pipeline planifié)" _m06o_planifie
