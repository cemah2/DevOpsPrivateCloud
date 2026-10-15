# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E03.sh — M14-E03 : Le point d'accès de l'API : keepalived et HAProxy
# À lancer depuis adm01. Lecture seule : DNS, NetBox, connexion TCP à la VIP, état de keepalived
# et d'HAProxy sur les nœuds de contrôle (SSH, sudo -n, socket d'administration en « show stat »),
# API GitLab en GET. Valable aussi APRÈS l'amorçage (E04, E05) : l'état des serveurs n'est pas exigé
# DOWN, seulement déclaré et contrôlé.

# shellcheck source=_m14-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-decouverte.sh"

title "M14-E03 — Le point d'accès de l'API : keepalived et HAProxy"
require_cmd jq dig curl

# --- 1. Le nom et l'adresse -----------------------------------------------------------------------
check_dns "DNS : $_M14D_API → $_M14D_VIP" "$_M14D_API" A "^${_M14D_VIP//./\\.}$" "$_M14D_DNS"
check_cmd "NetBox : $_M14D_VIP/24 active, rôle « vip », nom $_M14D_API" bash -c \
  'jq -e --arg n "$1" ".count == 1 and .results[0].status.value == \"active\" and .results[0].role.value == \"vip\" and .results[0].dns_name == \$n" <<<"$2" >/dev/null' \
  _ "$_M14D_API" "$(netbox_api "ipam/ip-addresses/?address=$_M14D_VIP/24" 2>/dev/null || true)"

# --- 2. La VIP ----------------------------------------------------------------------------------------
_m14d_e03_porteurs="$(_m14d_porteur_vip)"
check_cmd "La VIP $_M14D_VIP est portée par un et un seul nœud de contrôle (${_m14d_e03_porteurs:-aucun})" \
  bash -c '[[ "$(wc -w <<<"$1")" -eq 1 ]]' _ "$_m14d_e03_porteurs"
check_port "adm01 → $_M14D_VIP:8443 : la VIP accepte les connexions TCP" "$_M14D_VIP" 8443
check_port "adm01 → $_M14D_API:8443 (par le nom)" "$_M14D_API" 8443

for _m14d_e03_n in "${_M14D_CP[@]}"; do
  read -r _ _m14d_e03_ip _ <<<"${_M14D_PLAN[$_m14d_e03_n]:-0 0 x}"
  # --- 3. keepalived -------------------------------------------------------------------------------
  check_ssh "$_m14d_e03_n : keepalived actif, configuration valide" "$_m14d_e03_n" \
    'systemctl is-active --quiet keepalived && sudo -n keepalived -t -f /etc/keepalived/keepalived.conf'
  check_ssh "$_m14d_e03_n : instance VRRP VRID 140, VIP $_M14D_VIP, annonces unicast depuis $_m14d_e03_ip" "$_m14d_e03_n" \
    "sudo -n grep -Eq '^ *virtual_router_id 140\$' /etc/keepalived/keepalived.conf && sudo -n grep -Fq '${_M14D_VIP}/24' /etc/keepalived/keepalived.conf && sudo -n grep -Eq '^ *unicast_src_ip ${_m14d_e03_ip//./\\.}\$' /etc/keepalived/keepalived.conf"
  check_ssh "$_m14d_e03_n : les deux autres nœuds de contrôle en pairs unicast" "$_m14d_e03_n" \
    "[ \"\$(sudo -n sed -n '/unicast_peer/,/}/p' /etc/keepalived/keepalived.conf | grep -Ec '^ *10\\.10\\.40\\.5[1-3]\$')\" -eq 2 ]"
  check_ssh "$_m14d_e03_n : pas de préemption, état HAProxy suivi (script de suivi)" "$_m14d_e03_n" \
    'sudo -n grep -Eq "^ *nopreempt$" /etc/keepalived/keepalived.conf && sudo -n grep -A2 "track_script" /etc/keepalived/keepalived.conf | grep -q chk_'

  # --- 4. HAProxy -------------------------------------------------------------------------------------
  check_ssh "$_m14d_e03_n : HAProxy actif, configuration valide (haproxy -c)" "$_m14d_e03_n" \
    'systemctl is-active --quiet haproxy && sudo -n haproxy -c -q -f /etc/haproxy/haproxy.cfg'
  check_ssh "$_m14d_e03_n : HAProxy écoute $_M14D_VIP:8443 (même sans porter la VIP)" "$_m14d_e03_n" \
    "ss -Hltn 'sport = :8443' | grep -Fq '${_M14D_VIP}:8443' && [ \"\$(sysctl -n net.ipv4.ip_nonlocal_bind)\" = 1 ]"
  check_ssh "$_m14d_e03_n : frontend et backend en mode TCP (le TLS va jusqu'à kube-apiserver)" "$_m14d_e03_n" \
    "sudo -n sed -n '/^frontend /,/^\$/p;/^backend /,/^\$/p' /etc/haproxy/haproxy.cfg | grep -c '^ *mode tcp' | grep -qx 2"
  _m14d_e03_stat="$(_m14d_haproxy_stat "$_m14d_e03_n")"
  check_cmd "$_m14d_e03_n : trois serveurs déclarés vers :6443, contrôlés, aucun en maintenance" bash -c \
    'awk -F, "\$1 == \"be_k8s_api\" && \$2 != \"BACKEND\" && \$2 != \"FRONTEND\" {n++; if (\$18 ~ /MAINT/ || \$18 == \"no check\") bad++} END {exit !(n == 3 && bad == 0)}" <<<"$1"' \
    _ "$_m14d_e03_stat"
done

# --- 5. Le code et la documentation -------------------------------------------------------------------
check_output "plateforme/infra (main) : envs/k8s/api.tf (VIP dans NetBox, nom sans PTR)" 'role *= *"vip"' \
  _m14d_contenu_main plateforme/infra envs/k8s/api.tf
for _m14d_e03_f in roles/k8s_plan_controle/tasks/main.yml roles/k8s_plan_controle/tasks/point_acces.yml playbooks/k8s-cluster.yml; do
  check_cmd "plateforme/ansible (main) : $_m14d_e03_f" _m14d_fichier_main plateforme/ansible "$_m14d_e03_f"
done
check_output "plateforme/medisphere (main) : matrice des flux à jour (VIP de l'API, 8443)" '8443' \
  _m14d_contenu_main plateforme/medisphere docs/socle/matrice-flux.md
