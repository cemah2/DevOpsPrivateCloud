# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur le nœud distant
# check-E36.sh — M09-E36 « Panne : un nœud ne rejoint plus le cluster » : chaque nœud est membre,
# annonce sa bonne adresse, a l'heure juste, sert son API et répond aux appels relayés. Lecture seule.

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E36 — Les trois nœuds sont pleinement dans le cluster"
require_cmd ssh jq

_m09_e36_membres="$(_m09x_hv hv01 'cat /etc/pve/.members' 2>/dev/null)"
for _m09_e36_n in "${_m09x_noeuds[@]}"; do
  check_cmd "$_m09_e36_n : membre de la partition quorate à 3 votes" _m09x_membres_ok "$_m09_e36_n"
  check_output "$_m09_e36_n : adresse annoncée dans /etc/pve/.members = ${_m09x_ip[$_m09_e36_n]}, en ligne" \
    "^${_m09x_ip[$_m09_e36_n]//./\\.} 1\$" \
    jq -r --arg n "$_m09_e36_n" '.nodelist[$n] | "\(.ip) \(.online)"' <<<"$_m09_e36_membres"
  check_ssh_output "$_m09_e36_n : son nom se résout localement vers ${_m09x_ip[$_m09_e36_n]}" \
    "$(_m09x_cible "$_m09_e36_n")" "^${_m09x_ip[$_m09_e36_n]//./\\.}[[:space:]]" "getent hosts $_m09_e36_n"
  check_ssh "$_m09_e36_n : chrony actif et activé, horloge synchronisée" "$(_m09x_cible "$_m09_e36_n")" \
    'systemctl is-active -q chrony && systemctl is-enabled -q chrony && chronyc tracking | grep -Eq "^Leap status[[:space:]]+: Normal"'
  check_cmd "$_m09_e36_n : écart d'horloge avec adm01 inférieur à 5 s" bash -c '
    t=$(ssh -o BatchMode=yes -o ConnectTimeout=8 ${WB_SSH_OPTS:-} "$1" date +%s 2>/dev/null) || exit 1
    d=$(( t - $(date +%s) )); [ "${d#-}" -lt 5 ]' _ "$(_m09x_cible "$_m09_e36_n")"
  check_ssh "$_m09_e36_n : pveproxy actif, l'interface répond sur 8006" "$(_m09x_cible "$_m09_e36_n")" \
    'systemctl is-active -q pveproxy && timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/8006"'
  check_ssh "hv01 → $_m09_e36_n : appel d'API relayé (pvesh get /nodes/$_m09_e36_n/version)" "$(_m09x_cible hv01)" \
    "timeout 25 pvesh get /nodes/$_m09_e36_n/version --output-format json >/dev/null"
done
check_output "authkey de Corosync identique sur les trois nœuds" '^1$' bash -c '
  for n in hv01 hv02 hv03; do
    ssh -o BatchMode=yes -o ConnectTimeout=8 ${WB_SSH_OPTS:-} "$n" "sha256sum < /etc/corosync/authkey" 2>/dev/null || echo erreur-$n
  done | sort -u | wc -l'
check_cmd "pile HA armée (pas de disarm-ha en cours)" _m09x_pas_desarmee
check_cmd "panne M09-E36 close (lab/bin/break 09 36 --annuler après réparation)" _m09x_aucune_panne_active E36
