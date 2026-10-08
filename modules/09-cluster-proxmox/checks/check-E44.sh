# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur le nœud ou par bash -c
# check-E44.sh — M09-E44 « Sous le capot : pmxcfs, votequorum et le gestionnaire HA » : compte rendu
# présent, structuré et commité ; aucune trace laissée active (journal de debug de Corosync, capture,
# copie de config.db hors du nœud). Lecture seule.

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E44 — Sous le capot du cluster"
require_cmd git ssh jq

_m09_e44_rel="docs/virtualisation/analyses/cluster-hv-par1-sous-le-capot.md"
_m09_e44_cr="$_m09x_depot/$_m09_e44_rel"
check_cmd "compte rendu $_m09_e44_rel présent" test -s "$_m09_e44_cr"
check_output "section sur pmxcfs" '^## .*pmxcfs' cat "$_m09_e44_cr"
check_output "section sur Corosync et votequorum" '^## .*([Vv]otequorum|[Cc]orosync)' cat "$_m09_e44_cr"
check_output "section sur le gestionnaire HA" '^## .*HA' cat "$_m09_e44_cr"
check_output "section « Réponses aux questions »" '^## Réponses aux questions' cat "$_m09_e44_cr"
check_cmd "observations citées (config.db, corosync-cmapctl, corosync-quorumtool, manager_status, watchdog-mux)" \
  bash -c 'for m in config.db corosync-cmapctl corosync-quorumtool manager_status watchdog-mux; do grep -q -- "$m" "$1" || exit 1; done' _ "$_m09_e44_cr"
check_cmd "compte rendu commité, sans modification en attente" _m09x_doc_commite "$_m09_e44_rel"
check_cmd "aucune clé privée ni jeton dans le compte rendu" \
  bash -c '! grep -Eq "PRIVATE KEY|PVEAPIToken=|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" "$1"' _ "$_m09_e44_cr"
for _m09_e44_n in "${_m09x_noeuds[@]}"; do
  check_ssh "$_m09_e44_n : aucune capture tcpdump en cours, pas de copie de config.db hors de /var/lib/pve-cluster" \
    "$(_m09x_cible "$_m09_e44_n")" \
    '! pgrep -x tcpdump >/dev/null && ! find /root /tmp /var/tmp -xdev -name "config.db*" 2>/dev/null | grep -q .'
done
check_output "VM de test 198 supprimée" '^0$' \
  bash -c 'jq "[.[] | select(.vmid == 198)] | length" <<<"$1" 2>/dev/null || echo erreur' _ \
  "$(_m09x_json "$(_m09x_un_noeud)" /cluster/resources --type vm)"
check_ssh "corosync.conf : journal de debug désactivé" "$(_m09x_cible hv01)" \
  '! grep -Eq "^[[:space:]]*debug:[[:space:]]*on" /etc/pve/corosync.conf'
check_cmd "aucune copie de config.db sur adm01 (elle contient /etc/pve/priv)" \
  bash -c '! find "$HOME" -xdev -name "config.db*" 2>/dev/null | grep -q .'
