# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres jq entre apostrophes
# check-S07.sh — F1-S07 « Détruire et reconstruire les nœuds de k8s-par1 ».
# Lecture seule : qm config (pve01), arborescence du datastore PBS (pbs01), compte wb-checks,
# commandes de consultation sur les nœuds (ip, klist, systemctl, test), documents sur main.
# Preuve « non contournable » de la reconstruction : chaque VM 2141-2146 a été créée (meta ctime de
# Proxmox) APRÈS un instantané PBS de l'ancienne VM de même VMID pris dans les 30 jours précédents,
# et le cluster (espace kube-system) est né après ce même filet.

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S07 — Détruire et reconstruire les nœuds de k8s-par1"
require_cmd kubectl jq curl ssh openssl

# --- VMs : recréées après le filet ------------------------------------------------------------------
_f1_s07_pbs="$(_f1c_pbs_dates "${_f1c_vmids[@]}")"
check_cmd "datastore PBS lu sur $WB_PBS_HOST (instantanés de ${WB_F1_PBS_NS:-par1/k8s})" test -n "$_f1_s07_pbs"
_f1_s07_ctime_min=""
for _f1_s07_i in "${!_f1c_vmids[@]}"; do
  _f1_s07_v="${_f1c_vmids[$_f1_s07_i]}"
  _f1_s07_n="${_f1c_noeuds[$_f1_s07_i]:-?}"
  check_ssh_output "VM $_f1_s07_v ($_f1_s07_n) existe et tourne" "$WB_PVE_HOST" '^status: running' "qm status $_f1_s07_v"
  _f1_s07_c="$(_f1c_vm_ctime "$_f1_s07_v")"
  check_cmd "VM $_f1_s07_v créée après une sauvegarde PBS récente de l'ancienne VM (création : ${_f1_s07_c:+$(date -d "@$_f1_s07_c" '+%F %R')})" \
    _f1c_pbs_avant "$_f1_s07_pbs" "$_f1_s07_v" "${_f1_s07_c:-x}"
  if [[ "$_f1_s07_c" =~ ^[0-9]+$ ]] && { [[ -z "$_f1_s07_ctime_min" ]] || ((_f1_s07_c < _f1_s07_ctime_min)); }; then
    _f1_s07_ctime_min="$_f1_s07_c"
  fi
done

# k8s-w03 (2146) : installée par l'usine (journaux de l'installateur Debian), carte sur le VLAN 40.
check_cmd "k8s-w03 : installée par l'installateur réseau (journaux /var/log/installer présents)" \
  _f1c_hote k8s-w03 'test -s /var/log/installer/syslog || test -s /var/log/installer/partman'
_f1_s07_net="$(_f1c_pve "qm config 2146" | grep -E '^net[0-9]+:' || true)"
check_cmd "VM 2146 : une carte sur le VNet vk8s (VLAN 40)" grep -q 'bridge=vk8s' <<<"$_f1_s07_net"
check_cmd "VM 2146 : plus aucune carte sur le VNet du provisioning (vprov)" \
  bash -c '[[ -n "$1" ]] && ! grep -q "bridge=vprov" <<<"$1"' _ "$_f1_s07_net"

