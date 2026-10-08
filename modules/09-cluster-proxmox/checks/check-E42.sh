# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur le nœud distant
# check-E42.sh — M09-E42 « Panne : impossible de modifier une VM » : sur chaque nœud, pmxcfs tourne,
# /etc/pve est monté et le nœud a le quorum ; disque système non saturé ; la VIP de l'API est portée
# par un nœud quorate. Lecture seule (aucune écriture d'essai dans /etc/pve).

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E42 — /etc/pve est inscriptible partout"
require_cmd ssh

for _m09_e42_n in "${_m09x_noeuds[@]}"; do
  _m09_e42_c="$(_m09x_cible "$_m09_e42_n")"
  check_cmd "$_m09_e42_n : pve-cluster actif, /etc/pve monté, nœud quorate" _m09x_ecriture_pve_possible "$_m09_e42_n"
  check_ssh "$_m09_e42_n : système de fichiers racine rempli à moins de 90 %" "$_m09_e42_c" \
    '[ "$(df --output=pcent / | tail -n 1 | tr -dc 0-9)" -lt 90 ]'
  check_ssh "$_m09_e42_n : aucun fichier caché sous le point de montage /etc/pve" "$_m09_e42_c" '
    m=$(mktemp -d) && mount --bind -o ro / "$m" 2>/dev/null || { rmdir "$m"; exit 0; }
    n=$(find "$m/etc/pve" -mindepth 1 2>/dev/null | wc -l); umount "$m"; rmdir "$m"; [ "$n" -eq 0 ]'
  check_cmd "$_m09_e42_n : aucun filtrage parasite (table $_m09x_table absente)" _m09x_pas_de_table "$_m09_e42_n"
done
_m09_e42_vip=""
for _m09_e42_n in "${_m09x_noeuds[@]}"; do
  if _m09x_hv "$_m09_e42_n" "ip -4 -o addr show | grep -qF ' 10.10.10.200/'" >/dev/null 2>&1; then
    _m09_e42_vip="$_m09_e42_n"
  fi
done
if [[ -n "$_m09_e42_vip" ]]; then
  check_cmd "VIP 10.10.10.200 portée par un nœud quorate ($_m09_e42_vip)" _m09x_ecriture_pve_possible "$_m09_e42_vip"
else
  skip "VIP 10.10.10.200 portée par un nœud quorate" "aucune VIP (M09-E18 non fait ?)"
fi
check_cmd "pile HA armée (pas de disarm-ha en cours)" _m09x_pas_desarmee
check_cmd "panne M09-E42 close (lab/bin/break 09 42 --annuler après réparation)" _m09x_aucune_panne_active E42
