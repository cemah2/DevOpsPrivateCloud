# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E09.sh — M27-E09 : Kafka avec Strimzi (KRaft, pools de nœuds, topics, utilisateurs)
# À lancer depuis adm01, PENDANT l'essai (avant le retrait de la fin d'E10). Lecture seule :
# Application kafka-essai, objets kafka.strimzi.io de l'espace kafka-essai (ClusterRole
# wb-checks-services), Deployment de l'opérateur, documentation. Jamais les Secrets des utilisateurs.

# shellcheck source=_m27-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-operationnel.sh"

title "M27-E09 — Kafka avec Strimzi : KRaft, pools de nœuds, topics et utilisateurs"
require_cmd jq kubectl curl

_m27o_e09_app="$(_m27d_app kafka-essai)"
if [[ -z "$_m27o_e09_app" ]] && _m27o_absent applications.argoproj.io kafka-essai -n argocd; then
  # Essai déjà retiré (fin d'E10) : ce check n'a plus d'objet ; la documentation reste.
  skip "grappe kafka-essai" "Application kafka-essai absente : essai retiré ? Vérifie le retrait avec lab/bin/check 27 10"
  check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/kafka-essai.md" _m27d_doc_contient "${_M27D_DOC}/kafka-essai.md" 'strimzi'
  return 0
fi

# --- 1. Opérateur et Application ------------------------------------------------------------------------------
check_cmd "Application kafka-essai : chart strimzi-kafka-operator 1.3.x" _m27d_json "$_m27o_e09_app" \
  'any((.spec.sources // [.spec.source])[]; (.chart // "") == "strimzi-kafka-operator" and ((.targetRevision // "") | test("^1\\.3\\.")))'
check_cmd "Application kafka-essai : dossier kafka-essai de plateforme/donnees" _m27d_app_source "$_m27o_e09_app" "plateforme/donnees" "kafka-essai"
check_cmd "Application kafka-essai : synchronisée et saine" _m27d_json "$_m27o_e09_app" "$_M27D_APP_SAINE"
check_cmd "opérateur Strimzi 1.3 prêt dans kafka-essai, image du cache Harbor (quay)" _m27d_json \
  "$(_m27d_k get deployments -n kafka-essai -o json)" \
  'any(.items[]; any(.spec.template.spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/quay/strimzi/operator:1\\.3\\."))
     and (.status.readyReplicas // 0) >= 1)'
check_cmd "l'opérateur ne surveille que son espace (STRIMZI_NAMESPACE = espace du pod)" _m27d_json \
  "$(_m27d_k get deployments -n kafka-essai -o json)" \
  'any(.items[].spec.template.spec.containers[].env[]?; .name == "STRIMZI_NAMESPACE"
     and ((.valueFrom.fieldRef.fieldPath // "") == "metadata.namespace" or (.value // "") == "kafka-essai"))'

# --- 2. La grappe --------------------------------------------------------------------------------------------
_m27o_e09_k="$(_m27d_k get kafkas.kafka.strimzi.io kafka-essai -n kafka-essai -o json)"
check_cmd "Kafka kafka-essai : version 4.3.1, prête" _m27d_json "$_m27o_e09_k" \
  '.spec.kafka.version == "4.3.1" and any(.status.conditions[]?; .type == "Ready" and .status == "True")'
check_cmd "Kafka kafka-essai : écouteur tls 9093 (TLS + SCRAM-SHA-512), autorisation simple" _m27d_json "$_m27o_e09_k" \
  'any(.spec.kafka.listeners[]; .name == "tls" and .port == 9093 and .tls == true and .authentication.type == "scram-sha-512")
   and .spec.kafka.authorization.type == "simple"'
check_cmd "Kafka kafka-essai : opérateurs de topics et d'utilisateurs déclarés" _m27d_json "$_m27o_e09_k" \
  '.spec.entityOperator.topicOperator != null and .spec.entityOperator.userOperator != null'
_m27o_e09_pool="$(_m27d_k get kafkanodepools.kafka.strimzi.io double-role -n kafka-essai -o json)"
check_cmd "KafkaNodePool double-role : 3 répliques aux deux rôles, stockage ceph-rbd" _m27d_json "$_m27o_e09_pool" \
  '.spec.replicas == 3 and (.spec.roles | index("controller") != null and index("broker") != null)
   and any(.spec.storage.volumes[]? // .spec.storage; (.class // "") == "ceph-rbd")'
check_cmd "3 pods Kafka prêts (pool double-role), sur 3 nœuds différents" bash -c '[[ "$1" -eq 3 && "$2" -eq 3 ]]' _ \
  "$(_m27d_pods_prets kafka-essai strimzi.io/pool-name=double-role)" "$(_m27d_noeuds_distincts kafka-essai strimzi.io/pool-name=double-role)"

# --- 3. Topics et utilisateurs ---------------------------------------------------------------------------------
_m27o_e09_t="$(_m27d_k get kafkatopics.kafka.strimzi.io -n kafka-essai -o json)"
check_cmd "topic rendez-vous.evenements : 3 partitions, facteur 3, min.insync.replicas 2, prêt" _m27d_json "$_m27o_e09_t" \
  'any(.items[]; (.spec.topicName // .metadata.name) == "rendez-vous.evenements" and .spec.partitions == 3 and .spec.replicas == 3
     and ((.spec.config["min.insync.replicas"] // 0) | tostring) == "2"
     and any(.status.conditions[]?; .type == "Ready" and .status == "True"))'
check_cmd "topic notifications.rebut prêt" _m27d_json "$_m27o_e09_t" \
  'any(.items[]; (.spec.topicName // .metadata.name) == "notifications.rebut" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))'
check_cmd "KafkaUser mediagenda et medinotif : SCRAM-SHA-512, ACL, prêts" _m27d_json \
  "$(_m27d_k get kafkausers.kafka.strimzi.io -n kafka-essai -o json)" \
  '[.items[] | select(.metadata.name == "mediagenda" or .metadata.name == "medinotif")
     | select(.spec.authentication.type == "scram-sha-512" and .spec.authorization.type == "simple"
              and any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 2'

check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/kafka-essai.md (date de retrait prévue)" \
  _m27d_doc_contient "${_M27D_DOC}/kafka-essai.md" 'retrait'
