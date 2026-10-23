# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E16.sh — M28-E16 « Backstage en production » : deux réplicas prêts sur deux nœuds, PDB, sondes
# du nouveau backend ; image = dernière étiquette de plateforme/portail et backstage.json modifié ;
# portail-db archivée avec une sauvegarde récente ; métriques, alertes, journaux ; RB-284. Lecture seule.

# shellcheck source=_m28-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-production.sh"

title "M28-E16 — Backstage en production"
require_cmd kubectl jq curl

_m28_e16_deux_noeuds() {
  kube -n portail get pods -l app.kubernetes.io/name=backstage -o json 2>/dev/null | jq -e '
    [.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True")) | .spec.nodeName] | unique | length >= 2' >/dev/null 2>&1
}
_m28_e16_image_derniere() {
  local img tag
  img="$(kube -n portail get deploy portail -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)" || return 1
  tag="$(gitlab_api 'projects/plateforme%2Fportail/repository/tags?order_by=updated&per_page=1' 2>/dev/null | jq -r '.[0].name // empty')" || return 1
  [[ -n "$tag" && "$img" == *":$tag"* ]]
}
_m28_e16_bump() {
  gitlab_api 'projects/plateforme%2Fportail/repository/commits?path=backstage.json&per_page=5' 2>/dev/null |
    jq -e 'length >= 2' >/dev/null 2>&1
}
_m28_e16_sauvegarde() {
  local depuis
  depuis="$(date -u -d '-26 hours' +%Y-%m-%dT%H:%M:%SZ)"
  kube -n portail get backups.postgresql.cnpg.io -o json 2>/dev/null | jq -e --arg d "$depuis" '
    [.items[] | select(.spec.cluster.name == "portail-db" and .status.phase == "completed"
                       and ((.status.stoppedAt // .metadata.creationTimestamp) >= $d))] | length >= 1' >/dev/null 2>&1
}

if _m28p_api_repond; then
  check_cmd "Deployment portail : au moins 2 réplicas prêts" _m28p_kq '(.status.readyReplicas // 0) >= 2' -n portail deploy portail
  check_cmd "pods du portail prêts sur au moins deux nœuds" _m28_e16_deux_noeuds
  check_cmd "sondes du nouveau backend (/.backstage/health/v1/readiness et liveness)" _m28p_kq '
    .spec.template.spec.containers[0] | (.readinessProbe.httpGet.path == "/.backstage/health/v1/readiness")
      and (.livenessProbe.httpGet.path == "/.backstage/health/v1/liveness")' -n portail deploy portail
  check_cmd "un PDB protège le portail" _m28p_kq '(.items | length) >= 1' -n portail poddisruptionbudgets
  check_cmd "image déployée = dernière étiquette de plateforme/portail" _m28_e16_image_derniere
  check_cmd "portail-db : archivage continu par le plugin Barman Cloud" _m28p_kq '
    any(.spec.plugins[]?; .name == "barman-cloud.cloudnative-pg.io" and .isWALArchiver == true)
    and any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")' -n portail clusters.postgresql.cnpg.io portail-db
  check_cmd "portail-db : une sauvegarde completed de moins de 26 h" _m28_e16_sauvegarde
  check_cmd "portail-db : sauvegarde planifiée (ScheduledBackup)" _m28p_kq \
    '[.items[] | select(.spec.cluster.name == "portail-db")] | length >= 1' -n portail scheduledbackups.postgresql.cnpg.io
else
  skip "portail et portail-db dans le cluster" "l'API ne répond pas au compte des checks"
fi
check_cmd "backstage.json modifié sur main depuis la création (montée de version)" _m28_e16_bump

if _m28p_prom_repond; then
  check_cmd "Prometheus collecte le portail (cible up hors base)" _m28p_prom_vrai 'sum(up{namespace="portail", job!~".*db.*"})'
  check_cmd "alerte « portail indisponible » chargée" _m28p_alerte_chargee 'Portail.*Indisponible|Backstage.*Down'
  check_cmd "alerte « sauvegarde de portail-db trop ancienne » chargée" _m28p_alerte_chargee 'Portail.*Sauvegarde|portail.*backup'
else
  skip "métriques et alertes du portail" "Prometheus ne répond pas"
fi
_m28_e16_journaux() {
  loki_requete '{namespace="portail"}' plateforme 15m 2>/dev/null | jq -e '[.data.result[]?.values[]?] | length > 0' >/dev/null 2>&1
}
check_cmd "Loki reçoit les journaux du portail (15 min)" _m28_e16_journaux
check_cmd "RB-284 publié (main) : diagnostic par étage, retour arrière, restauration" \
  _m28p_doc RB-284 'Gateway|HTTPRoute' 'restaur' 'revert|retour arri'
