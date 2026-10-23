# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E39.sh — M25-E39 « Panne : la grappe n'a plus de leader » : les trois nœuds répondent,
# descellés ; un seul actif (200), deux en attente (429) ; la VIP mène à l'actif ; la configuration
# Raft compte toujours vault01, vault02 et vault03, tous électeurs (aucun pair retiré dans la
# précipitation) ; autopilot sain, tolérance d'au moins une panne, chaque serveur sain ; openbao actif
# et activé sur chaque nœud ; plus aucun filtrage du port de grappe 8201 ; journal INC-5239 sur main.
# Lecture seule : sys/health et sys/leader sans jeton, AppRole wb-checks (Raft, autopilot : lectures
# ajoutées au M25-E24), SSH en consultation (systemctl, nft list), GitLab en lecture.

# shellcheck source=_m25-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert.sh"

title "M25-E39 — Panne : la grappe n'a plus de leader"
require_cmd curl jq
_m25p_connexion

for _m25x_e39_n in "${_M25P_NOEUDS[@]}"; do
  check_cmd "$_m25x_e39_n : répond et est descellé (sys/health)" \
    _m25p_jq "$(_m25p_sante "$_m25x_e39_n")" '.initialized == true and .sealed == false'
done

_m25x_e39_codes() {
  local n c actifs=0 attente=0
  for n in "${_M25P_NOEUDS[@]}"; do
    c="$(_m25p_code "$n")"
    case "$c" in 200) actifs=$((actifs + 1)) ;; 429) attente=$((attente + 1)) ;; esac
  done
  ((actifs == 1 && attente == ${#_M25P_NOEUDS[@]} - 1))
}
check_cmd "un nœud actif (200) et deux en attente (429) : la grappe a de nouveau un leader" _m25x_e39_codes
check_cmd "sys/leader lu par la VIP : le nœud qui la porte est l'actif (is_self)" \
  _m25p_jq "$(curl -s --max-time "$WB_TIMEOUT" "https://$_M25P_SERVICE:$_M25P_PORT/v1/sys/leader" 2>/dev/null || echo null)" '.is_self == true'

_m25x_e39_raft="$(_m25p_bao sys/storage/raft/configuration)"
if [[ "$_m25x_e39_raft" == null ]]; then
  check_cmd "configuration Raft lisible (grappe sans actif, ou AppRole wb-checks sans sys/storage/raft/configuration ?)" false
else
  check_cmd "Raft : vault01, vault02 et vault03 sont toujours pairs (aucun remove-peer), tous électeurs" \
    _m25p_jq "$_m25x_e39_raft" '([.data.config.servers[].node_id] | sort == ["vault01", "vault02", "vault03"]) and all(.data.config.servers[]; .voter == true)'
  check_cmd "Raft : un seul leader" _m25p_jq "$_m25x_e39_raft" '[.data.config.servers[] | select(.leader)] | length == 1'
fi
check_cmd "autopilot : sain, tolérance d'au moins une panne, chacun des trois serveurs sain" \
  _m25p_jq "$(_m25p_bao sys/storage/raft/autopilot/state)" \
  '.data.healthy == true and .data.failure_tolerance >= 1 and ([.data.servers[] | select(.healthy == true)] | length == 3)'

for _m25x_e39_n in "${_M25P_NOEUDS[@]}"; do
  check_ssh "$_m25x_e39_n : openbao actif et activé au démarrage" "$_m25x_e39_n" \
    'systemctl is-active --quiet openbao && systemctl is-enabled --quiet openbao'
  check_ssh "$_m25x_e39_n : aucune règle nftables ne bloque le port de grappe 8201" "$_m25x_e39_n" \
    'r="$(sudo -n nft list ruleset)" && [ -n "$r" ] && ! printf "%s\n" "$r" | grep -E "8201" | grep -Eq "(drop|reject)"'
done

check_cmd "journal de diagnostic INC-5239 sur main (plateforme/medisphere)" _m25x_journal INC-5239
