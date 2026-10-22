# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E21.sh — M22-E21 « Panne : les requêtes expirent » : requêtes de référence sur 24 h et 7 jours,
# limites de requête saines pour chaque locataire, découpage actif, RB-224, panne close. Lecture seule.

# shellcheck source=_m22-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-expert.sh"

title "M22-E21 — Les requêtes répondent de nouveau"
require_cmd curl jq awk

if ! _m22p_pret; then
  skip "requêtes" "Loki ne répond pas sur $_m22p_loki_url/ready"
else
  _m22_e21_ok() { _m22p_requete plateforme "$1" "$2" "${3:-}" | jq -e '.http == 200 and .status == "success"' >/dev/null 2>&1; }
  check_cmd "tableau de Nadia : lignes par espace sur 24 h (locataire plateforme)" \
    _m22_e21_ok 'sum by (namespace) (count_over_time({namespace=~".+"}[10m]))' 24h
  check_cmd "requête sur 7 jours (pas de 1 h)" \
    _m22_e21_ok 'sum by (namespace) (count_over_time({namespace=~".+"}[1h]))' 168h 1h

  _m22_e21_limites() {
    local t="$1" qt ql qs
    qt="$(_m22p_secondes "$(_m22p_limite "$t" query_timeout)")"
    ql="$(_m22p_limite "$t" max_query_length)"
    qs="$(_m22p_limite "$t" max_query_series)"
    [[ -n "$ql" && "$qs" =~ ^[0-9]+$ ]] || return 1
    # délai ≥ 30 s ; durée maximale ≥ 7 jours (0 = sans limite) ; séries ≥ 100 (0 = sans limite)
    ((qt >= 30)) || return 1
    { [[ "$ql" == 0s || "$ql" == 0 ]] || (($(_m22p_heures "$ql") >= 168)); } || return 1
    ((qs == 0 || qs >= 100))
  }
  for _m22_e21_t in plateforme mediagenda medidoc audit; do
    check_cmd "$_m22_e21_t : limites de requête saines (délai ≥ 30 s, durée ≥ 7 j, séries ≥ 100)" _m22_e21_limites "$_m22_e21_t"
  done
  _m22_e21_decoupage() {
    [[ "$(_m22p_config limits_config.split_queries_by_interval)" =~ ^[1-9] ]] || return 1
    ! _m22p_runtime | grep -Eq 'split_queries_by_interval:[[:space:]]*"?0'
  }
  check_cmd "découpage des requêtes actif, et non désactivé pour un locataire" _m22_e21_decoupage
fi

check_cmd "RB-224 publié (main) : requêtes lentes ou en échec (limites, découpage, statistiques)" \
  _m22p_doc docs/observabilite/journaux RB-224 'query_timeout|d[ée]lai' 'max_query' 'stats|statistiques'
check_cmd "panne M22-E21 close (lab/bin/break 22 21 --annuler après réparation)" _m22x_aucune_panne_active E21
