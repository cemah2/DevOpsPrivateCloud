# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E17.sh — M14-E17 : Drainer, ajouter et retirer un nœud
# À lancer depuis adm01. Lecture seule : nœuds (« kube »), pvesh en root sur pve01, NetBox, GitLab.

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E17 — Drainer, ajouter et retirer un nœud"
require_cmd jq kubectl curl

_m14o_e17_n="$(_m14o_k get nodes -o json)"
check_cmd "k8s-w04 n'est plus un nœud du cluster" _m14o_json "$_m14o_e17_n" '[.items[] | select(.metadata.name == "k8s-w04")] | length == 0'
check_cmd "les six nœuds de référence sont Ready" _m14o_json "$_m14o_e17_n" \
  '[.items[] | select(.metadata.name | test("^k8s-(cp0[1-3]|w0[1-3])$"))
    | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length == 6'
check_cmd "aucun nœud SchedulingDisabled (cordon oublié)" _m14o_json "$_m14o_e17_n" '[.items[] | select(.spec.unschedulable == true)] | length == 0'
_m14o_e17_vm() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null \
    | jq -e '[.[] | select(.vmid == 2147)] | length == 0' >/dev/null 2>&1
}
check_cmd "la VM 2147 (k8s-w04) n'existe plus sur pve01" _m14o_e17_vm
_m14o_e17_nb() {
  netbox_api "virtualization/virtual-machines/?name=k8s-w04" 2>/dev/null \
    | jq -e '[.results[] | select(.status.value == "active")] | length == 0' >/dev/null 2>&1
}
check_cmd "k8s-w04 n'est plus actif dans NetBox" _m14o_e17_nb
check_cmd "cluster/noeuds.yaml (main) ne décrit plus k8s-w04" \
  bash -c '! grep -Eq "^[[:space:]]+k8s-w04:" <<<"$1" && [[ -n "$1" ]]' _ "$(_m14o_contenu_main "$_M14O_P_K8S" cluster/noeuds.yaml)"
_m14o_e17_chg="docs/kubernetes/changements/CHG-1517-ajout-retrait-noeud.md"
check_cmd "plateforme/medisphere : $_m14o_e17_chg sur main" _m14o_fichier_main "$_M14O_P_DOC" "$_m14o_e17_chg"
check_output "la fiche justifie les options de drain" 'ignore-daemonsets' _m14o_contenu_main "$_M14O_P_DOC" "$_m14o_e17_chg"
check_output "la fiche donne le nombre d'ECHEC mesuré" 'ECHEC' _m14o_contenu_main "$_M14O_P_DOC" "$_m14o_e17_chg"
