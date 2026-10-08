# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées sur l'hôte distant
#
# check-E04.sh — M09-E04 : Former le cluster et ses liens Corosync
# À lancer depuis adm01. Lecture seule : pvecm, corosync-cmapctl, corosync-cfgtool, nft en root
# sur hv01 et hv02. Reste valable après E05 (QDevice) et E08 (troisième nœud).

# shellcheck source=_m09-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-decouverte.sh"

title "M09-E04 — Former le cluster et ses liens Corosync"

_m09d_e04_statut="$(_m09d_hv hv01 'pvecm status')"
check_cmd "Cluster nommé hv-par1" grep -Eq '^Name:[[:space:]]+hv-par1$' <<<"$_m09d_e04_statut"
check_cmd "Transport knet, authentification et chiffrement de Corosync actifs (Secure auth: on)" \
  bash -c 'grep -Eq "^Transport:[[:space:]]+knet$" <<<"$1" && grep -Eq "^Secure auth:[[:space:]]+on$" <<<"$1"' _ "$_m09d_e04_statut"
check_cmd "Le cluster a le quorum (vu de hv01)" grep -Eq '^Quorate:[[:space:]]+Yes$' <<<"$_m09d_e04_statut"
check_cmd "Au moins deux nœuds membres" bash -c 'n=$(sed -nE "s/^Nodes:[[:space:]]+([0-9]+)$/\1/p" <<<"$1"); [ "${n:-0}" -ge 2 ]' _ "$_m09d_e04_statut"
check_ssh "hv02 voit le même cluster, avec le quorum" hv02 \
  'pvecm status | grep -Eq "^Name:[[:space:]]+hv-par1$" && pvecm status | grep -Eq "^Quorate:[[:space:]]+Yes$"'
check_ssh "Les deux nœuds sont dans /etc/pve/nodes" hv01 'test -d /etc/pve/nodes/hv01 && test -d /etc/pve/nodes/hv02'

# --- Deux liens Corosync par nœud : lien 0 sur COROSYNC, lien 1 sur MGMT ----------------------------
check_cmd "hv01 : lien 0 = 10.10.32.51, lien 1 = 10.10.10.51" _m09d_anneaux hv01 hv01 10.10.32.51 10.10.10.51
check_cmd "hv02 : lien 0 = 10.10.32.52, lien 1 = 10.10.10.52" _m09d_anneaux hv01 hv02 10.10.32.52 10.10.10.52
for _m09d_e04_n in hv01 hv02; do
  check_ssh "$_m09d_e04_n : deux liens knet, aucun pair déconnecté" "$_m09d_e04_n" \
    'o=$(corosync-cfgtool -s) && [ "$(grep -c "^LINK ID" <<<"$o")" -ge 2 ] && ! grep -qi "disconnected" <<<"$o"'
  check_ssh "$_m09d_e04_n : la table nftables d'essai (m09_essai) a été retirée" "$_m09d_e04_n" \
    '! nft list tables 2>/dev/null | grep -q "m09_essai"'
done
check_ssh "Aucun nombre de votes attendus forcé à la baisse (expected = highest expected)" hv01 \
  's=$(corosync-quorumtool -s); e=$(sed -nE "s/^Expected votes:[[:space:]]+([0-9]+).*/\1/p" <<<"$s"); h=$(sed -nE "s/^Highest expected:[[:space:]]+([0-9]+).*/\1/p" <<<"$s"); [ -n "$e" ] && [ "$e" = "$h" ]'
