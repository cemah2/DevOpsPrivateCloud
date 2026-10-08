# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur le nœud distant
# check-E41.sh — M09-E41 « Panne : la sauvegarde nocturne a échoué » : stockage pbs-par2 actif sur
# chaque nœud, datastore et namespace attendus, sauvegardes listées, au moins une sauvegarde de moins
# de 24 h (preuve que le chemin d'écriture refonctionne). Lecture seule.

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E41 — Les sauvegardes vers PBS refonctionnent"
require_cmd ssh jq

for _m09_e41_n in "${_m09x_noeuds[@]}"; do
  check_ssh_output "$_m09_e41_n : stockage pbs-par2 actif" "$(_m09x_cible "$_m09_e41_n")" \
    '^pbs-par2[[:space:]]+pbs[[:space:]]+active' 'pvesm status --storage pbs-par2'
done
check_ssh "storage.cfg : pbs-par2 vers le datastore ds-lab, namespace par1/hv" "$(_m09x_cible hv01)" '
  s=$(awk "/^[a-z]+: /{d=(\$2==\"pbs-par2\")} d" /etc/pve/storage.cfg)
  grep -Eq "^[[:space:]]+datastore ds-lab$" <<<"$s" && grep -Eq "^[[:space:]]+namespace par1/hv$" <<<"$s"'
_m09_e41_liste="$(_m09x_json hv01 /nodes/hv01/storage/pbs-par2/content --content backup)"
check_output "pbs-par2 : les sauvegardes du namespace sont listées" '^[1-9][0-9]*$' \
  bash -c 'jq length <<<"$1" 2>/dev/null' _ "$_m09_e41_liste"
check_output "pbs-par2 : au moins une sauvegarde de moins de 24 h" '^[1-9][0-9]*$' \
  bash -c 'jq --argjson t "$(( $(date +%s) - 86400 ))" "[.[] | select((.ctime // 0) > \$t)] | length" <<<"$1" 2>/dev/null' _ "$_m09_e41_liste"
check_cmd "panne M09-E41 close (lab/bin/break 09 41 --annuler après réparation)" _m09x_aucune_panne_active E41
