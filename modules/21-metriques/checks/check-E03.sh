# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E03.sh — M21-E03 : Explorer Prometheus : cibles, séries et étiquettes
# À lancer depuis adm01. Lecture seule : API GitLab (fichiers sur main), API de Prometheus.

# shellcheck source=_m21-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-decouverte.sh"

title "M21-E03 — Explorer Prometheus : cibles, séries et étiquettes"
require_cmd jq curl

# --- 1. Le compte rendu d'exploration ---------------------------------------------------------------
_m21d_e03_doc="$(_m21d_contenu_main plateforme/medisphere docs/observabilite/metriques/exploration.md)"
if [[ -z "$_m21d_e03_doc" ]]; then
  _ko "plateforme/medisphere : docs/observabilite/metriques/exploration.md absent de main"
else
  _ok "plateforme/medisphere : docs/observabilite/metriques/exploration.md présent sur main"
  # Le compte rendu répond aux questions de l'énoncé : on y cherche les notions, pas des phrases.
  check_output "exploration.md : découverte de services et étiquettes avant/après relabeling" \
    '(__meta_kubernetes|__address__)' printf '%s' "$_m21d_e03_doc"
  check_output "exploration.md : page TSDB Status (séries de tête, cardinalité)" \
    '([Hh]ead|[Tt]ête).{0,40}([Ss]éries|[Ss]eries)|prometheus_tsdb_head_series|numSeries' printf '%s' "$_m21d_e03_doc"
  check_output "exploration.md : configuration générée par l'opérateur (Secret prometheus-kps, ou page /config)" \
    'prometheus-kps|/config|configuration générée' printf '%s' "$_m21d_e03_doc"
  check_output "exploration.md : chiffres relevés (nombre de cibles et de séries)" '[0-9]{3,}' printf '%s' "$_m21d_e03_doc"
fi

# --- 2. Les requêtes d'exploration --------------------------------------------------------------------
_m21d_controler_fichier_promql plateforme/observabilite requetes/E03.promql 6
