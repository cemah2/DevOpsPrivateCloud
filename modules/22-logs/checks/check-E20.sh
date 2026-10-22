# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E20.sh — M22-E20 « Panne : Loki refuse les écritures » : Loki prêt, écritures reçues par
# locataire, aucun rejet ni échec de vidage récents, lectures du stockage sur 24 h, limites d'ingestion
# et de flux saines, RB-223, panne close. Lecture seule.

# shellcheck source=_m22-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-expert.sh"

title "M22-E20 — Loki accepte de nouveau les écritures"
require_cmd curl jq

if ! _m22p_pret; then
  skip "écritures et lectures" "Loki ne répond pas sur $_m22p_loki_url/ready"
else
  check_cmd "plateforme : des lignes reçues ces 5 dernières minutes" _m22x_lignes_recentes plateforme '{namespace=~".+"}' 5m
  check_cmd "mediagenda : des lignes reçues ces 10 dernières minutes" _m22x_lignes_recentes mediagenda '{namespace=~"mediagenda-.+"}' 10m
  check_cmd "audit : des lignes reçues ces 10 dernières minutes" _m22x_audit_recent 10m
  _m22_e20_stockage() {
    _m22p_requete plateforme 'sum(count_over_time({namespace=~".+"}[1h]))' 24h 1h | jq -e '.http == 200 and .status == "success"' >/dev/null 2>&1
  }
  check_cmd "lecture du stockage : requête sur 24 h sans erreur" _m22_e20_stockage

  _m22_e20_prom() {
    local rc=0
    _m22x_prom_zero "$1" || rc=$?
    return "$rc"
  }
  _m22_e20_rc=0
  _m22x_prom_zero 'sum(increase(loki_discarded_samples_total[10m]))' >/dev/null 2>&1 || _m22_e20_rc=$?
  if ((_m22_e20_rc == 2)); then
    skip "rejets et échecs de vidage" "Prometheus ne collecte pas Loki (pas de loki_build_info) : lab/bin/check 22 02"
  else
    check_cmd "aucune ligne rejetée par Loki ces 10 dernières minutes (loki_discarded_samples_total)" \
      _m22_e20_prom 'sum(increase(loki_discarded_samples_total[10m]))'
    check_cmd "aucun échec de vidage de chunks ces 15 dernières minutes" \
      _m22_e20_prom 'sum(increase(loki_ingester_chunks_flush_failures_total[15m]))'
  fi

  if [[ -n "$(_m22p_runtime)" ]]; then
    _m22_e20_debit() {
      local v
      v="$(_m22p_surcharge "$1" ingestion_rate_mb)"
      awk -v v="$v" 'BEGIN { exit !(v != "" && v + 0 >= 1) }'
    }
    for _m22_e20_t in plateforme mediagenda medidoc; do
      check_cmd "$_m22_e20_t : débit d'ingestion d'au moins 1 Mo/s" _m22_e20_debit "$_m22_e20_t"
    done
    _m22_e20_flux() {
      local actifs limite
      actifs="$(_m22p_metrique '^loki_ingester_memory_streams\{.*tenant="plateforme"')"
      [[ "$actifs" == absent ]] && actifs=0
      limite="$(_m22p_surcharge plateforme max_global_streams_per_user)"
      [[ "$limite" =~ ^[0-9]+$ ]] && ((limite > 2 * actifs))
    }
    check_cmd "plateforme : limite de flux au moins deux fois supérieure aux flux actifs" _m22_e20_flux
  else
    skip "limites d'ingestion" "ConfigMap journaux/loki-runtime illisible pour le compte des checks"
  fi

  if kube -n wb-pannes get deployment journal-temoin >/dev/null 2>&1; then
    check_cmd "le témoin journal-temoin (wb-pannes) est bien dans Loki" \
      _m22x_lignes_recentes plateforme '{namespace="wb-pannes"} |= "journal-temoin"' 5m
  fi
fi

check_cmd "RB-223 publié (main) : 429, limites, identifiants du stockage" \
  _m22p_doc docs/observabilite/journaux RB-223 '429' 'ingestion_rate|limite' 'S3|RGW|compartiment'
check_cmd "panne M22-E20 close (lab/bin/break 22 20 --annuler après réparation)" _m22x_aucune_panne_active E20
