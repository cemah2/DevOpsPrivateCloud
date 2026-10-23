# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E02.sh — M27-E02 : CloudNativePG en profondeur : rôles, bases et pooler
# À lancer depuis adm01. Lecture seule : droits du compte wb-checks (auth can-i, sur lui-même),
# objets CloudNativePG des espaces mediagenda-recette et mediagenda-prod, ExternalSecret de l'API,
# métriques de PgBouncer (Prometheus), documentation sur main (GitLab).

# shellcheck source=_m27-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-decouverte.sh"

title "M27-E02 — CloudNativePG en profondeur : rôles, bases et pooler"
require_cmd jq kubectl curl awk

# --- 1. ClusterRole wb-checks-services ----------------------------------------------------------------
_m27d_e02_cr="$(_m27d_k get clusterrole wb-checks-services -o json)"
check_cmd "ClusterRole wb-checks-services agrégée (étiquette workbook.medisphere.internal/checks=true)" _m27d_json "$_m27d_e02_cr" \
  '.metadata.labels["workbook.medisphere.internal/checks"] == "true"'
check_cmd "wb-checks-services : RabbitMQ et Strimzi en lecture, aucun verbe d'écriture, aucun Secret" _m27d_json "$_m27d_e02_cr" \
  '([.rules[].apiGroups[]] | index("rabbitmq.com") != null and index("kafka.strimzi.io") != null)
   and all(.rules[]; all(.verbs[]; . == "get" or . == "list" or . == "watch"))
   and ([.rules[].resources[]?] | index("secrets") == null)'
# Contrôle fonctionnel : ce que le compte des checks peut réellement faire (il s'interroge lui-même).
check_output "le compte des checks peut lister les objets rabbitmq.com" '^yes' kube auth can-i list queues.rabbitmq.com --all-namespaces
check_output "le compte des checks ne peut toujours PAS lire les Secrets" '^no' kube auth can-i get secrets -n mediagenda-recette

