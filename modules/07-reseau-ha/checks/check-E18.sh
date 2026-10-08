# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E18.sh — M07-E18 : Raccorder le site de Lyon en WireGuard
# À lancer depuis adm01, lyo-gw01 et lyo-pc01 démarrées. Lecture seule.
# Valable aussi après M07-E19 (les routes viennent alors de BGP : le contrôle porte sur la route,
# pas sur sa source).

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E18 — Raccorder le site de Lyon en WireGuard"

check_ssh "gw01 : wg2 écoute sur UDP 51822" gw01 '[ "$(sudo -n wg show wg2 listen-port)" = 51822 ]'
check_ssh "gw01 : wg2 porte 10.255.2.1/24" gw01 'ip -o -4 addr show dev wg2 | grep -q " 10\.255\.2\.1/24 "'
check_ssh "gw01 : poignée de main avec LYO1 de moins de 3 minutes" gw01 \
  't=$(sudo -n wg show wg2 latest-handshakes | awk "{print \$2}" | sort -n | tail -n 1); [ -n "$t" ] && [ "$t" -gt 0 ] && [ $(( $(date +%s) - t )) -lt 180 ]'
check_ssh "lyo-gw01 : wg2 porte 10.255.2.2 et vise 10.10.99.1:51822" lyo-gw01 \
  'ip -o -4 addr show dev wg2 | grep -q " 10\.255\.2\.2/" && sudo -n wg show wg2 endpoints | grep -q "10\.10\.99\.1:51822"'
check_ssh "gw01 : 10.30.0.0/16 routé par wg2" gw01 'ip route show 10.30.0.0/16 | grep -q "dev wg2"'
for _m07o_h in gw01 lyo-gw01; do
  check_ssh "$_m07o_h : /etc/wireguard/wg2.conf en 0600 root" "$_m07o_h" \
    '[ "$(sudo -n stat -c "%a %U" /etc/wireguard/wg2.conf)" = "600 root" ]'
done

check_ssh "lyo-pc01 : résout gitlab.par1… par 10.10.20.10, depuis le LAN de l'agence" lyo-pc01 \
  'dig +short +time=2 +tries=1 -b 10.30.10.10 @10.10.20.10 gitlab.par1.medisphere.internal A | grep -q "^10\.10\.70\.200$"'
check_ssh "lyo-pc01 : joint les services publiés (HTTPS, racine MédiSphère)" lyo-pc01 \
  '[ "$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://gitlab.par1.medisphere.internal/users/sign_in)" = 200 ]'
check_ssh "lyo-pc01 : la route vers INFRA passe par le routeur de l'agence" lyo-pc01 \
  'ip route get 10.10.20.10 | grep -q "via 10\.30\.10\.1"'
check_ssh "lyo-pc01 : MGMT n'est PAS joint par le tunnel (route d'administration conservée)" lyo-pc01 \
  '! ip route get 10.10.10.10 | grep -q "via 10\.30\.10\.1"'
check_ssh "lyo-pc01 : pas de ping vers adm01 depuis l'adresse de l'agence" lyo-pc01 \
  '! ping -c 2 -W 2 -I 10.30.10.10 10.10.10.10 >/dev/null 2>&1'

_m07o_in="$(_m07o_nft_gw01 input)"
check_output "gw01 : entrée du tunnel ouverte à lyo-gw01 seulement (UDP 51822)" \
  'ip saddr 10\.10\.99\.250 udp dport 51822 accept' echo "$_m07o_in"
check_output "gw01 : LYO1 autorisé vers la VIP des répartiteurs (443)" \
  'iifname "wg2".*ip saddr 10\.30\.0\.0/16.*ip daddr 10\.10\.70\.200 tcp dport 443 accept' _m07o_nft_gw01 forward
check_cmd "plateforme/ansible : rôle wireguard sur main" \
  _m07o_fichier_main "$_M07O_PROJET_ANSIBLE" roles/wireguard/tasks/main.yml
_m07o_cle_claire() {
  # Une clé privée WireGuard en clair (44 caractères base64 après « PrivateKey = ») dans le dépôt.
  local c
  c="$(_m07o_contenu_dossier "$_M07O_PROJET_ANSIBLE" roles/wireguard/templates)$(_m07o_contenu_main "$_M07O_PROJET_ANSIBLE" inventories/lab/host_vars/gw01/wireguard.yml)"
  [[ -n "$c" ]] && ! grep -Eq '^[[:space:]]*(PrivateKey[[:space:]]*=|cle_privee:)[[:space:]]*"?[A-Za-z0-9+/]{43}="?[[:space:]]*$' <<<"$c"
}
check_cmd "plateforme/ansible : aucune clé privée WireGuard en clair (rôle, host_vars de gw01)" _m07o_cle_claire
