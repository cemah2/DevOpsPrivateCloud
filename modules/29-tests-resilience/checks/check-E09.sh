# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E09.sh — M29-E09 : Chaos Mesh : installer avec des garde-fous
# À lancer depuis adm01. Lecture seule : Application Argo CD, objets de chaos-mesh et de
# chaos-experiences, espaces et leurs annotations, ValidatingAdmissionPolicy (compte wb-checks,
# wb-checks-services-m29), fichiers de plateforme/medisphere sur main.

# shellcheck source=_m29-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-operationnel.sh"

title "M29-E09 — Chaos Mesh : installer avec des garde-fous"
require_cmd jq curl kubectl

# --- 1. Installation par Argo CD ----------------------------------------------------------------------
_m29o_e09_app="$(_m29d_k get applications.argoproj.io -n argocd chaos-mesh -o json)"
check_cmd "Application chaos-mesh : chart 2.8.x tiré de Harbor (charts/), projet plateforme" _m29d_json "$_m29o_e09_app" \
  '.spec.project == "plateforme" and any((.spec.sources // [.spec.source])[]; (.repoURL | test("registry\\.par1\\.medisphere\\.internal/charts")) and .chart == "chaos-mesh" and (.targetRevision | startswith("2.8.")))'
check_cmd "Application chaos-mesh : synchronisée et saine" _m29d_json "$_m29o_e09_app" \
  '.status.sync.status == "Synced" and .status.health.status == "Healthy"'
check_cmd "Application chaos-mesh : application côté serveur (CRD > 256 Kio)" _m29d_json "$_m29o_e09_app" \
  '.spec.syncPolicy.syncOptions // [] | index("ServerSideApply=true") != null'

_m29o_e09_ctl="$(_m29d_k get deployment -n chaos-mesh chaos-controller-manager -o json)"
_m29o_e09_env() { _m29d_json "$_m29o_e09_ctl" 'any(.spec.template.spec.containers[].env[]?; .name == $n and .value == $v)' --arg n "$1" --arg v "$2"; }
check_cmd "GARDE-FOU : filtre d'espaces actif (ENABLE_FILTER_NAMESPACE=true)" _m29o_e09_env ENABLE_FILTER_NAMESPACE true
check_cmd "GARDE-FOU : webhook validate-auth actif (SECURITY_MODE=true)" _m29o_e09_env SECURITY_MODE true
check_cmd "contrôleur prêt, image du cache Harbor" _m29d_json "$_m29o_e09_ctl" \
  '(.status.readyReplicas // 0) >= 1 and all(.spec.template.spec.containers[]; .image | startswith("registry.par1.medisphere.internal/"))'
_m29o_e09_ds="$(_m29d_k get daemonset -n chaos-mesh chaos-daemon -o json)"
check_cmd "chaos-daemon : runtime containerd, un pod prêt par nœud" _m29d_json "$_m29o_e09_ds" \
  '(((.spec.template.spec.containers[0].command // []) + (.spec.template.spec.containers[0].args // [])) | index("containerd")) != null and .status.numberReady == .status.desiredNumberScheduled and .status.numberReady >= 1'
check_cmd "pas de tableau de bord ni de serveur DNS de Chaos Mesh" _m29d_json \
  "$(_m29d_k get deployments -n chaos-mesh -o json)" '[.items[].metadata.name | select(test("dashboard|dns-server"))] | length == 0'

