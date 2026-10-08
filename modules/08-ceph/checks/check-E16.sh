# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E16.sh — M08-E16 : Exports NFS
# À lancer depuis adm01. Lecture seule (nfs cluster info, nfs export info, port 2049).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E16 — Exports NFS"
require_cmd jq

_m08o_info="$(_m08o_ceph nfs cluster info par1)"
_m08o_export="$(_m08o_ceph nfs export info par1 /legacy-rdv)"
_m08o_sv="$(_m08o_ceph fs subvolume info cephfs legacy-rdv --group_name applications)"

check_cmd "cluster NFS par1 : démon sur ceph01, port 2049" \
  jq -e '.par1.backend | map(select(.hostname == "ceph01" and .port == 2049)) | length >= 1' <<<"$_m08o_info"
check_port "ceph01 (10.10.30.51) répond sur TCP 2049" 10.10.30.51 2049
check_cmd "sous-volume applications/legacy-rdv présent" jq -e '.path | startswith("/volumes/applications/legacy-rdv/")' <<<"$_m08o_sv"
check_cmd "export /legacy-rdv : sert le sous-volume applications/legacy-rdv (pas la racine du volume)" \
  jq -e '.pseudo == "/legacy-rdv" and (.path | startswith("/volumes/applications/legacy-rdv/")) and .fsal.name == "CEPH"' <<<"$_m08o_export"
check_cmd "export /legacy-rdv : fermé par défaut (access_type none)" \
  jq -e '(.access_type | ascii_downcase) == "none"' <<<"$_m08o_export"
check_cmd "export /legacy-rdv : lecture-écriture pour 10.10.30.20 seulement" \
  jq -e '[.clients[] | select((.access_type | ascii_downcase) == "rw")] as $c
         | ($c | length) >= 1 and ([$c[].addresses[]] | unique == ["10.10.30.20"])' <<<"$_m08o_export"
check_cmd "export /legacy-rdv : root_squash" \
  jq -e '[.clients[].squash | ascii_downcase | gsub("_"; "")] | all(. == "rootsquash" or . == "root")' <<<"$_m08o_export"
if remote "$_M08O_CLIENT" 'findmnt -n /mnt/legacy-rdv >/dev/null' >/dev/null 2>&1; then
  check_ssh "pieces-jointes/ appartient à un utilisateur non root" "$_M08O_CLIENT" \
    '[ "$(stat -c %u /mnt/legacy-rdv/pieces-jointes 2>/dev/null)" -gt 0 ] && [ "$(stat -c %u /mnt/legacy-rdv/pieces-jointes)" -ne 65534 ]'
else
  skip "propriétaire de pieces-jointes/" "export non monté sur cephcli01 : auto-évaluation (corrigé, étape 4)"
fi
