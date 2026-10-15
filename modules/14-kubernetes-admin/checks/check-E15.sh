# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E15.sh — M14-E15 : StatefulSets, DaemonSets, Jobs et CronJobs
# À lancer depuis adm01. Lecture seule (« kube »).

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E15 — StatefulSets, DaemonSets, Jobs et CronJobs"
require_cmd jq kubectl

_m14o_e15_ns=mediagenda-dev
_m14o_e15_sts="$(_m14o_k get statefulset valkey -n "$_m14o_e15_ns" -o json)"
check_cmd "valkey est un StatefulSet de 3 pods prêts" _m14o_json "$_m14o_e15_sts" '.spec.replicas == 3 and .status.readyReplicas == 3'
check_cmd "valkey : derrière un Service headless (clusterIP: None) nommé dans serviceName" \
  _m14o_json "$(_m14o_k get service -n "$_m14o_e15_ns" -o json)" \
  'any(.items[]; .metadata.name == $s and .spec.clusterIP == "None")' --arg s "$(jq -r '.spec.serviceName // "?"' <<<"${_m14o_e15_sts:-{\}}" 2>/dev/null || echo '?')"
check_cmd "plus de Deployment valkey (remplacé par le StatefulSet)" \
  _m14o_json "$(_m14o_k get deployments -n "$_m14o_e15_ns" -o json)" '[.items[] | select(.metadata.name == "valkey")] | length == 0'
check_cmd "valkey-1 et valkey-2 sont configurés en répliques de valkey-0" _m14o_json "$_m14o_e15_sts" \
  '[.spec.template.spec.containers[] | ((.command // []) + (.args // [])) | join(" ")] | join(" ") | test("replicaof")'
check_cmd "l'API utilise le primaire (valkey-0) dans sa configuration" \
  _m14o_json "$(_m14o_k get configmap mediagenda-api-config -n "$_m14o_e15_ns" -o json)" '.data.MEDIAGENDA_VALKEY_URL | test("valkey-0\\.")'

_m14o_e15_jobs="$(_m14o_k get jobs -n "$_m14o_e15_ns" -o json)"
check_cmd "un Job mediagenda-migration-* a réussi" _m14o_json "$_m14o_e15_jobs" \
  'any(.items[]; (.metadata.name | startswith("mediagenda-migration-")) and (.status.succeeded // 0) >= 1)'
check_cmd "le Job de migration est gardé au moins un jour (ttlSecondsAfterFinished absent ou ≥ 86400)" _m14o_json "$_m14o_e15_jobs" \
  '[.items[] | select(.metadata.name | startswith("mediagenda-migration-"))] | length >= 1 and all((.spec.ttlSecondsAfterFinished // 86400) >= 86400)'
check_cmd "l'API n'a plus d'initContainer de migration" \
  _m14o_json "$(_m14o_k get deployment mediagenda-api -n "$_m14o_e15_ns" -o json)" '(.spec.template.spec.initContainers // []) | length == 0'

_m14o_e15_cj="$(_m14o_k get cronjob mediagenda-sauvegarde -n "$_m14o_e15_ns" -o json)"
check_cmd "CronJob mediagenda-sauvegarde : 2 h 15 heure de Paris" _m14o_json "$_m14o_e15_cj" \
  '(.spec.schedule | gsub("\\s+"; " ")) == "15 2 * * *" and .spec.timeZone == "Europe/Paris"'
check_cmd "CronJob : concurrencyPolicy Forbid et startingDeadlineSeconds défini" _m14o_json "$_m14o_e15_cj" \
  '.spec.concurrencyPolicy == "Forbid" and (.spec.startingDeadlineSeconds // 0) > 0'
check_cmd "au moins une exécution réussie du CronJob (planifiée ou manuelle)" _m14o_json "$_m14o_e15_jobs" \
  'any(.items[]; any(.metadata.ownerReferences[]?; .kind == "CronJob" and .name == "mediagenda-sauvegarde") and (.status.succeeded // 0) >= 1)'

_m14o_e15_ds="$(_m14o_k get daemonset sonde-noeud -n wb-essais -o json)"
_m14o_e15_nb="$(_m14o_k get nodes -o json | jq '.items | length' 2>/dev/null || echo 0)"
check_cmd "DaemonSet sonde-noeud : un pod prêt sur chacun des nœuds ($_m14o_e15_nb)" _m14o_json "$_m14o_e15_ds" \
  '.status.desiredNumberScheduled == $n and .status.numberReady == $n and $n >= 6' --argjson n "${_m14o_e15_nb:-0}"
