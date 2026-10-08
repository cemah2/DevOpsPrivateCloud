# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E15.sh — M09-E15 : Sauvegarder le cluster vers PBS
# À lancer depuis adm01. Lecture seule : storage.cfg (sans les secrets), présence de la clé (pas son
# contenu), tâche de sauvegarde, liste des sauvegardes, ACL de pbs01 en lecture, registre des secrets.

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E15 — Sauvegarder le cluster vers PBS"
require_cmd jq

_m09o_s="$(_m09o_stockage_cfg pbs-par2)"
check_output "pbs-par2 : type pbs, serveur 10.20.10.10, datastore ds-lab" '^pbs: pbs-par2' echo "$_m09o_s"
check_cmd "pbs-par2 : serveur 10.20.10.10 et datastore ds-lab" bash -c \
  'grep -Eq "^[[:space:]]+server 10\.20\.10\.10$" <<<"$1" && grep -Eq "^[[:space:]]+datastore ds-lab$" <<<"$1"' _ "$_m09o_s"
check_output "pbs-par2 : namespace par1/hv" '^[[:space:]]+namespace par1/hv$' echo "$_m09o_s"
check_output "pbs-par2 : jeton wb-hv@pbs!hv-par1 (pas root@pam, pas le compte de pve01)" '^[[:space:]]+username wb-hv@pbs!hv-par1$' echo "$_m09o_s"
check_output "pbs-par2 : empreinte du certificat de pbs01 épinglée" '^[[:space:]]+fingerprint ([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$' echo "$_m09o_s"
check_output "pbs-par2 : chiffrement côté client configuré" '^[[:space:]]+encryption-key ' echo "$_m09o_s"
check_ssh "la clé de chiffrement est dans /etc/pve/priv/storage/pbs-par2.enc (root seul)" "$(_m09o_noeud)" \
  '[ -s /etc/pve/priv/storage/pbs-par2.enc ] && [ "$(stat -c %a /etc/pve/priv/storage/pbs-par2.enc)" = 600 ]'
check_cmd "pbs-par2 actif sur les trois nœuds" _m09o_stockage_actif_partout pbs-par2

_m09o_b="$(_m09o_pvesh /cluster/backup/hv-nuit)"
check_cmd "tâche hv-nuit : activée, quotidienne à 03:15, vers pbs-par2" _m09o_json "$_m09o_b" \
  '((.enabled // 1) | tostring | test("^(1|true)$")) and .schedule == "03:15" and .storage == "pbs-par2"'
check_cmd "tâche hv-nuit : mode snapshot, toutes les VMs" _m09o_json "$_m09o_b" \
  '.mode == "snapshot" and ((.all // 0) | tostring | test("^(1|true)$"))'
check_cmd "tâche hv-nuit : pas d'élagage côté client (keep-all=1, la rétention est sur PBS)" bash -c \
  'jq -e "(.\"prune-backups\" // \"\") | test(\"keep-all=1\")" <<<"$1" >/dev/null 2>&1 || grep -Eq "prune-backups keep-all=1" <<<"$2"' _ "$_m09o_b" "$_m09o_s"

_m09o_n="$(_m09o_noeud)"
_m09o_c="$(_m09o_hv "$_m09o_n" "pvesh get /nodes/$_m09o_n/storage/pbs-par2/content --output-format json")"
for _m09o_id in 101 102 103; do
  check_cmd "sauvegarde CHIFFRÉE de moins de 48 h pour l'invité $_m09o_id" _m09o_json "$_m09o_c" \
    'map(select((.vmid == $id) and (.ctime > (now - 172800)) and ((.encrypted // "") != ""))) | length > 0' --argjson id "$_m09o_id"
done
check_cmd "restau01 (127) n'existe plus" _m09o_json "$(_m09o_ressources)" 'length > 0 and (map(select(.vmid == 127)) | length == 0)'

# --- pbs01 (lecture des ACL) --------------------------------------------------------------------------
if remote "$_M09O_PBS" true >/dev/null 2>&1; then
  _m09o_acl="$(remote "$_M09O_PBS" 'proxmox-backup-manager acl list --output-format json' 2>/dev/null || true)"
  check_cmd "pbs01 : DatastoreBackup sur /datastore/ds-lab/par1/hv pour wb-hv@pbs ET son jeton" _m09o_json "$_m09o_acl" \
    '([.[] | select(.path == "/datastore/ds-lab/par1/hv" and .roleid == "DatastoreBackup") | .ugid] | index("wb-hv@pbs") != null and index("wb-hv@pbs!hv-par1") != null)'
  check_cmd "pbs01 : aucun droit de wb-hv@pbs (ni de son jeton) ailleurs que sur par1/hv" _m09o_json "$_m09o_acl" \
    '[.[] | select((.ugid | startswith("wb-hv@pbs")) and .path != "/datastore/ds-lab/par1/hv")] | length == 0'
else
  skip "ACL de pbs01" "l'alias $_M09O_PBS ne répond pas"
fi

_m09o_reg="$(_m09o_contenu_main plateforme/medisphere docs/socle/registre-secrets.md)"
check_cmd "registre des secrets (main) : jeton wb-hv@pbs et clé de chiffrement des sauvegardes du cluster" bash -c \
  'grep -q "wb-hv@pbs" <<<"$1" && grep -Eiq "chiffrement.*(hv-par1|pbs-par2)|(hv-par1|pbs-par2).*chiffrement" <<<"$1"' _ "$_m09o_reg"
