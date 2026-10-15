# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M15-E36 « Panne : la résolution DNS échoue dans les pods » : Corefile conforme,
# aucune politique qui interdit le DNS, Deployments de MédiAgenda en ClusterFirst et déployés.
# Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E36 — La résolution DNS fonctionne dans les pods"
require_cmd kubectl jq curl

_m15_e36_cf="$(kube -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' 2>/dev/null)" || true
_m15_e36_bloc="$(awk '/^[[:space:]]*medisphere\.internal(:53)?[[:space:]]*\{/ {b=1} b {print} b && /^[[:space:]]*\}[[:space:]]*$/ {b=0}' <<<"$_m15_e36_cf")" || true
check_cmd "Corefile : un bloc medisphere.internal existe" test -n "$_m15_e36_bloc"
check_output "Corefile : le bloc medisphere.internal transfère vers dns01 et dns02" \
  'forward[[:space:]]+\.[[:space:]]+(10\.10\.20\.10[[:space:]]+10\.10\.20\.16|10\.10\.20\.16[[:space:]]+10\.10\.20\.10)' \
  printf '%s\n' "$_m15_e36_bloc"
check_output "Corefile : le bloc principal transfère vers les récurseurs dns01/dns02" \
  '^[[:space:]]*forward[[:space:]]+\.[[:space:]]+[^#]*10\.10\.20\.1[06]' printf '%s\n' "$_m15_e36_cf"
check_cmd "CoreDNS : au moins deux pods prêts" \
  _m15x_jq '[.items[] | select(.status.conditions[]? | .type == "Ready" and .status == "True")] | length >= 2' -n kube-system pods -l k8s-app=kube-dns
check_cmd "aucune politique Cilium de mediagenda-* n'interdit la sortie (egressDeny)" \
  _m15x_jq '[.items[] | select(.metadata.namespace | startswith("mediagenda-")) | select(.spec.egressDeny != null)] | length == 0' cnp -A
check_cmd "Deployments de $_m15x_ns_app : dnsPolicy ClusterFirst (ou non précisée)" \
  _m15x_jq '[.items[] | .spec.template.spec.dnsPolicy // "ClusterFirst"] | all(. == "ClusterFirst" or . == "ClusterFirstWithHostNet")' -n "$_m15x_ns_app" deploy
check_cmd "Deployments de $_m15x_ns_app : déploiement terminé (tous les réplicas à jour et disponibles)" \
  _m15x_jq '.items | length > 0 and all(.status.observedGeneration >= .metadata.generation and (.status.updatedReplicas // 0) == .spec.replicas and (.status.availableReplicas // 0) == .spec.replicas and (.status.unavailableReplicas // 0) == 0)' \
  -n "$_m15x_ns_app" deploy
check_cmd "https://$_m15x_hote/pret répond 200 depuis adm01" _m15x_https_200 /pret
check_cmd "panne M15-E36 close (lab/bin/break 15 36 --annuler après réparation)" _m15x_aucune_panne_active E36
