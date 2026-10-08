# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les expressions entre apostrophes sont évaluées sur l'hôte distant
#
# check-E08.sh — M07-E08 : Une adresse virtuelle avec VRRP
# À lancer depuis adm01. Lecture seule : HTTP vers srv01, srv02 et la VIP, état des serveurs en
# SSH (configuration de keepalived, adresses, journal), API GitLab en lecture.

# shellcheck source=_m07-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-decouverte.sh"

title "M07-E08 — Une adresse virtuelle avec VRRP"
require_cmd jq curl dig

_m07d_e08_vip="10.10.99.240"

# --- 1. Les serveurs web --------------------------------------------------------------------------
for _m07d_e08_v in srv01:10.10.99.252 srv02:10.10.99.253; do
  _m07d_e08_s="${_m07d_e08_v%%:*}"; _m07d_e08_ip="${_m07d_e08_v##*:}"
  check_output "$_m07d_e08_s : la page d'accueil donne le nom du serveur" "$_m07d_e08_s" \
    curl -s --max-time "$WB_TIMEOUT" --noproxy '*' "http://$_m07d_e08_ip/"
  check_output "$_m07d_e08_s : GET /sante répond « ok »" '^ok$' \
    curl -sf --max-time "$WB_TIMEOUT" --noproxy '*' "http://$_m07d_e08_ip/sante"
done

# --- 2. keepalived : version, VRID, unicast, suivi, scripts non privilégiés ----------------------
for _m07d_e08_v in srv01:10.10.99.252:10.10.99.253 srv02:10.10.99.253:10.10.99.252; do
  IFS=: read -r _m07d_e08_s _m07d_e08_moi _m07d_e08_pair <<<"$_m07d_e08_v"
  check_cmd "$_m07d_e08_s : keepalived actif et lancé au démarrage" _m07d_actif "$_m07d_e08_s" keepalived.service
  _m07d_e08_conf="$(remote "$_m07d_e08_s" 'sudo -n cat /etc/keepalived/keepalived.conf' 2>/dev/null || true)"
  check_output "$_m07d_e08_s : VRRP version 3" '^[[:space:]]*vrrp_version 3' printf '%s' "$_m07d_e08_conf"
  check_output "$_m07d_e08_s : VRID 199" '^[[:space:]]*virtual_router_id 199[[:space:]]*$' printf '%s' "$_m07d_e08_conf"
  check_cmd "$_m07d_e08_s : annonces unicast ($_m07d_e08_moi → $_m07d_e08_pair)" \
    bash -c 'grep -Eq "unicast_src_ip $2" <<<"$1" && grep -Eq "unicast_peer" <<<"$1" && grep -Eq "^[[:space:]]+$3[[:space:]]*$" <<<"$1"' \
    _ "$_m07d_e08_conf" "${_m07d_e08_moi//./\\.}" "${_m07d_e08_pair//./\\.}"
  check_cmd "$_m07d_e08_s : un script de suivi est attaché à l'instance (track_script)" \
    bash -c 'grep -q "track_script" <<<"$1" && grep -q "vrrp_script" <<<"$1"' _ "$_m07d_e08_conf"
  check_cmd "$_m07d_e08_s : scripts sous un compte non privilégié (script_user ≠ root, enable_script_security)" \
    bash -c 'u=$(sed -nE "s/^[[:space:]]*script_user[[:space:]]+([^[:space:]]+).*/\1/p" <<<"$1"); [[ -n "$u" && "$u" != root ]] && grep -q "enable_script_security" <<<"$1"' \
    _ "$_m07d_e08_conf"
done

# --- 3. La VIP : un seul porteur, srv01 quand tout va bien ---------------------------------------
_m07d_e08_porteurs="$(for s in srv01 srv02; do
  remote "$s" "ip -4 -br addr show dev eth0" 2>/dev/null | grep -q "$_m07d_e08_vip/" && echo "$s"
done | tr '\n' ' ')"
check_cmd "VIP $_m07d_e08_vip portée par srv01 seul (porteur(s) : ${_m07d_e08_porteurs:-aucun})" \
  test "$_m07d_e08_porteurs" = "srv01 "
check_dns "DNS : web-demo.par1.medisphere.internal → $_m07d_e08_vip" web-demo.par1.medisphere.internal A '^10\.10\.99\.240$' "$_M07D_DNS"
check_output "http://web-demo.par1.medisphere.internal/ répond « srv01 »" 'srv01' \
  curl -s --max-time "$WB_TIMEOUT" --noproxy '*' http://web-demo.par1.medisphere.internal/

# --- 4. Une bascule a eu lieu ---------------------------------------------------------------------
check_ssh "srv02 : le journal montre au moins un passage à l'état maître (bascule testée)" srv02 \
  '{ sudo -n journalctl --no-pager -o cat -t keepalived-transition; sudo -n journalctl --no-pager -o cat -u keepalived.service; } | grep -Eq "etat=MASTER|Entering MASTER STATE"'

# --- 5. Le code -------------------------------------------------------------------------------------
check_cmd "plateforme/ansible (main) : rôle keepalived" _m07d_ansible_main roles/keepalived/tasks/main.yml
check_cmd "plateforme/ansible (main) : rôle nginx_web" _m07d_ansible_main roles/nginx_web/tasks/main.yml
check_cmd "plateforme/ansible (main) : scénario Molecule keepalived" _m07d_ansible_main molecule/keepalived/molecule.yml
check_cmd "plateforme/ansible (main) : playbook m07-web.yml" _m07d_ansible_main playbooks/m07-web.yml
