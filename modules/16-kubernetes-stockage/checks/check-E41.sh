# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M16-E41 « Panne : l'archivage des WAL est bloqué » : archivage continu en
# fonctionnement, ObjectStore cnpg-s3 vers le compartiment cnpg-k8s-par1 avec sa CA, plugin Barman
# Cloud archiveur de WAL, et une sauvegarde de base terminée depuis l'incident. Lecture seule.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E41 — Les WAL de mediagenda-db sont archivés"
require_cmd kubectl jq

_m16_e41_c="$(_m16x_cnpg)"
_m16_e41_os="$(_m16x_j objectstores.barmancloud.cnpg.io cnpg-s3 -n "$_m16x_ns_db")"
check_cmd "mediagenda-db : archivage continu en fonctionnement (condition ContinuousArchiving)" _m16x_q "$_m16_e41_c" \
  'any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")'
check_cmd "mediagenda-db : plugin Barman Cloud archiveur de WAL vers l'ObjectStore cnpg-s3" _m16x_q "$_m16_e41_c" \
  'any(.spec.plugins[]?; .name == "barman-cloud.cloudnative-pg.io" and (.isWALArchiver // false) and .parameters.barmanObjectName == "cnpg-s3")'
check_cmd "ObjectStore cnpg-s3 : destination dans le compartiment cnpg-k8s-par1" _m16x_q "$_m16_e41_os" \
  '.spec.configuration.destinationPath | test("^s3://cnpg-k8s-par1(/|$)")'
check_cmd "ObjectStore cnpg-s3 : point d'accès s3-01 et CA fournie (endpointCA)" _m16x_q "$_m16_e41_os" \
  '(.spec.configuration.endpointURL // "" | contains("s3-01.par1.medisphere.internal:8333")) and (.spec.configuration.endpointCA.name // "" | length > 0)'
check_cmd "une sauvegarde de base de mediagenda-db terminée depuis l'incident" _m16x_cree_apres \
  "$(_m16x_j backups.postgresql.cnpg.io -n "$_m16x_ns_db")" "$(_m16x_injection E41)" \
  '.spec.cluster.name == "mediagenda-db" and .status.phase == "completed"'
check_cmd "panne M16-E41 close (lab/bin/break 16 41 --annuler après réparation)" _m16x_aucune_panne_active E41
