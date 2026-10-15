# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E02.sh — M15-E02 : Suivre un paquet de pod à pod
# À lancer depuis adm01. Lecture seule : objets du cluster (wb-checks), interfaces des nœuds en SSH,
# fichiers de plateforme/ansible et plateforme/medisphere sur main (API GitLab en GET).

# shellcheck source=_m15-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-decouverte.sh"

title "M15-E02 — Suivre un paquet de pod à pod"
require_cmd kubectl jq curl ssh

# --- Les sondes -----------------------------------------------------------------------------------
_m15d_e02_pods="$(_m15d_get -n "$_M15D_NS" pods -l app.kubernetes.io/name=sonde)"
for _m15d_e02_p in sonde-w01a:k8s-w01 sonde-w01b:k8s-w01 sonde-w02:k8s-w02; do
  check_cmd "pod ${_m15d_e02_p%%:*} en marche sur ${_m15d_e02_p##*:}" _m15d_json "$_m15d_e02_pods" \
    'any(.items[]; .metadata.name == $n and .spec.nodeName == $h and .status.phase == "Running")' \
    --arg n "${_m15d_e02_p%%:*}" --arg h "${_m15d_e02_p##*:}"
done
check_cmd "les sondes ont une adresse dans 10.240.0.0/16" _m15d_json "$_m15d_e02_pods" \
  '[.items[] | select(.metadata.name | test("^sonde-w0")) | .status.podIP // ""] | length >= 3 and all(test("^10\\.240\\."))'
check_cmd "sonde-w01a et sonde-w02 sont dans deux /24 différents (deux nœuds)" _m15d_json "$_m15d_e02_pods" '
  [.items[] | select(.metadata.name == "sonde-w01a" or .metadata.name == "sonde-w02") | .status.podIP // "" | split(".")[0:3] | join(".")]
  | length == 2 and .[0] != .[1]'

# --- IPAM et mode réseau de Cilium -------------------------------------------------------------------
_m15d_e02_cn="$(_m15d_get ciliumnodes)"
check_cmd "chaque nœud a un /24 de pods dans 10.240.0.0/16 (CiliumNode)" _m15d_json "$_m15d_e02_cn" \
  '(.items | length) == $n and all(.items[]; (.spec.ipam.podCIDRs // []) | length >= 1 and all(test("^10\\.240\\.[0-9]+\\.0/24$")))' \
  --argjson n "${#_M15D_NOEUDS[@]}"
check_output "Cilium en mode tunnel (routing-mode)" '^tunnel$' _m15d_cilium_cfg routing-mode
check_output "tunnel VXLAN (tunnel-protocol)" '^vxlan$' _m15d_cilium_cfg tunnel-protocol

# --- Le tunnel sur les nœuds -----------------------------------------------------------------------
check_ssh_output "k8s-w01 : interface cilium_vxlan de type vxlan, port 8472" k8s-w01 'vxlan .*dstport 8472' \
  'ip -d link show cilium_vxlan'
check_ssh_output "k8s-w01 : cilium_host porte une adresse de 10.240.0.0/16" k8s-w01 'inet 10\.240\.' \
  'ip -4 addr show cilium_host'

# --- Outils de diagnostic (playbook) ---------------------------------------------------------------
for _m15d_e02_n in "${_M15D_NOEUDS[@]}"; do
  check_ssh "$_m15d_e02_n : tcpdump, conntrack, iptables et bpftool installés" "$_m15d_e02_n" \
    'command -v tcpdump && command -v conntrack && command -v iptables-save && command -v bpftool'
done
check_cmd "playbooks/k8s-outils-diagnostic.yml sur main de plateforme/ansible" \
  _m15d_fichier_main "$_M15D_PROJET_ANSIBLE" playbooks/k8s-outils-diagnostic.yml

# --- La fiche ----------------------------------------------------------------------------------------
_m15d_e02_doc="$(_m15d_contenu_main "$_M15D_PROJET_DOC" docs/kubernetes/reseau/chemin-paquet.md)"
check_cmd "docs/kubernetes/reseau/chemin-paquet.md sur main" test -n "$_m15d_e02_doc"
check_output "la fiche décrit le tunnel VXLAN (port 8472)" '8472' echo "$_m15d_e02_doc"
check_cmd "la fiche parle de l'identité portée par le VNI et du MTU (1450)" \
  bash -c 'grep -qiE "VNI" <<<"$1" && grep -qiE "identit" <<<"$1" && grep -qE "1450" <<<"$1"' _ "$_m15d_e02_doc"
