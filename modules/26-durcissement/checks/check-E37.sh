# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M26-E37 « Falco est muet » : Falco couvre tous les nœuds, règles MédiSphère actives,
# sortie vers le bon Alertmanager, priorité raisonnable, Loki reçoit, pipeline vert, panne close. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E37 — Falco détecte et achemine de nouveau"
require_cmd jq yq kubectl curl

_e37_couvre_noeuds() {
  _m26x_kq '.status.desiredNumberScheduled == (.status.numberReady // 0)
            and (.spec.template.spec.nodeSelector // {} | has("node-role.kubernetes.io/control-plane") | not)
            and .status.desiredNumberScheduled > 1' -n "$_m26x_ns_falco" daemonset falco
}
_e37_priorite_ok() {
  ! kube -n "$_m26x_ns_falco" get configmap -o json 2>/dev/null |
    jq -e '[.items[].data["falco.yaml"] // "" | select(test("(?m)^priority: *(critical|emergency|alert)"))] | length > 0' >/dev/null 2>&1
}
# L'URL vit dans les valeurs (plateforme/gitops) ; dans le cluster, elle est dans un Secret que le
# compte des checks ne lit pas : on contrôle la source, et la synchronisation de l'Application falco.
_e37_sidekick_ok() {
  _m26x_git_brut plateforme/gitops valeurs/falco/values.yaml |
    yq -e '.falcosidekick.config.alertmanager.hostport | test("kps-alertmanager\\.supervision(\\.svc)?(\\.cluster\\.local)?:9093$")' >/dev/null 2>&1 &&
    _m26x_app_ok falco
}
# Au moins une détection de la règle « shell interactif » arrivée dans Loki depuis 1 h (l'essai rejoué).
_e37_loki_ok() {
  loki_requete '{service="falco"} |~ "(?i)shell interactif"' audit 1h 2>/dev/null |
    jq -e '.status == "success" and ([.data.result[]?.values[]?] | length > 0)' >/dev/null 2>&1
}

check_cmd "le DaemonSet Falco couvre tous les nœuds" _e37_couvre_noeuds
check_cmd "la règle « shell interactif dans un conteneur applicatif » est chargée et active" \
  _m26x_regle_falco_active 'shell interactif dans un conteneur'
check_cmd "la priorité minimale de Falco laisse passer les règles MédiSphère" _e37_priorite_ok
check_cmd "falcosidekick joint l'Alertmanager du cluster" _e37_sidekick_ok
check_cmd "un essai récent (moins d'1 h) est arrivé dans Loki (service=falco, locataire audit)" _e37_loki_ok
check_cmd "pipeline de main de plateforme/politiques vert" _m26x_pipeline_main_vert plateforme/politiques
check_cmd "RB-260 : section « Falco est muet »" _m26x_doc_contient "$_m26x_rb/RB-260-*.md" '(muet|ne d[ée]tecte|aucune alerte)'
check_cmd "panne M26-E37 close" _m26x_aucune_panne_active E37
