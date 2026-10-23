# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E23.sh — M28-E23 « Un locataire sature le cluster » : plus de charge hors cadre dans medidoc-dev
# (pods sans requests, priorité critique), plus de conteneur tué récemment, garde-fous du locataire et
# des espaces (LimitRange partout, budget global, pas de medisphere-critique), post-mortem INC-5523,
# RB-289 ; panne close. Lecture seule.

# shellcheck source=_m28-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-expert.sh"

title "M28-E23 — Le locataire MédiDoc est de nouveau dans son cadre"
require_cmd kubectl jq curl

_m28_e23_cadre() {
  kube -n medidoc-dev get pods -o json 2>/dev/null | jq -e '
    [.items[] | select(.status.phase == "Running" or .status.phase == "Pending")
     | select((.spec.priorityClassName // "") == "medisphere-critique"
              or any(.spec.containers[]; (.resources.requests // {}) | length == 0))] | length == 0' >/dev/null 2>&1
}
_m28_e23_limitrange_partout() {
  local ns n
  ns="$(kube get namespaces -l capsule.clastix.io/tenant=medidoc -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)" || return 1
  [[ -n "$ns" ]] || return 1
  for n in $ns; do
    kube -n "$n" get limitranges -o json 2>/dev/null | jq -e '.items | length >= 1' >/dev/null 2>&1 || return 1
  done
}
_m28_e23_noeuds() {
  kube get nodes -o json 2>/dev/null |
    jq -e 'all(.items[]; all(.status.conditions[]; .type != "MemoryPressure" or .status != "True"))' >/dev/null 2>&1
}

if _m28p_api_repond; then
  check_cmd "medidoc-dev : aucun pod en medisphere-critique ni sans requests" _m28_e23_cadre
  check_cmd "medidoc-dev : aucun conteneur OOMKilled depuis 15 min" _m28x_aucun_oom medidoc-dev "" 15
  check_cmd "aucun nœud en pression mémoire" _m28_e23_noeuds
  check_cmd "locataire medidoc : medisphere-critique non autorisée" _m28p_tenant medidoc \
    '(.spec.priorityClasses.allowed // []) | index("medisphere-critique") == null'
  check_cmd "locataire medidoc : budget global en place" _m28p_tenant medidoc \
    '[.spec.rules[]? | select((.quota // []) | length > 0) | select((.namespaceSelector // null) == null)] | length >= 1'
  check_cmd "chaque espace du locataire medidoc a un LimitRange" _m28_e23_limitrange_partout
else
  skip "charge, nœuds, locataire" "l'API ne répond pas au compte des checks"
fi
check_cmd "post-mortem INC-5523 publié (main)" _m28p_doc_k8s INC-5523 'chronologie' 'cause' 'action'
check_cmd "RB-289 publié (main)" _m28p_doc RB-289 'endigu' 'LimitRange' 'priorit'
check_cmd "panne M28-E23 close (lab/bin/break 28 23 --annuler après réparation)" _m28x_aucune_panne_active E23
