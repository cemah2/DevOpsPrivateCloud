# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes (variables jq, pas du shell)
#
# check-E08.sh — M14-E08 : ConfigMaps, Secrets, sondes et ressources
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks, qui ne lit PAS les Secrets : on
# vérifie comment ils sont consommés, pas leur contenu) ; GET /pret à travers le mandataire de l'API.

# shellcheck source=_m14-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-decouverte.sh"

title "M14-E08 — ConfigMaps, Secrets, sondes et ressources"
require_cmd jq

_m14d_e08_ns=wb-essais
_m14d_e08_dep="$(_m14d_k -n "$_m14d_e08_ns" get deployments -o json)"
_m14d_e08_api="$(jq -c '.items[] | select(.metadata.name == "mediagenda-api") | .spec.template.spec' <<<"${_m14d_e08_dep:-{\}}" 2>/dev/null || true)"
_m14d_e08_c="$(jq -c '.containers[] | select(.ports[]?.containerPort == 8000)' <<<"${_m14d_e08_api:-{\}}" 2>/dev/null || true)"
_m14d_e08_cm="$(_m14d_k -n "$_m14d_e08_ns" get configmap mediagenda-api-config -o json)"

# --- 1. Configuration et secrets -----------------------------------------------------------------------
check_cmd "ConfigMap mediagenda-api-config : niveau de journal, fuseau, délai d'arrêt, URL de Valkey" _m14d_json "$_m14d_e08_cm" \
  '.data | has("MEDIAGENDA_LOG_LEVEL") and has("MEDIAGENDA_FUSEAU") and has("MEDIAGENDA_DELAI_ARRET") and has("MEDIAGENDA_VALKEY_URL")'
check_cmd "Le ConfigMap ne contient aucun mot de passe (ni URL de base avec identifiants)" _m14d_json "$_m14d_e08_cm" \
  '[.data | to_entries[] | select((.key | test("MDP|PASSWORD|SECRET|DB_URL"; "i")) or (.value | test("://[^/@]+:[^/@]+@")))] | length == 0'
check_cmd "API : configuration chargée depuis le ConfigMap (envFrom)" _m14d_json "$_m14d_e08_c" \
  '[.envFrom[]?.configMapRef.name] | index("mediagenda-api-config") != null'
check_cmd "API : mot de passe de la base lu dans un Secret (secretKeyRef), jamais écrit en clair" _m14d_json "$_m14d_e08_c" \
  '([.env[]? | select(.valueFrom.secretKeyRef != null)] | length >= 1)
   and ([.env[]? | select(.value != null) | .value | select(test("://[^/@$]+:[^/@$(]+@"))] | length == 0)'
check_cmd "API : URL de la base construite par référence à une variable \$(…) issue du Secret" _m14d_json "$_m14d_e08_c" \
  '[.env[]? | select(.name == "MEDIAGENDA_DB_URL") | .value | test("\\$\\([A-Z_]+\\)")] == [true]'

# --- 2. Sondes --------------------------------------------------------------------------------------------
check_cmd "API : startupProbe sur /sante" _m14d_json "$_m14d_e08_c" '.startupProbe.httpGet.path == "/sante"'
check_cmd "API : livenessProbe sur /sante (ne dépend ni de la base ni du cache)" _m14d_json "$_m14d_e08_c" \
  '.livenessProbe.httpGet.path == "/sante"'
check_cmd "API : readinessProbe sur /pret" _m14d_json "$_m14d_e08_c" '.readinessProbe.httpGet.path == "/pret"'
check_cmd "API : le démarrage laisse au moins 30 s avant que la vivacité ne compte" _m14d_json "$_m14d_e08_c" \
  '((.startupProbe.periodSeconds // 10) * (.startupProbe.failureThreshold // 3)) >= 30'
for _m14d_e08_d in postgresql valkey; do
  check_cmd "$_m14d_e08_d : sonde de disponibilité" _m14d_json "$_m14d_e08_dep" \
    '.items[] | select(.metadata.name == $d) | [.spec.template.spec.containers[] | has("readinessProbe")] | any' --arg d "$_m14d_e08_d"
done

# --- 3. Ressources, QoS, arrêt, sécurité --------------------------------------------------------------------
check_cmd "API : demandes CPU et mémoire, limite de mémoire" _m14d_json "$_m14d_e08_c" \
  '.resources.requests.cpu != null and .resources.requests.memory != null and .resources.limits.memory != null'
_m14d_e08_pods="$(_m14d_k -n "$_m14d_e08_ns" get pods -o json)"
check_cmd "Pods de l'API en classe QoS Burstable" _m14d_json "$_m14d_e08_pods" \
  '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "mediagenda-api" and .status.phase == "Running") | .status.qosClass]
   | length >= 2 and all(. == "Burstable")'
check_cmd "Pod PostgreSQL en classe QoS Guaranteed" _m14d_json "$_m14d_e08_pods" \
  '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "postgresql" and .status.phase == "Running") | .status.qosClass] == ["Guaranteed"]'
check_cmd "API : délai de grâce supérieur à MEDIAGENDA_DELAI_ARRET (arrêt propre avant SIGKILL)" bash -c \
  '[[ -n "$1" && "$1" != "{}" ]] || exit 1; g="$(jq -r ".terminationGracePeriodSeconds // 30" <<<"$1")"; d="$(jq -r ".data.MEDIAGENDA_DELAI_ARRET // \"20\"" <<<"$2")"; (( g > d ))' \
  _ "${_m14d_e08_api:-{\}}" "${_m14d_e08_cm:-{\}}"
check_cmd "API : runAsNonRoot, sans élévation de privilèges, système de fichiers en lecture seule" bash -c \
  'jq -e ".securityContext.runAsNonRoot == true" <<<"$1" >/dev/null && jq -e ".securityContext.allowPrivilegeEscalation == false and .securityContext.readOnlyRootFilesystem == true" <<<"$2" >/dev/null' \
  _ "${_m14d_e08_api:-{\}}" "${_m14d_e08_c:-{\}}"

# --- 4. L'application est prête ---------------------------------------------------------------------------
check_cmd "GET /pret à travers le Service : PostgreSQL et Valkey joignables" _m14d_json \
  "$(_m14d_proxy_get "$_m14d_e08_ns" mediagenda-api:http /pret)" '.statut == "pret" and .postgresql == "ok" and .valkey == "ok"'
check_cmd "Service mediagenda-api : deux points de terminaison prêts" _m14d_json \
  "$(_m14d_k -n "$_m14d_e08_ns" get endpointslices -l kubernetes.io/service-name=mediagenda-api -o json)" \
  '[.items[].endpoints[]? | select(.conditions.ready == true)] | length == 2'

# --- 5. Le code ------------------------------------------------------------------------------------------
check_cmd "mediagenda/api (main) : k8s/essais/mediagenda-api-config.yaml" \
  _m14d_fichier_main mediagenda/api k8s/essais/mediagenda-api-config.yaml
check_cmd "mediagenda/api (main) : aucun Secret Kubernetes versionné sous k8s/" bash -c \
  '[[ "$1" == *k8s/essais/* ]] && ! grep -Eiq "^k8s/.*secret" <<<"$1"' _ "$(_m14d_arbre_main mediagenda/api)"
