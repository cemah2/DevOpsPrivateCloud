# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E16.sh — M07-E16 : FRR sur la bordure : préparer le BGP de la plateforme
# À lancer depuis adm01, leaf01 démarrée. Lecture seule.

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E16 — FRR sur la bordure : préparer le BGP de la plateforme"
require_cmd jq

check_ssh "gw01 : FRR 10.7 actif" gw01 'systemctl is-active --quiet frr && dpkg-query -W -f="\${Version}" frr | grep -q "^10\.7\."'
_m07o_resume="$(_m07o_vtysh gw01 'show bgp ipv4 unicast summary json')"
check_output "gw01 : AS 65000" '^65000$' jq -r '.as // empty' <<<"$_m07o_resume"
check_output "gw01 : router-id 10.10.10.2" '^10\.10\.10\.2$' jq -r '.routerId // empty' <<<"$_m07o_resume"
check_output "gw01 : session avec leaf01 (10.10.99.251) établie" '^Established$' \
  jq -r '.peers["10.10.99.251"].state // empty' <<<"$_m07o_resume"

_m07o_conf="$(_m07o_vtysh gw01 'show running-config')"
check_cmd "gw01 : bgp ebgp-requires-policy n'est pas désactivé" bash -c \
  'grep -q "^router bgp 65000" <<<"$1" && ! grep -q "no bgp ebgp-requires-policy" <<<"$1"' _ "$_m07o_conf"
check_output "gw01 : groupe K8S en AS 65040" 'neighbor K8S remote-as 65040' echo "$_m07o_conf"
check_output "gw01 : écoute passive du groupe K8S sur 10.10.40.0/24" 'bgp listen range 10\.10\.40\.0/24 peer-group K8S' echo "$_m07o_conf"
check_output "gw01 : groupe K8S fermé (shutdown)" 'neighbor K8S shutdown' echo "$_m07o_conf"
check_output "gw01 : politiques d'entrée et de sortie sur la session leaf01" '^2$' bash -c \
  'grep -cE "neighbor 10\.10\.99\.251 route-map [^ ]+ (in|out)$" <<<"$1"' _ "$_m07o_conf"

# Routes apprises : uniquement dans 10.10.255.0/24 ou 10.10.41.0/24, et au moins une boucle.
_m07o_appris="$(_m07o_vtysh gw01 'show bgp ipv4 unicast neighbors 10.10.99.251 routes json')"
check_output "gw01 : au moins une boucle de la fabric apprise de leaf01" '^[1-9][0-9]*$' \
  jq -r '[.routes // {} | keys[] | select(startswith("10.10.255."))] | length' <<<"$_m07o_appris"
check_output "gw01 : rien d'autre que 10.10.255.0/24 et 10.10.41.0/24 accepté de leaf01" '^0$' \
  jq -r '[.routes // {} | keys[] | select((startswith("10.10.255.") or startswith("10.10.41.")) | not)] | length' <<<"$_m07o_appris"
check_ssh "gw01 : routes de la fabric installées dans le noyau (proto bgp)" gw01 \
  'ip route show proto bgp | grep -q "^10\.10\.255\."'
check_ssh "gw01 : aucune route par défaut ni route de MGMT apprise par BGP" gw01 \
  '! ip route show proto bgp | grep -Eq "^(default|10\.10\.10\.)"'
check_ping "adm01 joint la boucle de spine01 (10.10.255.1)" 10.10.255.1

_m07o_in="$(_m07o_nft_gw01 input)"
_m07o_bgp_cible() {
  local r
  r="$(grep -E 'tcp dport (179|\{[^}]*\b179\b)' <<<"$_m07o_in" || true)"
  [[ -n "$r" ]] && ! grep -v 'ip saddr' <<<"$r" | grep -q .
}
check_cmd "gw01 : port 179 ouvert en entrée à des sources désignées seulement" _m07o_bgp_cible
check_output "gw01 : port 179 ouvert à leaf01 (10.10.99.251)" 'ip saddr 10\.10\.99\.251 tcp dport 179 accept' echo "$_m07o_in"
check_cmd "plateforme/ansible : scénario Molecule frr_bordure sur main" \
  _m07o_fichier_main "$_M07O_PROJET_ANSIBLE" molecule/frr_bordure/molecule.yml
