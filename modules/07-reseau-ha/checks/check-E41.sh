# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E41.sh — M07-E41 « Panne : ça part mais ça ne revient pas » : chemins aller et retour
# symétriques par la fabric entre les boucles de srv01 et srv02. Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E41 — Routage symétrique dans la maquette"
require_cmd ssh jq

check_cmd "srv01 → srv02 de boucle à boucle (ping -I 10.10.255.21 10.10.255.22)" _m07x_ok srv01 \
  'ping -n -c 2 -W 2 -I 10.10.255.21 10.10.255.22'
check_cmd "srv02 → srv01 de boucle à boucle (ping -I 10.10.255.22 10.10.255.21)" _m07x_ok srv02 \
  'ping -n -c 2 -W 2 -I 10.10.255.22 10.10.255.21'
# Le chemin de retour (route, règles de routage par politique comprises) ne contourne pas la fabric.
_m07_e41_pas_admin='a="$(ip -4 -o route show default | sed -nE "s/.* dev ([^ ]+).*/\1/p" | head -n 1)"
d="$(ip -o route get "$1" ${2:+from "$2"} | sed -nE "s/.* dev ([^ ]+).*/\1/p" | head -n 1)"
[ -n "$d" ] && [ "$d" != "$a" ]'
check_cmd "srv02 : la réponse vers 10.10.255.21 (source 10.10.255.22) part par la fabric" _m07x_ok srv02 \
  "set -- 10.10.255.21 10.10.255.22; $_m07_e41_pas_admin"
check_cmd "srv01 : la réponse vers 10.10.255.22 (source 10.10.255.21) part par la fabric" _m07x_ok srv01 \
  "set -- 10.10.255.22 10.10.255.21; $_m07_e41_pas_admin"
for _m07_e41_h in leaf01 leaf02; do
  check_cmd "$_m07_e41_h : les boucles des serveurs sont jointes par la fabric, pas par le VLAN 99" _m07x_ok "$_m07_e41_h" \
    "set -- 10.10.255.21; $_m07_e41_pas_admin && set -- 10.10.255.22 && $_m07_e41_pas_admin"
done
check_cmd "panne M07-E41 close (lab/bin/break 07 41 --annuler après réparation)" _m07x_aucune_panne_active E41