# --- 2. Espaces : exception écrite et liste fermée ------------------------------------------------------
_m29o_e09_ns="$(_m29d_k get namespaces -o json)"
check_cmd "espace chaos-mesh : PSA privileged (exception écrite), restricted en audit et avertissement" _m29d_json "$_m29o_e09_ns" \
  'any(.items[]; .metadata.name == "chaos-mesh" and .metadata.labels["pod-security.kubernetes.io/enforce"] == "privileged"
     and .metadata.labels["pod-security.kubernetes.io/warn"] == "restricted" and (.metadata.annotations["medisphere.internal/exception-psa"] // "") != "")'
check_cmd "espace chaos-experiences : restricted" _m29d_json "$_m29o_e09_ns" \
  'any(.items[]; .metadata.name == "chaos-experiences" and .metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted")'
_m29o_e09_annotes="$(jq -c '[.items[] | select(.metadata.annotations["chaos-mesh.org/inject"] == "enabled") | .metadata.name]' <<<"${_m29o_e09_ns:-{\}}" 2>/dev/null || echo '[]')"
check_cmd "espaces annotés chaos-mesh.org/inject=enabled ⊆ {mediagenda-recette, medinotif-recette, wb-essais} : $_m29o_e09_annotes" \
  _m29d_json "$_m29o_e09_annotes" '(. - $ok) == [] and index("mediagenda-recette") != null' --argjson ok "$_M29O_ESPACES_CHAOS"
check_cmd "aucun espace *-prod ni messagerie annoté" _m29d_json "$_m29o_e09_annotes" 'all(.[]; (test("-prod$") or . == "messagerie") | not)'
check_cmd "quota d'objets de chaos dans chaos-experiences" _m29d_json "$(_m29d_k get resourcequota -n "$_M29O_CHAOS_NS" -o json)" \
  'any(.items[]; .spec.hard | keys | any(startswith("count/") and endswith(".chaos-mesh.org")))'

# --- 3. VAP : la liste fermée tenue par le cluster --------------------------------------------------
_m29o_e09_vap="$(_m29d_k get validatingadmissionpolicies.admissionregistration.k8s.io medisphere-chaos-espaces -o json)"
check_cmd "VAP medisphere-chaos-espaces : espaces ET objets chaos-mesh.org surveillés" _m29d_json "$_m29o_e09_vap" \
  '[.spec.matchConstraints.resourceRules[].apiGroups[]] | (index("") != null and index("chaos-mesh.org") != null)'
check_cmd "VAP medisphere-chaos-espaces : liaison en Deny" _m29d_json \
  "$(_m29d_k get validatingadmissionpolicybindings.admissionregistration.k8s.io medisphere-chaos-espaces -o json)" \
  '.spec.validationActions | index("Deny") != null'
check_cmd "VAP hostPath : chemins de chaos-daemon déclarés pour l'espace chaos-mesh" _m29d_json \
  "$(_m29d_k get configmap -n kube-system medisphere-hostpath -o json)" '(.data["chaos-mesh"] // "") | test("/run/containerd")'

# --- 4. Première expérience -----------------------------------------------------------------------------
if [[ -n "${_M29_MINI_PROJET:-}" ]]; then
  skip "PodChaos e09-pod-failure-api" "mini-projet : l'expérience a pu être supprimée depuis M29-E09"
else
  _m29o_e09_exp="$(_m29d_k get podchaos -n "$_M29O_CHAOS_NS" e09-pod-failure-api -o json)"
  check_cmd "PodChaos e09-pod-failure-api : pod-failure, une durée, mediagenda-recette seulement" _m29d_json "$_m29o_e09_exp" \
    '.spec.action == "pod-failure" and (.spec.duration // "") != "" and .spec.selector.namespaces == ["mediagenda-recette"]'
  check_cmd "PodChaos e09-pod-failure-api : un pod a été visé puis rétabli (Selected et AllRecovered)" _m29d_json "$_m29o_e09_exp" \
    '[.status.conditions[]? | select(.status == "True") | .type] as $c | ($c | index("Selected")) != null and ($c | index("AllRecovered")) != null'
fi
check_cmd "aucun objet de chaos hors de chaos-experiences" _m29d_json \
  "$(_m29d_k get podchaos,networkchaos,stresschaos,iochaos,timechaos,schedules,workflows -A -o json)" \
  'all(.items[]; .metadata.namespace == $ns)' --arg ns "$_M29O_CHAOS_NS"

# --- 5. Documentation ---------------------------------------------------------------------------------
_m29o_e09_rb="$(_m29d_arbre "$_M29D_P_DOC" docs/qualite/runbooks | grep -E '/RB-292-[^/]+\.md$' || true)"
check_cmd "plateforme/medisphere : RB-292 (arrêt d'urgence du chaos)" bash -c '[[ -n "$1" ]]' _ "$_m29o_e09_rb"
check_cmd "registre des exceptions : EXC-K-005 (PSA de chaos-mesh)" \
  _m29d_contient "$_M29D_P_DOC" docs/securite/durcissement/exceptions.md 'EXC-K-005.*chaos-mesh'