# --- Le cluster est neuf --------------------------------------------------------------------------------
if _f1c_api_repond; then
  _f1_s07_ne="$(_f1c_naissance)"
  check_cmd "cluster né il y a moins de $_f1c_naissance_jours jours (espace kube-system : ${_f1_s07_ne:+$(date -d "@$_f1_s07_ne" '+%F %R')})" \
    bash -c '[[ "$1" =~ ^[0-9]+$ ]] && (( $(date +%s) - $1 < $2 * 86400 ))' _ "${_f1_s07_ne:-x}" "$_f1c_naissance_jours"
  check_cmd "cluster né après la création des nouvelles VMs (pas un ancien cluster rattaché)" \
    bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] && (( $1 >= $2 ))' _ "${_f1_s07_ne:-x}" "${_f1_s07_ctime_min:-y}"

  _f1_s07_nodes="$(_f1c_kj nodes)"
  [[ -n "$_f1_s07_nodes" ]] || _f1_s07_nodes='{"items":[]}'
  for _f1_s07_n in "${_f1c_noeuds[@]}"; do
    check_cmd "nœud $_f1_s07_n enregistré, kubelet $_f1c_version_k8s.x" \
      jq -e --arg n "$_f1_s07_n" --arg v "$_f1c_version_k8s." \
        'any(.items[]; .metadata.name == $n and (.status.nodeInfo.kubeletVersion | startswith($v)))' <<<"$_f1_s07_nodes"
  done
  check_cmd "exactement six nœuds (aucun reste de l'ancien cluster ni k8s-w04)" \
    jq -e '.items | length == 6' <<<"$_f1_s07_nodes"

  _f1_s07_api="$(_f1c_kj -n kube-system pods -l component=kube-apiserver)"
  [[ -n "$_f1_s07_api" ]] || _f1_s07_api='{"items":[]}'
  check_cmd "trois serveurs d'API" jq -e '.items | length == 3' <<<"$_f1_s07_api"
  for _f1_s07_opt in authentication-config audit-policy-file encryption-provider-config; do
    check_cmd "les trois serveurs d'API ont --$_f1_s07_opt" \
      jq -e --arg o "--$_f1_s07_opt=" '(.items | length == 3) and all(.items[]; any(.spec.containers[0].command[]; startswith($o)))' \
      <<<"$_f1_s07_api"
  done
  check_cmd "aucun serveur d'API avec les anciennes options --oidc-* (exclusives de l'authentification structurée)" \
    jq -e '(.items | length == 3) and all(.items[]; all(.spec.containers[0].command[]; startswith("--oidc-") | not))' <<<"$_f1_s07_api"
  check_cmd "trois membres etcd en service (pods etcd prêts)" _f1c_kq \
    '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 3' \
    -n kube-system pods -l component=etcd
else
  check_cmd "l'API du nouveau cluster répond au compte des checks (kubeconfig de wb-checks recréé ?)" false
fi

# --- VIP de l'API -----------------------------------------------------------------------------------------
_f1_s07_vip=0
for _f1_s07_h in "${_f1c_cp[@]}"; do
  if _f1c_hote "$_f1_s07_h" 'ip -4 -o addr show | grep -q " 10\.10\.40\.200/"'; then _f1_s07_vip=$((_f1_s07_vip + 1)); fi
done
check_cmd "exactement un nœud de contrôle porte 10.10.40.200 ($_f1_s07_vip)" test "$_f1_s07_vip" -eq 1
check_output "l'API répond par la VIP (https://10.10.40.200:8443/livez)" '^ok$' \
  curl -sk --max-time "$WB_TIMEOUT" https://10.10.40.200:8443/livez

# --- Socle des nœuds : annuaire, conformité, supervision, instantanés etcd ----------------------------------
for _f1_s07_h in "${_f1c_noeuds[@]}"; do
  check_cmd "$_f1_s07_h : inscrit dans FreeIPA (clé d'hôte host/ dans /etc/krb5.keytab)" \
    _f1c_hote "$_f1_s07_h" 'klist -k /etc/krb5.keytab 2>/dev/null | grep -q "host/'"$_f1_s07_h"'\."'
  # Pas de node_exporter système sur les nœuds : le DaemonSet de kps lira ce fichier (collecteur textfile).
  check_cmd "$_f1_s07_h : durci, score de conformité publié (collecteur textfile)" \
    _f1c_hote "$_f1_s07_h" 'grep -q "^medisphere_conformite" /var/lib/prometheus/node-exporter/conformite.prom'
done
for _f1_s07_h in "${_f1c_cp[@]}"; do
  check_cmd "$_f1_s07_h : minuterie d'instantané etcd active" _f1c_hote "$_f1_s07_h" 'systemctl is-active --quiet etcd-instantane.timer'
done

# --- Documents ------------------------------------------------------------------------------------------------
check_cmd "docs/day0/chronologie.md : gel, destruction, création des VMs, playbooks, amorçage, durées" \
  _f1c_doc '^chronologie\.md$' 'gel' 'destruct|tofu' 'k8s-w03|usine|pxe' 'kubeadm|amor(ç|c)' '[0-9]{1,2}[:h][0-9]{2}'
check_cmd "docs/day0/volumes-ancien-cluster.md : volumes orphelins de k8s-rbd, décision, purge réversible, revue" \
  _f1c_doc '^volumes-ancien-cluster\.md$' 'k8s-rbd' 'csi-vol' 'd(e|é)cision' 'trash|corbeille' '[0-9]{4}-[0-9]{2}-[0-9]{2}'
