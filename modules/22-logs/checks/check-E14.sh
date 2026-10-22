# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E14.sh — M22-E14 « Performance de Loki et cardinalité des étiquettes » : étiquettes de la liste
# fermée, flux actifs sous la moitié de la limite, découpage et cache des requêtes, requête sur 7 jours,
# performance.md, alerte de cardinalité chargée. Lecture seule.

# shellcheck source=_m22-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-production.sh"

title "M22-E14 — Performance et cardinalité"
require_cmd curl jq awk

if ! _m22p_pret; then
  skip "Loki" "Loki ne répond pas sur $_m22p_loki_url/ready (lab/bin/check 22 02)"
else
  for _m22_e14_t in plateforme mediagenda medidoc audit; do
    check_cmd "$_m22_e14_t : aucune étiquette hors de la liste fermée (dernière heure)" _m22p_etiquettes_fermees "$_m22_e14_t"
  done

  # Flux actifs < 50 % de max_global_streams_per_user (surcharge du locataire ou valeur globale)
  _m22_e14_flux_ok() {
    local actifs limite
    actifs="$(_m22p_metrique "^loki_ingester_memory_streams\\{.*tenant=\"$1\"")"
    [[ "$actifs" == absent ]] && actifs=0
    limite="$(_m22p_runtime | _m22p_yaml "overrides.$1.max_global_streams_per_user")"
    [[ -n "$limite" ]] || limite="$(_m22p_config limits_config.max_global_streams_per_user)"
    [[ "$limite" =~ ^[0-9]+$ ]] && ((limite > 0 && actifs * 2 < limite))
  }
  for _m22_e14_t in plateforme mediagenda medidoc audit; do
    check_cmd "$_m22_e14_t : flux actifs sous la moitié de la limite de flux" _m22_e14_flux_ok "$_m22_e14_t"
  done

  _m22_e14_decoupage() {
    local h
    h="$(_m22p_heures "$(_m22p_config limits_config.split_queries_by_interval)")"
    [[ "$(_m22p_config limits_config.split_queries_by_interval)" =~ ^[1-9] ]] && ((h <= 24))
  }
  check_cmd "découpage des requêtes actif (split_queries_by_interval entre 1 min et 24 h)" _m22_e14_decoupage
  check_output "cache des résultats activé (query_range.cache_results)" '^true$' _m22p_config query_range.cache_results

  _m22_e14_nadia() {
    _m22p_requete plateforme 'sum by (namespace) (count_over_time({namespace=~".+"} |= "ERROR" [1h]))' 168h 1h |
      jq -e '.http == 200 and .status == "success"' >/dev/null 2>&1
  }
  check_cmd "requête par espace sur 7 jours (pas de 1 h) : réponse en moins de 60 s" _m22_e14_nadia
fi

check_cmd "performance.md publié (main) : flux mesurés, seuils, réglages" \
  _m22p_doc docs/observabilite/journaux performance 'flux' 'seuil' 'split_queries_by_interval|d[ée]coupage'

_m22_e14_alerte() {
  prom_api rules 2>/dev/null |
    jq -e '[.data.groups[].rules[] | select(.type == "alerting") | select(.query | test("loki_ingester_memory_streams"))] | length >= 1' >/dev/null 2>&1
}
check_cmd "une alerte sur les flux actifs de Loki (loki_ingester_memory_streams) est chargée dans Prometheus" _m22_e14_alerte
