# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les expressions entre apostrophes sont évaluées par bash -c
#
# check-E02.sh — M07-E02 : Cartographier le réseau du lab de bout en bout
# À lancer depuis adm01. Lecture seule : lit docs/socle/reseau/cartographie.md sur la branche main
# de plateforme/medisphere (API GitLab, jeton en lecture des checks).

# shellcheck source=_m07-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-decouverte.sh"

title "M07-E02 — Cartographier le réseau du lab de bout en bout"
require_cmd jq curl

_m07d_e02_doc="$(_m07d_projet_brut plateforme/medisphere docs/socle/reseau/cartographie.md)"

check_cmd "plateforme/medisphere (main) : docs/socle/reseau/cartographie.md publié" \
  test -n "$_m07d_e02_doc"

# --- 1. Couche 2 : les 13 VLAN et leur VNet ---------------------------------------------------
_m07d_e02_vlans() {
  local doc="$1" e vnet vlan manquants=0
  for e in vmgmt:10 vinfra:20 vstopub:30 vstoclu:31 vcoro:32 vk8s:40 vk8slb:41 vosapi:50 \
    vostun:51 vosext:52 vprov:60 vdmz:70 vsandbox:99; do
    vnet="${e%%:*}"; vlan="${e##*:}"
    # Le VNet et son numéro de VLAN sur la même ligne (tableau ou liste).
    grep -Eiq "\b$vnet\b.*\b$vlan\b|\b$vlan\b.*\b$vnet\b" <<<"$doc" || manquants=$((manquants + 1))
  done
  ((manquants == 0))
}
check_cmd "Les 13 VLAN de PAR1 avec leur VNet (même ligne : nom du VNet et numéro)" _m07d_e02_vlans "$_m07d_e02_doc"
check_output "Les deux ponts de pve01 (vmbr0, vmbr1)" 'vmbr0' printf '%s' "$_m07d_e02_doc"
check_output "Le pont du lab est décrit (vmbr1, VLAN-aware)" 'vmbr1' printf '%s' "$_m07d_e02_doc"

# --- 2. Couche 3 : gw01 et ses tunnels ----------------------------------------------------------
check_output "gw01 : le trunk ens19 et ses sous-interfaces (ens19.<VLAN>)" 'ens19\.[0-9]+' printf '%s' "$_m07d_e02_doc"
check_output "gw01 : l'interface WAN ens18" 'ens18' printf '%s' "$_m07d_e02_doc"
check_cmd "Les tunnels wg0 (PAR2) et wg1 (VPN d'administration)" \
  bash -c 'grep -q "wg0" <<<"$1" && grep -q "wg1" <<<"$1"' _ "$_m07d_e02_doc"

# --- 3. Trajets, MTU, points uniques de défaillance --------------------------------------------
check_cmd "Les trois trajets (git01:443, runner01 vers Internet, pbs01:8007)" \
  bash -c 'grep -q "git01" <<<"$1" && grep -q "runner01" <<<"$1" && grep -q "8007" <<<"$1"' _ "$_m07d_e02_doc"
check_cmd "Un tableau des MTU (mot « MTU » et des valeurs relevées)" \
  bash -c 'grep -q "MTU" <<<"$1" && grep -Eq "\b1500\b" <<<"$1"' _ "$_m07d_e02_doc"

# Section « point(s) unique(s) de défaillance » : au moins 5 entrées (liste ou lignes de tableau).
_m07d_e02_spof() {
  awk '
    /^#+ / { dedans = (tolower($0) ~ /point[s]? unique[s]? de d..?faillance|spof/); entete = 0; next }
    dedans && /^[[:space:]]*\|[-:| ]+\|[[:space:]]*$/ { next }     # séparateur de tableau
    dedans && /^[[:space:]]*\|/ { if (entete++ == 0) next }        # 1re ligne de tableau = en-tête
    dedans && /^[[:space:]]*([-*]|[0-9]+[.)]|\|)/ { n++ }
    END { print n + 0 }
  ' <<<"$1"
}
_m07d_e02_n="$(_m07d_e02_spof "$_m07d_e02_doc")"
check_cmd "Section « points uniques de défaillance » : au moins cinq entrées (trouvé : ${_m07d_e02_n})" \
  test "$_m07d_e02_n" -ge 5

# --- 4. Des commandes pour revérifier ------------------------------------------------------------
_m07d_e02_cmds() {
  local n=0 c
  for c in 'bridge (vlan|link|fdb)' 'ip (-[a-z]+ )*route' 'wg show' 'nft list' 'pvesh get' 'ip (-[a-z]+ )*(addr|link)' 'tcpdump'; do
    grep -Eq "$c" <<<"$1" && n=$((n + 1))
  done
  ((n >= 4))
}
check_cmd "Au moins quatre familles de commandes de vérification (bridge, ip route, wg show, nft, pvesh…)" \
  _m07d_e02_cmds "$_m07d_e02_doc"
