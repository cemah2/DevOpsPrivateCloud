# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E14.sh — M29-E14 « k6-operator : tests distribués et non-régression de performance » :
# Application k6-operator, espace k6 (restricted, quota), image par Harbor, TestRun distribué versionné,
# séries k6 dans Prometheus, écriture distante restreinte à k6, tableau, référence, pipeline planifié,
# RB-295. Lecture seule.

# shellcheck source=_m29-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-production.sh"

title "M29-E14 — k6-operator et non-régression de performance"
require_cmd kubectl jq curl yq

if _m29p_api_repond; then
  check_cmd "Application Argo CD k6-operator : Synced et Healthy" _m29p_app_saine k6-operator
  check_cmd "espace k6 : Pod Security « restricted » imposé" _m29p_kq \
    '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"' namespace k6
  check_cmd "espace k6 : un ResourceQuota" _m29p_kq '.items | length >= 1' -n k6 resourcequotas
  check_cmd "k6-operator : contrôleur prêt, image tirée de registry.par1.medisphere.internal" _m29p_kq \
    'any(.items[]; (.status.readyReplicas // 0) >= 1 and all(.spec.template.spec.containers[]; .image | startswith("registry.par1.medisphere.internal/")))' \
    -n k6 deployments
  if kube get testruns.k6.io -n k6 -o name >/dev/null 2>&1; then
    check_cmd "aucun TestRun de k6 en erreur" _m29p_kq '[.items[] | select(.status.stage == "error")] | length == 0' -n k6 testruns.k6.io
  else
    skip "TestRun dans le cluster" "le compte des checks ne lit pas k6.io (ClusterRole wb-checks-services-m29, M29-E09)"
  fi
else
  skip "k6-operator dans le cluster" "l'API ne répond pas au compte des checks"
fi

# TestRun versionné (le nettoyage « post » supprime l'objet en fin d'essai : on vérifie le manifeste).
_m29_e14_docs="$(_m29p_yaml_json "$_m29p_resilience" charge)" || true
[[ -n "$_m29_e14_docs" ]] || _m29_e14_docs='[]'
_m29_e14_testrun() {
  jq -e 'any(.[]; .kind == "TestRun" and (.spec.parallelism // 0) >= 4 and (.spec.script.configMap.name // "") != ""
           and ((.spec.runner.image // "") | startswith("registry.par1.medisphere.internal/"))
           and (.spec.runner.containerSecurityContext.allowPrivilegeEscalation == false)
           and (.spec.cleanup // "") == "post")' >/dev/null 2>&1 <<<"$_m29_e14_docs"
}
check_cmd "charge/ (main) : un TestRun parallelism ≥ 4, script en ConfigMap, image Harbor, durci, cleanup post" _m29_e14_testrun

check_cmd "Prometheus : séries k6_http_req_duration_* étiquetées par testid (7 j)" _m29p_prom_non_vide \
  'count by (testid) (count_over_time({__name__=~"k6_http_req_duration_.+", testid!=""}[7d]))'

if _m29p_api_repond; then
  _m29_e14_cnp_k6() {
    kube get ciliumnetworkpolicies.cilium.io -n supervision -o json 2>/dev/null | jq -e '
      any(.items[]; any(.spec.ingress[]?;
        any(.fromEndpoints[]?; .matchLabels["k8s:io.kubernetes.pod.namespace"] == "k6" and .matchLabels.runner == "true")
        and any(.toPorts[]?.rules.http[]?; .path == "/api/v1/write")))' >/dev/null 2>&1
  }
  _m29_e14_cnp_large() {
    # Aucune règle n'ouvre /api/v1/write depuis une entité large ou un sélecteur vide.
    kube get ciliumnetworkpolicies.cilium.io -n supervision -o json 2>/dev/null | jq -e '
      [.items[].spec.ingress[]? | select(any(.toPorts[]?.rules.http[]?; .path == "/api/v1/write"))
       | select(((.fromEntities // []) | length) > 0 or any(.fromEndpoints[]?; (.matchLabels // {}) == {} and (.matchExpressions // []) == []))]
      | length == 0' >/dev/null 2>&1
  }
  check_cmd "supervision : une CiliumNetworkPolicy ouvre POST /api/v1/write aux seuls exécuteurs de k6" _m29_e14_cnp_k6
  check_cmd "supervision : aucune règle n'ouvre /api/v1/write à une entité ou à tout le cluster" _m29_e14_cnp_large
else
  skip "politiques réseau de supervision" "l'API ne répond pas au compte des checks"
fi

_m29_e14_tableau() { grafana_api "dashboards/uid/m29-charge-k6" 2>/dev/null | jq -e '.dashboard.uid == "m29-charge-k6" and (.dashboard | tostring | test("testid"))' >/dev/null 2>&1; }
check_cmd "Grafana : le tableau m29-charge-k6 filtre par testid" _m29_e14_tableau

_m29_e14_reference() {
  _m29p_fichier_main "$_m29p_resilience" charge/references/mediagenda-recette.json 2>/dev/null |
    jq -e '(.p95_s // .p95 // null) != null and (.taux_erreurs // .erreurs // null) != null' >/dev/null 2>&1
}
check_cmd "charge/references/mediagenda-recette.json : p95 et taux d'erreurs de référence" _m29_e14_reference
check_cmd "plateforme/resilience : dernier pipeline PLANIFIÉ réussi" _m29p_pipeline_ok "$_m29p_resilience" schedule
check_cmd "RB-295 publié (main) : non-régression de performance" _m29p_doc docs/qualite '^RB-295' 'r[ée]f[ée]rence' 'testid|Prometheus'
