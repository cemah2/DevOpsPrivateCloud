# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E22.sh — M22-E22 « Panne : les journaux d'une équipe ont disparu » : journaux de MédiAgenda et
# MédiDoc dans LEUR locataire et pas dans celui de la plateforme, profondeur de requête de MédiDoc
# égale à sa rétention, source Grafana « Loki — mediagenda » qui renvoie des données, RB-222 (locataires),
# panne close. Lecture seule.

# shellcheck source=_m22-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-expert.sh"

title "M22-E22 — Chaque équipe retrouve ses journaux"
require_cmd curl jq

if ! _m22p_pret; then
  skip "affectation des locataires" "Loki ne répond pas sur $_m22p_loki_url/ready"
else
  check_cmd "mediagenda : journaux récents des espaces mediagenda-* dans le locataire mediagenda" \
    _m22x_lignes_recentes mediagenda '{namespace=~"mediagenda-.+"}' 10m
  _m22_e22_rien_chez_plateforme() { (($(_m22p_nb_lignes plateforme '{namespace=~"(mediagenda|medidoc)-.+"}' 10m) == 0)); }
  check_cmd "plateforme : aucune ligne des espaces mediagenda-* ou medidoc-* (10 dernières minutes)" _m22_e22_rien_chez_plateforme
  _m22_e22_profondeur() {
    local l r
    l="$(_m22p_limite medidoc max_query_lookback)"
    r="$(_m22p_limite medidoc retention_period)"
    [[ -n "$l" && -n "$r" ]] || return 1
    [[ "$l" == 0s ]] || (($(_m22p_heures "$l") >= $(_m22p_heures "$r")))
  }
  check_cmd "medidoc : la profondeur de requête couvre toute la rétention" _m22_e22_profondeur
fi

_m22_e22_uid="$(grafana_api frontend/settings 2>/dev/null | jq -r '.datasources["Loki — mediagenda"].uid // empty' 2>/dev/null || true)"
if [[ -z "$_m22_e22_uid" ]]; then
  skip "source Grafana « Loki — mediagenda »" "introuvable avec le compte Viewer des checks (lab/bin/check 22 02)"
else
  _m22_e22_grafana() {
    grafana_api "datasources/proxy/uid/$_m22_e22_uid/loki/api/v1/query_range?query=$(jq -rn '"count_over_time({namespace=~\"mediagenda-.+\"}[10m])" | @uri')&since=10m&limit=10" 2>/dev/null |
      jq -e '.status == "success" and (.data.result | length > 0)' >/dev/null 2>&1
  }
  check_cmd "Grafana : la source « Loki — mediagenda » renvoie les journaux récents de MédiAgenda" _m22_e22_grafana
fi

check_cmd "RB-222 publié (main) : section sur l'affectation des locataires" \
  _m22p_doc docs/observabilite/journaux RB-222 'locataire' 'X-Scope-OrgID|tenant'
check_cmd "panne M22-E22 close (lab/bin/break 22 22 --annuler après réparation)" _m22x_aucune_panne_active E22
