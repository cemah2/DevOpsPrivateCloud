# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E25.sh — M16-E25 « PostgreSQL : bascule, maintenance et montée de version »
# Lecture seule : Cluster mediagenda-db (timeline, instances, isolement, stratégie), clusters
# d'essai pg-essai et pg-essai-import (image, bootstrap), compte rendu (API GitLab).

# shellcheck source=_m16-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-production.sh"

title "M16-E25 — PostgreSQL : bascule, maintenance et montée de version"
require_cmd jq kubectl curl

_m16_e25_db="$(_m16p_kj clusters.postgresql.cnpg.io "$_M16P_BASE" -n "$_M16P_RECETTE")"
title "mediagenda-db après les bascules"
check_cmd "mediagenda-db est sain, 3 instances prêtes" \
  _m16p_jq "$_m16_e25_db" '.status.phase == "Cluster in healthy state" and .spec.instances == 3 and .status.readyInstances == 3'
check_cmd "timeline ≥ 3 : au moins deux promotions (bascule planifiée et bascule sur panne)" \
  _m16p_jq "$_m16_e25_db" '(.status.timelineID // 1) >= 3'
check_cmd "aucune instance isolée (annotation cnpg.io/fencedInstances vide ou absente)" \
  _m16p_jq "$_m16_e25_db" '((.metadata.annotations["cnpg.io/fencedInstances"] // "[]") | fromjson | length) == 0'
check_cmd "stratégie de mise à jour du primaire fixée explicitement (décision écrite)" \
  _m16p_jq "$_m16_e25_db" '.spec.primaryUpdateStrategy == "supervised" or .spec.primaryUpdateStrategy == "unsupervised"'
check_cmd "mediagenda-db : archivage continu actif" _m16p_archivage_actif "$_M16P_RECETTE" "$_M16P_BASE"

title "Montées de version sur les clusters d'essai"
_m16_e25_essai="$(_m16p_kj clusters.postgresql.cnpg.io pg-essai -n wb-essais)"
_m16_e25_import="$(_m16p_kj clusters.postgresql.cnpg.io pg-essai-import -n wb-essais)"
check_cmd "pg-essai est sain" _m16p_cluster_sain wb-essais pg-essai
check_cmd "pg-essai tourne en PostgreSQL 18 (image :18.*-minimal-trixie)" \
  _m16p_jq "$_m16_e25_essai" '(.spec.imageName // "") | test(":18\\.[0-9]+-minimal-trixie$")'
check_cmd "pg-essai-import est sain" _m16p_cluster_sain wb-essais pg-essai-import
check_cmd "pg-essai-import : PostgreSQL 18, créé par import (bootstrap.initdb.import)" \
  _m16p_jq "$_m16_e25_import" '((.spec.imageName // "") | test(":18\\.")) and (.spec.bootstrap.initdb.import.type // "") != ""'

title "Nettoyage"
# L'API liste au plus 1000 rendez-vous, triés par date de début : les témoins (créneaux de 2030 et
# au-delà) sont en fin de liste ; au-delà de 1000 rendez-vous, le contrôle ne peut pas conclure.
_m16_e25_temoins() {
  local l
  l="$(_m16p_api '/api/v1/rendez-vous?limite=1000')" || return 1
  jq -e 'length < 1000 and all(.[]; .praticien != "wb-temoin")' >/dev/null 2>&1 <<<"$l"
}
check_cmd "aucun rendez-vous de test (praticien wb-temoin) ne reste dans la recette" _m16_e25_temoins

title "Documentation"
check_cmd "compte rendu tests/bascules-postgresql.md (bascules, pg_rewind, montée majeure)" \
  _m16p_doc_main docs/kubernetes/stockage/tests/bascules-postgresql.md 'pg_rewind' 'switchover|bascule planifiée' 'import' 'pg_upgrade|en place'
