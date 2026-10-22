# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E24.sh — M23-E24 « Sous le capot : spans, contexte et OTLP » : livrable présent et étayé. Lecture seule.

# shellcheck source=_m23-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-production.sh"

title "M23-E24 — Sous le capot : spans, contexte et OTLP"
require_cmd jq curl

_m23_e24_doc=docs/observabilite/traces
check_cmd "livrable sous-le-capot.md : traceparent décomposé (version, trace-id, parent-id, drapeaux)" \
  _m23p_doc "$_m23_e24_doc" sous-le-capot '00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}' 'trace-?id' 'parent'
check_cmd "livrable : message OTLP décrit (resourceSpans, scopeSpans, spans)" \
  _m23p_doc "$_m23_e24_doc" sous-le-capot 'resourceSpans' 'scopeSpans'
check_cmd "livrable : bloc Tempo lu dans tempo-k8s-par1 (UUID de bloc, meta.json, vParquet)" \
  _m23p_doc "$_m23_e24_doc" sous-le-capot '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' 'meta\.json' 'vParquet[45]'
check_cmd "livrable : sorties de tempo-cli (list blocks, view schema ou list column)" \
  _m23p_doc "$_m23_e24_doc" sous-le-capot 'tempo-cli (list blocks|view schema|list column|query)'
check_cmd "livrable : chemin d'une span de l'application jusqu'au bloc (live-store, WAL ou bloc)" \
  _m23p_doc "$_m23_e24_doc" sous-le-capot 'live-store' 'WAL|wal'
_m23_e24_s3="$HOME/.config/workbook/s3-tempo.env"
if [[ -r "$_m23_e24_s3" ]]; then
  check_cmd "compartiment tempo-k8s-par1 : blocs présents (lecture avec s3-tempo.env)" _m23p_compartiment_non_vide "$_m23_e24_s3" tempo-k8s-par1
else
  skip "compartiment tempo-k8s-par1" "identité de lecture absente : $_m23_e24_s3"
fi
