# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M08-E34 « Livrer du stockage à une équipe en temps limité » (MédiNotif)
# À lancer à T4. Lecture seule : espace de noms et image (rbd info), groupe et sous-volume CephFS
# (info), compte RGW (radosgw-admin account get), capacités cephx (sans les clés), essais de listage
# depuis cephcli01, quota de rbd-equipes, sonde, registre (API GitLab).

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E34 — Stockage de l'équipe MédiNotif"
require_cmd jq curl
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

_m08_e34_gio=1073741824

title "Identité (exigence 1)"
check_cmd "client.medinotif existe" _m08p_entite_existe client.medinotif
check_cmd "client.medinotif : aucune capacité « allow * » / « allow rwx »" _m08p_sans_allow_tout client.medinotif
check_cmd "client.medinotif : OSD limités à rbd-equipes namespace=medinotif" \
  _m08p_caps client.medinotif osd 'pool=rbd-equipes namespace=medinotif'
check_cmd "client.medinotif : MDS limités à /volumes/medinotif" _m08p_caps client.medinotif mds 'path=/volumes/medinotif'
check_ssh_output "cephcli01 : trousseau de test en 600" cephcli01 '^600$' \
  'sudo -n stat -c %a /etc/ceph/ceph.client.medinotif.keyring'

title "Bloc (exigence 2)"
check_cmd "image rbd-equipes/medinotif/rabbitmq-recette de 20 Gio" bash -c \
  'jq -e --argjson t "$2" ".size == \$t" >/dev/null <<<"$1"' _ \
  "$(_m08p_rbd 'info rbd-equipes/medinotif/rabbitmq-recette --format json' 2>/dev/null || echo null)" $((20 * _m08_e34_gio))

title "Fichier (exigence 3)"
check_cmd "cephfs : groupe medinotif plafonné à 5 Gio" bash -c \
  'jq -e --argjson t "$2" ".bytes_quota == \$t" >/dev/null <<<"$1"' _ \
  "$(_m08p_json 'fs subvolumegroup info cephfs medinotif')" $((5 * _m08_e34_gio))
check_cmd "cephfs : sous-volume modeles de 2 Gio dans le groupe medinotif" bash -c \
  'jq -e --argjson t "$2" ".bytes_quota == \$t" >/dev/null <<<"$1"' _ \
  "$(_m08p_json 'fs subvolume info cephfs modeles --group_name medinotif')" $((2 * _m08_e34_gio))

title "Objet (exigence 4)"
# Champs « quota » du compte : format à confirmer sur ton lab (radosgw-admin account get).
_m08_e34_compte="$(_m08p_rgw 'account get --account-name=medinotif' 2>/dev/null || echo null)"
check_cmd "compte RGW medinotif" bash -c 'jq -e ".id | startswith(\"RGW\")" >/dev/null <<<"$1"' _ "$_m08_e34_compte"
check_cmd "compte RGW medinotif : quota de 10 Gio activé" bash -c \
  'jq -e --argjson t "$2" "(.quota.enabled == true) and (.quota.max_size == \$t)" >/dev/null <<<"$1"' _ \
  "$_m08_e34_compte" $((10 * _m08_e34_gio))

title "Cloisonnement (exigence 5)"
check_cmd "medinotif liste son espace de noms" _m08p_identite_ok cephcli01 medinotif rbd-equipes/medinotif
for _m08_e34_c in rbd-equipes/mediagenda rbd-equipes/medidoc rbd-test; do
  check_cmd "medinotif ne peut pas lister $_m08_e34_c" _m08p_identite_refus cephcli01 medinotif "$_m08_e34_c"
done

title "Capacité, supervision, documentation (exigences 6, 8, 9)"
check_cmd "quota de rbd-equipes ≥ 90 Gio (40 + 20 + 30)" _m08p_pool_quota_min rbd-equipes $((90 * _m08_e34_gio))
check_cmd "la sonde ms-verif-ceph conclut que le cluster va bien" timeout 180 /usr/local/bin/ms-verif-ceph --quiet
check_cmd "allocations.md sur main : MédiNotif et CHG-960" \
  _m08p_doc_main docs/stockage/allocations.md medinotif 'CHG-960'
check_cmd "registre des secrets : identité et identifiants S3 de MédiNotif" \
  _m08p_doc_main docs/socle/registre-secrets.md medinotif
