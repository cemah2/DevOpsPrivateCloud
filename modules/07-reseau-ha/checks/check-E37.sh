# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E37.sh — M07-E37 « Panne : deux maîtres VRRP » : un seul maître par paire (srv01/srv02,
# lb01/lb02), configurations cohérentes, VRRP non filtré. Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E37 — Un seul maître VRRP par paire"
require_cmd ssh jq

_m07_e37_paire() {
  local a="$1" b="$2" vip="$3" vrid="$4" h
  for h in "$a" "$b"; do
    check_cmd "$h : keepalived actif" _m07x_ok "$h" 'systemctl is-active -q keepalived'
    check_cmd "$h : routeur virtuel $vrid présent dans la configuration de keepalived" _m07x_ok "$h" \
      "grep -rqE 'virtual_router_id[[:space:]]+$vrid([^0-9]|\$)' /etc/keepalived"
    check_cmd "$h : aucun filtrage du protocole VRRP" _m07x_ok "$h" \
      "! nft list ruleset 2>/dev/null | grep -Ei 'vrrp|protocol 112' | grep -Eq '(drop|reject)'"
  done
  check_cmd "VIP $vip portée par un seul de $a/$b" _m07x_un_seul_maitre "$a" "$b" "$vip"
}

# _m07_e37_unicast_croise — en unicast, lb01 désigne lb02 et réciproquement (multicast : sans objet).
_m07_e37_unicast_croise() {
  local a b
  a="$(_m07x_sur lb01 'cat /etc/keepalived/keepalived.conf /etc/keepalived/conf.d/*.conf 2>/dev/null' | tr '\n' ' ')"
  b="$(_m07x_sur lb02 'cat /etc/keepalived/keepalived.conf /etc/keepalived/conf.d/*.conf 2>/dev/null' | tr '\n' ' ')"
  grep -q unicast_peer <<<"$a$b" || return 0
  grep -qE 'unicast_peer[[:space:]]*\{[^}]*10\.10\.70\.11([^0-9]|$)' <<<"$a" &&
    grep -qE 'unicast_peer[[:space:]]*\{[^}]*10\.10\.70\.10([^0-9]|$)' <<<"$b"
}

_m07_e37_paire srv01 srv02 10.10.99.240 199
check_output "la VIP 10.10.99.240 sert la page d'un serveur (srv01 ou srv02)" 'srv0[12]' \
  _m07x_sur srv01 'curl -s --max-time 5 http://10.10.99.240/'
if _m07x_existe lb01 && _m07x_existe lb02; then
  _m07_e37_paire lb01 lb02 10.10.70.200 170
  check_cmd "lb01 / lb02 : en unicast, chacun désigne l'autre comme pair" _m07_e37_unicast_croise
else
  skip "paire lb01/lb02" "répartiteurs absents (M07-E12)"
fi
check_cmd "panne M07-E37 close (lab/bin/break 07 37 --annuler après réparation)" _m07x_aucune_panne_active E37
