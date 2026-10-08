# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E26.sh — M09-E26 « Sécuriser le cluster »
# Lecture seule : fichiers du pare-feu (/etc/pve/firewall), état de pve-firewall, essais de
# connexion TCP depuis gw01, runner01 et adm01 (ouverts puis refermés), certificats servis,
# double authentification (GET /access/tfa), sshd -T, documentation sur GitLab.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E26 — Sécuriser le cluster"
require_cmd jq ssh openssl
_m09p_charger
_m09_e26_ref="$(_m09p_noeud 2>/dev/null || echo hv01)"

title "Pare-feu de cluster"
check_ssh_output "cluster.fw : pare-feu activé au niveau du datacenter" "root@$_m09_e26_ref.$_M09P_ZONE" \
  '^enable: 1$' 'cat /etc/pve/firewall/cluster.fw'
check_ssh_output "cluster.fw : géré par le rôle pve_pare_feu" "root@$_m09_e26_ref.$_M09P_ZONE" \
  'pve_pare_feu' 'head -3 /etc/pve/firewall/cluster.fw'
check_ssh "cluster.fw : IPSet management avec adm01, le VPN et runner01" "root@$_m09_e26_ref.$_M09P_ZONE" \
  's=$(awk "/^\[IPSET management\]/{f=1;next} /^\[/{f=0} f" /etc/pve/firewall/cluster.fw); for a in "10\.10\.10\.10" "10\.255\.1\.0/24" "10\.10\.20\.15"; do printf "%s\n" "$s" | grep -Eq "^$a( |$)" || exit 1; done'
for _m09_e26_n in "${_M09P_NOEUDS[@]}"; do
  check_ssh "$_m09_e26_n : pare-feu du nœud non désactivé, pve-firewall actif" "root@$_m09_e26_n.$_M09P_ZONE" \
    '! grep -qs "^enable: 0" /etc/pve/nodes/$(hostname)/host.fw && pve-firewall status | grep -q "enabled/running"'
done

title "Flux (preuves positives et négatives)"
for _m09_e26_ip in 10.10.10.51 10.10.10.52 10.10.10.53; do
  check_cmd "gw01 → $_m09_e26_ip:8006 refusé" _m09p_port_ferme gw01 "$_m09_e26_ip" 8006
  check_cmd "gw01 → $_m09_e26_ip:22 refusé" _m09p_port_ferme gw01 "$_m09_e26_ip" 22
  check_port "adm01 → $_m09_e26_ip:8006 accepté" "$_m09_e26_ip" 8006
done
check_cmd "runner01 → VIP $_M09P_VIP:8006 accepté" _m09p_port_ouvert runner01 "$_M09P_VIP" 8006
check_cmd "cluster quorate, trois nœuds en ligne" _m09p_quorate_3
check_cmd "Ceph en HEALTH_OK" _m09p_ceph_ok
check_cmd "VIP portée par un seul nœud (VRRP passe le pare-feu)" _m09p_vip_unique

title "Certificats de l'interface 8006"
for _m09_e26_n in hv01 hv02 hv03 hv; do
  check_cmd "$_m09_e26_n.$_M09P_ZONE:8006 : PKI MédiSphère, nom vérifié, ≤ 31 jours, > 10 jours restants" \
    _m09p_cert_ok "$_m09_e26_n.$_M09P_ZONE" 8006 10
done
for _m09_e26_n in "${_M09P_NOEUDS[@]}"; do
  check_ssh "$_m09_e26_n : renouvellement automatique (cert-renewer@pveproxy ou ACME de Proxmox VE)" "root@$_m09_e26_n.$_M09P_ZONE" \
    'systemctl is-active --quiet cert-renewer@pveproxy.timer || pvenode config get 2>/dev/null | grep -Eq "^acme(domain[0-9])?:"'
done

title "Double authentification et SSH"
_m09_e26_tfa() {
  local tfa membres u
  tfa="$(_m09p_pvesh /access/tfa)" || return 1
  membres="$(_m09p_pvesh /access/groups/hv-admins | jq -r '.members[]?')" || return 1
  [[ -n "$membres" ]] || return 1
  for u in root@pam $membres; do
    jq -e --arg u "$u" 'any(.[]; .userid == $u and any(.entries[]?; .type == "totp"))' >/dev/null <<<"$tfa" || return 1
  done
}
check_cmd "TOTP pour root@pam et chaque membre de hv-admins (groupe non vide)" _m09_e26_tfa
for _m09_e26_n in "${_M09P_NOEUDS[@]}"; do
  check_ssh_output "$_m09_e26_n : sshd refuse les mots de passe" "root@$_m09_e26_n.$_M09P_ZONE" \
    '^passwordauthentication no$' 'sshd -T 2>/dev/null'
done

title "Documentation"
check_cmd "docs/virtualisation/matrice-flux-hv-par1.md sur main" _m09p_doc "" matrice-flux-hv-par1
