# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E30.sh — M06-E30 « Durcir les services et mettre à jour la matrice des flux »
# Lancé depuis adm01. Lecture seule : règles nftables (sudo -n), tentatives de connexion TCP
# depuis runner01 et adm01 (sans échange de données), dépôt de documentation.

# shellcheck source=_m06-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-production.sh"

title "M06-E30 — Durcir les services et mettre à jour la matrice des flux"
require_cmd ssh jq curl

title "Filtrage d'entrée local"
for _m06_h in dns01 dns02 ca01 nbx01; do
  check_ssh_output "$_m06_h : chaîne d'entrée locale en politique drop" "$_m06_h" 'hook input .*policy drop' \
    'sudo -n nft list table inet filtre_local'
  check_ssh "$_m06_h : filtrage chargé au démarrage (nftables activé)" "$_m06_h" 'systemctl is-enabled --quiet nftables'
done

title "Depuis runner01 (même VLAN que les services)"
check_cmd "runner01 → dns01:5300 (serveur faisant autorité) : fermé" _m06p_port_ferme runner01 10.10.20.10 5300
check_cmd "runner01 → dns01:8004 (contrôle Kea) : fermé" _m06p_port_ferme runner01 10.10.20.10 8004
check_cmd "runner01 → dns02:8001 (écouteur HA de Kea) : fermé" _m06p_port_ferme runner01 10.10.20.16 8001
check_cmd "runner01 → nbx01:5432 (PostgreSQL) : fermé" _m06p_port_ferme runner01 10.10.20.13 5432
check_cmd "runner01 → nbx01:6379 (Valkey) : fermé" _m06p_port_ferme runner01 10.10.20.13 6379
check_cmd "runner01 → dns01:8081 (API PowerDNS) : ouvert" _m06p_port_ouvert runner01 10.10.20.10 8081
check_cmd "runner01 → dns01:53 (DNS en TCP) : ouvert" _m06p_port_ouvert runner01 10.10.20.10 53
check_cmd "runner01 → dns02:22 (SSH, pipeline Ansible) : ouvert" _m06p_port_ouvert runner01 10.10.20.16 22
check_cmd "runner01 → ca01:443 (ACME) : ouvert" _m06p_port_ouvert runner01 10.10.20.11 443
check_cmd "runner01 → nbx01:443 (NetBox) : ouvert" _m06p_port_ouvert runner01 10.10.20.13 443

title "Depuis adm01"
for _m06_p in 5300 8004 8081; do
  check_port "adm01 → dns01:$_m06_p : ouvert" 10.10.20.10 "$_m06_p"
done
check_port "adm01 → ca01:80 (CRL) : ouvert" 10.10.20.11 80

title "Matrice de gw01"
check_ssh_output "gw01 : DNS vers dns02 dans la chaîne forward" gw01 \
  'daddr \{[^}]*10\.10\.20\.16[^}]*\}.*dport 53|daddr 10\.10\.20\.16 .*dport 53' 'sudo -n nft list chain inet filter forward'
check_ssh_output "gw01 : renouvellements DHCP vers dns02 dans la chaîne forward" gw01 \
  'daddr \{[^}]*10\.10\.20\.16[^}]*\}.*dport 67|daddr 10\.10\.20\.16 .*dport 67' 'sudo -n nft list chain inet filter forward'
check_ssh_output "gw01 : sauvegardes applicatives du module 06 vers PBS" gw01 \
  'saddr \{[^}]*10\.10\.20\.1[13][^}]*\}.*dport 8007' 'sudo -n nft list chain inet filter forward'
check_ssh "gw01 : /etc/nftables.conf valide" gw01 'sudo -n nft -c -f /etc/nftables.conf'

title "Documentation"
_m06_mf="$(_m06p_fichier_main plateforme/medisphere docs/socle/matrice-flux.md 2>/dev/null || true)"
check_output "matrice-flux.md : dns02 mentionné" 'dns02' printf '%s\n' "$_m06_mf"
check_output "matrice-flux.md : CRL mentionnée" '[Cc][Rr][Ll]' printf '%s\n' "$_m06_mf"
check_output "matrice-flux.md : flux internes au VLAN INFRA traités" '(INFRA|pare_feu_local)' printf '%s\n' "$_m06_mf"