# --- 2. Rôles et base (recette) ------------------------------------------------------------------------
_m27d_e02_ns="mediagenda-${_M27D_ENV_RECETTE}"
_m27d_e02_db="$(_m27d_k get clusters.postgresql.cnpg.io mediagenda-db -n "$_m27d_e02_ns" -o json)"
check_cmd "recette : rôle de groupe mediagenda_lecture déclaré sans connexion et réconcilié" _m27d_json "$_m27d_e02_db" \
  'any(.spec.managed.roles[]?; .name == "mediagenda_lecture" and (.login // false) == false and (.ensure // "present") == "present")
   and ((.status.managedRolesStatus.byStatus.reconciled // []) | index("mediagenda_lecture") != null)'
check_cmd "recette : accès de Lucas temporaire (validUntil + membre de mediagenda_lecture), ou déjà retiré (ensure: absent)" _m27d_json "$_m27d_e02_db" \
  'any(.spec.managed.roles[]?; .name == "lucas_lecture" and
     (((.ensure // "present") == "absent") or
      (.login == true and (.validUntil // "") != "" and ((.inRoles // []) | index("mediagenda_lecture") != null) and (.superuser // false) == false)))'
check_cmd "recette : aucun rôle géré en échec de réconciliation" _m27d_json "$_m27d_e02_db" \
  '((.status.managedRolesStatus.cannotReconcile // {}) | length) == 0'

for _m27d_e02_env in "$_M27D_ENV_RECETTE" "$_M27D_ENV_PROD"; do
  _m27d_e02_n="mediagenda-${_m27d_e02_env}"
  _m27d_e02_c="$(_m27d_k get clusters.postgresql.cnpg.io mediagenda-db -n "$_m27d_e02_n" -o json)"
  check_cmd "$_m27d_e02_env : pg_stat_statements activé (paramètre pg_stat_statements.* du Cluster)" _m27d_json "$_m27d_e02_c" \
    '(.spec.postgresql.parameters // {}) | keys | any(startswith("pg_stat_statements."))'
  _m27d_e02_bases="$(_m27d_k get databases.postgresql.cnpg.io -n "$_m27d_e02_n" -o json)"
  check_cmd "$_m27d_e02_env : CRD Database pour la base mediagenda (grappe mediagenda-db, reclaim retain explicite, appliquée)" _m27d_json "$_m27d_e02_bases" \
    'any(.items[]; .spec.name == "mediagenda" and .spec.cluster.name == "mediagenda-db" and .spec.owner == "mediagenda"
       and .spec.databaseReclaimPolicy == "retain" and .status.applied == true)'

  # --- 3. Pooler -----------------------------------------------------------------------------------------
  _m27d_e02_p="$(_m27d_k get poolers.postgresql.cnpg.io mediagenda-db-pooler-rw -n "$_m27d_e02_n" -o json)"
  check_cmd "$_m27d_e02_env : Pooler mediagenda-db-pooler-rw (rw, transaction, ≥ 2 instances, grappe mediagenda-db)" _m27d_json "$_m27d_e02_p" \
    '.spec.type == "rw" and .spec.pgbouncer.poolMode == "transaction" and (.spec.instances // 1) >= 2 and .spec.cluster.name == "mediagenda-db"'
  check_cmd "$_m27d_e02_env : au moins 2 pods PgBouncer prêts, sur 2 nœuds différents" bash -c '[[ "$1" -ge 2 && "$2" -ge 2 ]]' _ \
    "$(_m27d_pods_prets "$_m27d_e02_n" cnpg.io/poolerName=mediagenda-db-pooler-rw)" \
    "$(_m27d_noeuds_distincts "$_m27d_e02_n" cnpg.io/poolerName=mediagenda-db-pooler-rw)"
  check_cmd "$_m27d_e02_env : PodMonitor des pods du pooler, étiqueté pour Prometheus" _m27d_json \
    "$(_m27d_k get podmonitors.monitoring.coreos.com -n "$_m27d_e02_n" -o json)" \
    'any(.items[]; .metadata.labels["medisphere.internal/supervision"] == "oui"
       and .spec.selector.matchLabels["cnpg.io/poolerName"] == "mediagenda-db-pooler-rw")'
  # Chemin des connexions : l'API par le pooler, le migrateur en direct.
  _m27d_e02_es="$(_m27d_k get externalsecrets.external-secrets.io -n "$_m27d_e02_n" -o json)"
  check_cmd "$_m27d_e02_env : l'URL de l'API (mediagenda-db-api) vise mediagenda-db-pooler-rw" _m27d_json "$_m27d_e02_es" \
    'any(.items[]; .metadata.name == "mediagenda-db-api" and (.spec.target.template.data.uri // "" | test("@mediagenda-db-pooler-rw[:/]")))'
  check_cmd "$_m27d_e02_env : le migrateur (mediagenda-db-migrateur) va DIRECTEMENT au primaire, pas au pooler" _m27d_json "$_m27d_e02_es" \
    'any(.items[]; .metadata.name == "mediagenda-db-migrateur") and
     all(.items[] | select(.metadata.name == "mediagenda-db-migrateur") | (.spec.target.template.data // {}) | to_entries[]; (.value | test("pooler") | not))'
  _m27d_e02_tx="$(_m27d_prom "sum(increase(cnpg_pgbouncer_stats_total_xact_count{namespace=\"${_m27d_e02_n}\",database=\"mediagenda\"}[30m]))")"
  check_cmd "$_m27d_e02_env : des transactions passent par PgBouncer vers la base mediagenda (30 dernières minutes : ${_m27d_e02_tx})" \
    _m27d_positif "$_m27d_e02_tx"
done

# --- 4. Documentation -------------------------------------------------------------------------------------
check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/postgresql.md (pooler, durées mesurées)" \
  _m27d_doc_contient "${_M27D_DOC}/postgresql.md" 'pooler-rw'
check_cmd "postgresql.md : des durées de bascule renseignées (secondes)" \
  _m27d_doc_contient "${_M27D_DOC}/postgresql.md" '[0-9]+([,.][0-9]+)? ?s( |$|\b)'
