# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E14.sh — M28-E14 « Capacité et équité » : classes de priorité (ordre, lot sans préemption),
# locataires (classes autorisées et par défaut, budget global), production en medisphere-critique avec
# PDB, script de recommandations VPA et MR, tableau de bord, capacite.md. Lecture seule.

# shellcheck source=_m28-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-production.sh"

title "M28-E14 — Capacité et équité"
require_cmd kubectl jq curl

_m28_e14_prio() {
  kube get priorityclasses -o json 2>/dev/null | jq -e '
    ([.items[] | {(.metadata.name): .}] | add) as $p
    | $p["medisphere-critique"] and $p["medisphere-standard"] and $p["medisphere-lot"]
    and $p["medisphere-critique"].value > $p["medisphere-standard"].value
    and $p["medisphere-standard"].value > $p["medisphere-lot"].value
    and $p["medisphere-lot"].preemptionPolicy == "Never"
    and ([.items[] | select(.globalDefault == true)] | length) <= 1' >/dev/null 2>&1
}

if _m28p_api_repond; then
  check_cmd "classes medisphere-critique > -standard > -lot, lot sans préemption, au plus une globalDefault" _m28_e14_prio
  for _m28_e14_t in mediagenda medinotif medidoc; do
    check_cmd "locataire $_m28_e14_t : classes autorisées et classe par défaut" _m28p_tenant "$_m28_e14_t" \
      '(.spec.priorityClasses.allowed // [] | length) > 0 and (.spec.priorityClasses.default // "") != ""'
    check_cmd "locataire $_m28_e14_t : budget global sur TOUS ses espaces (règle quota sans namespaceSelector)" _m28p_tenant "$_m28_e14_t" \
      '[.spec.rules[]? | select((.quota // []) | length > 0) | select((.namespaceSelector // null) == null)] | length >= 1'
  done
  check_cmd "locataire medidoc : medisphere-critique non autorisée (pas de production)" _m28p_tenant medidoc \
    '(.spec.priorityClasses.allowed // []) | index("medisphere-critique") == null'
  check_cmd "mediagenda-prod : pods de l'API en medisphere-critique" _m28p_pods_prio mediagenda-prod app.kubernetes.io/name=mediagenda medisphere-critique
  check_cmd "medinotif-prod : pods en medisphere-critique" _m28p_pods_prio medinotif-prod app.kubernetes.io/name=medinotif medisphere-critique
  check_cmd "mediagenda-prod : base mediagenda-db en medisphere-critique" _m28p_kq '.spec.priorityClassName == "medisphere-critique"' \
    -n mediagenda-prod clusters.postgresql.cnpg.io mediagenda-db
  for _m28_e14_ns in mediagenda-prod medinotif-prod; do
    check_cmd "$_m28_e14_ns : au moins un PDB qui permet une éviction" _m28p_kq \
      '(.items | length) > 0 and any(.items[]; (.status.disruptionsAllowed // 0) >= 1)' -n "$_m28_e14_ns" poddisruptionbudgets
  done
else
  skip "classes, locataires, production" "l'API ne répond pas au compte des checks"
fi

check_cmd "plateforme/k8s : outils/recommandations-vpa.sh sur main" \
  _m28p_fichier_contient plateforme/k8s outils/recommandations-vpa.sh 'verticalpodautoscaler|vpa' 'recommendation'
check_cmd "plateforme/k8s : une MR de recommandations du VPA a été ouverte" _m28p_mr_existe plateforme/k8s 'vpa|recommandation'
_m28_e14_tableau() { grafana_api "search?query=Capacit" 2>/dev/null | jq -e 'length >= 1' >/dev/null 2>&1; }
check_cmd "Grafana : tableau « Capacité et locataires »" _m28_e14_tableau
check_cmd "capacite.md (main) : bilan, budgets, priorités" _m28p_doc capacite 'budget' 'priorit' 'pr[ée]empt'
