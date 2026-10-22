# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions PromQL et filtres jq entre apostrophes
#
# check-E27.sh — M25-E27 « Superviser OpenBao » : job openbao à quatre cibles joignables avec
# vault_core_unsealed ; télémétrie lisible sans jeton sur chaque nœud ; règles chargées (les cinq de
# la fiche, l'instantané, la tolérance) ; tests promtool sur main et pipeline vert ; sonde du témoin
# verte sur la VIP ; tableau provisionné.
# À lancer depuis adm01. Lecture seule : Prometheus du cluster (vue globale), témoin de mon01,
# Grafana (Viewer), GitLab, /v1/sys/metrics des nœuds.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E27 — Superviser OpenBao"
require_cmd curl jq

check_output "job openbao : quatre cibles joignables (vault01-03, kms01)" '^4$' \
  _m25p_valeur 'count(up{job="openbao"} == 1)'
check_output "vault_core_unsealed présent pour les quatre cibles" '^4$' \
  _m25p_valeur 'count(max by (instance) (vault_core_unsealed{job="openbao"}))'

for _m25_e27_n in "${_M25P_NOEUDS[@]}" "$_M25P_KMS"; do
  check_output "$_m25_e27_n : /v1/sys/metrics?format=prometheus lisible sans jeton" '^vault_core_unsealed' \
    bash -c 'curl -s --max-time "$2" "$1/v1/sys/metrics?format=prometheus" | grep -E "^vault_core_unsealed"' _ \
    "$(_m25p_url "$_m25_e27_n")" "$WB_TIMEOUT"
done

_m25_e27_regles="$(prom_api 'rules?type=alert' 2>/dev/null || echo null)"
for _m25_e27_a in OpenBaoScelle OpenBaoSansLeader OpenBaoAuditEnEchec OpenBaoBauxNombreux CertificatServicesExpireBientot; do
  check_cmd "alerte $_m25_e27_a chargée" _m25p_jq "$_m25_e27_regles" 'any(.data.groups[].rules[]; .name == $n)' --arg n "$_m25_e27_a"
done
check_cmd "une alerte sur l'âge du dernier instantané est chargée" _m25p_jq "$_m25_e27_regles" \
  'any(.data.groups[].rules[]; .query | test("openbao_instantane"))'
check_cmd "une alerte sur la tolérance aux pannes d'autopilot est chargée" _m25p_jq "$_m25_e27_regles" \
  'any(.data.groups[].rules[]; .query | test("vault_autopilot_failure_tolerance"))'
check_cmd "l'alerte de nœud scellé regarde aussi up (un processus arrêté n'émet rien)" _m25p_jq "$_m25_e27_regles" \
  'any(.data.groups[].rules[]; .name == "OpenBaoScelle" and (.query | test("vault_core_unsealed")) and (.query | test("up\\b|up\\{")))'

_m25_e27_test="$(_m25p_arbre "$_M25P_OBS" tests | grep -Ei 'secrets|openbao' | head -n 1 || true)"
check_cmd "tests promtool des règles du coffre sur main de $_M25P_OBS (${_m25_e27_test:-aucun})" test -n "$_m25_e27_test"
_m25_e27_pipeline() {
  gitlab_api "projects/$(jq -rn --arg v "$_M25P_OBS" '$v|@uri')/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -e '.[0].status == "success"' >/dev/null 2>&1
}
check_cmd "dernier pipeline de main de $_M25P_OBS réussi (tests des règles compris)" _m25_e27_pipeline

check_output "témoin mon01 : la sonde de la VIP (sys/health) est verte" '^1$' \
  _m25p_temoin_valeur 'max(probe_success{instance=~".*openbao\\.par1\\.medisphere\\.internal.*sys/health.*"})'
check_output "témoin mon01 : les sondes des quatre nœuds existent et sont vertes" '^4$' \
  _m25p_temoin_valeur 'count(probe_success{instance=~".*(vault0[1-3]|kms01)\\.par1.*sys/health.*"} == 1)'
_m25_e27_tableau() { grafana_api "search?query=OpenBao&type=dash-db" 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1; }
check_cmd "tableau OpenBao provisionné dans Grafana" _m25_e27_tableau
