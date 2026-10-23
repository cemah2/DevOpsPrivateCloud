# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S11.sh — F3-S11 « Jeudi : la moitié des noms ne répond plus » (INC-5911) : les deux récurseurs
# répondent et VALIDENT (drapeau ad) les noms de par1 et de apps.par1 ; sur chaque passerelle, toute
# route vers une adresse de service (10.10.41.x/32) vient de BGP et ne passe que par des nœuds du
# cluster ; aucune règle de pare-feu ne jette le BGP des nœuds ; toutes les sessions BGP de Cilium
# sont établies ; les adresses de service principales répondent depuis adm01 ; trace de l'incident.
# Lecture seule : dig, kube, SSH de lecture sur les passerelles (ip route, sudo -n nft list).

# shellcheck source=_f3-fin.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-fin.sh"

title "F3-S11 — Tous les noms répondent (INC-5911)"
require_cmd dig jq kubectl ssh curl

_f3s_sante

# --- Résolution -------------------------------------------------------------------------------------------
_s11_valide() { dig +dnssec +time=3 +tries=2 "@$1" "$2" A 2>/dev/null | grep -Eq 'flags:[a-z ]* ad[ ;]'; }
for _s11_srv in "dns01:10.10.20.10" "dns02:10.10.20.16"; do
  for _s11_nom in git01.par1.medisphere.internal grafana.apps.par1.medisphere.internal; do
    check_cmd "${_s11_srv%%:*} résout et valide (DNSSEC, drapeau ad) $_s11_nom" _s11_valide "${_s11_srv#*:}" "$_s11_nom"
  done
done

# --- Bordure ----------------------------------------------------------------------------------------------
# _s11_routes_propres GW — toute /32 de 10.10.41.0/24 est apprise par BGP et n'a que des nœuds du
#   cluster (10.10.40.51-53, 61-64) comme prochains sauts.
_s11_routes_propres() {
  local j
  j="$(_f3f_ssh "$1" "ip -j -4 route show table main")"
  [[ -n "$j" ]] || return 1
  jq -e '[.[] | select(.dst | test("^10\\.10\\.41\\.[0-9]+$"))] as $r
    | ($r | length) > 0
      and all($r[]; .protocol == "bgp"
        and all(((.nexthops // [])[].gateway, (.gateway // empty)); test("^10\\.10\\.40\\.(5[1-3]|6[1-4])$")))' >/dev/null 2>&1 <<<"$j"
}
# _s11_bgp_ouvert GW — aucune règle de la table inet filter ne jette du TCP 179.
_s11_bgp_ouvert() {
  local r
  r="$(_f3f_ssh "$1" "sudo -n nft list table inet filter")"
  [[ -n "$r" ]] || return 1
  ! grep -Eq 'tcp (dport|sport) 179 .*(drop|reject)' <<<"$r"
}
for _s11_gw in "${_f3f_passerelles[@]}"; do
  check_cmd "$_s11_gw : routes des adresses de service apprises par BGP, uniquement vers des nœuds du cluster" _s11_routes_propres "$_s11_gw"
  check_cmd "$_s11_gw : aucune règle nftables ne jette le BGP (TCP 179)" _s11_bgp_ouvert "$_s11_gw"
done

_s11_bgp="$(_f3f_k get ciliumbgpnodeconfigs.cilium.io -o json)"
check_cmd "Cilium : toutes les sessions BGP des nœuds sont établies (deux passerelles par nœud)" \
  _f3f_json "$_s11_bgp" '(.items | length) >= 1 and all(.items[];
    ([.status.bgpInstances[]?.peers[]?] | length) >= 2
    and all(.status.bgpInstances[]?.peers[]?; (.peeringState // "" | ascii_downcase) == "established"))'

# --- Joignabilité depuis adm01 ----------------------------------------------------------------------------
read -r -a _s11_cibles <<<"${WB_F3_S11_CIBLES:-10.10.41.10:443 10.10.41.60:9090 10.10.41.61:9093 10.10.41.62:3100}"
for _s11_c in "${_s11_cibles[@]}"; do
  check_port "adresse de service ${_s11_c%%:*} joignable (TCP ${_s11_c##*:}) depuis adm01" "${_s11_c%%:*}" "${_s11_c##*:}"
done

# --- Trace -----------------------------------------------------------------------------------------------
check_cmd "RB-337 publié (docs/exploitation/runbooks/)" _f3f_rb_present RB-337
_f3s_trace INC-5911 2
