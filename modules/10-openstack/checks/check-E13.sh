# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E13.sh — M10-E13 : Projets et quotas pour les équipes
# À lancer depuis adm01. Lecture seule : API OpenStack (dont Placement : greffon osc-placement).

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E13 — Projets et quotas pour les équipes"
require_cmd openstack jq

_m10o_ram() { # _m10o_ram PROJET — quota de mémoire (Mio) du projet, vide si illisible
  local id
  id="$(_m10o_projet_id "$1")"
  [[ -n "$id" ]] || return 0
  _m10o_os quota show -f json "$id" | jq -r 'map(select(.Resource == "ram")) | first | .Limit // empty' 2>/dev/null || true
}
_m10o_r_dev="$(_m10o_ram mediagenda-dev)"
_m10o_r_prod="$(_m10o_ram mediagenda-prod)"
_m10o_r_plat="$(_m10o_ram plateforme)"
for _m10o_p in "mediagenda-dev:$_m10o_r_dev" "mediagenda-prod:$_m10o_r_prod" "plateforme:$_m10o_r_plat"; do
  check_output "${_m10o_p%%:*} : quota de mémoire posé (${_m10o_p#*:} Mio), différent du défaut (51200) et non illimité" \
    '^[1-9][0-9]*$' bash -c '[[ "$1" != 51200 ]] && echo "$1"' _ "${_m10o_p#*:}"
done
check_cmd "mediagenda-prod a au moins autant de mémoire que mediagenda-dev" \
  bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ && "$1" -ge "$2" ]]' _ "$_m10o_r_prod" "$_m10o_r_dev"

_m10o_capacite() { # mémoire utilisable des calculs = somme de (total - reserved) * ratio
  local h u inv total=0 n=0
  for h in $_M10O_CALCULS; do
    u="$(_m10o_rp_uuid "$h")"
    [[ -n "$u" ]] || continue
    inv="$(_m10o_os resource provider inventory show -f json "$u" MEMORY_MB || true)"
    total=$(( total + $(jq -r '((.total - .reserved) * .allocation_ratio) | floor' <<<"$inv" 2>/dev/null || echo 0) ))
    n=$((n + 1))
  done
  [[ "$n" -eq 2 ]] && echo "$total"
}
_m10o_cap="$(_m10o_capacite || true)"
if [[ -n "$_m10o_cap" ]]; then
  check_cmd "somme des quotas de mémoire ($(( ${_m10o_r_dev:-0} + ${_m10o_r_prod:-0} + ${_m10o_r_plat:-0} )) Mio) ≤ mémoire utilisable des calculs ($_m10o_cap Mio)" \
    bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ && "$3" =~ ^[0-9]+$ ]] && (( $1 + $2 + $3 <= $4 ))' _ \
    "$_m10o_r_dev" "$_m10o_r_prod" "$_m10o_r_plat" "$_m10o_cap"
else
  _ko "Placement : inventaires MEMORY_MB des deux calculs illisibles (greffon osc-placement installé ?)"
fi

_m10o_gab="$(_m10o_os flavor show -f json m1.prod-db || true)"
_m10o_prod_id="$(_m10o_projet_id mediagenda-prod)"
check_cmd "m1.prod-db : privé" jq -e '.["os-flavor-access:is_public"] == false' <<<"$_m10o_gab"
check_cmd "m1.prod-db : accessible au seul projet mediagenda-prod" \
  jq -e --arg p "$_m10o_prod_id" '$p != "" and ((.access_project_ids // []) == [$p])' <<<"$_m10o_gab"

for _m10o_p in mediagenda-dev mediagenda-prod; do
  check_output "$_m10o_p : aucune attribution du rôle admin" '^0$' \
    bash -c 'openstack --os-cloud "$1" role assignment list --role admin --project "$2" --project-domain medisphere -f json 2>/dev/null | jq length' _ "$_M10O_CLOUD" "$_m10o_p"
done
check_cmd "l'utilisateur d'essai essai-admin n'existe plus" \
  bash -c '! openstack --os-cloud "$1" user show --domain medisphere essai-admin >/dev/null 2>&1 && openstack --os-cloud "$1" token issue >/dev/null 2>&1' _ "$_M10O_CLOUD"
