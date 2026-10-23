# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # programmes awk et filtres jq entre apostrophes
# check-E21.sh — M29-E21 « Panne : Terratest laisse des VMs derrière lui » : aucune VM 2290-2299, aucun
# état Terratest orphelin sur adm01, test de vm-debian qui diffère sa destruction et fixe un délai,
# nettoyeur versionné et planifié, RB-298, panne close. Lecture seule (pvesh en lecture sur pve01).

# shellcheck source=_m29-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-expert.sh"

title "M29-E21 — Plus de ressources de test orphelines"
require_cmd jq curl ssh

_m29_e21_tofu="${WB_M29_PROJET_TOFU_MODULES:-plateforme/tofu-modules}"
_m29_e21_vms="$(remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" </dev/null 2>/dev/null)" || _m29_e21_vms=""
if [[ -z "$_m29_e21_vms" ]]; then
  skip "VMs de Terratest" "pvesh illisible sur $WB_PVE_HOST"
else
  check_cmd "pve01 : aucune VM dans la plage Terratest 2290-2299" \
    bash -c '[[ "$(jq "[.[] | select(.vmid >= 2290 and .vmid <= 2299)] | length" <<<"$1")" == 0 ]]' _ "$_m29_e21_vms"
  check_cmd "pve01 : aucune VM étiquetée terratest ni nommée tt-* ailleurs" \
    bash -c '[[ "$(jq "[.[] | select(((.tags // \"\") | test(\"terratest\")) or ((.name // \"\") | test(\"^tt-\")))] | length" <<<"$1")" == 0 ]]' _ "$_m29_e21_vms"
fi
_m29_e21_orphelins() {
  [[ -z "$(find "${WB_M29_TERRATEST_TMP:-/tmp}" -maxdepth 6 -name terraform.tfstate -path '*vm-debian*' 2>/dev/null | head -n 1)" ]]
}
check_cmd "adm01 : aucun état Terratest orphelin (terraform.tfstate sous ${WB_M29_TERRATEST_TMP:-/tmp})" _m29_e21_orphelins

# Le test : defer … Destroy enregistré AVANT InitAndApply, et un délai explicite (go test -timeout).
_m29_e21_defer() {
  local f c
  while IFS= read -r f; do
    [[ "$f" == vm-debian/test/*.go ]] || continue
    c="$(_m29p_fichier_main "$_m29_e21_tofu" "$f" 2>/dev/null)" || continue
    awk '/defer[[:space:]]+terraform\.Destroy/ && !a { d = NR } /terraform\.(InitAndApply|Apply)\(/ && !a { a = NR }
         END { exit !(d > 0 && a > 0 && d < a) }' <<<"$c" && return 0
  done < <(_m29p_arbre "$_m29_e21_tofu" vm-debian/test)
  return 1
}
check_cmd "vm-debian/test : « defer terraform.Destroy » posé avant « InitAndApply »" _m29_e21_defer
check_cmd "plateforme/tofu-modules : go test lancé avec un délai explicite (-timeout)" \
  _m29p_fichier_contient "$_m29_e21_tofu" .gitlab-ci.yml 'go test[^#]*-timeout'
check_cmd "outils/nettoyer-terratest.sh : sélection par étiquette et plage, simulation par défaut" \
  _m29p_fichier_contient "$_m29_e21_tofu" outils/nettoyer-terratest.sh 'terratest' '2290' 'simulation|--appliquer'
check_cmd "plateforme/tofu-modules : un pipeline planifié a tourné et réussi" _m29p_pipeline_ok "$_m29_e21_tofu" schedule
check_cmd "RB-298 publié (main) : ressources de test orphelines" _m29p_doc docs/qualite '^RB-298' 'terratest' '2290'
check_cmd "panne M29-E21 close (lab/bin/break 29 21 --annuler après réparation)" _m29x_aucune_panne_active E21
