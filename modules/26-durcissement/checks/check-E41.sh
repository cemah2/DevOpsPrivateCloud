# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M26-E41 « kubectl logs/exec refusés » : aucune CSR de service en attente, approbateur
# actif à la regex large, CA des kubelets correcte, logs d'un pod du nœud témoin lisibles. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E41 — kubectl logs/exec fonctionnent de nouveau"
require_cmd jq kubectl

_e41_csr_ok() {
  _m26x_kq '[.items[]? | select(.spec.signerName == "kubernetes.io/kubelet-serving")
            | select((.status.conditions // []) | (any(.type == "Approved") | not))] | length == 0' \
    certificatesigningrequests.certificates.k8s.io
}
# Valeurs de l'Application kubelet-csr-approver (M26-E25) : plateforme/gitops.
_e41_valeurs() { _m26x_git_brut plateforme/gitops valeurs/kubelet-csr-approver/values.yaml 2>/dev/null; }
_e41_regex_large() { _e41_valeurs | grep -Eq "^providerRegex: *['\"]?\^k8s-\(cp\|w\)0\[1-9\]\\\$['\"]?"; }
_e41_approbateur_actif() {
  ! _e41_valeurs | grep -Eq '^replicas: *0([^0-9]|$)' &&
    _m26x_kq '[.items[]? | select((.status.readyReplicas // 0) >= 1)] | length >= 1' \
      deployments -A -l app.kubernetes.io/name=kubelet-csr-approver
}
# kubectl logs d'un pod qui tourne sur le nœud témoin (le chemin API → kubelet de CE nœud).
_e41_logs_ok() {
  local ns p
  read -r ns p < <(kube get pods -A --field-selector "spec.nodeName=$1,status.phase=Running" \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -n 1) || return 1
  [[ -n "${p:-}" ]] && kube -n "$ns" logs "$p" --all-containers --tail=1 --limit-bytes=256 >/dev/null 2>&1
}

check_cmd "aucune CSR de service de kubelet (kubelet-serving) en attente" _e41_csr_ok
check_cmd "l'approbateur de CSR accepte les noms de tous les nœuds (plateforme/gitops)" _e41_regex_large
check_cmd "l'approbateur de CSR tourne (au moins un réplica prêt, pas de « replicas: 0 »)" _e41_approbateur_actif
_m26_e41_cp="${WB_M26_CP:-k8s-cp03}"
if _m26x_ssh_ok "$_m26_e41_cp"; then
  check_ssh "$_m26_e41_cp : --kubelet-certificate-authority ne pointe pas vers la CA du front-proxy" "$_m26_e41_cp" \
    "! sudo -n grep -q 'kubelet-certificate-authority=/etc/kubernetes/pki/front-proxy-ca.crt' /etc/kubernetes/manifests/kube-apiserver.yaml"
else
  skip "$_m26_e41_cp" "SSH + sudo -n impossible (nœud de contrôle)"
fi
_m26_e41_noeud="${WB_M26_NOEUD:-k8s-w03}"
if _m26x_ssh_ok "$_m26_e41_noeud"; then
  check_ssh "$_m26_e41_noeud : le kubelet présente un certificat de service" "$_m26_e41_noeud" \
    "timeout 5 openssl s_client -connect 127.0.0.1:10250 </dev/null 2>/dev/null | grep -q 'BEGIN CERTIFICATE'"
else
  skip "$_m26_e41_noeud" "SSH + sudo -n impossible"
fi
check_cmd "kubectl logs d'un pod de $_m26_e41_noeud répond (API → kubelet)" _e41_logs_ok "$_m26_e41_noeud"
check_cmd "panne M26-E41 close" _m26x_aucune_panne_active E41
