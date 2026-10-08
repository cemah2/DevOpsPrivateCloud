# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E25.sh — M08-E25 « Sauvegarder hors du cluster »
# Lecture seule : unités et droits sur cephcli01 (sudo -n stat/systemctl), compte wb-sauvegarde de
# ceph01, capacités cephx (sans les clés), datastore de pbs01 (find), pools (rbd ls), documentation
# (API GitLab).

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E25 — Sauvegarder hors du cluster"
require_cmd jq curl
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

title "cephcli01 : planification et secrets"
_m08_e25_tim=wb-backup-ceph.timer
_m08_e25_svc=wb-backup-ceph.service
check_ssh "timer $_m08_e25_tim activé et actif" cephcli01 \
  "systemctl is-enabled -q $_m08_e25_tim && systemctl is-active -q $_m08_e25_tim"
check_ssh_output "timer à 01:30" cephcli01 '01:30' "systemctl show -p TimersCalendar $_m08_e25_tim"
check_ssh "le service a déjà tourné et son dernier passage a réussi" cephcli01 \
  'v=$(systemctl show -p ExecMainStartTimestampMonotonic --value '"$_m08_e25_svc"'); [ -n "$v" ] && [ "$v" != 0 ] && [ "$(systemctl show -p Result --value '"$_m08_e25_svc"')" = success ]'
check_ssh_output "le service déclenche ms-alerte@… en cas d'échec" cephcli01 'ms-alerte@' \
  "systemctl show -p OnFailure $_m08_e25_svc"
check_ssh "secrets PBS de cephcli01 (jeton, clé de chiffrement) : root:root, 600" cephcli01 \
  'for f in /etc/wb-backup/pbs-cephcli01.env /etc/wb-backup/pbs-cephcli01.key; do [ "$(sudo -n stat -c %U:%G:%a "$f" 2>/dev/null)" = root:root:600 ] || exit 1; done'

title "pbs01 : sauvegardes dans par1/ceph"
check_cmd "une archive des volumes RBD de moins de 48 h" _m08p_pbs_recent '*rbd*.didx' 48
check_cmd "une archive de la configuration du cluster de moins de 48 h" _m08p_pbs_recent '*config*.didx' 48

title "Droits"
check_cmd "client.sauvegarde existe" _m08p_entite_existe client.sauvegarde
check_cmd "client.sauvegarde : aucune capacité « allow * »" _m08p_sans_allow_tout client.sauvegarde
check_cmd "client.sauvegarde : droits OSD limités par pool (profile rbd pool=…)" \
  _m08p_caps client.sauvegarde osd 'profile rbd[a-z-]* pool='
check_ssh "ceph01 : chaque clé autorisée de wb-sauvegarde a une commande forcée et « restrict »" ceph01 \
  'f=/home/wb-sauvegarde/.ssh/authorized_keys; c=$(sudo -n grep -Ev "^[[:space:]]*(#|$)" "$f" 2>/dev/null) || exit 1; [ -n "$c" ] || exit 1
   ! grep -Ev "command=\"[^\"]+\"" <<<"$c" | grep -q . && ! grep -Ev "(^|,)restrict(,| )" <<<"$c" | grep -q .'
check_ssh "ceph01 : wb-sauvegarde n'a pas de sudo général (une commande précise seulement)" ceph01 \
  'l=$(sudo -n sudo -l -U wb-sauvegarde 2>/dev/null) || exit 1; grep -q "NOPASSWD: /" <<<"$l" && ! grep -Eq "\(ALL( : ALL)?\) (NOPASSWD: )?ALL\$" <<<"$l"'
check_ssh "ceph01 : le script d'export forcé ne lit pas le magasin config-key" ceph01 \
  's=$(sudo -n sed -nE "s/.*command=\"(sudo( -n)? )?([^ \"]+).*/\3/p" /home/wb-sauvegarde/.ssh/authorized_keys | head -n 1); [ -n "$s" ] && sudo -n test -r "$s" && ! sudo -n grep -Eq "config-key[[:space:]]+(dump|get|ls|export)" "$s"'

title "Restauration"
check_cmd "docs/stockage/sauvegarde.md sur main (conception)" \
  _m08p_doc_main docs/stockage/sauvegarde.md 'export-diff' 'import-diff'
check_cmd "docs/stockage/tests/restauration-ceph.md sur main (RTO, import-diff)" \
  _m08p_doc_main docs/stockage/tests/restauration-ceph.md 'RTO' 'import-diff'
_m08_e25_pas_de_restau() {
  local l
  l="$(_m08p_rbd 'ls rbd-test')" || return 1
  ! grep -q '^restau-' <<<"$l"
}
check_cmd "plus aucune image restau-* dans rbd-test" _m08_e25_pas_de_restau
