# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E15.sh — M08-E15 : Codes d'effacement
# À lancer depuis adm01. Lecture seule (erasure-code-profile get, pool ls detail, rbd info, status).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E15 — Codes d'effacement"
require_cmd jq

_m08o_profil="$(_m08o_ceph osd erasure-code-profile get ec-21-hdd --format json)"
_m08o_pool="$(_m08o_ceph osd pool ls detail --format json | jq -c '.[] | select(.pool_name == "rbd-ec-donnees")' 2>/dev/null || true)"
_m08o_image="$(_m08o_outil rbd info rbd-test/archives-ec --format json)"

check_cmd "profil ec-21-hdd : k=2, m=1" jq -e '.k == "2" and .m == "1"' <<<"$_m08o_profil"
check_cmd "profil ec-21-hdd : greffon isa (défaut Tentacle)" jq -e '.plugin == "isa"' <<<"$_m08o_profil"
check_cmd "profil ec-21-hdd : classe hdd, domaine de panne rack" \
  jq -e '."crush-device-class" == "hdd" and ."crush-failure-domain" == "rack"' <<<"$_m08o_profil"
check_cmd "pool rbd-ec-donnees : code d'effacement, profil ec-21-hdd" \
  jq -e '.type == 3 and .erasure_code_profile == "ec-21-hdd"' <<<"$_m08o_pool"
check_cmd "pool rbd-ec-donnees : réécritures autorisées (allow_ec_overwrites)" \
  jq -e '.flags_names | test("ec_overwrites")' <<<"$_m08o_pool"
check_cmd "pool rbd-ec-donnees : application rbd" jq -e '.application_metadata | has("rbd")' <<<"$_m08o_pool"
check_cmd "image rbd-test/archives-ec : données dans rbd-ec-donnees" \
  jq -e '.data_pool == "rbd-ec-donnees"' <<<"$_m08o_image"
check_cmd "tous les PG sont active+clean" _m08o_pgs_propres "$(_m08o_ceph status --format json)"
