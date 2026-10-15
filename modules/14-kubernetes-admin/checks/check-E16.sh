# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E16.sh — M14-E16 : Mises à jour progressives, retour arrière et PDB
# À lancer depuis adm01. Lecture seule (« kube »).

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E16 — Mises à jour progressives, retour arrière et PDB"
require_cmd jq kubectl

_m14o_e16_ns=mediagenda-dev
_m14o_e16_d="$(_m14o_k get deployment mediagenda-api -n "$_m14o_e16_ns" -o json)"
check_cmd "stratégie : maxUnavailable 0 et maxSurge ≥ 1" _m14o_json "$_m14o_e16_d" \
  '.spec.strategy.type == "RollingUpdate" and ((.spec.strategy.rollingUpdate.maxUnavailable | tostring) == "0" or (.spec.strategy.rollingUpdate.maxUnavailable | tostring) == "0%")
   and ((.spec.strategy.rollingUpdate.maxSurge | tostring) | test("^[1-9]"))'
check_cmd "minReadySeconds > 0 et progressDeadlineSeconds ≤ 300" _m14o_json "$_m14o_e16_d" \
  '(.spec.minReadySeconds // 0) > 0 and (.spec.progressDeadlineSeconds // 600) <= 300'
check_cmd "Deployment entièrement à jour et disponible" _m14o_json "$_m14o_e16_d" \
  '.status.observedGeneration == .metadata.generation and .status.updatedReplicas == .spec.replicas
   and .status.availableReplicas == .spec.replicas and (.status.unavailableReplicas // 0) == 0
   and any(.status.conditions[]; .type == "Progressing" and .status == "True")'
check_cmd "révision courante sur une image v* de Harbor (pas d'essai v9.9.9 resté en place)" _m14o_json "$_m14o_e16_d" \
  '[.spec.template.spec.containers[].image] | any(test("^registry\\.par1\\.medisphere\\.internal/medisphere/mediagenda-api:v[0-9]") and (test("v9\\.9\\.9") | not))'
check_cmd "historique : au moins trois révisions" _m14o_json "$_m14o_e16_d" \
  '(.metadata.annotations["deployment.kubernetes.io/revision"] // "0" | tonumber) >= 3'
_m14o_e16_rs="$(_m14o_k get replicasets -n "$_m14o_e16_ns" -l app.kubernetes.io/name=mediagenda-api -o json)"
check_cmd "anciens ReplicaSets conservés (au moins deux)" _m14o_json "$_m14o_e16_rs" '.items | length >= 2'

_m14o_e16_pdb="$(_m14o_k get pdb mediagenda-api -n "$_m14o_e16_ns" -o json)"
check_cmd "PDB mediagenda-api : maxUnavailable 1 (ou minAvailable laissant une perturbation)" _m14o_json "$_m14o_e16_pdb" \
  '(.spec.maxUnavailable | tostring) == "1" or (.status.disruptionsAllowed // 0) >= 1'
check_cmd "PDB : sélectionne les 3 pods de l'API et autorise une perturbation" _m14o_json "$_m14o_e16_pdb" \
  '.status.expectedPods >= 3 and .status.disruptionsAllowed >= 1'
check_cmd "PDB : les pods malades restent évinçables (unhealthyPodEvictionPolicy: AlwaysAllow)" _m14o_json "$_m14o_e16_pdb" \
  '.spec.unhealthyPodEvictionPolicy == "AlwaysAllow"'
check_output "journal ~/m14/e16/journal.md (comptes d'ECHEC, mises à jour cassées)" 'ECHEC|[Pp]rogress' cat "$_M14O_TRAVAIL/e16/journal.md"
