# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E08.sh — M06-E08 : Basculer le DNS du lab sans coupure
# À lancer depuis adm01. Lecture seule : qui tient le port 53 de dns01, résolution vue des
# clients du lab (SSH), DHCP toujours servi, documentation du changement.

# shellcheck source=_m06-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-decouverte.sh"

title "M06-E08 — Basculer le DNS du lab sans coupure"
require_cmd dig

# --- 1. Le port 53 a changé de propriétaire ---------------------------------------------------
check_ssh "dns01 : le port 53 est tenu par PowerDNS Recursor, et par lui seul" dns01 \
  's=$(sudo -n ss -Hlnup "sport = :53"; sudo -n ss -Hltnp "sport = :53"); grep -q pdns_recursor <<<"$s" && ! grep -Eq "dnsmasq|pdns_server" <<<"$s"'
check_output "10.10.20.10 : « version.bind » répond PowerDNS Recursor" 'PowerDNS Recursor 5\.4' \
  _m06d_dig "$_M06D_DNS" CH TXT version.bind
check_ssh "dns01 : plus rien n'écoute sur le port d'essai 5301" dns01 '! sudo -n ss -Hlnup "sport = :5301" | grep -q .'
# Après M06-E16, dnsmasq a quitté dns01 au profit de Kea : le contrôle accepte cet état ultérieur.
check_ssh "dns01 : dnsmasq ne fait plus de DNS (port=0) mais sert toujours le DHCP (ou Kea l'a remplacé, M06-E16)" dns01 \
  'if dpkg-query -W -f="\${Status}" dnsmasq 2>/dev/null | grep -q "install ok installed"; then
     systemctl is-active --quiet dnsmasq && sudo -n grep -Ehq "^port=0$" /etc/dnsmasq.d/*.conf && sudo -n ss -Hlnup "sport = :67" | grep -q dnsmasq
   else
     sudo -n ss -Hlnup "sport = :67" | grep -q kea-dhcp4
   fi'
check_ssh "dns01 : aucune règle nftables temporaire de bascule ne subsiste" dns01 \
  '! sudo -n nft list tables 2>/dev/null | grep -qi bascule'

# --- 2. Les clients ne voient pas la différence -----------------------------------------------------
check_cmd "adm01 : le nom court « git01 » se résout (domaine de recherche)" getent hosts git01
check_cmd "adm01 : un nom Internet se résout" getent ahostsv4 deb.debian.org
for _m06d_e08_h in gw01 dns01 git01 runner01; do
  check_ssh "$_m06d_e08_h : résout un nom du lab et un nom Internet" "$_m06d_e08_h" \
    'getent hosts adm01.par1.medisphere.internal >/dev/null && getent ahostsv4 deb.debian.org >/dev/null'
done
check_output "TCP : une question en TCP aboutit sur 10.10.20.10" '^10\.10\.20\.12$' \
  _m06d_dig "$_M06D_DNS" +tcp git01.par1.medisphere.internal A
check_output "Inverse d'une adresse privée inconnue : NXDOMAIN local (pas de fuite vers Internet)" 'status: NXDOMAIN' \
  _m06d_dig_complet "$_M06D_DNS" -x 10.10.99.254

# --- 3. Le changement est tracé ------------------------------------------------------------------------
check_cmd "Dépôt de documentation : fiche de changement CHG-708 (déroulé, retour arrière, compte rendu)" \
  bash -c 'f=$(find "$1/docs/socle" -iname "*CHG-708*" -name "*.md" 2>/dev/null | head -n 1); [[ -n "$f" ]] && grep -qi "retour arri" "$f" && grep -qi "compte rendu" "$f"' \
  _ "${WB_DEPOT:-$HOME/medisphere}"
check_cmd "plateforme/ansible (main) : playbook de bascule" _m06d_fichier_main playbooks/bascule-dns.yml
