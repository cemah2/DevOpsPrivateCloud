# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E05.sh — M26-E05 : kube-bench et kubescape : évaluer k8s-par1
# À lancer depuis adm01. Lecture seule : fichiers de plateforme/medisphere par l'API de GitLab (rapports
# kube-bench en JSON, résumé kubescape, analyse), pods de wb-diagnostic par le compte des checks.

# shellcheck source=_m26-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-decouverte.sh"

title "M26-E05 — kube-bench et kubescape : évaluer k8s-par1"
require_cmd jq curl kubectl

_m26d_e05_mesures="$_M26D_DOC/mesures/k8s-par1"

# --- 1. Les rapports de kube-bench ---------------------------------------------------------------------
# _m26d_e05_kb NŒUD TYPES — rapport JSON de kube-bench du nœud : JSON complet (Controls + Totals),
# produit avec le référentiel cis-1.12 pour TOUS les groupes, et contenant les types de contrôles attendus.
_m26d_e05_kb() {
  local json
  json="$(_m26d_contenu_main "$_M26D_DEPOT_DOC" "$_m26d_e05_mesures/kube-bench-$1.json")"
  _m26d_json "$json" '(.Totals.total_pass | type == "number") and (.Controls | length > 0)
    and ([.Controls[].version] | all(. == "cis-1.12"))
    and ([.Controls[].node_type] as $t | $types | split(",") | all(. as $x | $t | index($x)))' \
    --arg types "$2"
}
check_cmd "mesures/k8s-par1/kube-bench-k8s-cp01.json : kube-bench, référentiel cis-1.12, cibles master et etcd" \
  _m26d_e05_kb k8s-cp01 "master,etcd"
check_cmd "mesures/k8s-par1/kube-bench-k8s-w01.json : kube-bench, référentiel cis-1.12, cible node" \
  _m26d_e05_kb k8s-w01 "node"

# --- 2. Le résumé de kubescape ---------------------------------------------------------------------------
_m26d_e05_ks="$(_m26d_contenu_main "$_M26D_DEPOT_DOC" "$_m26d_e05_mesures/kubescape-resume.json")"
check_cmd "mesures/k8s-par1/kubescape-resume.json : JSON valide" _m26d_json "$_m26d_e05_ks" 'type == "object" or type == "array"'
check_cmd "kubescape-resume.json : scores des cadres NSA et MITRE" \
  bash -c 'grep -qi "nsa" <<<"$1" && grep -qi "mitre" <<<"$1"' _ "$_m26d_e05_ks"

# --- 3. L'analyse ---------------------------------------------------------------------------------------
_m26d_e05_doc="$(_m26d_doc mesure-k8s-par1.md)"
if [[ -z "$_m26d_e05_doc" ]]; then
  _ko "plateforme/medisphere : $_M26D_DOC/mesure-k8s-par1.md absent de main"
else
  check_cmd "mesure-k8s-par1.md : référentiel cis-1.12 cité, et l'écart de version (1.36) expliqué" \
    bash -c 'grep -q "cis-1\.12" <<<"$1" && grep -q "1\.36" <<<"$1"' _ "$_m26d_e05_doc"
  # Un tableau de classement : au moins cinq lignes qui commencent par un identifiant CIS (1.2.15, 4.2.14…).
  check_cmd "mesure-k8s-par1.md : FAIL de kube-bench classés (au moins cinq identifiants CIS dans un tableau)" \
    bash -c '[ "$(grep -cE "^\| *[1-5]\.[0-9]+(\.[0-9]+)?" <<<"$1")" -ge 5 ]' _ "$_m26d_e05_doc"
fi

# --- 4. Rien ne reste dans wb-diagnostic --------------------------------------------------------------
_m26d_e05_pods="$(_m26d_k -n wb-diagnostic get pods -o json)"
if [[ -z "$_m26d_e05_pods" ]]; then
  skip "Pods de wb-diagnostic" "liste illisible par le compte des checks"
else
  check_cmd "wb-diagnostic : plus aucun pod kube-bench (Jobs nettoyés une heure après leur fin)" \
    _m26d_json "$_m26d_e05_pods" '[.items[].metadata.name | select(startswith("kube-bench"))] | length == 0'
fi
