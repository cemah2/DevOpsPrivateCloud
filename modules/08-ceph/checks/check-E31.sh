# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E31.sh — M08-E31 « Cloisonner le stockage par équipe »
# Lecture seule : pools, quotas, espaces de noms RBD, groupes de sous-volumes CephFS, capacités cephx
# (sans les clés), essais de LISTAGE (rbd ls) avec les identités des équipes depuis cephcli01, registre
# des allocations (API GitLab). Aucun essai d'écriture : les refus d'écriture sont à prouver par toi
# (matrice de l'indice 3).

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E31 — Cloisonner le stockage par équipe"
require_cmd jq curl
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

_m08_e31_equipes=(mediagenda medidoc)

title "Bloc : pool rbd-equipes"
check_cmd "le pool rbd-equipes existe, application rbd" _m08p_pool_app rbd-equipes rbd
check_cmd "rbd-equipes : règle de la classe ssd" _m08p_pool_classe rbd-equipes ssd
check_cmd "rbd-equipes : un quota en octets est posé" _m08p_pool_quota_min rbd-equipes 1
_m08_e31_ns="$(_m08p_rbd 'namespace ls rbd-equipes --format json' 2>/dev/null || echo null)"
for _m08_e31_e in "${_m08_e31_equipes[@]}"; do
  check_cmd "espace de noms rbd-equipes/$_m08_e31_e" bash -c \
    'jq -e --arg n "$2" "any(.[]?; (.name // .) == \$n)" >/dev/null <<<"$1"' _ "$_m08_e31_ns" "$_m08_e31_e"
done

title "Fichier : groupes de sous-volumes"
for _m08_e31_e in "${_m08_e31_equipes[@]}"; do
  check_cmd "cephfs : groupe $_m08_e31_e avec un plafond (bytes_quota)" bash -c \
    'jq -e "(.bytes_quota | type) == \"number\" and .bytes_quota > 0" >/dev/null <<<"$1"' _ \
    "$(_m08p_json "fs subvolumegroup info cephfs $_m08_e31_e")"
done

title "Identités des équipes"
for _m08_e31_e in "${_m08_e31_equipes[@]}"; do
  _m08_e31_c="client.$_m08_e31_e"
  check_cmd "$_m08_e31_c existe" _m08p_entite_existe "$_m08_e31_c"
  check_cmd "$_m08_e31_c : aucune capacité « allow * » / « allow rwx »" _m08p_sans_allow_tout "$_m08_e31_c"
  check_cmd "$_m08_e31_c : OSD limités à l'espace de noms $_m08_e31_e de rbd-equipes" \
    _m08p_caps "$_m08_e31_c" osd "pool=rbd-equipes namespace=$_m08_e31_e"
  check_cmd "$_m08_e31_c : aucun droit sur rbd-test" _m08p_jq _M08P_AUTH \
    "all(.[] | select(.entity == \"$_m08_e31_c\") | .caps | to_entries[]; (.value | test(\"rbd-test\") | not))"
  check_cmd "$_m08_e31_c : MDS limités au chemin du groupe (/volumes/$_m08_e31_e)" \
    _m08p_caps "$_m08_e31_c" mds "path=/volumes/$_m08_e31_e"
done

title "Isolement, depuis cephcli01 (listage avec chaque identité)"
for _m08_e31_e in "${_m08_e31_equipes[@]}"; do
  _m08_e31_autre=medidoc
  [[ "$_m08_e31_e" == medidoc ]] && _m08_e31_autre=mediagenda
  check_cmd "$_m08_e31_e liste son espace de noms" _m08p_identite_ok cephcli01 "$_m08_e31_e" "rbd-equipes/$_m08_e31_e"
  check_cmd "$_m08_e31_e ne peut pas lister rbd-equipes/$_m08_e31_autre" \
    _m08p_identite_refus cephcli01 "$_m08_e31_e" "rbd-equipes/$_m08_e31_autre"
  check_cmd "$_m08_e31_e ne peut pas lister l'espace par défaut de rbd-equipes" \
    _m08p_identite_refus cephcli01 "$_m08_e31_e" rbd-equipes
  check_cmd "$_m08_e31_e ne peut pas lister rbd-test" _m08p_identite_refus cephcli01 "$_m08_e31_e" rbd-test
done

title "Code et registre"
check_cmd "docs/stockage/allocations.md sur main : les deux équipes" \
  _m08p_doc_main docs/stockage/allocations.md mediagenda medidoc
check_cmd "plateforme/ceph : rbd-equipes décrit dans le code de main" _m08p_recherche_main plateforme/ceph rbd-equipes
check_cmd "plateforme/ceph : dernier pipeline de main réussi" _m08p_pipeline_ok plateforme/ceph
