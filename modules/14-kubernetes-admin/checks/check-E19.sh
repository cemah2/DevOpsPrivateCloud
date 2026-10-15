# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E19.sh — M14-E19 : Tirer les images depuis Harbor
# À lancer depuis adm01. Lecture seule : hosts.toml des nœuds (SSH admin), API Harbor (robot de
# lecture des checks), comptes de service et pods (« kube »), GitLab (aucun Secret versionné).

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E19 — Tirer les images depuis Harbor"
require_cmd jq kubectl curl ssh

declare -A _m14o_e19_miroir=([docker.io]=dockerhub [quay.io]=quay [ghcr.io]=ghcr [registry.k8s.io]=k8s)
for _m14o_e19_noeud in "${_M14O_NOEUDS[@]}"; do
  _m14o_e19_manque=""
  for _m14o_e19_r in "${!_m14o_e19_miroir[@]}"; do
    remote "$_m14o_e19_noeud" "grep -q 'registry.par1.medisphere.internal/v2/${_m14o_e19_miroir[$_m14o_e19_r]}\"' /etc/containerd/certs.d/$_m14o_e19_r/hosts.toml && grep -q 'override_path *= *true' /etc/containerd/certs.d/$_m14o_e19_r/hosts.toml" \
      >/dev/null 2>&1 || _m14o_e19_manque+=" $_m14o_e19_r"
  done
  check_output "$_m14o_e19_noeud : miroirs Harbor pour docker.io, quay.io, ghcr.io, registry.k8s.io (manquants :${_m14o_e19_manque:- aucun})" \
    '^$' echo "$_m14o_e19_manque"
done
check_ssh "les hosts.toml sont posés par le rôle containerd (en-tête Ansible)" "${_M14O_W[0]}" \
  'grep -qiE "ansible|rôle containerd" /etc/containerd/certs.d/docker.io/hosts.toml'

_m14o_e19_depot() { # PROJET MOTIF
  harbor_api "projects/$1/repositories?page_size=100" 2>/dev/null \
    | jq -e --arg m "$2" '[.[] | select((.name | test($m)) and (.pull_count // 0) >= 1)] | length >= 1' >/dev/null 2>&1
}
check_cmd "Harbor : le cache k8s a servi k8s/pause" _m14o_e19_depot k8s '^k8s/pause$'
check_cmd "Harbor : le cache dockerhub a servi au moins une image (busybox, postgres, valkey…)" _m14o_e19_depot dockerhub '^dockerhub/'

for _m14o_e19_ns in mediagenda-dev mediagenda-recette; do
  check_cmd "$_m14o_e19_ns : default et mediagenda-api portent le Secret de tirage harbor-pull" \
    _m14o_json "$(_m14o_k get serviceaccounts -n "$_m14o_e19_ns" -o json)" \
    '[.items[] | select(.metadata.name == "default" or .metadata.name == "mediagenda-api")
      | [.imagePullSecrets[]?.name] | index("harbor-pull") != null] | length == 2 and all'
done
_m14o_e19_pods="$(_m14o_k get pods -n mediagenda-dev -o json)"
check_cmd "mediagenda-dev : API prête, image medisphere/mediagenda-api de Harbor, compte mediagenda-api" _m14o_json "$_m14o_e19_pods" \
  '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "mediagenda-api")
    | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
    | select(.spec.serviceAccountName == "mediagenda-api")
    | select(any(.spec.containers[]; .image | startswith("registry.par1.medisphere.internal/medisphere/mediagenda-api:")))] | length >= 1'
check_cmd "mediagenda-dev : toutes les images sous registry.par1.medisphere.internal/" _m14o_json "$_m14o_e19_pods" \
  '[.items[] | (.spec.containers + (.spec.initContainers // []))[].image] | length >= 1 and all(startswith("registry.par1.medisphere.internal/"))'
check_cmd "mediagenda-dev : PostgreSQL et Valkey prêts" _m14o_json "$_m14o_e19_pods" \
  '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] as $n | $n == "postgresql" or $n == "valkey")
    | select(any(.status.conditions[]?; .type == "Ready" and .status == "True")) | .metadata.labels["app.kubernetes.io/name"]] | unique | length == 2'

for _m14o_e19_p in "$_M14O_P_K8S" "$_M14O_P_APP"; do
  _m14o_e19_secret=0
  for _m14o_e19_f in $(gitlab_api "$_m14o_e19_p/repository/tree?ref=main&recursive=true&per_page=100" 2>/dev/null \
      | jq -r '.[] | select(.type == "blob" and (.path | test("\\.ya?ml$"))) | .path' 2>/dev/null || true); do
    if _m14o_contenu_main "$_m14o_e19_p" "$_m14o_e19_f" | grep -Eq '^kind: *Secret[[:space:]]*$'; then
      # seule exception : le jeton de wb-checks, sans donnée (rempli par le contrôleur)
      [[ "$_m14o_e19_f" == "rbac/wb-checks.yaml" ]] || _m14o_e19_secret=1
    fi
  done
  check_cmd "aucun Secret versionné dans ${_m14o_e19_p#projects/}" test "$_m14o_e19_secret" -eq 0
done
check_cmd "plateforme/k8s : outils/secret-tirage.sh sur main" _m14o_fichier_main "$_M14O_P_K8S" outils/secret-tirage.sh
check_cmd "identifiants du robot en 600 (~/.config/workbook/harbor-k8s-pull.env)" \
  _m14o_local600 "${WB_HARBOR_K8S_PULL_FILE:-$HOME/.config/workbook/harbor-k8s-pull.env}"
