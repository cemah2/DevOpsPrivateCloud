# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur le nœud distant
# check-E35.sh — M09-E35 « Panne : le cluster a perdu le quorum » : les trois nœuds sont dans une même
# partition quorate à 3 votes, les deux liens Corosync sont connectés partout, la configuration de
# Corosync est cohérente et la pile HA est armée. Lecture seule.

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E35 — Le cluster hv-par1 a le quorum"
require_cmd ssh

for _m09_e35_n in "${_m09x_noeuds[@]}"; do
  check_cmd "$_m09_e35_n : quorate, 3 votes attendus et 3 présents" _m09x_membres_ok "$_m09_e35_n"
  check_cmd "$_m09_e35_n : liens Corosync 0 et 1 connectés vers les deux autres nœuds" _m09x_liens_ok "$_m09_e35_n"
  check_cmd "$_m09_e35_n : aucun filtrage parasite des ports de Corosync (table $_m09x_table absente)" \
    _m09x_pas_de_table "$_m09_e35_n"
  check_ssh "$_m09_e35_n : copie locale de corosync.conf identique à /etc/pve/corosync.conf" \
    "$(_m09x_cible "$_m09_e35_n")" 'cmp -s /etc/corosync/corosync.conf /etc/pve/corosync.conf'
done
check_ssh "corosync.conf : pas de expected_votes forcé dans la section quorum" "$(_m09x_cible hv01)" \
  '! grep -Eq "^[[:space:]]*expected_votes:" /etc/pve/corosync.conf'
check_output "authkey de Corosync identique sur les trois nœuds" '^1$' bash -c '
  for n in hv01 hv02 hv03; do
    ssh -o BatchMode=yes -o ConnectTimeout=8 ${WB_SSH_OPTS:-} "$n" "sha256sum < /etc/corosync/authkey" 2>/dev/null || echo erreur-$n
  done | sort -u | wc -l'
check_cmd "pile HA armée (pas de disarm-ha en cours)" _m09x_pas_desarmee
check_cmd "runbook RB-093 (perte de quorum) présent et commité dans le dépôt de documentation" \
  bash -c 'f=$(cd "$1" && ls docs/virtualisation/runbooks/RB-093*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && cd "$1" && git ls-files --error-unmatch "$f" >/dev/null 2>&1' _ "$_m09x_depot"
check_cmd "panne M09-E35 close (lab/bin/break 09 35 --annuler après réparation)" _m09x_aucune_panne_active E35
