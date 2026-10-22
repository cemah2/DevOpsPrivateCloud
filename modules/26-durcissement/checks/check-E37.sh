# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M26-E37 « Falco est muet » : Falco couvre tous les nœuds, règles MédiSphère actives,
# sortie vers le bon Alertmanager, priorité raisonnable, Loki reçoit, pipeline vert, panne close. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E37 — Falco détecte et achemine de nouveau"
require_cmd jq kubectl curl

_e37_couvre_noeuds() {
  _m26x_kq '.status.desiredNumberScheduled == (.status.numberReady // 0)
            and (.spec.template.spec.nodeSelector // {} | has("node-role.kubernetes.io/control-plane") | not)
            and .status.desiredNumberScheduled > 1' -n "$_m26x_ns_falco" daemonset falco
}
_e37_priorite_ok() {
  ! kube -n "$_m26x_ns_falco" get configmap -o json 2>/dev/null |
    jq -e '[.items[].data["falco.yaml"] // "" | select(test("(?m)^priority: *(critical|emergency|alert)"))] | length > 0' >/dev/null 2>&1
}
_e37_sidekick_ok() {
  kube -n "$_m26x_ns_falco" get deploy,cm -o json 2>/dev/null | grep -q 'kps-alertmanager.supervision:9093' &&
    ! kube -n "$_m26x_ns_falco" get deploy,cm -o json 2>/dev/null | grep -q ':9095'
}
_e37_loki_ok() { loki_requete '{service="falco"}' audit 1h 2>/dev/null | jq -e '.status == "success"' >/dev/null 2>&1; }

check_cmd "le DaemonSet Falco couvre tous les nœuds (aucun exclu par nodeSelector)" _e37_couvre_noeuds
check_cmd "la règle « shell interactif dans un conteneur applicatif » est chargée et active" \
  _m26x_regle_falco_active 'Shell interactif dans un conteneur'
check_cmd "la priorité minimale chargée n'est pas remontée à « critical »" _e37_priorite_ok
check_cmd "falcosidekick pointe vers l'Alertmanager du cluster (9093, pas 9095)" _e37_sidekick_ok
check_cmd "le locataire audit de Loki répond pour service=falco" _e37_loki_ok
check_cmd "pipeline de main de plateforme/politiques vert" _m26x_pipeline_main_vert plateforme/politiques
check_cmd "RB-260 : section « Falco est muet »" _m26x_doc_contient "$_m26x_rb/RB-260-*.md" '(muet|ne d[ée]tecte|aucune alerte)'
check_cmd "panne M26-E37 close" _m26x_aucune_panne_active E37
