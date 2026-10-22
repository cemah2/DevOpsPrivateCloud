# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions PromQL et filtres jq entre apostrophes
#
# check-E14.sh — M21-E14 : Recording rules et cardinalité
# À lancer depuis adm01. Lecture seule : Prometheus du cluster, objets PrometheusRule et
# ServiceMonitor (« kube »), GitLab.

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E14 — Recording rules et cardinalité"
require_cmd jq kubectl curl

_m21o_e14_pr="$(_m21o_k get prometheusrules.monitoring.coreos.com -n "$_M21O_NS" -o json)"
for _m21o_e14_n in enregistrement-mediagenda enregistrement-medidoc; do
  check_cmd "PrometheusRule $_m21o_e14_n présente, avec l'étiquette de sélection" _m21o_json "$_m21o_e14_pr" \
    --arg n "$_m21o_e14_n" 'any(.items[]; .metadata.name == $n and .metadata.labels["medisphere.internal/supervision"] == "oui")'
done
_m21o_e14_r="$(_m21o_regles record)"
for _m21o_e14_g in mediagenda.enregistrement medidoc.enregistrement; do
  check_cmd "groupe $_m21o_e14_g chargé et sain (aucune erreur à la dernière évaluation)" _m21o_json "$_m21o_e14_r" \
    --arg g "$_m21o_e14_g" '[.data.groups[] | select(.name == $g)] as $x
      | ($x | length) == 1 and ($x[0].rules | length) >= 4 and ($x[0].rules | all(.health == "ok" and ((.lastError // "") == "")))'
done
check_cmd "environnement:mediagenda_requetes:taux5m : au moins deux environnements" \
  _m21o_au_moins 'count(environnement:mediagenda_requetes:taux5m)' 2
check_cmd "environnement:mediagenda_duree_requetes:p95_5m : au moins deux environnements" \
  _m21o_au_moins 'count(environnement:mediagenda_duree_requetes:p95_5m)' 2

# sampleLimit du moniteur de MédiAgenda : posée, et au-dessus de ce qui est collecté aujourd'hui.
_m21o_e14_sm="$(_m21o_k get servicemonitors.monitoring.coreos.com -A -o json)"
_m21o_e14_limite="$(jq -r '[.items[] | select(.metadata.name == "mediagenda" and (.metadata.namespace | startswith("mediagenda-"))) | .spec.sampleLimit // 0] | min // 0' <<<"$_m21o_e14_sm" 2>/dev/null || echo 0)"
_m21o_e14_max="$(_m21o_valeur 'max(scrape_samples_scraped{job="mediagenda"})')"
_m21o_e14_limite_ok() {
  [[ "${_m21o_e14_limite:-0}" =~ ^[0-9]+$ ]] && (( _m21o_e14_limite > 0 )) && [[ -n "$_m21o_e14_max" ]] \
    && awk -v l="$_m21o_e14_limite" -v m="$_m21o_e14_max" 'BEGIN { exit !(l + 0 > m + 0) }'
}
check_cmd "ServiceMonitor mediagenda : sampleLimit posée dans chaque espace (${_m21o_e14_limite:-0}) et supérieure au volume collecté (${_m21o_e14_max:-?})" \
  _m21o_e14_limite_ok
check_output "plateforme/observabilite : test promtool des règles d'enregistrement sur main" 'enregistrement' \
  _m21o_arbre "$_M21O_P_OBS" tests
