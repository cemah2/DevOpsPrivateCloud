# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E06.sh — M10-E06 : Glance : les images
# À lancer depuis adm01. Lecture seule : CLI openstack (image show, image list, image member
# list, project show) avec le cloud WB_OS_CLOUD et le cloud de Julien (E05).

# shellcheck source=_m10-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-decouverte.sh"

title "M10-E06 — Glance : les images"
require_cmd jq openstack

# Les propriétés d'image apparaissent, selon la version de la CLI, dans « properties » ou à la
# racine de la réponse : on regarde les deux.
_m10d_e06_prop='def p(k): (.properties // {})[k] // .[k];'

# _m10d_e06_image NOM VISIBILITE OS_DISTRO OS_VERSION — image active, qcow2, propriétés du ticket.
_m10d_e06_image() {
  local j
  j="$(_m10d_os image show "$1")"
  _m10d_jq "$j" "$_m10d_e06_prop
    .status == \"active\" and .visibility == \"$2\" and .disk_format == \"qcow2\"
    and p(\"hw_disk_bus\") == \"scsi\" and p(\"hw_scsi_model\") == \"virtio-scsi\"
    and (p(\"hw_qemu_guest_agent\") | tostring | test(\"^(yes|true|True)$\"))
    and p(\"os_distro\") == \"$3\" and (p(\"os_version\") | tostring) == \"$4\"
    and p(\"os_type\") == \"linux\""
}
# _m10d_e06_somme NOM — Glance a calculé une somme SHA-512.
_m10d_e06_somme() {
  _m10d_jq "$(_m10d_os image show "$1")" "$_m10d_e06_prop
    p(\"os_hash_algo\") == \"sha512\" and (p(\"os_hash_value\") | tostring | test(\"^[0-9a-f]{128}$\"))"
}

check_cmd "debian-13 : active, publique, qcow2, propriétés du ticket" _m10d_e06_image debian-13 public debian 13
check_cmd "rocky-10 : active, partagée (shared), qcow2, propriétés du ticket" _m10d_e06_image rocky-10 shared rocky 10
check_cmd "debian-13 : somme SHA-512 calculée par Glance" _m10d_e06_somme debian-13
check_cmd "rocky-10 : somme SHA-512 calculée par Glance" _m10d_e06_somme rocky-10
check_cmd "Une seule image nommée debian-13 et une seule rocky-10 (pas de doublon ambigu)" \
  _m10d_jq "$(_m10d_os image list)" \
  '(map(select(.Name == "debian-13")) | length == 1) and (map(select(.Name == "rocky-10")) | length == 1)'

_m10d_e06_plat="$(_m10d_id_projet plateforme)"
check_cmd "rocky-10 : le projet plateforme est membre et a ACCEPTÉ le partage" \
  _m10d_jq "$(_m10d_os image member list rocky-10)" \
  "map(select(.\"Member ID\" == \"$_m10d_e06_plat\" and .Status == \"accepted\")) | length == 1"
check_cmd "julien.petit (mediagenda-dev) voit debian-13 mais pas rocky-10" \
  _m10d_jq "$(_m10d_os --os-cloud medisphere-mediagenda-dev image list)" \
  '([.[].Name] | index("debian-13") != null) and ([.[].Name] | index("rocky-10") == null)'
