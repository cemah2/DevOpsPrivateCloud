# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E13.sh — M22-E13 « Rétention, locataires et limites » : compactor et rétention actifs, durées
# par locataire, surcharges rechargées, limites d'ingestion différenciées, effacement ouvert/fermé selon
# le locataire, demande d'effacement d'essai, politique et RB-221 publiés. Lecture seule.

# shellcheck source=_m22-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-production.sh"

title "M22-E13 — Rétention, locataires et limites"
require_cmd curl jq awk kubectl

if ! _m22p_pret; then
  skip "configuration de Loki" "Loki ne répond pas sur $_m22p_loki_url/ready (lab/bin/check 22 02)"
else
  check_output "compactor : rétention activée" '^true$' _m22p_config compactor.retention_enabled
  check_output "compactor : magasin des demandes d'effacement configuré" '^(s3|aws|filesystem|gcs|azure)$' \
    _m22p_config compactor.delete_request_store
  check_output "le compactor tourne (/services)" '^compactor => Running' _m22p_loki /services

  _m22_e13_retention_ok() {
    local fin
    fin="$(_m22p_metrique '^loki_compactor_apply_retention_last_successful_run_timestamp_seconds')"
    [[ "$fin" =~ ^[0-9]+$ ]] && ((fin > 0)) && (($(date +%s) - fin < 3 * 3600))
  }
  _m22_e13_demarre_depuis() {
    local d
    d="$(_m22p_metrique '^process_start_time_seconds')"
    [[ "$d" =~ ^[0-9]+$ ]] && (($(date +%s) - d > 1800))
  }
  if _m22_e13_demarre_depuis; then
    check_cmd "un passage de rétention a réussi il y a moins de 3 h" _m22_e13_retention_ok
  else
    skip "passage de rétention réussi" "loki-0 a démarré il y a moins de 30 min : relance plus tard"
  fi

  # Rétention et profondeur de requête par locataire (/config/tenant/v1/limits)
  _m22_e13_duree() { # LOCATAIRE CLÉ MIN MAX — la limite (en heures) est dans [MIN, MAX]
    local h
    h="$(_m22p_heures "$(_m22p_limite "$1" "$2")")"
    ((h >= $3 && h <= $4))
  }
  _m22_e13_profondeur() { # LOCATAIRE — 0 < max_query_lookback ≤ retention_period
    local r l
    r="$(_m22p_heures "$(_m22p_limite "$1" retention_period)")"
    l="$(_m22p_heures "$(_m22p_limite "$1" max_query_lookback)")"
    ((r > 0 && l > 0 && l <= r))
  }
  check_cmd "audit : rétention d'au moins 1 an" _m22_e13_duree audit retention_period 8760 9000
  check_cmd "mediagenda : rétention de 30 jours" _m22_e13_duree mediagenda retention_period 720 744
  check_cmd "medidoc : rétention de 30 jours" _m22_e13_duree medidoc retention_period 720 744
  check_cmd "plateforme : rétention de 14 jours" _m22_e13_duree plateforme retention_period 336 336
  for _m22_e13_t in audit mediagenda medidoc plateforme; do
    check_cmd "$_m22_e13_t : profondeur de requête bornée par la rétention" _m22_e13_profondeur "$_m22_e13_t"
  done

  check_output "surcharges par locataire rechargées avec succès" '^1$' \
    _m22p_metrique '^loki_runtime_config_last_reload_successful'

  if [[ -z "$(_m22p_runtime)" ]]; then
    skip "surcharges d'ingestion et d'effacement" "ConfigMap journaux/loki-runtime illisible pour le compte des checks"
  else
    _m22_e13_essai_contraint() {
      local e p
      e="$(_m22p_surcharge essai ingestion_rate_mb)"
      p="$(_m22p_surcharge plateforme ingestion_rate_mb)"
      awk -v e="$e" -v p="$p" 'BEGIN { exit !(e != "" && p != "" && e + 0 > 0 && e + 0 < p + 0) }' || return 1
      e="$(_m22p_surcharge essai max_global_streams_per_user)"
      p="$(_m22p_surcharge plateforme max_global_streams_per_user)"
      [[ "$e" =~ ^[0-9]+$ && "$p" =~ ^[0-9]+$ ]] && ((e > 0 && e < p))
    }
    check_cmd "essai : débit d'ingestion et nombre de flux inférieurs à ceux de plateforme" _m22_e13_essai_contraint
    check_output "audit : API d'effacement fermée (deletion_mode)" '^disabled$' _m22p_surcharge audit deletion_mode
    check_output "plateforme : API d'effacement fermée (deletion_mode)" '^disabled$' _m22p_surcharge plateforme deletion_mode
    for _m22_e13_t in mediagenda medidoc essai; do
      check_output "$_m22_e13_t : effacement ouvert (filter-and-delete)" '^filter-and-delete$' _m22p_surcharge "$_m22_e13_t" deletion_mode
    done
  fi

  check_output "audit : l'API d'effacement refuse le locataire (403)" '^403$' _m22p_code /loki/api/v1/delete audit
  _m22_e13_demande() { _m22p_loki /loki/api/v1/delete essai | jq -e 'length >= 1' >/dev/null 2>&1; }
  check_cmd "essai : au moins une demande d'effacement enregistrée" _m22_e13_demande
fi

check_cmd "politique-journaux.md publiée (main) : durées 1 an / 30 jours / 14 jours et effacement" \
  _m22p_doc docs/observabilite/journaux politique-journaux '365|1 an' '30 jours|30 j' '14 jours|14 j' 'effacement'
check_cmd "RB-221 publié (main) : demande, vérification, annulation" \
  _m22p_doc docs/observabilite/journaux RB-221 'delete' 'annul' 'v[ée]rif'
