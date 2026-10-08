# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent la sortie en argument ($1)
# check-E37.sh — M09-E37 « Panne : une VM HA reste en erreur » : aucune ressource HA en erreur ni
# bloquée, aucun nœud resté en maintenance par oubli, aucune règle désactivée pour conflit, pile HA
# armée, LRM actifs ou au repos partout. Lecture seule.

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E37 — La HA du cluster est saine"
require_cmd ssh

_m09_e37_ha="$(_m09x_ha_status)"
check_output "ha-manager status répond (quorum OK, CRM maître présent)" '^master [a-z0-9-]+ \(active' printf '%s\n' "$_m09_e37_ha"
check_cmd "aucune ressource HA en état error" bash -c '! grep -Eq "^service [^ ]+ \([^)]*error\)" <<<"$1"' _ "$_m09_e37_ha"
check_cmd "aucune ressource HA en attente de clôture ou de reprise (fence, recovery)" \
  bash -c '! grep -Eq "^service [^ ]+ \([^)]*(fence|recovery)\)" <<<"$1"' _ "$_m09_e37_ha"
for _m09_e37_n in "${_m09x_noeuds[@]}"; do
  check_output "$_m09_e37_n : LRM actif ou au repos (ni maintenance, ni perdu)" \
    "^lrm $_m09_e37_n \\((active|idle)" printf '%s\n' "$_m09_e37_ha"
done
check_cmd "pile HA armée (pas de disarm-ha en cours)" _m09x_pas_desarmee
check_ssh "aucune règle HA en conflit (désactivée automatiquement)" "$(_m09x_cible "$(_m09x_un_noeud)")" \
  "! ha-manager rules config 2>/dev/null | grep -qi 'conflict'"
check_cmd "VMs de test pan-ha (191-193) retirées de la HA" bash -c '! grep -Eq "^service vm:19[123] " <<<"$1"' _ "$_m09_e37_ha"
check_cmd "panne M09-E37 close (lab/bin/break 09 37 --annuler après réparation)" _m09x_aucune_panne_active E37
