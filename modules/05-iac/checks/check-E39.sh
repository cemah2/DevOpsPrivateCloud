# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E39.sh — M05-E39 « Panne : la VM est créée mais injoignable » : chaque VM d'environnement
# démarrée est sur vsandbox, a reçu une adresse 10.10.99.x et accepte une connexion SSH neuve depuis
# adm01 ; DHCP et filtrage du VLAN 99 sont sains ; le plan est vide. Lecture seule.

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E39 — VMs d'environnement joignables"
require_cmd tofu jq ssh

# Chaque VM env-m05 démarrée : carte sur vsandbox, IPv4 du VLAN 99, SSH neuf (sans multiplexage).
_m05_e39_vms() {
  local id st ip n=0
  while read -r id st; do
    [[ -n "$id" && "$st" == running ]] || continue
    n=$((n + 1))
    remote "$WB_PVE_HOST" "qm config $id" 2>/dev/null | grep -Eq '^net0: .*bridge=vsandbox' || { echo "VM $id : pas sur vsandbox" >&2; return 1; }
    ip="$(_m05x_ip_vm "$id")"
    [[ -n "$ip" ]] || { echo "VM $id : pas d'adresse 10.10.99.x" >&2; return 1; }
    ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" "admin@$ip" true >/dev/null 2>&1 \
      || { echo "VM $id : SSH refusé ou expiré ($ip)" >&2; return 1; }
  done < <(_m05x_vms_env_pve)
  ((n > 0))
}

check_cmd "VMs env-m05 démarrées : sur vsandbox, adresse 10.10.99.x, SSH neuf depuis adm01" _m05_e39_vms
check_ssh "gw01 : aucune règle ne jette le DHCP du VLAN 99 (UDP/67)" gw01 \
  '! sudo -n nft list chain inet filter input | grep -Eq "dport (67|bootps) .*(drop|reject)"'
check_ssh "gw01 : aucune règle ne jette SSH vers 10.10.99.0/24" gw01 \
  '! sudo -n nft list chain inet filter forward | grep -Eq "10\.10\.99\.0/24 .*dport (22|ssh) .*(drop|reject)"'
check_ssh "dns01 : dnsmasq actif, configuration valide" dns01 'systemctl is-active -q dnsmasq && sudo -n dnsmasq --test'
check_ssh "dns01 : dnsmasq ne refuse pas les machines non déclarées (dhcp-ignore)" dns01 \
  '! sudo -n grep -rEqs "^[[:space:]]*dhcp-ignore" /etc/dnsmasq.conf /etc/dnsmasq.d/'
check_cmd "envs/lab-m05 : « tofu plan » ne propose aucun changement" _m05x_plan_vide "$_m05x_envs"
check_output "infra : copie de travail sans modification non commitée" '^$' git -C "$_m05x_infra" status --porcelain
check_cmd "panne M05-E39 close (lab/bin/break 05 39 --annuler après réparation)" _m05x_aucune_panne_active E39
