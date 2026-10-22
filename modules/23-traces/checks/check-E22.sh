# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E22.sh — M23-E22 « Panne : impossible de passer d'une trace à ses journaux » : liens Tempo ↔ Loki
# cohérents (source servie par Grafana), journaux porteurs de trace_id. Lecture seule.

# shellcheck source=_m23-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-expert.sh"

title "M23-E22 — De la trace aux journaux, et retour"
require_cmd jq curl

_m23_e22_lien_tempo() {
  local s cible
  s="$(_m23p_settings)"
  cible="$(jq -r '[.datasources[]? | select(.type == "tempo") | .jsonData.tracesToLogsV2.datasourceUid // empty][0] // empty' <<<"$s")"
  [[ -n "$cible" ]] || return 1
  jq -e --arg u "$cible" '[.datasources[]? | select(.type == "loki" and .uid == $u and ((.name | test("plateforme|audit"; "i")) | not))] | length == 1' >/dev/null <<<"$s"
}
check_cmd "Tempo → Loki : tracesToLogsV2 désigne une source Loki existante d'un locataire applicatif" _m23_e22_lien_tempo
_m23_e22_lien_loki() {
  _m23p_settings | jq -e --arg t "$(_m23p_tempo_uid)" '[.datasources[]? | select(.type == "loki" and (.name | test("mediagenda"; "i")))
     | .jsonData.derivedFields[]? | select(.datasourceUid == $t and ((.matcherRegex // "") | test("trace_id")))] | length >= 1' >/dev/null 2>&1
}
check_cmd "Loki (mediagenda) → Tempo : champ dérivé sur trace_id vers la source Tempo" _m23_e22_lien_loki
_m23_e22_lignes() {
  loki_requete '{namespace="mediagenda-dev"} | trace_id != ""' mediagenda 15m 2>/dev/null |
    jq -e '[.data.result[]?.values[]?] | length > 0' >/dev/null 2>&1
}
check_cmd "journaux de mediagenda-dev porteurs d'un trace_id (15 min, locataire mediagenda)" _m23_e22_lignes
check_cmd "runbook RB-233 « Plus de lien trace ↔ journaux » publié" \
  _m23p_doc "$_m23x_runbooks" RB-233 'tracesToLogs' 'derivedFields|champ d[ée]riv' 'X-Scope-OrgID|locataire'
check_cmd "panne M23-E22 close (lab/bin/break 23 22 --annuler après réparation)" _m23x_aucune_panne_active E22
