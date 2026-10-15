# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M14-E35 « Panne : un nœud est NotReady » : tous les nœuds Ready sans pression,
# kubelet et containerd sains sur les travailleurs (service, configuration, swap, certificat, disque),
# RB-140 complété, panne close. Lecture seule.

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E35 — Tous les nœuds sont Ready"
require_cmd jq ssh kubectl

if _m14x_api_repond; then
  check_cmd "6 nœuds dans le cluster (3 de contrôle, 3 travailleurs)" \
    _m14x_kq '[.items[].metadata.name] | sort == ["k8s-cp01","k8s-cp02","k8s-cp03","k8s-w01","k8s-w02","k8s-w03"]' nodes
  check_cmd "tous les nœuds sont Ready" \
    _m14x_kq 'all(.items[]; any(.status.conditions[]; .type == "Ready" and .status == "True"))' nodes
  check_cmd "aucun nœud en pression disque, mémoire ou PID" \
    _m14x_kq '[.items[].status.conditions[] | select((.type | test("Pressure$")) and .status == "True")] | length == 0' nodes
  check_cmd "aucun nœud laissé cordonné (SchedulingDisabled)" \
    _m14x_kq '[.items[] | select(.spec.unschedulable == true)] | length == 0' nodes
else
  skip "état des nœuds" "l'API ne répond pas au compte des checks (lab/bin/check 14 39)"
fi

# shellcheck disable=SC2016  # commandes évaluées sur le nœud
for _m14_e35_h in "${_m14x_w[@]}"; do
  check_cmd "$_m14_e35_h : kubelet actif et activé au démarrage" \
    _m14x_noeud "$_m14_e35_h" 'systemctl is-active -q kubelet && systemctl is-enabled -q kubelet'
  check_cmd "$_m14_e35_h : aucune option retirée du kubelet (--pod-infra-container-image)" \
    _m14x_noeud "$_m14_e35_h" '! grep -qs -- --pod-infra-container-image /etc/default/kubelet /var/lib/kubelet/kubeadm-flags.env'
  check_cmd "$_m14_e35_h : containerd actif, configuration lisible (containerd config dump)" \
    _m14x_noeud "$_m14_e35_h" 'systemctl is-active -q containerd && containerd config dump >/dev/null 2>&1'
  check_cmd "$_m14_e35_h : aucun swap actif ni déclaré dans /etc/fstab" \
    _m14x_noeud "$_m14_e35_h" '[ -z "$(swapon --show --noheadings)" ] && ! awk '\''$1 !~ /^#/ && $3 == "swap"'\'' /etc/fstab | grep -q .'
  check_cmd "$_m14_e35_h : certificat client du kubelet signé par la CA du cluster, valable plus de 24 h" \
    _m14x_noeud "$_m14_e35_h" 'c=/var/lib/kubelet/pki/kubelet-client-current.pem; openssl verify -CAfile /etc/kubernetes/pki/ca.crt "$c" >/dev/null 2>&1 && openssl x509 -in "$c" -noout -checkend 86400 >/dev/null'
  check_cmd "$_m14_e35_h : /var/lib/containerd occupé à moins de 85 %" \
    _m14x_noeud "$_m14_e35_h" '[ "$(df --output=pcent /var/lib/containerd | tail -n 1 | tr -dc 0-9)" -lt 85 ]'
done

check_cmd "RB-140 couvre kubelet, containerd, swap, certificat et disque" \
  bash -c 'f=$(ls "$1"/docs/kubernetes/runbooks/RB-140-*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && for m in kubelet containerd swap certificat disque; do grep -qi -- "$m" "$f" || exit 1; done' _ "$_m14x_depot"
check_cmd "panne M14-E35 close (lab/bin/break 14 35 --annuler après réparation)" _m14x_aucune_panne_active E35
