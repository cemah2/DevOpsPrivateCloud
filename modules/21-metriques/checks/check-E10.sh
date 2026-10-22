# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions PromQL et filtres jq entre apostrophes
#
# check-E10.sh — M21-E10 : Exportateurs natifs (Ceph, HAProxy, PowerDNS, Kea, GitLab, Harbor)
# À lancer depuis adm01. Lecture seule : Prometheus du cluster, objets ScrapeConfig (« kube »),
# requêtes HTTP en GET vers les exportateurs (MGMT joint tout le lab).

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E10 — Exportateurs natifs : Ceph, HAProxy, PowerDNS, Kea, GitLab, Harbor"
require_cmd jq kubectl curl

# Cibles : job et nombre minimal de cibles attendues.
for _m21o_e10_j in ceph:3 haproxy:5 powerdns-autoritaire:2 powerdns-recurseur:2 gitlab-rails:1 \
  gitlab-exporter:1 gitlab-sidekiq:1 gitlab-workhorse:1 gitlab-gitaly:1 harbor:4; do
  check_cmd "job ${_m21o_e10_j%%:*} : au moins ${_m21o_e10_j##*:} cible(s), toutes joignables (up == 1)" \
    _m21o_job_up "${_m21o_e10_j%%:*}" "${_m21o_e10_j##*:}"
done

_m21o_e10_sc="$(_m21o_k get scrapeconfigs.monitoring.coreos.com -n "$_M21O_NS" -o json)"
check_cmd "les ScrapeConfig de supervision portent ces jobs et l'étiquette de sélection" _m21o_json "$_m21o_e10_sc" '
  [.items[] | select(.metadata.labels["medisphere.internal/supervision"] == "oui") | .spec.jobName // empty] as $j
  | ["ceph","haproxy","powerdns-autoritaire","powerdns-recurseur","gitlab-rails","harbor"] | all(. as $x | $j | index($x) != null)'

# Ceph : le mgr ACTIF seul sert les métriques ; les autres répondent sans série.
check_cmd "ceph_health_status présent une seule fois (mgr actif ; pas de doublon, pas d'absence)" \
  _m21o_au_moins 'count(ceph_health_status) == 1' 1
# HAProxy : les deux répartiteurs et les trois nœuds de contrôle exposent l'état de leurs serveurs.
check_cmd "haproxy_server_status vient de 5 instances (lb01, lb02, k8s-cp01-03)" \
  _m21o_au_moins 'count(count by (instance) (haproxy_server_status{job="haproxy"}))' 5

# Le frontend de métriques ne sert QUE /metrics (adm01 est autorisé : on teste un autre chemin).
check_http "lb01:8405 ne sert pas autre chose que /metrics (404 attendu sur /)" \
  "http://lb01.par1.medisphere.internal:8405/" 404
check_output "lb01:8405/metrics renvoie les métriques d'HAProxy" '^haproxy_process_' \
  curl -s --max-time "$WB_TIMEOUT" http://lb01.par1.medisphere.internal:8405/metrics
# L'API d'écriture de PowerDNS exige toujours la clé (401 sans clé), même depuis un client autorisé.
check_http "API de PowerDNS (dns01:8081) refusée sans clé d'API (401)" \
  "http://dns01.par1.medisphere.internal:8081/api/v1/servers/localhost/zones" 401

check_output "inventaire ~/m21/e10/inventaire.md : Kea traité (natif ou non, solution retenue)" '[Kk]ea' \
  cat "$_M21O_TRAVAIL/e10/inventaire.md"
