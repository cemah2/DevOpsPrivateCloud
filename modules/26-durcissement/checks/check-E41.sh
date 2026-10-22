# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M26-E41 « kubectl logs/exec refusés » : aucune CSR de service en attente, regex large,
# horloges synchrones, CA des kubelets correcte, logs d'un pod témoin lisibles. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E41 — kubectl logs/exec fonctionnent de nouveau"
require_cmd jq kubectl

_e41_csr_ok() {
  _m26x_kq '[.items[]? | select(.spec.signerName == "kubernetes.io/kubelet-serving")
            | select((.status.conditions // []) | (any(.type == "Approved") | not))] | length == 0' \
    certificatesigningrequests.certificates.k8s.io
}
_e41_regex_large() {
  _m26x_git_brut plateforme/politiques kubelet-csr-approver/values.yaml 2>/dev/null |
    grep -Eq 'providerRegex: *.\^k8s-\(cp\|w\)0\[1-9\]'
}
_e41_logs_ok() {
  local p
  p="$(kube -n "$_m26x_ns_kyverno" get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || return 1
  [[ -n "$p" ]] && kube -n "$_m26x_ns_kyverno" logs "$p" --tail=1 --limit-bytes=256 >/dev/null 2>&1
}

check_cmd "aucune CSR de service de kubelet (kubelet-serving) en attente" _e41_csr_ok
check_cmd "l'approbateur couvre tous les nœuds (providerRegex large)" _e41_regex_large
_m26_e41_cp="${WB_M26_CP:-k8s-cp03}"
if _m26x_ssh_ok "$_m26_e41_cp"; then
  check_ssh "$_m26_e41_cp : --kubelet-certificate-authority ne pointe pas vers la CA du front-proxy" "$_m26_e41_cp" \
    "! sudo -n grep -q 'kubelet-certificate-authority=/etc/kubernetes/pki/front-proxy-ca.crt' /etc/kubernetes/manifests/kube-apiserver.yaml"
else
  skip "$_m26_e41_cp" "SSH + sudo -n impossible (nœud de contrôle)"
fi
_m26_e41_noeud="${WB_M26_NOEUD:-k8s-w03}"
if _m26x_ssh_ok "$_m26_e41_noeud"; then
  check_ssh "$_m26_e41_noeud : chrony actif (horloge synchronisée)" "$_m26_e41_noeud" \
    "systemctl is-active chrony chronyd 2>/dev/null | grep -q '^active'"
else
  skip "$_m26_e41_noeud" "SSH + sudo -n impossible"
fi
check_cmd "kubectl logs d'un pod de kyverno répond (kubelet vérifié)" _e41_logs_ok
check_cmd "panne M26-E41 close" _m26x_aucune_panne_active E41
