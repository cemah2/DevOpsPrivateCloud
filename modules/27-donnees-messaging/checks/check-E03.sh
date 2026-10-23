# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E03.sh — M27-E03 : RabbitMQ par l'opérateur : la grappe messagerie/rabbitmq
# À lancer depuis adm01. Lecture seule : Applications Argo CD, objets des espaces rabbitmq-system et
# messagerie (« kube »), API de gestion de RabbitMQ par le compte wb-checks (rabbitmq_api), client
# Keycloak (keycloak_api), fichiers sur main (GitLab).

# shellcheck source=_m27-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-decouverte.sh"

title "M27-E03 — RabbitMQ par l'opérateur : la grappe messagerie/rabbitmq"
require_cmd jq kubectl curl

# --- 1. Opérateurs -------------------------------------------------------------------------------------
_m27d_e03_appop="$(_m27d_app rabbitmq-operateurs)"
check_cmd "Application rabbitmq-operateurs : plateforme/donnees, chemin vendor/rabbitmq" \
  _m27d_app_source "$_m27d_e03_appop" "plateforme/donnees" "vendor/rabbitmq"
check_cmd "Application rabbitmq-operateurs : synchronisée et saine" _m27d_json "$_m27d_e03_appop" "$_M27D_APP_SAINE"
check_cmd "plateforme/donnees (main) : copie épinglée du Cluster Operator 2.23.1" \
  _m27d_fichier_main "$_M27D_P_DONNEES" vendor/rabbitmq/cluster-operator/cluster-operator-2.23.1.yml
check_cmd "plateforme/donnees (main) : copie épinglée du Messaging Topology Operator 1.20.4" \
  _m27d_fichier_main "$_M27D_P_DONNEES" vendor/rabbitmq/messaging-topology-operator/messaging-topology-operator-with-certmanager-1.20.4.yaml
check_output "plateforme/donnees (main) : outils/recopier-operateurs.sh vérifie des empreintes SHA-256" '[0-9a-f]{64}' \
  _m27d_contenu_main "$_M27D_P_DONNEES" outils/recopier-operateurs.sh
