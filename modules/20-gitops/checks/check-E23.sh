# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E23.sh — M20-E23 « Flux : le même déploiement avec un autre outil ». Lecture seule : sur flux01,
# par SSH, « k3s kubectl get » sous sudo -n (objets de Flux et de l'application) ; GitLab (dépôt
# formation/flux-labo, comparatif dans plateforme/medisphere, charts-miroir) ; Proxmox (pvesh get).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E23 — Flux : le même déploiement avec un autre outil"
require_cmd jq curl yq ssh dig

_e23_hote="${WB_M20_FLUX01:-flux01}"
# _e23_k ARGS… — kubectl de k3s sur flux01, en lecture ; JSON vide si injoignable.
_e23_k() { remote "$_e23_hote" "sudo -n k3s kubectl $*" 2>/dev/null || true; }

_e23_vm() {
  remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null \
    | jq -e '[.[] | select(.vmid == 2202 and .name == "flux01" and .status == "running"
      and ((.tags // "") | split(";") | index("env-m20") != null))] | length == 1' >/dev/null 2>&1
}
check_cmd "Proxmox : VM 2202 flux01 en marche, étiquette env-m20" _e23_vm
check_dns "flux01.par1.medisphere.internal : 10.10.99.62 (adresse fixe)" flux01.par1.medisphere.internal A '^10\.10\.99\.62$'

_e23_noeud="$(_e23_k get nodes -o json)"
if [[ -z "$_e23_noeud" ]]; then
  check_cmd "flux01 joignable en SSH, k3s lisible (sudo -n k3s kubectl)" false
else
  check_cmd "flux01 : nœud k3s Ready, version 1.36" \
    _m20o_jq "$_e23_noeud" '[.items[] | select(.status.nodeInfo.kubeletVersion | startswith("v1.36"))
      | .status.conditions[] | select(.type == "Ready" and .status == "True")] | length == 1'
  _e23_ctrl="$(_e23_k get deployments -n flux-system -o json)"
  check_cmd "flux-system : source, kustomize, helm et notification controllers prêts" \
    _m20o_jq "$_e23_ctrl" '[.items[] | select(.metadata.name | test("^(source|kustomize|helm|notification)-controller$"))
      | select((.status.readyReplicas // 0) >= 1)] | length == 4'
  check_cmd "contrôleurs de Flux en version 2.9 (étiquette app.kubernetes.io/version)" \
    _m20o_jq "$_e23_ctrl" '[.items[] | .metadata.labels["app.kubernetes.io/version"] // "" | startswith("v2.9.")] | length > 0 and all'
  _e23_gr="$(_e23_k get gitrepositories.source.toolkit.fluxcd.io flux-system -n flux-system -o json)"
  check_cmd "GitRepository flux-system : formation/flux-labo sur git01 en HTTPS, Ready" \
    _m20o_jq "$_e23_gr" '(.spec.url | test("^https://git01\\.par1\\.medisphere\\.internal/formation/flux-labo"))
      and ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 1)'
  _e23_ks="$(_e23_k get kustomizations.kustomize.toolkit.fluxcd.io -n flux-system -o json)"
  for _e23_n in flux-system labo podinfo; do
    check_cmd "Kustomization $_e23_n : Ready" \
      _m20o_jq "$_e23_ks" '[.items[] | select(.metadata.name == $n) | .status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 1' --arg n "$_e23_n"
  done
  check_cmd "Kustomization labo : prune activé" \
    _m20o_jq "$_e23_ks" '[.items[] | select(.metadata.name == "labo") | .spec.prune] == [true]'
  _e23_hr="$(_e23_k get helmreleases.helm.toolkit.fluxcd.io podinfo -n flux-system -o json)"
  check_cmd "HelmRelease podinfo : Ready, chart tiré d'un OCIRepository" \
    _m20o_jq "$_e23_hr" '(.spec.chartRef.kind == "OCIRepository")
      and ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 1)'
  _e23_oci="$(_e23_k get ocirepositories.source.toolkit.fluxcd.io podinfo -n flux-system -o json)"
  check_cmd "OCIRepository podinfo : registre Harbor MédiSphère (charts/), version exacte" \
    _m20o_jq "$_e23_oci" '(.spec.url | startswith("oci://registry.par1.medisphere.internal/charts/")) and (.spec.ref.tag | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))'
  _e23_labo="$(_e23_k get deployment labo -n labo -o json)"
  check_cmd "labo sur flux01 : Deployment prêt" _m20o_jq "$_e23_labo" '(.status.readyReplicas // 0) >= 1 and .status.readyReplicas == .spec.replicas'
fi
# Le Secret de synchronisation doit porter un jeton de DÉPLOIEMENT (lecture seule), pas le jeton d'API
# du bootstrap : on ne lit pas le Secret, on regarde les jetons du projet dans GitLab.

_e23_p=formation/flux-labo
check_cmd "$_e23_p : manifestes de Flux commités (clusters/flux01/flux-system/gotk-components.yaml)" \
  _m20o_gl_existe "$_e23_p" clusters/flux01/flux-system/gotk-components.yaml
_e23_jetons() {
  gitlab_api "projects/$(_m20o_enc "$_e23_p")/deploy_tokens" 2>/dev/null \
    | jq -e '[.[] | select(.revoked != true and .expired != true and (.scopes | index("read_repository") != null)
              and (.scopes | index("write_repository") == null))] | length >= 1' >/dev/null 2>&1
}
check_cmd "$_e23_p : jeton de déploiement en lecture seule pour flux01" _e23_jetons
_e23_pat() {
  gitlab_api "projects/$(_m20o_enc "$_e23_p")/access_tokens" 2>/dev/null \
    | jq -e '[.[] | select(.active == true and (.scopes | index("api") != null))] | length == 0' >/dev/null 2>&1
}
check_cmd "$_e23_p : plus de jeton d'accès de projet « api » actif (celui du bootstrap est révoqué)" _e23_pat
_e23_charts() { _m20o_gl_fichier plateforme/charts-miroir charts.yaml | yq -e '[.charts[] | select(.nom == "podinfo")] | length == 1' >/dev/null 2>&1; }
check_cmd "plateforme/charts-miroir : podinfo recopié par le miroir (charts.yaml)" _e23_charts
check_cmd "plateforme/medisphere : docs/livraison/gitops/comparatif-flux.md sur main" \
  _m20o_gl_existe plateforme/medisphere docs/livraison/gitops/comparatif-flux.md
_e23_comparatif() {
  local c
  c="$(_m20o_gl_fichier plateforme/medisphere docs/livraison/gitops/comparatif-flux.md)"
  grep -qi 'helmrelease' <<<"$c" && grep -qi 'prune' <<<"$c" && grep -Eqi 'recommand|retenu|choix' <<<"$c"
}
check_cmd "comparatif : Helm, prune et une recommandation" _e23_comparatif
