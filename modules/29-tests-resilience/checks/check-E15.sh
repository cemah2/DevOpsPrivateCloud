# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E15.sh — M29-E15 « Résilience des données sous charge » : mediagenda-db sain après au moins une
# bascule, réplication synchrone, grappe RabbitMQ complète sans alarme, file quorum notifications de
# medinotif-recette avec ses trois membres en ligne, PodChaos de la bascule limité à la recette,
# rapport et RB-296. Lecture seule (API de gestion de RabbitMQ avec le compte wb-checks).

# shellcheck source=_m29-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-production.sh"

title "M29-E15 — Résilience des données sous charge"
require_cmd kubectl jq curl yq

if _m29p_api_repond; then
  check_cmd "mediagenda-db (recette) : 3 instances prêtes, phase saine" _m29p_kq \
    '.status.readyInstances == 3 and (.status.phase | test("healthy"; "i"))' -n "$_m29p_recette" clusters.postgresql.cnpg.io mediagenda-db
  # Une bascule a eu lieu PENDANT le module 29 : le primaire actuel est en place depuis après la création
  # de l'espace chaos-experiences (M29-E09). Comparer à la création du cluster ne suffirait pas : les
  # bascules du M27 (switchover, nœud drainé) rendraient ce contrôle vert sans rien faire ici.
  _m29_e15_bascule() {
    local depuis
    depuis="$(kube get namespace "$_m29p_chaos_ns" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)" || return 1
    [[ -n "$depuis" ]] || return 1
    kube get clusters.postgresql.cnpg.io mediagenda-db -n "$_m29p_recette" -o json 2>/dev/null |
      jq -e --arg depuis "$depuis" '(.status.currentPrimaryTimestamp // "") != ""
        and ((.status.currentPrimaryTimestamp | sub("\\.[0-9]+"; "") | fromdateiso8601) > ($depuis | fromdateiso8601))' >/dev/null 2>&1
  }
  check_cmd "mediagenda-db : le primaire a changé depuis le début du module (création de $_m29p_chaos_ns)" _m29_e15_bascule
  check_cmd "mediagenda-db : réplication synchrone demandée (≥ 1 réplique)" _m29p_kq \
    '((.spec.postgresql.synchronous.number // 0) >= 1) or ((.spec.minSyncReplicas // 0) >= 1)' \
    -n "$_m29p_recette" clusters.postgresql.cnpg.io mediagenda-db
  check_cmd "Pooler mediagenda-db-pooler-rw : prêt" _m29p_kq \
    '(.status.instances // 0) >= 1' -n "$_m29p_recette" poolers.postgresql.cnpg.io mediagenda-db-pooler-rw
else
  skip "mediagenda-db" "l'API ne répond pas au compte des checks"
fi

_m29_e15_noeuds() {
  rabbitmq_api nodes 2>/dev/null | jq -e 'length == 3 and all(.[]; .running == true and (.mem_alarm | not) and (.disk_free_alarm | not))' >/dev/null 2>&1
}
_m29_e15_file() {
  rabbitmq_api "queues/medinotif-recette/notifications" 2>/dev/null |
    jq -e '.type == "quorum" and ((.members // []) | length) == 3 and ((.online // []) | length) == 3' >/dev/null 2>&1
}
check_cmd "RabbitMQ : 3 nœuds en marche, aucune alarme mémoire ni disque" _m29_e15_noeuds
check_cmd "RabbitMQ : file quorum notifications (medinotif-recette) avec 3 membres en ligne" _m29_e15_file

# PodChaos de la bascule subie : versionné dans chaos/e15/ (ou présent dans chaos-experiences).
_m29_e15_docs="$(_m29p_yaml_json "$_m29p_resilience" chaos/e15)" || true
[[ -n "$_m29_e15_docs" ]] || _m29_e15_docs='[]'
_m29_e15_podchaos() {
  jq -e 'any(.[]; .kind == "PodChaos" and .spec.action == "pod-kill" and .spec.mode == "one"
           and .spec.selector.namespaces == ["mediagenda-recette"]
           and .spec.selector.labelSelectors["cnpg.io/instanceRole"] == "primary")' >/dev/null 2>&1 <<<"$_m29_e15_docs"
}
check_cmd "chaos/e15/ : PodChaos pod-kill « one » du primaire, limité à mediagenda-recette" _m29_e15_podchaos
check_cmd "chaos/e15/ : aucune cible dans un espace de prod ni dans messagerie" \
  bash -c '[[ "$(jq length <<<"$2")" -gt 0 && "$(jq "$1" <<<"$2")" == 0 ]]' _ "$_m29p_jq_espaces_interdits" "$_m29_e15_docs"

check_cmd "rapport docs/qualite/rapports/*-resilience-donnees.md : CHG-3015, bascules, notifications" \
  _m29p_doc docs/qualite/rapports 'resilience-donnees' 'CHG-3015' 'promote|bascule' 'notification'
check_cmd "RB-296 publié (main) : perte du primaire ou d'un nœud RabbitMQ" _m29p_doc docs/qualite '^RB-296' 'quorum' 'pooler|PgBouncer'
