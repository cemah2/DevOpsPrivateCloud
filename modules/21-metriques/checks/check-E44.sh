# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c ou sur mon01
# shellcheck source-path=SCRIPTDIR
# check-E44.sh — M21-E44 « Sous le capot : WAL, blocs et chunks » : compte rendu présent, structuré, chiffré
# et commité ; instantané retiré du disque de mon01 ; API d'administration du témoin refermée ; aucune
# API d'administration ouverte dans le cluster. Lecture seule.

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E44 — Sous le capot : WAL, blocs et chunks"
require_cmd git jq curl

_m21_e44_cr="$_m21x_depot/docs/observabilite/metriques/analyses/tsdb-sous-le-capot.md"
check_cmd "compte rendu docs/observabilite/metriques/analyses/tsdb-sous-le-capot.md présent" test -s "$_m21_e44_cr"
check_output "section sur le WAL et la tête (head block)" '^## .*(WAL|t[êe]te|head)' cat "$_m21_e44_cr"
check_output "section sur les blocs (meta.json, index, chunks, tombstones)" '^## .*[Bb]locs?' cat "$_m21_e44_cr"
check_output "section sur la compaction et la rétention" '^## .*[Cc]ompaction' cat "$_m21_e44_cr"
check_output "section sur l'analyse (promtool tsdb analyze)" '^## .*([Aa]nalyse|cardinalit)' cat "$_m21_e44_cr"
check_output "section « Réponses aux questions »" '^## Réponses aux questions' cat "$_m21_e44_cr"
check_cmd "notions citées : WAL, checkpoint, chunks_head, meta.json, ULID, compaction, promtool tsdb" \
  bash -c 'for m in WAL checkpoint chunks_head meta.json ULID compaction "promtool tsdb"; do grep -qi -- "$m" "$1" || exit 1; done' _ "$_m21_e44_cr"
check_cmd "chiffres relevés : un identifiant de bloc (ULID) réel et un nombre de séries" \
  bash -c 'grep -Eq "\b01[0-9A-HJKMNP-TV-Z]{24}\b" "$1" && grep -Eqi "s[ée]ries[^0-9]{0,40}[0-9]{3,}|[0-9]{3,}[^0-9]{0,20}s[ée]ries" "$1"' _ "$_m21_e44_cr"
check_cmd "compte rendu commité, sans modification en attente" \
  bash -c 'cd "$1" && git ls-files --error-unmatch docs/observabilite/metriques/analyses/tsdb-sous-le-capot.md >/dev/null 2>&1 && [ -z "$(git status --porcelain -- docs/observabilite/metriques/analyses)" ]' _ "$_m21x_depot"

if _m21x_mon01 'true'; then
  check_cmd "mon01 : plus aucun instantané dans le répertoire de données du témoin (snapshots/ vide)" \
    _m21x_mon01 "$_M21X_UNITE"'
u="$(unite_de prometheus)" && d="$(option_de "$u" storage.tsdb.path)" && [ -n "$d" ] && [ -d "$d" ] &&
{ [ ! -d "$d/snapshots" ] || [ -z "$(ls -A "$d/snapshots")" ]; }'
else
  skip "instantanés sur mon01" "SSH + sudo -n vers $_m21x_mon01 impossible depuis ce poste"
fi
check_cmd "mon01 : API d'administration du témoin refermée après l'exercice (web.enable-admin-api = false)" \
  bash -c 'curl -sf --max-time 5 "http://$1:9090/api/v1/status/flags" | jq -e ".data[\"web.enable-admin-api\"] == \"false\"" >/dev/null' \
  _ "${_m21x_mon01}.par1.medisphere.internal"
check_cmd "cluster : aucune API d'administration TSDB ouverte (enableAdminAPI)" \
  _m21x_kq '[.items[].spec.enableAdminAPI // false] | all(. == false)' -n supervision prometheuses.monitoring.coreos.com
