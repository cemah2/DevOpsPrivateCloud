# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E19.sh — M03-E19 « Panne : le build attend SSH indéfiniment »
# Tout ce dont une installation automatisée sur vsandbox a besoin : bail DHCP, DNS, accès au
# serveur HTTP de Packer, agent QEMU dans le preseed ; et rien d'oublié après l'essai.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E19 — Panne : le build attend SSH indéfiniment"
require_cmd jq ssh curl git
_m03_charger
_m03_preseed="$_M03_SRC/debian13-base/http/preseed.cfg"

title "Réseau de build (vsandbox)"
check_ssh "dns01 : configuration de dnsmasq valide" dns01 "dnsmasq --test"
check_ssh "dns01 : dnsmasq actif" dns01 "systemctl is-active -q dnsmasq"
check_ssh "dns01 : plage DHCP dynamique 10.10.99.100-199 du VLAN 99" dns01 \
  "grep -hE '^[[:space:]]*dhcp-range=.*10\.10\.99\.100,10\.10\.99\.1[0-9]{2}' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf"
check_ssh "gw01 : configuration persistante valide (nft -c)" gw01 "sudo -n nft -c -f /etc/nftables.conf"
check_ssh_output "gw01 : flux vsandbox → serveur HTTP de Packer (TCP 8100-8199) autorisé" gw01 \
  '8100-8199.*accept' "sudo -n nft list chain inet filter forward"
check_ssh "gw01 : aucun rejet des ports 8100-8199 ni du DNS pour vsandbox dans les règles chargées" gw01 \
  '! sudo -n nft list chain inet filter forward | grep -E "10\.10\.99\.0/24.*(8100-8199|dport 53).*drop"'
check_ssh "gw01 : DNS de vsandbox vers dns01 autorisé" gw01 \
  'sudo -n nft list chain inet filter forward | grep -E "10\.10\.20\.10.*53.*accept" | grep -q .'

title "Projet (image de base Debian)"
check_cmd "preseed : l'agent QEMU est installé (clone local)" grep -q 'qemu-guest-agent' "$_m03_preseed"
check_cmd "preseed : l'agent QEMU est installé (main)" \
  _m03_fichier_main_contient debian13-base/http/preseed.cfg 'qemu-guest-agent'
check_output "clone local : aucune modification non commitée dans debian13-base/" '^$' \
  git -C "$_M03_SRC" status --porcelain -- debian13-base

title "Après l'essai"
check_cmd "aucune VM d'essai restante (9090-9099)" _m03_aucune_vm 9090 9099
_m03_est_template() { _m03_conf "$1" | grep -q '^template: 1'; }
check_cmd "template 9001 (tpl-debian13-base) toujours présent" _m03_est_template 9001
check_cmd "journal de diagnostic de l'incident (docs/socle/journal/, INC-3001)" \
  bash -c 'grep -rqs "INC-3001" "$1"' _ "$_M03_DOC/journal"
