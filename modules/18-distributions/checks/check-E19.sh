# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E19.sh — M18-E19 « Panne : le nœud k3s ne rejoint plus le cluster »
# Lecture seule : nœuds du banc k3s-ha (kubeconfig k3s-ha), service, horloge et configuration de l'agent
# k3s-ha02 (SSH, sudo -n pour lire ; le jeton n'est jamais affiché : seule son empreinte de CA est
# comparée à celle du serveur), joignabilité du superviseur depuis l'agent, documentation sur main.

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E19 — Le nœud k3s rejoint son cluster"
require_cmd kubectl jq ssh
_e19_srv=k3s-ha01.par1.medisphere.internal

check_cmd "l'API du banc k3s-ha répond (readyz)" _m18p_joignable "$_M18P_KC_K3SHA"
check_cmd "k3s-ha01 et k3s-ha02 sont Ready" _m18p_noeuds_prets "$_M18P_KC_K3SHA" 2

title "Agent k3s-ha02"
check_ssh_output "k3s-agent actif sans redémarrage depuis au moins 5 minutes" k3s-ha02 '^ok$' \
  't=$(date -d "$(systemctl show k3s-agent -p ActiveEnterTimestamp --value)" +%s 2>/dev/null) && systemctl is-active -q k3s-agent && [ $(( $(date +%s) - t )) -ge 300 ] && echo ok'
check_ssh_output "horloge synchronisée (NTPSynchronized=yes)" k3s-ha02 '^yes$' 'timedatectl show -p NTPSynchronized --value'
_e19_ecart() {
  local t
  t="$(remote k3s-ha02 'date +%s' 2>/dev/null)" || return 1
  [[ "$t" =~ ^[0-9]+$ ]] || return 1
  local d=$(( t - $(date +%s) ))
  (( d < 0 )) && d=$(( -d ))
  (( d < 60 ))
}
check_cmd "horloge de k3s-ha02 à moins d'une minute de celle de adm01" _e19_ecart
check_ssh_output "configuration : serveur k3s-ha01 sur le port 6443" k3s-ha02 "k3s-ha01(\\.par1\\.medisphere\\.internal)?:6443" \
  'sudo -n grep -rhsE "^(server:|K3S_URL=)" /etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.d/ /etc/systemd/system/k3s-agent.service.env'
# Empreinte de la CA portée par le jeton (format K10<sha256>::…) = empreinte de /cacerts du serveur.
# Jeton au format court (sans K10) : pas d'empreinte à comparer, contrôle neutre.
_e19_script_jeton="$(cat <<'SCRIPT'
f=/etc/rancher/k3s/config.yaml; e=/etc/systemd/system/k3s-agent.service.env
t="$(sed -n 's/^token:[[:space:]]*//p' "$f" 2>/dev/null | tr -d '"' | head -n 1)"
tf="$(sed -n 's/^token-file:[[:space:]]*//p' "$f" 2>/dev/null | tr -d '"' | head -n 1)"
[ -z "$t" ] && [ -n "$tf" ] && t="$(cat "$tf" 2>/dev/null)"
[ -z "$t" ] && t="$(sed -n 's/^K3S_TOKEN=//p' "$e" 2>/dev/null | tr -d "\"'")"
[ -n "$t" ] || exit 1
case "$t" in K10*) h="${t#K10}"; h="${h%%::*}" ;; *) echo ok; exit 0 ;; esac
[ "$h" = "$(curl -sk --max-time 5 "https://$SRV:6443/cacerts" | sha256sum | cut -d' ' -f1)" ] && echo ok
SCRIPT
)"
check_ssh_output "jeton : empreinte de CA conforme à celle du serveur (ou jeton au format court)" k3s-ha02 '^ok$' \
  "sudo -n env SRV=$_e19_srv bash -c $(printf '%q' "$_e19_script_jeton")"
check_ssh_output "le superviseur de k3s-ha01 répond depuis l'agent (TCP 6443)" k3s-ha02 '^pong$' \
  "curl -sk --max-time 5 https://$_e19_srv:6443/ping"

title "Documentation"
check_cmd "RB-183 publié (vérifications, messages typiques, ce qu'on ne fait jamais)" \
  _m18p_doc_prefixe docs/kubernetes/distributions/runbooks RB-183 'jeton|token' '6443' 'horloge|NTP|chrony' 'journalctl'
check_cmd "journal de diagnostic INC-4519 publié dans docs/kubernetes/journal/" \
  _m18p_un_fichier_contient plateforme/medisphere docs/kubernetes/journal 'INC-4519'
