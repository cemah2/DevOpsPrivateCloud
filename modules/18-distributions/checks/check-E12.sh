# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E12.sh — M18-E12 : pivoter le cluster de gestion
# À lancer depuis adm01. Lecture seule : kubectl get avec k3s01.kubeconfig et capi-essai.kubeconfig,
# qm status sur pve01, « kind get clusters » sur m18-dev01, GitLab en GET.

# shellcheck source=_m18-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-operationnel.sh"

title "M18-E12 — Pivoter le cluster de gestion"
require_cmd jq kubectl

check_cmd "k3s01 : cinq fournisseurs aux versions du module" _m18o_fournisseurs_ok k3s01
check_cmd "k3s01 : contrôleurs des fournisseurs disponibles" _m18o_controleurs_ok k3s01
_m18d_e12_cl="$(_m18d_kj k3s01 -n capi-essai get cluster capi-essai -o json)"
check_cmd "k3s01 : capi-essai provisionné" _m18d_json "$_m18d_e12_cl" '.status.phase == "Provisioned" and (.spec.paused // false) == false'
check_cmd "k3s01 : plan de contrôle disponible, deux travailleurs" bash -c \
  'jq -e ".status.availableReplicas == 1" <<<"$1" >/dev/null && jq -e ".spec.replicas == 2" <<<"$2" >/dev/null' _ \
  "$(_m18d_kj k3s01 -n capi-essai get kubeadmcontrolplane capi-essai-plan-controle -o json)" \
  "$(_m18d_kj k3s01 -n capi-essai get machinedeployment capi-essai-travailleurs -o json)"
_m18d_e12_m="$(_m18d_kj k3s01 -n capi-essai get machines -o json)"
check_cmd "k3s01 : trois machines Running" _m18d_json "$_m18d_e12_m" '(.items | length == 3) and all(.items[]; .status.phase == "Running")'
check_output "k3s01 : Secret capi-essai-proxmox déplacé, insecure=false" '^false$' \
  _m18o_secret_cle k3s01 capi-essai capi-essai-proxmox insecure
check_cmd "k3s01 : Secret medisphere-root-ca déplacé" _m18d_json \
  "$(_m18d_kj k3s01 -n capi-essai get secret medisphere-root-ca -o json)" '.data["ca.crt"] | length > 0'

# Les VMs n'ont pas été recréées : la VM du nœud de contrôle tourne depuis plus longtemps que
# l'objet Cluster n'existe sur k3s01 (le pivot recrée les objets, pas les VMs).
if _m18d_json "$_m18d_e12_cl" '.spec.infrastructureRef.kind == "ProxmoxCluster"'; then
  _m18d_e12_id="$(_m18d_kj k3s01 -n capi-essai get proxmoxmachines -o json \
    | jq -r '[.items[] | select(.metadata.labels["cluster.x-k8s.io/control-plane"] != null)][0].spec.virtualMachineID // empty' 2>/dev/null || true)"
  _m18d_e12_age="$(jq -r '(now - (.metadata.creationTimestamp | fromdateiso8601)) | floor' <<<"$_m18d_e12_cl" 2>/dev/null || echo 0)"
  _m18d_e12_up="$(remote "${WB_PVE_HOST:-pve01}" "qm status ${_m18d_e12_id:-0} --verbose" 2>/dev/null | sed -n 's/^uptime: //p' || true)"
  check_cmd "VM du nœud de contrôle (${_m18d_e12_id:-?}) antérieure au pivot (pas recréée)" bash -c \
    '[[ -n "$1" && -n "$2" && "$1" -gt "$2" ]]' _ "${_m18d_e12_up:-}" "$_m18d_e12_age"
else
  skip "VMs Proxmox antérieures au pivot" "repli CAPD"
fi
check_cmd "capi-essai : trois nœuds Ready en v1.36.4" _m18d_noeuds_prets "$(_m18d_kj capi-essai get nodes -o json)" 3 v1.36.4

# --- L'ancien cluster de gestion ----------------------------------------------------------------------------
check_cmd "Le cluster kind « gestion » n'existe plus sur m18-dev01" bash -c '! grep -qx gestion <<<"$1"' _ \
  "$(remote "$_M18D_DEV" 'kind get clusters 2>/dev/null' || echo gestion)"
check_cmd "kind-gestion.kubeconfig supprimé" test ! -e "$_M18D_DIR/kind-gestion.kubeconfig"

_m18d_fichiers_main plateforme/distributions capi/pivot.sh
check_output "cluster-api.md (main) : section pivot" '(P|p)ivot' \
  _m18d_contenu_main plateforme/medisphere docs/kubernetes/distributions/cluster-api.md
