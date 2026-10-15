# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes (variables jq, pas du shell)
#
# check-E07.sh — M14-E07 : Pods, Deployments et Services : MédiAgenda sur le cluster
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks) ; GET sur l'API de MédiAgenda à
# travers le mandataire du serveur d'API (services/proxy), API GitLab en GET.

# shellcheck source=_m14-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-decouverte.sh"

title "M14-E07 — Pods, Deployments et Services : MédiAgenda sur le cluster"
require_cmd jq

_m14d_e07_ns=wb-essais
_m14d_e07_dep="$(_m14d_k -n "$_m14d_e07_ns" get deployments -o json)"
_m14d_e07_pods="$(_m14d_k -n "$_m14d_e07_ns" get pods -o json)"

# --- 1. Les trois Deployments -------------------------------------------------------------------------
check_cmd "mediagenda-api : 2 réplicas demandés, 2 prêts et à jour" _m14d_json "$_m14d_e07_dep" \
  '.items[] | select(.metadata.name == "mediagenda-api")
   | .spec.replicas == 2 and .status.readyReplicas == 2 and .status.updatedReplicas == 2'
check_cmd "mediagenda-api : image de Harbor (projet medisphere), étiquette de version ou empreinte, jamais latest" \
  _m14d_json "$_m14d_e07_dep" \
  '.items[] | select(.metadata.name == "mediagenda-api") | [.spec.template.spec.containers[].image]
   | length >= 1 and all(.[]; test("^registry\\.par1\\.medisphere\\.internal/medisphere/mediagenda-api(:v[0-9]+\\.[0-9]+\\.[0-9]+|@sha256:[0-9a-f]{64})$"))'
check_cmd "mediagenda-api : identifiants de tirage harbor-pull (pod ou compte de service default)" bash -c \
  'jq -e ".items[] | select(.metadata.name == \"mediagenda-api\") | [.spec.template.spec.imagePullSecrets[]?.name] | index(\"harbor-pull\")" <<<"$1" >/dev/null \
   || jq -e "[.imagePullSecrets[]?.name] | index(\"harbor-pull\")" <<<"$2" >/dev/null' \
  _ "$_m14d_e07_dep" "$(_m14d_k -n "$_m14d_e07_ns" get serviceaccount default -o json)"
check_cmd "mediagenda-api : conteneur d'initialisation des migrations, terminé sans erreur" _m14d_json "$_m14d_e07_pods" \
  '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "mediagenda-api" and .status.phase == "Running")
    | .status.initContainerStatuses[]? | select(.state.terminated.reason == "Completed")] | length >= 2'
for _m14d_e07_d in postgresql valkey; do
  check_cmd "$_m14d_e07_d : 1 réplica prêt, données en emptyDir (jetables, assumé au M14)" _m14d_json "$_m14d_e07_dep" \
    '.items[] | select(.metadata.name == $d) | .status.readyReplicas == 1
     and ([.spec.template.spec.volumes[]? | select(has("emptyDir"))] | length >= 1)' --arg d "$_m14d_e07_d"
done
check_cmd "postgresql : stratégie Recreate (jamais deux instances sur les mêmes données)" _m14d_json "$_m14d_e07_dep" \
  '.items[] | select(.metadata.name == "postgresql") | .spec.strategy.type == "Recreate"'
check_cmd "Pods étiquetés app.kubernetes.io/name et app.kubernetes.io/part-of=mediagenda" _m14d_json "$_m14d_e07_pods" \
  '[.items[] | select(.metadata.labels["app.kubernetes.io/part-of"] == "mediagenda")] | length >= 4'
check_cmd "Les deux pods de l'API tournent sur des travailleurs" _m14d_json "$_m14d_e07_pods" \
  '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "mediagenda-api" and .status.phase == "Running")
    | .spec.nodeName | test("^k8s-w")] | length == 2 and all'

# --- 2. Les Services -------------------------------------------------------------------------------------
_m14d_e07_svc="$(_m14d_k -n "$_m14d_e07_ns" get services -o json)"
check_cmd "Service mediagenda-api : ClusterIP, port 80 vers le port nommé http (8000)" _m14d_json "$_m14d_e07_svc" \
  '.items[] | select(.metadata.name == "mediagenda-api") | .spec.type == "ClusterIP"
   and (.spec.clusterIP | test("^10\\.96\\.")) and .spec.ports[0].port == 80
   and (.spec.ports[0].targetPort == "http" or .spec.ports[0].targetPort == 8000)'
for _m14d_e07_s in postgresql:5432 valkey:6379; do
  check_cmd "Service ${_m14d_e07_s%%:*} : ClusterIP, port ${_m14d_e07_s##*:}" _m14d_json "$_m14d_e07_svc" \
    '.items[] | select(.metadata.name == $s) | .spec.type == "ClusterIP" and .spec.ports[0].port == ($p | tonumber)' \
    --arg s "${_m14d_e07_s%%:*}" --arg p "${_m14d_e07_s##*:}"
done
check_cmd "Service mediagenda-api : deux points de terminaison prêts (EndpointSlice)" _m14d_json \
  "$(_m14d_k -n "$_m14d_e07_ns" get endpointslices -l kubernetes.io/service-name=mediagenda-api -o json)" \
  '[.items[].endpoints[]? | select(.conditions.ready == true)] | length == 2'

# --- 3. L'application répond ---------------------------------------------------------------------------
check_cmd "GET /sante à travers le Service : statut ok" _m14d_json \
  "$(_m14d_proxy_get "$_m14d_e07_ns" mediagenda-api:http /sante)" '.statut == "ok"'
check_cmd "GET /api/v1/rendez-vous : au moins un rendez-vous créé (donc base migrée et joignable)" _m14d_json \
  "$(_m14d_proxy_get "$_m14d_e07_ns" mediagenda-api:http '/api/v1/rendez-vous?limite=5')" 'type == "array" and length >= 1'

# --- 4. Le code ------------------------------------------------------------------------------------------
for _m14d_e07_f in k8s/essais/mediagenda-api.yaml k8s/essais/postgresql.yaml k8s/essais/valkey.yaml; do
  check_cmd "mediagenda/api (main) : $_m14d_e07_f" _m14d_fichier_main mediagenda/api "$_m14d_e07_f"
done
