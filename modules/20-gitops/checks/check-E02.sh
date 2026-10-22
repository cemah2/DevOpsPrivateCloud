# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E02.sh — M20-E02 : Installer Argo CD par Helmfile
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks : pods, déploiements, ConfigMaps,
# HTTPRoute), DNS, GET HTTPS sur le serveur d'Argo CD, API GitLab en GET.

# shellcheck source=_m20-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-decouverte.sh"

title "M20-E02 — Installer Argo CD par Helmfile"
require_cmd jq kubectl curl dig

# --- 1. L'espace de noms ---------------------------------------------------------------------------
_m20d_e02_ns="$(_m20d_k get namespace "$_M20D_NS" -o json)"
check_cmd "Espace argocd : Pod Security « restricted » appliqué (enforce)" _m20d_json "$_m20d_e02_ns" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"'
check_cmd "Espace argocd : étiquette medisphere.internal/exposition=oui (routes admises par gw-par1)" \
  _m20d_json "$_m20d_e02_ns" '.metadata.labels["medisphere.internal/exposition"] == "oui"'
check_cmd "Espace argocd : pas d'étiquette d'équipe (ce n'est pas un espace applicatif)" \
  _m20d_json "$_m20d_e02_ns" '(.metadata.labels // {}) | has("medisphere.internal/equipe") | not'

