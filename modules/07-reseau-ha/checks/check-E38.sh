# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E38.sh — M07-E38 « Panne : les gros transferts se figent » : la découverte du MTU du chemin
# fonctionne à travers la fabric, les deux extrémités de chaque lien leaf-spine ont le même MTU,
# aucun ICMP utile n'est jeté. Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E38 — MTU et découverte du MTU du chemin dans la fabric"
require_cmd ssh jq

# _m07_e38_mtu HÔTE PAIR — MTU de l'interface qui porte la session BGP PAIR (interface ou adresse).
_m07_e38_mtu() {
  _m07x_sur "$1" "p='$2'; if [ -e /sys/class/net/\$p ]; then d=\$p; else d=\$(ip -o route get \$p | sed -nE 's/.* dev ([^ ]+).*/\\1/p'); fi; cat /sys/class/net/\$d/mtu" 2>/dev/null
}

# _m07_e38_liens_coherents — toutes les extrémités des liens leaf ↔ spine (sessions vers l'AS 65100
# côté leaves, vers 65101/65102 côté spines) ont le même MTU : 4 liens, donc 8 extrémités.
_m07_e38_liens_coherents() {
  local h pair as mtus=()
  for h in leaf01 leaf02 spine01 spine02; do
    while read -r pair _ as _; do
      case "$h:$as" in
        leaf0?:65100 | spine0?:65101 | spine0?:65102) mtus+=("$(_m07_e38_mtu "$h" "$pair")") ;;
      esac
    done < <(_m07x_pairs "$h")
  done
  ((${#mtus[@]} >= 8)) || return 1
  [[ -n "${mtus[0]}" && "$(printf '%s\n' "${mtus[@]}" | sort -u | wc -l)" -eq 1 ]]
}

check_cmd "fabric : MTU identique sur les 8 extrémités des liens leaf ↔ spine" _m07_e38_liens_coherents
check_output "srv01 → srv02 : la découverte du MTU du chemin répond (écho ou « mtu = … »)" \
  '(bytes from|mtu)' _m07x_sur srv01 'ping -n -M do -s 1472 -c 3 -W 2 -I 10.10.255.21 10.10.255.22 2>&1'
for _m07_e38_h in spine01 spine02 leaf01 leaf02 srv01 srv02; do
  check_cmd "$_m07_e38_h : aucune règle nftables ne jette d'ICMP (hors limitation de débit)" \
    _m07x_pas_d_icmp_jete "$_m07_e38_h"
done
for _m07_e38_h in srv01 srv02; do
  check_cmd "$_m07_e38_h : un filtrage d'entrée en « drop » accepte aussi « related »" _m07x_ok "$_m07_e38_h" '
    r="$(nft list ruleset 2>/dev/null)"
    echo "$r" | grep -q "hook input.*policy drop" || exit 0
    echo "$r" | grep -q "related"'
done
if _m07x_ok srv02 'r="$(nginx -T 2>/dev/null | sed -nE "s/^[ \t]*root[ \t]+([^;]+);.*/\1/p" | head -n 1)"; [ -f "$r/export-nuit.bin" ]'; then
  check_cmd "srv01 → srv02 : le fichier export-nuit.bin se télécharge en moins de 20 s" _m07x_ok srv01 \
    'curl -sf -o /dev/null --max-time 20 --interface 10.10.255.21 http://10.10.255.22/export-nuit.bin'
else
  skip "téléchargement de export-nuit.bin" "fichier de test absent (panne close)"
fi
check_cmd "panne M07-E38 close (lab/bin/break 07 38 --annuler après réparation)" _m07x_aucune_panne_active E38
