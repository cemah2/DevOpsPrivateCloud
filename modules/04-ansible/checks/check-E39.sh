# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur pve01
# check-E39.sh — M04-E39 « Panne : l'inventaire dynamique est vide » : l'inventaire dynamique seul
# retrouve les cinq hôtes du socle dans les bons groupes ; le compte et le jeton wb-ansible sont
# en état. Lecture seule (API Proxmox en GET par le plugin, pveum en lecture).

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E39 — L'inventaire dynamique voit le socle"
require_cmd jq ssh

_m04_e39_json="$(_m04x_ansible ansible-inventory -i inventories/lab/proxmox.yml --list 2>/dev/null)" || _m04_e39_json='{}'

_m04_e39_dans() {
  _m04x_hotes_groupe "$_m04_e39_json" "$1" | grep -qx "$2"
}

check_cmd "inventories/lab/proxmox.yml présent" test -f "$_m04x_src/inventories/lab/proxmox.yml"
for _m04_e39_h in gw01 adm01 dns01 git01 runner01; do
  check_cmd "groupe socle : $_m04_e39_h" _m04_e39_dans socle "$_m04_e39_h"
done
check_cmd "groupe role_routeur : gw01" _m04_e39_dans role_routeur gw01
check_cmd "groupe role_bastion : adm01" _m04_e39_dans role_bastion adm01
check_cmd "groupe role_dns : dns01" _m04_e39_dans role_dns dns01
check_cmd "groupe role_gitlab : git01" _m04_e39_dans role_gitlab git01
check_cmd "groupe role_runner : runner01" _m04_e39_dans role_runner runner01
check_ssh "pve01 : ACL de l'utilisateur wb-ansible@pve sur /pool/lab" "$WB_PVE_HOST" \
  'pveum acl list --output-format json | perl -MJSON::PP -0777 -ne '"'"'for (@{decode_json($_)}) { exit 0 if $_->{path} eq "/pool/lab" && $_->{type} eq "user" && $_->{ugid} eq "wb-ansible\@pve" } exit 1'"'"
check_ssh "pve01 : jeton wb-ansible@pve!ansible valide encore au moins 30 jours" "$WB_PVE_HOST" \
  'pveum user token list wb-ansible@pve --output-format json | perl -MJSON::PP -0777 -ne '"'"'for (@{decode_json($_)}) { if ($_->{tokenid} eq "ansible") { my $e = $_->{expire} // 0; exit(($e == 0 || $e > time() + 30*86400) ? 0 : 1) } } exit 1'"'"
check_cmd "panne M04-E39 close" _m04x_aucune_panne_active E39