# --- 2. Les composants -----------------------------------------------------------------------------
_m20d_e02_dep="$(_m20d_k -n "$_M20D_NS" get deployments -o json)"
_m20d_e02_sts="$(_m20d_k -n "$_M20D_NS" get statefulsets -o json)"
for _m20d_e02_d in argocd-server argocd-repo-server argocd-redis argocd-applicationset-controller argocd-notifications-controller; do
  check_cmd "Deployment $_m20d_e02_d : 1 réplica demandé, prêt" _m20d_json "$_m20d_e02_dep" \
    '[.items[] | select(.metadata.name == $d)] | length == 1 and
     (.[0].spec.replicas == 1) and ((.[0].status.readyReplicas // 0) == 1)' --arg d "$_m20d_e02_d"
done
check_cmd "StatefulSet argocd-application-controller : 1 réplica, prêt" _m20d_json "$_m20d_e02_sts" \
  '[.items[] | select(.metadata.name == "argocd-application-controller")] | length == 1 and
   (.[0].spec.replicas == 1) and ((.[0].status.readyReplicas // 0) == 1)'
check_cmd "Dex absent (pas de SSO avant le M24)" _m20d_json "$_m20d_e02_dep" \
  '[.items[] | select(.metadata.name | test("dex"))] | length == 0'
check_cmd "Composants installés par la release Helm « argocd » (annotations meta.helm.sh)" _m20d_json "$_m20d_e02_dep" \
  '[.items[] | select(.metadata.name == "argocd-server")][0].metadata.annotations["meta.helm.sh/release-name"] == "argocd"'
check_cmd "Chart argo-cd 10.10.x (étiquette helm.sh/chart)" _m20d_json "$_m20d_e02_dep" \
  '[.items[] | select(.metadata.name == "argocd-server")][0].metadata.labels["helm.sh/chart"] | test("^argo-cd-10\\.10\\.")'

_m20d_e02_pods="$(_m20d_k -n "$_M20D_NS" get pods -o json)"
check_cmd "Toutes les images des pods d'argocd viennent de Harbor (registry.par1.medisphere.internal/)" \
  _m20d_json "$_m20d_e02_pods" \
  '[.items[] | .spec.containers[], (.spec.initContainers // [])[] | .image] | length > 0
   and all(startswith("registry.par1.medisphere.internal/"))'
check_cmd "Argo CD en 3.5.x (image du serveur, PLAN §6)" _m20d_json "$_m20d_e02_dep" \
  '[.items[] | select(.metadata.name == "argocd-server")][0].spec.template.spec.containers[0].image
   | split(":") | last | test($re)' --arg re "$_M20D_VERSION_RE"
check_cmd "Aucun pod d'argocd en redémarrage en boucle (moins de 5 redémarrages par conteneur)" \
  _m20d_json "$_m20d_e02_pods" '[.items[].status.containerStatuses[]?.restartCount] | all(. < 5)'

# --- 3. Configuration ------------------------------------------------------------------------------
_m20d_e02_params="$(_m20d_k -n "$_M20D_NS" get configmap argocd-cmd-params-cm -o json)"
check_cmd "argocd-cmd-params-cm : server.insecure = true (TLS terminé à la Gateway)" _m20d_json "$_m20d_e02_params" \
  '.data["server.insecure"] == "true"'
_m20d_e02_tls="$(_m20d_k -n "$_M20D_NS" get configmap argocd-tls-certs-cm -o json)"
check_cmd "argocd-tls-certs-cm : certificat de confiance pour git01.par1.medisphere.internal" _m20d_json "$_m20d_e02_tls" \
  '.data["git01.par1.medisphere.internal"] // "" | test("BEGIN CERTIFICATE")'
check_cmd "argocd-cm : URL publique https://${_M20D_ARGOCD_HOTE}" _m20d_json \
  "$(_m20d_k -n "$_M20D_NS" get configmap argocd-cm -o json)" '.data.url == $u' --arg u "https://${_M20D_ARGOCD_HOTE}"

# --- 4. Exposition ---------------------------------------------------------------------------------
_m20d_e02_route="$(_m20d_k -n "$_M20D_NS" get httproutes.gateway.networking.k8s.io -o json)"
check_cmd "HTTPRoute vers argocd-server, nom ${_M20D_ARGOCD_HOTE}, écouteur https de passerelles/gw-par1" \
  _m20d_json "$_m20d_e02_route" \
  '[.items[] | select((.spec.hostnames // []) | index($h))
    | select(any(.spec.parentRefs[]; .name == "gw-par1" and .namespace == "passerelles" and .sectionName == "https"))
    | select(any(.spec.rules[].backendRefs[]?; .name == "argocd-server"))] | length == 1' --arg h "$_M20D_ARGOCD_HOTE"
check_cmd "HTTPRoute acceptée par gw-par1, références résolues" _m20d_json "$_m20d_e02_route" \
  '[.items[] | select((.spec.hostnames // []) | index($h)) | .status.parents[]?
    | select(.parentRef.name == "gw-par1")
    | ([.conditions[] | select((.type == "Accepted" or .type == "ResolvedRefs") and .status == "True")] | length == 2)]
   | any' --arg h "$_M20D_ARGOCD_HOTE"
check_dns "DNS : ${_M20D_ARGOCD_HOTE} → 10.10.41.10 (gw-par1)" "$_M20D_ARGOCD_HOTE" A '^10\.10\.41\.10$'
check_http "https://${_M20D_ARGOCD_HOTE}/healthz répond 200 (certificat vérifié)" "$_M20D_ARGOCD_URL/healthz" 200
check_output "L'interface web est servie (page HTML d'Argo CD)" 'Argo CD' \
  curl -sf --max-time "${WB_TIMEOUT:-5}" "$_M20D_ARGOCD_URL/"

# --- 5. Le code ------------------------------------------------------------------------------------
for _m20d_e02_f in releases/argocd.yaml.gotmpl composants/argocd/values.yaml espaces/argocd.yaml; do
  check_cmd "plateforme/k8s (main) : $_m20d_e02_f" _m20d_fichier_main plateforme/k8s "$_m20d_e02_f"
done
check_output "releases/argocd.yaml.gotmpl : chart argo/argo-cd épinglé en 10.10.x" '^[[:space:]]*version:[[:space:]]*"?10\.10\.[0-9]+' \
  _m20d_contenu_main plateforme/k8s releases/argocd.yaml.gotmpl
