# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E08.sh — M19-E08 : construire des images dans le cluster, BuildKit rootless partagé
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks : Deployment, pods, Service,
# objets cert-manager et Cilium ; jamais les Secrets), API Harbor et GitLab en GET.

# shellcheck source=_m19-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-decouverte.sh"

title "M19-E08 — Construire des images dans le cluster : BuildKit rootless partagé"
require_cmd jq curl kubectl

# --- 1. Le démon ----------------------------------------------------------------------------------
check_cmd "Deployment buildkit/buildkitd prêt, image rootless de Harbor épinglée par empreinte" _m19d_json \
  "$(_m19d_kj -n buildkit get deployment buildkitd)" '
  (.status.readyReplicas // 0) >= 1
  and any(.spec.template.spec.containers[];
          (.image | startswith("registry.par1.medisphere.internal/dockerhub/moby/buildkit:"))
          and (.image | test("rootless@sha256:[0-9a-f]{64}$")))'
check_cmd "Service buildkit/buildkitd sur le port 1234" _m19d_json "$(_m19d_kj -n buildkit get service buildkitd)" \
  'any(.spec.ports[]; .port == 1234)'
for _m19d_e08_ns in buildkit ci-jobs; do
  check_cmd "aucun conteneur privilégié dans l'espace $_m19d_e08_ns (pods présents)" _m19d_json \
    "$(_m19d_kj -n "$_m19d_e08_ns" get pods)" '
    [.items[] | (.spec.containers + (.spec.initContainers // []))[] | select(.securityContext.privileged == true)] | length == 0'
done
check_cmd "le conteneur buildkitd tourne sous un UID non nul, sans mode privilégié" _m19d_json \
  "$(_m19d_kj -n buildkit get deployment buildkitd)" '
  (.spec.template.spec.securityContext.runAsUser // 0) as $p
  | all(.spec.template.spec.containers[]; (.securityContext.privileged // false) == false
        and ((.securityContext.runAsUser // $p) > 0))'

# --- 2. TLS mutuel (objets cert-manager, pas leurs Secrets) ----------------------------------------
check_cmd "ClusterIssuer buildkit-ca prête (autorité CA)" _m19d_json \
  "$(_m19d_kj get clusterissuers.cert-manager.io buildkit-ca)" \
  '.spec.ca.secretName != null and any(.status.conditions[]?; .type == "Ready" and .status == "True")'
for _m19d_e08_c in "buildkit buildkitd-serveur" "ci-jobs buildkit-client"; do
  read -r _m19d_e08_ns _m19d_e08_nom <<<"$_m19d_e08_c"
  check_cmd "certificat $_m19d_e08_ns/$_m19d_e08_nom prêt, émis par la ClusterIssuer buildkit-ca" _m19d_json \
    "$(_m19d_kj -n "$_m19d_e08_ns" get certificates.cert-manager.io "$_m19d_e08_nom")" '
    .spec.issuerRef.name == "buildkit-ca" and (.spec.issuerRef.kind // "Issuer") == "ClusterIssuer"
    and any(.status.conditions[]?; .type == "Ready" and .status == "True")'
done
check_cmd "certificat serveur : nom du Service buildkitd.buildkit.svc.cluster.local" _m19d_json \
  "$(_m19d_kj -n buildkit get certificates.cert-manager.io buildkitd-serveur)" \
  '(.spec.dnsNames // []) | index("buildkitd.buildkit.svc.cluster.local") != null'

# --- 3. Politique réseau -----------------------------------------------------------------------------
check_cmd "CiliumNetworkPolicy dans buildkit : entrée réservée aux pods des espaces de jobs" _m19d_json \
  "$(_m19d_kj -n buildkit get ciliumnetworkpolicies.cilium.io)" '
  any(.items[]; (.spec.ingress // []) | length > 0
      and all(.[]; ((.fromEntities // []) | length == 0) and ((.fromCIDR // []) | length == 0)
                   and ((.fromEndpoints // []) | length > 0)
                   and all(.fromEndpoints[]; (.matchLabels["k8s:io.kubernetes.pod.namespace"] // "")
                                             | test("^ci-jobs(-protege)?$"))))
  and any(.items[]; (.spec.egress // []) | length > 0)'

# --- 4. Les jobs sont branchés sur le démon -----------------------------------------------------------
_m19d_e08_toml="$(_m19d_kj -n gitlab-runner get configmap gitlab-runner | jq -r '.data["config.template.toml"] // ""' 2>/dev/null || true)"
check_output "runner : BUILDKIT_HOST vers buildkitd.buildkit:1234 dans l'environnement des jobs" \
  'BUILDKIT_HOST=tcp://buildkitd\.buildkit(\.svc(\.cluster\.local)?)?:1234' printf '%s\n' "$_m19d_e08_toml"
check_output "runner : Secret buildkit-client monté dans les pods de job" 'name\s*=\s*"buildkit-client"' \
  printf '%s\n' "$_m19d_e08_toml"

# --- 5. Le cache en registre --------------------------------------------------------------------------
check_cmd "Harbor : plateforme/cache-buildkit contient au moins un artefact" _m19d_json \
  "$(harbor_api 'projects/plateforme/repositories/cache-buildkit/artifacts?page_size=5' 2>/dev/null || true)" 'length >= 1'

# --- 6. MédiAgenda construite par ce chemin -------------------------------------------------------------
_m19d_e08_p="$(_m19d_pipelines mediagenda/api 'ref=main&per_page=1')"
_m19d_e08_pid="$(jq -r '.[0].id // empty' <<<"${_m19d_e08_p:-[]}" 2>/dev/null || true)"
if [[ -n "$_m19d_e08_pid" ]]; then
  check_cmd "mediagenda/api : le dernier pipeline de main a un job de construction réussi sur $_M19D_RUNNER" _m19d_json \
    "$(_m19d_jobs mediagenda/api "$_m19d_e08_pid")" '
    any(.[]; (.name | test("construction")) and .status == "success" and (.runner.description // "") == $r)' \
    --arg r "$_M19D_RUNNER"
else
  check_cmd "mediagenda/api : un pipeline de main existe" false
fi
check_cmd "plateforme/k8s (main) : chart local charts/buildkitd" _m19d_fichier_main plateforme/k8s charts/buildkitd/Chart.yaml
check_cmd "plateforme/ci-templates (main) : un gabarit utilise BUILDKIT_HOST" \
  _m19d_grep_main plateforme/ci-templates '^templates/.*\.ya?ml$' 'BUILDKIT_HOST'
