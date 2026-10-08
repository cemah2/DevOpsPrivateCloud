# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E29.sh — M10-E29 « Ajouter et retirer un nœud de calcul »
# Lecture seule : inventaire Kolla du clone ~/src/openstack, services Nova, Placement (greffon
# osc-placement), agents OVN, GitLab.

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E29 — Ajouter et retirer un nœud de calcul"
require_cmd openstack jq
_m10p_charger

title "Inventaire et Nova"
_m10_inventaire() {
  awk '/^\[compute\]/ {s = 1; next} /^\[/ {s = 0} s && $1 == "oscmp02" {t = 1} END {exit !t}' \
    "$_M10P_SRC/openstack/inventaire/multinode" 2>/dev/null
}
check_cmd "inventaire Kolla (clone ~/src/openstack) : oscmp02 dans [compute]" _m10_inventaire
_m10_compute_ok() {
  jq -e --arg h oscmp02 '[.[] | select(.Binary == "nova-compute" and .Host == $h)]
    | length == 1 and .[0].State == "up" and .[0].Status == "enabled"' >/dev/null <<<"$_M10P_CS"
}
check_cmd "oscmp02 : un seul nova-compute, « up » et activé" _m10_compute_ok
_m10_un_par_hote() {
  jq -e 'type == "array" and ([.[] | select(.Binary == "nova-compute") | .Host] | (length > 0 and length == (unique | length)))' \
    >/dev/null <<<"$_M10P_CS"
}
check_cmd "un seul service de calcul par hôte" _m10_un_par_hote

title "Placement"
_m10_rp() {
  local l uuid inv
  l="$(_m10p_os resource provider list)" || return 1
  jq -e '[.[] | select(.name == "oscmp02")] | length == 1' >/dev/null <<<"$l" || return 1
  uuid="$(jq -r '.[] | select(.name == "oscmp02") | .uuid' <<<"$l")"
  inv="$(_m10p_os resource provider inventory list "$uuid")" || return 1
  jq -e '[.[].resource_class] | contains(["VCPU", "MEMORY_MB"])' >/dev/null <<<"$inv"
}
check_cmd "un seul fournisseur de ressources oscmp02, avec inventaire VCPU et MEMORY_MB" _m10_rp
_m10_pas_orphelin() {
  local l
  l="$(_m10p_os resource provider list)" || return 1
  # Tout fournisseur « racine » nommé comme un hôte doit correspondre à un nova-compute existant.
  jq -e --argjson cs "$_M10P_CS" '
    ([$cs[] | select(.Binary == "nova-compute") | .Host]) as $h
    | all(.[] | select(.name | test("^oscmp")); .name as $n | $h | index($n) != null)' >/dev/null <<<"$l"
}
check_cmd "aucun fournisseur de ressources orphelin (oscmp* sans nova-compute)" _m10_pas_orphelin

title "Réseau"
_m10_ovn_un_par_calcul() {
  jq -e '[.[] | select(.["Agent Type"] == "OVN Controller agent")] as $a
    | ([$a[].Host] | length == (unique | length)) and all($a[]; .Alive == true)
      and ([$a[].Host] | contains(["oscmp01", "oscmp02"]))' >/dev/null <<<"$_M10P_NA"
}
check_cmd "un seul agent « OVN Controller » par calcul, tous vivants" _m10_ovn_un_par_calcul

title "Runbook et ménage"
check_cmd "RB-102 dans docs/cloud/runbooks/ (historique avec coupure mesurée)" \
  _m10p_doc_contient docs/cloud/runbooks RB-102 'historique' 'oscmp02' '[0-9]+([,.][0-9]+)? ?(s|min)([^a-z]|$)'
check_cmd "plus aucune instance evac-essai*" _m10p_aucune_instance evac-essai
