# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E19.sh — M16-E19 : CloudNativePG : sauvegarde continue et restauration à un instant donné
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), API GitLab en GET.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E19 — CloudNativePG : sauvegarde continue et restauration à un instant donné"
# Le cluster mediagenda-db-pitr doit encore exister au moment du check (étape 9 : à supprimer après).
require_cmd jq kubectl curl

_m16o_ns=mediagenda-recette
check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
_m16o_os="$(_m16o_kj get objectstores.barmancloud.cnpg.io cnpg-s3 -n "$_m16o_ns")"
check_cmd "ObjectStore cnpg-s3 : HTTPS vers s3-01, endpointCA, rétention 14d, serverName vide" _m16o_json "$_m16o_os" '
  (.spec.configuration.endpointURL | startswith("https://s3-01.par1.medisphere.internal:8333"))
  and (.spec.configuration.endpointCA.name // "") != ""
  and .spec.retentionPolicy == "14d" and ((.spec.configuration.serverName // "") == "")
  and (.spec.configuration.destinationPath | startswith("s3://cnpg-k8s-par1"))'
check_cmd "serverRecoveryWindow de mediagenda-db renseigné" _m16o_json "$_m16o_os" \
  '(.status.serverRecoveryWindow["mediagenda-db"].firstRecoverabilityPoint // "") != ""'
_m16o_cl="$(_m16o_kj get clusters.postgresql.cnpg.io mediagenda-db -n "$_m16o_ns")"
check_cmd "mediagenda-db : plugin Barman Cloud archiveur de WAL vers cnpg-s3, sans barmanObjectStore" _m16o_json "$_m16o_cl" '
  any(.spec.plugins[]?; .name == "barman-cloud.cloudnative-pg.io" and .isWALArchiver == true
      and .parameters.barmanObjectName == "cnpg-s3")
  and (.spec.backup.barmanObjectStore == null)'
check_cmd "mediagenda-db : archivage continu en état (ContinuousArchiving True)" _m16o_json "$_m16o_cl" \
  'any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")'
check_cmd "au moins une sauvegarde (Backup) par plugin terminée" \
  _m16o_json "$(_m16o_kj get backups.postgresql.cnpg.io -n "$_m16o_ns")" \
  'any(.items[]; .spec.cluster.name == "mediagenda-db" and .spec.method == "plugin" and .status.phase == "completed")'
check_cmd "ScheduledBackup mediagenda-db-quotidienne : six champs, méthode plugin" \
  _m16o_json "$(_m16o_kj get scheduledbackups.postgresql.cnpg.io mediagenda-db-quotidienne -n "$_m16o_ns")" '
  (.spec.schedule | split(" ") | map(select(. != "")) | length) == 6 and .spec.method == "plugin"
  and .spec.pluginConfiguration.name == "barman-cloud.cloudnative-pg.io" and .spec.cluster.name == "mediagenda-db"'
_m16o_pitr="$(_m16o_kj get clusters.postgresql.cnpg.io mediagenda-db-pitr -n "$_m16o_ns")"
check_cmd "mediagenda-db-pitr existe et a au moins une instance prête" _m16o_json "$_m16o_pitr" '(.status.readyInstances // 0) >= 1'
check_cmd "mediagenda-db-pitr : recovery depuis cnpg-s3 (serverName mediagenda-db), targetTime avec fuseau, sans archivage" \
  _m16o_json "$_m16o_pitr" '
  .spec.bootstrap.recovery.source as $s
  | (.spec.bootstrap.recovery.recoveryTarget.targetTime // "" | test("(Z|[+-][0-9]{2}(:?[0-9]{2})?)$"))
    and any(.spec.externalClusters[]; .name == $s and .plugin.name == "barman-cloud.cloudnative-pg.io"
            and .plugin.parameters.barmanObjectName == "cnpg-s3" and .plugin.parameters.serverName == "mediagenda-db")
    and ((.spec.plugins // []) | length == 0)'
check_cmd "sortie des pods CNPG vers s3-01 (10.10.20.14/32) sur le seul port 8333, pas de sortie « world »" \
  _m16o_json "$(_m16o_kj get ciliumnetworkpolicies.cilium.io -n "$_m16o_ns")" '
  [.items[] | select(.spec.endpointSelector | tostring | test("cnpg.io/cluster")) | .spec.egress[]?] as $r
  | any($r[]; (.toCIDR // []) == ["10.10.20.14/32"] and ([.toPorts[]?.ports[]?.port] == ["8333"]))
    and all($r[]; ((.toEntities // []) | index("world") == null and index("all") == null))'
check_cmd "journal : comparaison mediagenda-db / mediagenda-db-pitr et durée de restauration" \
  _m16o_journal_tout E19 10 'mediagenda-db-pitr' '([0-9]+ ?(s|min)|[0-9]+m[0-9]+s)'
check_cmd "RB-162 sur main de plateforme/medisphere (targetTime, réinjection)" bash -c '
  grep -q "targetTime" <<<"$1" && grep -qiE "r[ée]inject|COPY" <<<"$1"' _ \
  "$(_m16o_contenu_main "$_M16O_PROJET_DOC" docs/kubernetes/stockage/runbooks/RB-162-restaurer-postgresql-instant-donne.md)"
