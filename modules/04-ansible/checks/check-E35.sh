# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E35.sh — M04-E35 « Panne : UNREACHABLE sur une partie du socle » : état sain.
# Chaque hôte du socle est joint par Ansible avec les bons paramètres de connexion, une nouvelle
# connexion SSH (sans multiplexage) aboutit, et le compte admin est valide. Lecture seule.

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E35 — Ansible joint tout le socle"
require_cmd ssh jq

# _m04_e35_inv HÔTE — l'inventaire donne la bonne adresse et le bon compte de connexion.
_m04_e35_inv() {
  local j
  j="$(_m04x_inv_host "$1")" || return 1
  jq -e --arg ip "${_m04x_ip[$1]}" '.ansible_host == $ip and ((.ansible_user // "admin") == "admin")' >/dev/null <<<"$j"
}

for _m04_e35_h in gw01 dns01 git01 runner01; do
  check_cmd "$_m04_e35_h : nouvelle connexion SSH (clé d'hôte reconnue, compte accepté)" _m04x_ssh_neuf "$_m04_e35_h"
  check_cmd "$_m04_e35_h : inventaire (ansible_host ${_m04x_ip[$_m04_e35_h]}, utilisateur admin)" _m04_e35_inv "$_m04_e35_h"
  check_cmd "$_m04_e35_h : Ansible le joint (module ping)" _m04x_ping "$_m04_e35_h"
done
check_cmd "adm01 : Ansible le gère (module ping)" _m04x_ping adm01
for _m04_e35_h in dns01 git01 runner01; do
  check_ssh "$_m04_e35_h : compte admin sans expiration échue" "$_m04_e35_h" \
    'e=$(sudo -n getent shadow admin | cut -d: -f8); [ -z "$e" ] || [ "$e" -gt "$(( $(date +%s) / 86400 ))" ]'
done
check_cmd "panne M04-E35 close (lab/bin/break 04 35 --annuler après réparation)" _m04x_aucune_panne_active E35
