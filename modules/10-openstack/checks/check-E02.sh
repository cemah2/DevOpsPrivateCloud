# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E02.sh — M10-E02 : Préparer les nœuds OpenStack
# À lancer depuis adm01. Lecture seule : qm config et pvesh sur pve01, copie de travail de
# plateforme/infra, DNS, état des nœuds en SSH (ip, ping, timedatectl), API GitLab en GET.

# shellcheck source=_m10-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-decouverte.sh"

title "M10-E02 — Préparer les nœuds OpenStack"
require_cmd jq dig

# nom:vmid:suffixe:mémoire:cpu
_m10d_e02_noeuds=("osctl01:2101:51:16384:x86-64-v2-AES" "oscmp01:2102:52:8192:host" "oscmp02:2103:53:8192:host")

# --- 1. Les VMs, déclarées et conformes ----------------------------------------------------------
check_cmd "plateforme/infra : état envs/openstack présent (backend envs/openstack/terraform.tfstate)" \
  grep -rqs 'envs/openstack/terraform.tfstate' "$_M10D_INFRA/envs/openstack" --include='*.tf'
for _m10d_e02_n in "${_m10d_e02_noeuds[@]}"; do
  IFS=: read -r _m10d_e02_nom _m10d_e02_id _m10d_e02_s _m10d_e02_mem _m10d_e02_cpu <<<"$_m10d_e02_n"
  _m10d_e02_conf="$(_m10d_qm "$_m10d_e02_id")"
  check_cmd "VM $_m10d_e02_id nommée $_m10d_e02_nom" grep -qE "^name: $_m10d_e02_nom$" <<<"$_m10d_e02_conf"
  check_cmd "$_m10d_e02_nom : 4 vCPU, $_m10d_e02_mem Mo" \
    bash -c 'grep -q "^cores: 4$" <<<"$1" && grep -q "^memory: $2$" <<<"$1"' _ "$_m10d_e02_conf" "$_m10d_e02_mem"
  if [[ "$_m10d_e02_cpu" == host ]]; then
    check_cmd "$_m10d_e02_nom : CPU host (KVM imbriqué)" grep -qE '^cpu: (cputype=)?host(,|$)' <<<"$_m10d_e02_conf"
  fi
  check_cmd "$_m10d_e02_nom : étiquettes env-m10 et role-openstack" \
    _m10d_etiquettes "$_m10d_e02_conf" env-m10 role-openstack
  check_cmd "$_m10d_e02_nom : membre du pool lab" _m10d_dans_pool "$_m10d_e02_id"
  check_cmd "$_m10d_e02_nom : net0 sur vosapi, MAC bc:24:11:50:00:$_m10d_e02_s, sans pare-feu" \
    _m10d_carte "$_m10d_e02_conf" net0 vosapi "bc:24:11:50:00:$_m10d_e02_s"
  check_cmd "$_m10d_e02_nom : net1 sur vostun, MAC bc:24:11:51:00:$_m10d_e02_s, MTU 9000" \
    _m10d_carte "$_m10d_e02_conf" net1 vostun "bc:24:11:51:00:$_m10d_e02_s" 9000
  check_cmd "$_m10d_e02_nom : net2 sur vstopub, MAC bc:24:11:30:00:$_m10d_e02_s, MTU 9000" \
    _m10d_carte "$_m10d_e02_conf" net2 vstopub "bc:24:11:30:00:$_m10d_e02_s" 9000
  if [[ "$_m10d_e02_nom" == osctl01 ]]; then
    check_cmd "osctl01 : net3 sur vosext, MAC bc:24:11:52:00:51, sans pare-feu" \
      _m10d_carte "$_m10d_e02_conf" net3 vosext "bc:24:11:52:00:51"
  else
    check_cmd "$_m10d_e02_nom : pas de carte sur le VLAN 52 (seul osctl01 est passerelle)" \
      bash -c '[[ -n "$1" ]] && ! grep -qE "^net[0-9]+: .*bridge=vosext" <<<"$1"' _ "$_m10d_e02_conf"
  fi
  check_cmd "$_m10d_e02_nom : VMID $_m10d_e02_id déclaré dans envs/openstack" \
    grep -rqsE "vmid[[:space:]]*=[[:space:]]*$_m10d_e02_id([^0-9]|$)" "$_M10D_INFRA/envs/openstack" --include='*.tf'
done
unset _m10d_e02_conf

