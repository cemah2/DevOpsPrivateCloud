# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions PromQL entre apostrophes
#
# check-E13.sh — M21-E13 : Relabeling, maîtriser les étiquettes
# À lancer depuis adm01. Lecture seule : Prometheus du cluster.

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E13 — Relabeling : maîtriser les étiquettes"
require_cmd jq curl

for _m21o_e13_env in dev recette prod; do
  check_cmd "MédiAgenda $_m21o_e13_env : séries étiquetées equipe=mediagenda, environnement=$_m21o_e13_env, site=par1" \
    _m21o_au_moins "count(mediagenda_http_requests_total{equipe=\"mediagenda\", environnement=\"$_m21o_e13_env\", site=\"par1\"})" 1
done
check_cmd "MédiAgenda : aucune série sans equipe ni environnement" \
  _m21o_vide 'mediagenda_http_requests_total{equipe=""} or mediagenda_http_requests_total{environnement=""}'
check_cmd "MédiDoc : séries étiquetées equipe=medidoc avec un environnement" \
  _m21o_au_moins 'count(medidoc_http_requests_total{equipe="medidoc", environnement!=""})' 1

check_cmd "MédiAgenda : plus aucun seau d'histogramme pour /sante, /pret, /metrics" \
  _m21o_vide 'mediagenda_http_request_duration_seconds_bucket{route=~"/sante|/pret|/metrics"}'
check_cmd "MédiAgenda : les seaux des routes de l'API sont toujours collectés" \
  _m21o_au_moins 'count(mediagenda_http_request_duration_seconds_bucket{route!~"/sante|/pret|/metrics"})' 1
check_cmd "MédiDoc : plus aucun seau d'histogramme pour les routes de sonde" \
  _m21o_vide 'medidoc_http_request_duration_seconds_bucket{route=~"GET /(healthz|readyz|metrics)"}'

check_cmd "cibles du chart (kubelet) : toutes ont une étiquette equipe" \
  _m21o_vide 'up{job="kubelet", equipe=""}'
check_cmd "kubelet : equipe=plateforme posée par la classe de collecte" \
  _m21o_au_moins 'count(up{job="kubelet", equipe="plateforme"})' 1
check_cmd "ScrapeConfig d'E10 (ceph, haproxy) : toutes les cibles ont une étiquette equipe" \
  _m21o_vide 'up{job=~"ceph|haproxy", equipe=""}'
_m21o_e13_config() { prom_api "status/config" 2>/dev/null | jq -r '.data.yaml // empty' 2>/dev/null || true; }
check_output "Prometheus du cluster : étiquette externe site=\"par1\" conservée" 'site: par1' _m21o_e13_config
