# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M14-E39 « Panne : l'API ne répond plus » : l'API répond par la VIP, chacun des trois
# kube-apiserver répond directement avec un certificat valable pour le nom ET l'adresse de la VIP,
# HAProxy et keepalived actifs partout, VIP portée par un seul nœud, suivi keepalived en place,
# aucun filtrage du 8443, manifeste kube-apiserver sain, RB-146, panne close. Lecture seule.

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E39 — L'API répond par la VIP"
require_cmd jq kubectl ssh

check_output "l'API répond par https://$_m14x_api:8443 (/livez)" '^ok$' kube get --raw /livez
for _m14_e39_h in "${_m14x_cp[@]}"; do
  _m14_e39_ip="${_m14x_ip[$_m14_e39_h]}"
  check_output "$_m14_e39_h : kube-apiserver répond en direct, certificat valable pour $_m14x_api" '^ok$' \
    kube --server "https://$_m14_e39_ip:6443" --tls-server-name "$_m14x_api" get --raw /livez
  check_output "$_m14_e39_h : certificat valable aussi pour l'adresse de la VIP ($_m14x_vip)" '^ok$' \
    kube --server "https://$_m14_e39_ip:6443" --tls-server-name "$_m14x_vip" get --raw /livez
  check_cmd "$_m14_e39_h : HAProxy et keepalived actifs" \
    _m14x_noeud "$_m14_e39_h" 'systemctl is-active -q haproxy && systemctl is-active -q keepalived'
  # shellcheck disable=SC2016
  check_cmd "$_m14_e39_h : keepalived suit bien son contrôle (vrrp_script ⇒ track_script)" \
    _m14x_noeud "$_m14_e39_h" 'f=/etc/keepalived/keepalived.conf; ! grep -q "^[[:space:]]*vrrp_script" "$f" || grep -q "^[[:space:]]*track_script" "$f"'
  check_cmd "$_m14_e39_h : aucune règle nftables ne jette le port 8443" \
    _m14x_noeud "$_m14_e39_h" '! nft list ruleset 2>/dev/null | grep -Eq "dport 8443 .*(drop|reject)"'
  check_cmd "$_m14_e39_h : manifeste kube-apiserver vers l'etcd local (127.0.0.1:2379)" \
    _m14x_noeud "$_m14_e39_h" 'grep -q -- "--etcd-servers=https://127.0.0.1:2379" /etc/kubernetes/manifests/kube-apiserver.yaml'
done
_m14_e39_porteurs() {
  local h n=0
  for h in "${_m14x_cp[@]}"; do
    remote "$h" "ip -4 -o addr show | grep -qw $_m14x_vip" </dev/null >/dev/null 2>&1 && n=$((n + 1))
  done
  ((n == 1))
}
check_cmd "VIP $_m14x_vip portée par exactement un nœud de contrôle" _m14_e39_porteurs
check_cmd "RB-146 (l'API ne répond plus) publié et commité" _m14x_doc_commite 'docs/kubernetes/runbooks/RB-146-*.md'
check_cmd "panne M14-E39 close (lab/bin/break 14 39 --annuler après réparation)" _m14x_aucune_panne_active E39