# --- 2. Noms -------------------------------------------------------------------------------------
for _m10d_e02_n in "${_m10d_e02_noeuds[@]}"; do
  IFS=: read -r _m10d_e02_nom _m10d_e02_id _m10d_e02_s _ _ <<<"$_m10d_e02_n"
  check_dns "DNS : $_m10d_e02_nom.par1.medisphere.internal → 10.10.50.$_m10d_e02_s" \
    "$_m10d_e02_nom.par1.medisphere.internal" A "^10\.10\.50\.$_m10d_e02_s$" "$_M10D_DNS"
  check_dns "DNS : 10.10.50.$_m10d_e02_s → $_m10d_e02_nom.par1.medisphere.internal" \
    "$_m10d_e02_s.50.10.10.in-addr.arpa" PTR "^$_m10d_e02_nom\.par1\.medisphere\.internal\.$" "$_M10D_DNS"
done
check_dns "DNS : openstack.par1.medisphere.internal → 10.10.50.201 (VIP externe)" \
  openstack.par1.medisphere.internal A '^10\.10\.50\.201$' "$_M10D_DNS"
check_dns "DNS : openstack-int.par1.medisphere.internal → 10.10.50.200 (VIP interne)" \
  openstack-int.par1.medisphere.internal A '^10\.10\.50\.200$' "$_M10D_DNS"

# --- 3. Dans les nœuds ---------------------------------------------------------------------------
for _m10d_e02_n in "${_m10d_e02_noeuds[@]}"; do
  IFS=: read -r _m10d_e02_nom _m10d_e02_id _m10d_e02_s _ _m10d_e02_cpu <<<"$_m10d_e02_n"
  check_ssh_output "$_m10d_e02_nom : ens18 porte 10.10.50.$_m10d_e02_s/24" "$_m10d_e02_nom" \
    "inet 10\.10\.50\.$_m10d_e02_s/24 " 'ip -o -4 addr show dev ens18'
  check_ssh_output "$_m10d_e02_nom : ens19 porte 10.10.51.$_m10d_e02_s/24 en MTU 9000" "$_m10d_e02_nom" \
    "^ok$" "ip -o link show ens19 | grep -q 'mtu 9000 ' && ip -o -4 addr show dev ens19 | grep -q 'inet 10.10.51.$_m10d_e02_s/24 ' && echo ok"
  check_ssh_output "$_m10d_e02_nom : ens20 porte 10.10.30.$((_m10d_e02_s + 10))/24 en MTU 9000" "$_m10d_e02_nom" \
    "^ok$" "ip -o link show ens20 | grep -q 'mtu 9000 ' && ip -o -4 addr show dev ens20 | grep -q 'inet 10.10.30.$((_m10d_e02_s + 10))/24 ' && echo ok"
  check_ssh "$_m10d_e02_nom : 9000 octets sans fragmentation vers ceph01 (10.10.30.51)" "$_m10d_e02_nom" \
    'ping -c 2 -W 2 -M do -s 8972 -I ens20 10.10.30.51'
  check_ssh_output "$_m10d_e02_nom : horloge synchronisée" "$_m10d_e02_nom" '^yes$' \
    'timedatectl show --property=NTPSynchronized --value'
  if [[ "$_m10d_e02_cpu" == host ]]; then
    check_ssh "$_m10d_e02_nom : /dev/kvm présent (accélération matérielle)" "$_m10d_e02_nom" \
      'test -c /dev/kvm && { test -d /sys/module/kvm_intel || test -d /sys/module/kvm_amd; }'
  fi
done
check_ssh "osctl01 → oscmp01, oscmp02 : 9000 octets sans fragmentation sur le VLAN 51" osctl01 \
  'ping -c 2 -W 2 -M do -s 8972 -I ens19 10.10.51.52 && ping -c 2 -W 2 -M do -s 8972 -I ens19 10.10.51.53'
check_ssh "oscmp01 → oscmp02 : 9000 octets sans fragmentation sur le VLAN 51" oscmp01 \
  'ping -c 2 -W 2 -M do -s 8972 -I ens19 10.10.51.53'
check_ssh "osctl01 : ens21 (VLAN 52) montée" osctl01 'ip -o link show ens21 | grep -q "[<,]UP[,>]"'
check_ssh "osctl01 : ens21 sans aucune adresse IPv4 ni IPv6" osctl01 '[ -z "$(ip -o addr show dev ens21)" ]'
check_ssh "Calculs : aucune carte ens21 (pas de patte sur le VLAN 52)" oscmp01 'ip link show ens18 >/dev/null && ! ip link show ens21 >/dev/null 2>&1'

# --- 4. Le code ----------------------------------------------------------------------------------
check_cmd "plateforme/ansible (main) : rôle noeud_openstack" \
  _m10d_fichier_main plateforme/ansible roles/noeud_openstack/tasks/main.yml
check_cmd "plateforme/ansible (main) : playbook des nœuds OpenStack" \
  _m10d_fichier_main plateforme/ansible playbooks/openstack-noeuds.yml
