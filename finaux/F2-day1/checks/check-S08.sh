# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S08.sh — F2-S08 « Traitements par lots et refacturation interne » : traitements de l'équipe Data
# en CronJob de classe medisphere-lot, requests déclarées, dernier passage réussi ; quota propre aux
# lots (portée par classe de priorité) ; règles d'enregistrement par locataire servies par Prometheus ;
# tableau de consommation par locataire dans Grafana ; rapport mensuel de refacturation publié.
# Lecture seule : kube (wb-checks), Prometheus, Grafana (Viewer), GitLab (GET).

# shellcheck source=_f2-equipes.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-equipes.sh"

title "F2-S08 — Traitements par lots et refacturation interne"
require_cmd jq curl kubectl

_s08_ns="$_f2b_ns_data"

# --- 1. Les traitements -----------------------------------------------------------------------------
_s08_cj="$(kube get cronjobs -n "$_s08_ns" -o json 2>/dev/null)" || _s08_cj='{"items":[]}'
_s08_lots() {
  jq -e '[.items[] | select(.spec.jobTemplate.spec.template.spec.priorityClassName == "medisphere-lot")] | length >= 1' \
    <<<"$_s08_cj" >/dev/null 2>&1
}
check_cmd "$_s08_ns : au moins un CronJob en classe medisphere-lot" _s08_lots
_s08_requests() {
  jq -e '[.items[] | select(.spec.jobTemplate.spec.template.spec.priorityClassName == "medisphere-lot")
          | .spec.jobTemplate.spec.template.spec.containers[]
          | select(((.resources.requests.cpu // "") == "") or ((.resources.requests.memory // "") == "")
                   or ((.resources.limits.memory // "") == ""))] | length == 0' <<<"$_s08_cj" >/dev/null 2>&1
}
check_cmd "$_s08_ns : les conteneurs des lots déclarent requests (CPU, mémoire) et limite mémoire" _s08_requests
_s08_reussi() {
  jq -e --argjson f "$_f2b_fraicheur" '
    any(.items[]; .spec.jobTemplate.spec.template.spec.priorityClassName == "medisphere-lot"
        and ((.status.lastSuccessfulTime // "1970-01-01T00:00:00Z") | fromdateiso8601) > (now - $f))' \
    <<<"$_s08_cj" >/dev/null 2>&1
}
check_cmd "$_s08_ns : un lot a réussi depuis moins de 36 h" _s08_reussi
_s08_quota_lots() {
  kube get resourcequotas -n "$_s08_ns" -o json 2>/dev/null | jq -e '
    any(.items[]; any(.spec.scopeSelector.matchExpressions[]?;
        .scopeName == "PriorityClass" and ((.values // []) | index("medisphere-lot")) != null))' >/dev/null 2>&1
}
check_cmd "$_s08_ns : un quota propre aux lots (portée PriorityClass medisphere-lot)" _s08_quota_lots

# --- 2. La mesure par locataire ---------------------------------------------------------------------
_s08_regles() {
  kube get prometheusrules.monitoring.coreos.com -A -o json 2>/dev/null |
    jq -e '[.items[].spec.groups[]?.rules[]? | .record // empty | select(startswith("locataire:"))] | length >= 4' >/dev/null 2>&1
}
check_cmd "PrometheusRule : au moins quatre règles d'enregistrement « locataire:… »" _s08_regles
for _s08_e in "${_f2b_equipes[@]}"; do
  check_cmd "Prometheus : CPU réservé par locataire servi pour $_s08_e (locataire:cpu_demande:somme)" \
    _f2b_prom_non_vide "locataire:cpu_demande:somme{locataire=\"$_s08_e\"}"
done
check_cmd "Prometheus : CPU consommé par locataire (locataire:cpu_utilise:taux5m)" \
  _f2b_prom_non_vide "locataire:cpu_utilise:taux5m{locataire=\"data\"}"
check_cmd "Prometheus : mémoire réservée et utilisée par locataire" \
  bash -c '[[ -n "$1" && -n "$2" ]]' _ \
  "$(_f2b_prom_val 'locataire:memoire_demandee:somme{locataire="data"}')" \
  "$(_f2b_prom_val 'locataire:memoire_utilisee:somme{locataire="data"}')"
check_cmd "Prometheus : stockage demandé par locataire (locataire:stockage_demande:somme)" \
  _f2b_prom_non_vide 'locataire:stockage_demande:somme{locataire="data"}'

# --- 3. Le tableau et le rapport --------------------------------------------------------------------
_s08_tableau() {
  grafana_api "dashboards/uid/$_f2b_tableau" 2>/dev/null |
    jq -e '[.dashboard.panels[]? | .. | objects | .expr? // empty | select(test("locataire:"))] | length >= 3' >/dev/null 2>&1
}
check_cmd "Grafana : tableau « $_f2b_tableau » (au moins trois requêtes sur les règles locataire:…)" _s08_tableau
_s08_rapport() {
  _f2b_doc "$_f2b_doc_dir"/mesures '^refacturation-[0-9]{4}-[0-9]{2}\.md$' "${_f2b_equipes[@]}" 'CPU' 'm[ée]moire' 'stockage'
}
check_cmd "rapport de refacturation docs/accueil/mesures/refacturation-AAAA-MM.md (locataires, CPU, mémoire, stockage)" _s08_rapport
check_cmd "RB-328 : production du rapport mensuel (docs/accueil/runbooks)" \
  _f2b_doc "$_f2b_doc_dir"/runbooks '^RB-328' 'showback|refacturation' 'locataire:'
