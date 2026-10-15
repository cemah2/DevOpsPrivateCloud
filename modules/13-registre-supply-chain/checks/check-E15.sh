# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E15.sh — M13-E15 « Sauvegarder et restaurer Harbor »
# Lecture seule : unités et droits sur reg01 (systemctl, stat, grep), datastore de pbs01 (find),
# politiques de réplication de reg02 (API, robot des checks de reg02), documentation (API GitLab).

# shellcheck source=_m13-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-production.sh"

title "M13-E15 — Sauvegarder et restaurer Harbor"
require_cmd jq curl

title "reg01 : planification et secrets"
check_ssh "wb-backup-harbor.timer activé et actif" reg01 \
  'systemctl is-enabled -q wb-backup-harbor.timer && systemctl is-active -q wb-backup-harbor.timer'
check_ssh_output "timer à 01:40" reg01 '01:40' 'systemctl show -p TimersCalendar wb-backup-harbor.timer'
check_cmd "le dernier passage de wb-backup-harbor.service a réussi (moins de 26 h)" \
  _m13p_unite_recente reg01 wb-backup-harbor.service 26
check_ssh_output "le service déclenche ms-alerte@… en cas d'échec" reg01 'ms-alerte@' \
  'systemctl show -p OnFailure wb-backup-harbor.service'
check_ssh "secrets PBS de reg01 (jeton, clé de chiffrement) : root:root, 600" reg01 \
  'for f in /etc/wb-backup/pbs-reg01.env /etc/wb-backup/pbs-reg01.key; do [ "$(sudo -n stat -c %U:%G:%a "$f" 2>/dev/null)" = root:root:600 ] || exit 1; done'
check_ssh "le script vide la base par pg_dump dans harbor-db et n'archive pas /data/database" reg01 \
  's=/usr/local/sbin/wb-backup-harbor.sh; sudo -n grep -q "pg_dump" "$s" && sudo -n grep -q "harbor-db" "$s" && ! sudo -n grep -Eq "pxar:[^ ]*/data/database|pxar:\\\$\\{?WB_DATA\\}?/database" "$s"'

title "pbs01 : par1/registre"
check_cmd "une archive des blobs (registre*) de moins de 48 h" _m13p_pbs_recent 'registre*.didx' 48
check_cmd "une archive du vidage de la base (base*) de moins de 48 h" _m13p_pbs_recent 'base*.didx' 48
check_cmd "une archive des clés (secret*) de moins de 48 h" _m13p_pbs_recent 'secret*.didx' 48

title "Restauration"
check_cmd "docs/registre/sauvegarde.md sur main" _m13p_doc_main docs/registre/sauvegarde.md 'pg_dump' 'secretkey'
check_cmd "docs/registre/tests/restauration-harbor.md (RTO, RPO)" \
  _m13p_doc_main docs/registre/tests/restauration-harbor.md 'RTO' 'RPO'
check_cmd "RB-131 publié dans docs/registre/runbooks/" _m13p_doc_prefixe docs/registre/runbooks RB-131
if [[ -r "$_M13P_REG02_FICHIER" ]] && _m13p_sante "$_M13P_REG02_URL"; then
  _m13_e15_p2="$(_m13p_api2 "replication/policies?page_size=50")" || _m13_e15_p2=""
  check_cmd "reg02 : aucune politique de réplication active vers elle-même" _m13p_jq "${_m13_e15_p2:-[]}" \
    '[.[]? | select(.enabled == true and ((.dest_registry.url // "") | test("reg02\\.par1")))] | length == 0'
else
  skip "politiques restaurées sur reg02" "reg02 absente ou robot des checks de reg02 illisible"
fi
