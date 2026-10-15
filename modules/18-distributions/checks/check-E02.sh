# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c ou sur l'hôte distant
#
# check-E02.sh — M18-E02 : kind et k3d, des clusters de développement
# À lancer depuis adm01. Lecture seule : qm config et pool sur pve01, NetBox et GitLab en GET,
# SSH vers m18-dev01 (versions, docker inspect/exec en lecture, kubectl get des clusters dev).

# shellcheck source=_m18-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-decouverte.sh"

title "M18-E02 — kind et k3d : des clusters de développement"
require_cmd jq kubectl

# --- 1. La VM et l'environnement ---------------------------------------------------------------
_m18d_vm "m18-dev01" 2188 m18-dev01 4 8192 "bc:24:11:99:18:88" env-m18 role-m18-dev
check_cmd "NetBox : VM m18-dev01 inscrite, étiquette env-m18" _m18d_json \
  "$(netbox_api 'virtualization/virtual-machines/?name=m18-dev01' 2>/dev/null || true)" \
  '.count == 1 and ([.results[0].tags[].slug] | index("env-m18"))'

# --- 2. Les outils -----------------------------------------------------------------------------
_m18d_e02_outils="$(remote "$_M18D_DEV" 'docker version --format "docker {{.Server.Version}}"; kind version; k3d version | head -1; kubectl version --client | head -1; clusterctl version -o short; talosctl version --client | grep Tag' 2>/dev/null || true)"
check_output "m18-dev01 : Docker Engine 29.8" '^docker 29\.8\.' echo "$_m18d_e02_outils"
check_output "m18-dev01 : kind 0.33.0" '^kind v0\.33\.0 ' echo "$_m18d_e02_outils"
check_output "m18-dev01 : k3d 5.9.0" '^k3d version v5\.9\.0' echo "$_m18d_e02_outils"
check_output "m18-dev01 : kubectl 1.36" 'Client Version: v1\.36\.' echo "$_m18d_e02_outils"
check_output "m18-dev01 : clusterctl 1.12.11" '^v1\.12\.11$' echo "$_m18d_e02_outils"
check_output "m18-dev01 : talosctl 1.14.2" 'Tag: +v1\.14\.2' echo "$_m18d_e02_outils"
check_output "adm01 : clusterctl 1.12.11" '^v1\.12\.11$' clusterctl version -o short
check_output "adm01 : talosctl 1.14.2" 'Tag: +v1\.14\.2' talosctl version --client

# --- 3. kind-dev --------------------------------------------------------------------------------
_m18d_e02_kind="$(remote "$_M18D_DEV" 'kubectl --context kind-dev --request-timeout=5s get nodes -o json' 2>/dev/null || true)"
check_cmd "kind-dev : trois nœuds Ready en v1.36.4 (un de contrôle, deux travailleurs)" bash -c \
  "$(declare -f _m18d_noeuds_prets _m18d_json); _m18d_noeuds_prets \"\$1\" 3 v1.36.4 && _m18d_json \"\$1\" '[.items[] | select(.metadata.labels | has(\"node-role.kubernetes.io/control-plane\"))] | length == 1'" \
  _ "$_m18d_e02_kind"
check_output "kind-dev : nœuds créés avec l'image à l'empreinte fixée" '^ok$' \
  remote "$_M18D_DEV" "for c in dev-control-plane dev-worker dev-worker2; do docker inspect -f '{{.Config.Image}}' \$c; done | sort -u | grep -qx '$_M18D_KIND_IMAGE' && echo ok"
check_output "kind-dev : containerd des nœuds renvoie docker.io vers le cache Harbor" 'registry\.par1\.medisphere\.internal/v2/dockerhub' \
  remote "$_M18D_DEV" 'docker exec dev-worker cat /etc/containerd/certs.d/docker.io/hosts.toml'
check_output "kind-dev : image medisphere/essai:local chargée dans un travailleur" 'medisphere/essai' \
  remote "$_M18D_DEV" 'docker exec dev-worker crictl images'

# --- 4. k3d-dev --------------------------------------------------------------------------------
_m18d_e02_k3d="$(remote "$_M18D_DEV" 'kubectl --context k3d-dev --request-timeout=5s get nodes -o json' 2>/dev/null || true)"
check_cmd "k3d-dev : un serveur et deux agents Ready en v1.36.5+k3s1" bash -c \
  "$(declare -f _m18d_noeuds_prets _m18d_json); _m18d_noeuds_prets \"\$1\" 3 v1.36.5+k3s1" _ "$_m18d_e02_k3d"
check_output "k3d-dev : Traefik absent" '^0$' \
  remote "$_M18D_DEV" 'kubectl --context k3d-dev --request-timeout=5s -n kube-system get deploy,helmchart -o name 2>/dev/null | grep -c traefik || true'
check_output "k3d-dev : image medisphere/essai:local importée dans un agent" 'medisphere/essai' \
  remote "$_M18D_DEV" 'docker exec k3d-dev-agent-0 crictl images'

# --- 5. Le code et la documentation -------------------------------------------------------------
_m18d_fichiers_main plateforme/infra envs/m18/versions.tf envs/m18/hotes.tf
_m18d_fichiers_main plateforme/ansible inventories/lab/netbox-m18.yml playbooks/m18.yml roles/outils_distributions/tasks/main.yml
_m18d_fichiers_main plateforme/distributions kind/dev.yaml kind/README.md k3d/dev.yaml k3d/README.md
check_output "plateforme/distributions (main) : k3d/dev.yaml fixe l'image rancher/k3s:v1.36.5-k3s1" '^image: rancher/k3s:v1\.36\.5-k3s1' \
  _m18d_contenu_main plateforme/distributions k3d/dev.yaml
_m18d_fichiers_main plateforme/medisphere docs/kubernetes/distributions/poste-dev.md docs/kubernetes/distributions/mesures.md