_m27d_e03_dep="$(_m27d_k get deployments -n rabbitmq-system -o json)"
check_cmd "Cluster Operator 2.23.1 prêt, image du cache Harbor" _m27d_json "$_m27d_e03_dep" \
  'any(.items[]; (.spec.template.spec.containers[0].image | test("^registry\\.par1\\.medisphere\\.internal/ghcr/rabbitmq/cluster-operator:2\\.23\\.1"))
     and (.status.readyReplicas // 0) >= 1)'
check_cmd "Messaging Topology Operator 1.20.4 prêt, image du cache Harbor" _m27d_json "$_m27d_e03_dep" \
  'any(.items[]; (.spec.template.spec.containers[0].image | test("^registry\\.par1\\.medisphere\\.internal/ghcr/rabbitmq/messaging-topology-operator:1\\.20\\.4"))
     and (.status.readyReplicas // 0) >= 1)'

# --- 2. La grappe ---------------------------------------------------------------------------------------
_m27d_e03_app="$(_m27d_app rabbitmq)"
check_cmd "Application rabbitmq : plateforme/donnees, chemin rabbitmq" _m27d_app_source "$_m27d_e03_app" "plateforme/donnees" "rabbitmq"
check_cmd "Application rabbitmq : espace messagerie, synchronisée et saine" _m27d_json "$_m27d_e03_app" \
  ".spec.destination.namespace == \"messagerie\" and $_M27D_APP_SAINE"
check_cmd "espace messagerie : Pod Security « restricted » appliquée" _m27d_json \
  "$(_m27d_k get namespace messagerie -o json)" '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"'
_m27d_e03_rc="$(_m27d_k get rabbitmqclusters.rabbitmq.com rabbitmq -n messagerie -o json)"
check_cmd "RabbitmqCluster rabbitmq : 3 réplicas, image ${_M27D_VERSION_RMQ} du cache Harbor PAR EMPREINTE" _m27d_json "$_m27d_e03_rc" \
  '.spec.replicas == 3 and (.spec.image | test("^registry\\.par1\\.medisphere\\.internal/dockerhub/library/rabbitmq:" + $re + "\\.[0-9]+(-management)?@sha256:[0-9a-f]{64}$"))' \
  --arg re "$_M27D_RMQ_RE"
check_cmd "RabbitmqCluster : stockage ceph-rbd, TLS (secret du certificat), anti-affinité obligatoire par nœud" _m27d_json "$_m27d_e03_rc" \
  '.spec.persistence.storageClassName == "ceph-rbd" and (.spec.tls.secretName // "") != ""
   and any(.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[]?; .topologyKey == "kubernetes.io/hostname")'
check_cmd "RabbitmqCluster : délai d'arrêt borné (pas les 7 jours par défaut)" _m27d_json "$_m27d_e03_rc" \
  '(.spec.terminationGracePeriodSeconds // 604800) <= 3600'
check_cmd "RabbitmqCluster : tous les réplicas prêts (condition AllReplicasReady)" _m27d_json "$_m27d_e03_rc" \
  'any(.status.conditions[]?; .type == "AllReplicasReady" and .status == "True")'
check_cmd "3 pods rabbitmq prêts, sur 3 nœuds différents" bash -c '[[ "$1" -eq 3 && "$2" -eq 3 ]]' _ \
  "$(_m27d_pods_prets messagerie app.kubernetes.io/name=rabbitmq)" "$(_m27d_noeuds_distincts messagerie app.kubernetes.io/name=rabbitmq)"
check_cmd "certificat rabbitmq-tls prêt, émis par openbao-services" _m27d_json \
  "$(_m27d_k get certificates.cert-manager.io -n messagerie -o json)" \
  'any(.items[]; .spec.secretName == ($s) and .spec.issuerRef.name == "openbao-services"
     and any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
  --arg s "$(jq -r '.spec.tls.secretName // "rabbitmq-tls"' <<<"${_m27d_e03_rc:-{\}}" 2>/dev/null || echo rabbitmq-tls)"
check_cmd "PodDisruptionBudget sur les pods de la grappe (au plus 1 indisponible)" _m27d_json \
  "$(_m27d_k get pdb -n messagerie -o json)" \
  'any(.items[]; .spec.selector.matchLabels["app.kubernetes.io/name"] == "rabbitmq" and (.spec.maxUnavailable == 1 or .spec.minAvailable == 2))'
_m27d_e03_cnp="$(_m27d_k get ciliumnetworkpolicies.cilium.io -n messagerie -o json)"
check_cmd "CiliumNetworkPolicy sur les pods de la grappe" _m27d_json "$_m27d_e03_cnp" \
  'any(.items[]; .spec.endpointSelector.matchLabels["app.kubernetes.io/name"] == "rabbitmq")'
check_cmd "politique réseau : AMQP en clair (5672) autorisé depuis NULLE PART" _m27d_json "$_m27d_e03_cnp" \
  '[.items[].spec.ingress[]?.toPorts[]?.ports[]? | select(.port == "5672" or .port == 5672 or .port == "amqp")] | length == 0'

# --- 3. L'API de gestion (compte wb-checks) ------------------------------------------------------------
if ! _m27d_rmq_lisible; then
  _ko "API de gestion injoignable avec le compte des checks (rabbitmq-checks.env, route, utilisateur wb-checks)"
else
  _ok "API de gestion joignable par https://rabbitmq.apps… avec le compte des checks"
  check_cmd "version de RabbitMQ ${_M27D_VERSION_RMQ}" _m27d_json "$(_m27d_rmq overview)" \
    '.rabbitmq_version | test("^" + $re + "\\.")' --arg re "$_M27D_RMQ_RE"
  check_cmd "3 nœuds en marche, sans alarme mémoire ni disque" _m27d_json "$(_m27d_rmq nodes)" \
    '([.[] | select(.running == true and .mem_alarm == false and .disk_free_alarm == false)] | length) == 3'
  check_cmd "métadonnées dans Khepri (feature flag khepri_db activé)" _m27d_json "$(_m27d_rmq feature-flags)" \
    'any(.[]; .name == "khepri_db" and .state == "enabled")'
  check_cmd "écouteur AMQPS 5671 présent" _m27d_json "$(_m27d_rmq overview)" \
    'any(.listeners[]?; .port == 5671)'
  check_cmd "le compte des checks porte l'étiquette monitoring (et pas administrator)" _m27d_json "$(_m27d_rmq whoami)" \
    '(.tags | if type == "array" then . else [.] end | map(tostring) | join(",")) as $t
     | ($t | test("monitoring")) and ($t | test("administrator") | not)'
fi
check_http "interface de gestion publiée (https://rabbitmq.apps.par1.medisphere.internal/)" \
  "${WB_RABBITMQ_URL:-https://rabbitmq.apps.par1.medisphere.internal}/" 200
check_cmd "configuration OAuth 2.0 de l'interface (management.oauth_enabled, client rabbitmq, issuer Keycloak)" _m27d_json "$_m27d_e03_rc" \
  '(.spec.rabbitmq.additionalConfig // "") as $c
   | ($c | test("(?m)^\\s*management\\.oauth_enabled\\s*=\\s*true")) and ($c | test("(?m)^\\s*management\\.oauth_client_id\\s*=\\s*rabbitmq\\s*$"))
     and ($c | test("(?m)^\\s*auth_oauth2\\.issuer\\s*=\\s*https://sso\\.par1\\.medisphere\\.internal/realms/medisphere"))'
_m27d_e03_kc="$(keycloak_api 'clients?clientId=rabbitmq' 2>/dev/null || true)"
if [[ -n "$_m27d_e03_kc" ]]; then
  check_cmd "Keycloak : client « rabbitmq » public, code d'autorisation + PKCE S256" _m27d_json "$_m27d_e03_kc" \
    'any(.[]; .clientId == "rabbitmq" and .publicClient == true and .standardFlowEnabled == true
       and (.attributes["pkce.code.challenge.method"] // "") == "S256")'
else
  skip "client Keycloak rabbitmq" "API de Keycloak injoignable avec le compte des checks (keycloak-checks.env, M24)"
fi

# --- 4. Fichier local des checks ---------------------------------------------------------------------
_m27d_e03_env="${WB_RABBITMQ_CHECKS_FILE:-$HOME/.config/workbook/rabbitmq-checks.env}"
check_cmd "rabbitmq-checks.env présent et en mode 600" bash -c '[[ -r "$1" && "$(stat -c %a "$1")" == 600 ]]' _ "$_m27d_e03_env"
check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/rabbitmq.md (compte de bris de glace documenté)" \
  _m27d_doc_contient "${_M27D_DOC}/rabbitmq.md" 'rabbitmq-default-user'
