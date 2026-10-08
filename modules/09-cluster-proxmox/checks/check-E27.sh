# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E27.sh — M09-E27 « Le réseau de migration »
# Lecture seule : datacenter.cfg, corosync.conf, état des liens Corosync, journaux des tâches de
# migration récentes (pvesh get), code Ansible de adm01, documentation sur GitLab.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E27 — Le réseau de migration"
require_cmd jq ssh
_m09p_charger
_m09_e27_ref="$(_m09p_noeud 2>/dev/null || echo hv01)"

title "Réglages du datacenter"
check_ssh_output "migration secure sur 10.10.30.0/24" "root@$_m09_e27_ref.$_M09P_ZONE" \
  '^migration: (.*,)?network=10\.10\.30\.0/24' 'cat /etc/pve/datacenter.cfg'
check_ssh "migration : pas de type insecure" "root@$_m09_e27_ref.$_M09P_ZONE" \
  '! grep -Eq "^migration:.*insecure" /etc/pve/datacenter.cfg'
check_ssh "limite de débit de migration fixée (entre 10 Mio/s et 10 Gio/s)" "root@$_m09_e27_ref.$_M09P_ZONE" \
  'v=$(sed -nE "s/^bwlimit:.*migration=([0-9]+).*/\1/p" /etc/pve/datacenter.cfg); [ -n "$v" ] && [ "$v" -ge 10240 ] && [ "$v" -le 10485760 ]'
check_cmd "rôle pve_cluster : migration et bwlimit dans le code" \
  bash -c 'grep -rqs "10\.10\.30\.0/24" "$1"/roles/pve_cluster/ && grep -rqs "bwlimit" "$1"/roles/pve_cluster/' _ "$_M09P_SRC/ansible"

title "Corosync à l'écart"
check_ssh "corosync.conf : aucun lien sur 10.10.30.0/24" "root@$_m09_e27_ref.$_M09P_ZONE" \
  '! grep -Eq "ring[0-9]_addr: *10\.10\.30\." /etc/pve/corosync.conf && grep -Eq "ring1_addr" /etc/pve/corosync.conf'
for _m09_e27_n in "${_M09P_NOEUDS[@]}"; do
  check_ssh "$_m09_e27_n : deux liens Corosync, aucun pair déconnecté" "root@$_m09_e27_n.$_M09P_ZONE" \
    's=$(corosync-cfgtool -s); [ "$(printf "%s\n" "$s" | grep -c "^LINK ID")" -ge 2 ] && ! printf "%s\n" "$s" | grep -qi "disconnected"'
done

title "Une migration sur le VLAN 30"
# _m09_e27_migration — une tâche qmigrate récente a annoncé une adresse dédiée du VLAN 30.
_m09_e27_migration() {
  local taches ligne noeud upid
  taches="$(_m09p_pvesh /cluster/tasks)" || return 1
  while read -r ligne; do
    [[ -n "$ligne" ]] || continue
    read -r noeud upid <<<"$ligne"
    if _m09p_hv "$noeud" "pvesh get /nodes/$noeud/tasks/$upid/log --limit 500 --output-format json" 2>/dev/null \
        | grep -Eq 'dedicated network address[^"]*\(10\.10\.30\.'; then
      return 0
    fi
  done < <(jq -r '.[] | select(.type == "qmigrate" and .status == "OK") | "\(.node) \(.upid)"' <<<"$taches" | head -n 20)
  return 1
}
check_cmd "journal d'une migration réussie récente : adresse dédiée 10.10.30.x" _m09_e27_migration

title "Fin d'exercice"
check_cmd "docs/virtualisation/tests/migration-hv-par1.md sur main" _m09p_doc tests migration-hv-par1
check_cmd "VM 122 détruite" _m09p_vm_cluster_absente 122
