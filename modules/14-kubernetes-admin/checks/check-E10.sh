# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M14-E10 : Espaces de noms, quotas et LimitRanges
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks), API GitLab (fichiers sur main).

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E10 — Espaces de noms, quotas et LimitRanges"
require_cmd jq kubectl curl

declare -A _m14o_e10_req=([mediagenda-dev]="2 4Gi 6 8Gi 20" [mediagenda-recette]="3 6Gi 8 12Gi 30")
for _m14o_e10_ns in mediagenda-dev mediagenda-recette; do
  _m14o_e10_env="${_m14o_e10_ns#mediagenda-}"
  _m14o_e10_n="$(_m14o_k get namespace "$_m14o_e10_ns" -o json)"
  check_cmd "$_m14o_e10_ns existe, étiquettes medisphere.internal/equipe=mediagenda et environnement=$_m14o_e10_env" \
    _m14o_json "$_m14o_e10_n" '.metadata.labels["medisphere.internal/equipe"] == "mediagenda"
      and .metadata.labels["medisphere.internal/environnement"] == $e' --arg e "$_m14o_e10_env"
  read -r _rc _rm _lc _lm _p <<<"${_m14o_e10_req[$_m14o_e10_ns]}"
  _m14o_e10_q="$(_m14o_k get resourcequota quota-equipe -n "$_m14o_e10_ns" -o json)"
  check_cmd "$_m14o_e10_ns : quota-equipe = $_rc CPU / $_rm de requêtes, $_lc CPU / $_lm de limites, $_p pods" \
    _m14o_json "$_m14o_e10_q" '.spec.hard as $h | $h["requests.cpu"] == $rc and $h["requests.memory"] == $rm
      and $h["limits.cpu"] == $lc and $h["limits.memory"] == $lm and $h.pods == $p' \
    --arg rc "$_rc" --arg rm "$_rm" --arg lc "$_lc" --arg lm "$_lm" --arg p "$_p"
  check_cmd "$_m14o_e10_ns : aucun NodePort ni LoadBalancer autorisé par le quota" \
    _m14o_json "$_m14o_e10_q" '.spec.hard["services.nodeports"] == "0" and .spec.hard["services.loadbalancers"] == "0"'
  _m14o_e10_l="$(_m14o_k get limitrange limites-defaut -n "$_m14o_e10_ns" -o json)"
  check_cmd "$_m14o_e10_ns : LimitRange limites-defaut (défauts 100m/128Mi → 500m/512Mi, max 2 CPU / 2Gi par conteneur)" \
    _m14o_json "$_m14o_e10_l" '[.spec.limits[] | select(.type == "Container")][0]
      | .defaultRequest.cpu == "100m" and .defaultRequest.memory == "128Mi"
        and .default.cpu == "500m" and .default.memory == "512Mi"
        and .max.cpu == "2" and .max.memory == "2Gi"'
  check_cmd "$_m14o_e10_ns : LimitRange avec un maximum par pod" \
    _m14o_json "$_m14o_e10_l" '[.spec.limits[] | select(.type == "Pod" and .max.cpu != null and .max.memory != null)] | length == 1'
  for _m14o_e10_f in 00-namespace 10-quota 20-limites; do
    check_cmd "plateforme/k8s : espaces/$_m14o_e10_ns/$_m14o_e10_f.yaml sur main" \
      _m14o_fichier_main "$_M14O_P_K8S" "espaces/$_m14o_e10_ns/$_m14o_e10_f.yaml"
  done
done

_m14o_e10_pods="$(_m14o_k get pods -n mediagenda-dev -o json)"
check_cmd "aucun pod d'essai (essai-*) ne reste dans mediagenda-dev" \
  _m14o_json "$_m14o_e10_pods" '[.items[] | select(.metadata.name | startswith("essai-"))] | length == 0'
check_cmd "aucun Deployment d'essai (essai-quota) ne reste dans mediagenda-dev" \
  _m14o_json "$(_m14o_k get deployments -n mediagenda-dev -o json)" '[.items[] | select(.metadata.name | startswith("essai-"))] | length == 0'
check_output "journal ~/m14/e10/journal.md (quotas, capacité, essais)" '[Qq]uota' cat "$_M14O_TRAVAIL/e10/journal.md"
