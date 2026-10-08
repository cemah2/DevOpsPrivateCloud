# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M10-E41 « Panne : l'envoi d'image échoue » : Glance accepte des images de taille
# normale et écrit dans Ceph (aucun plafond de taille anormal, pool images non plein, clé de
# client.glance identique à celle du cluster, comparée par empreinte). Lecture seule.
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E41 — Les images s'envoient"
require_cmd openstack jq ssh

check_cmd "$_m10x_ctl : glance_api en service" _m10x_ctr_sain "$_m10x_ctl" glance_api
check_cmd "Glance répond (image list)" _m10x_os image list --limit 1
check_cmd "$_m10x_ctl : aucun plafond de taille d'image sous 10 Gio (image_size_cap)" \
  bash -c 'v="$1"; [ -z "$v" ] || [ "$v" -ge 10737418240 ]' _ \
  "$(_m10x_ini "$_m10x_ctl" /etc/kolla/glance-api/glance-api.conf DEFAULT image_size_cap)"
_m10_e41_pas_plein() {
  local s
  s="$(_m10x_ceph health detail 2>/dev/null)" || return 1
  [[ -n "$s" ]] && ! grep -Eq "images.*(full|quota)" <<<"$s"
}
check_cmd "ceph-par1 : le pool images n'est pas plein (ni quota atteint)" _m10_e41_pas_plein
check_cmd "ceph-par1 : quota du pool images absent ou très au-dessus de son occupation" \
  bash -c 'q="$1"; o="$2"; [ -n "$q" ] && [ -n "$o" ] && { [ "$q" -eq 0 ] || [ "$q" -ge $((o + 5368709120)) ]; }' _ \
  "$(_m10x_ceph osd pool get-quota images -f json 2>/dev/null | jq -r '.quota_max_bytes // empty')" \
  "$(_m10x_ceph df -f json 2>/dev/null | jq -r '.pools[] | select(.name == "images") | .stats.stored')"
_m10_e41_a="$(remote "$_m10x_ctl" 'sudo -n sed -nE "s/^[[:space:]]*key[[:space:]]*=[[:space:]]*(\S+).*/\1/p" /etc/kolla/glance-api/ceph/ceph.client.glance.keyring | head -n 1 | sha256sum' 2>/dev/null)"
_m10_e41_b="$(_m10x_ceph auth get-key client.glance 2>/dev/null | tr -d '[:space:]' | sha256sum)"
check_cmd "clé de client.glance de glance-api identique à celle de ceph-par1" \
  test -n "$_m10_e41_a" -a "$_m10_e41_a" = "$_m10_e41_b" -a "$_m10_e41_b" != "$(printf '' | sha256sum)"
check_cmd "aucune image bloquée en queued/saving/importing dans le projet plateforme" \
  bash -c '! timeout 60 openstack --os-cloud "$1" image list --long -f json 2>/dev/null | jq -e "map(select(.Status == \"queued\" or .Status == \"saving\" or .Status == \"importing\")) | length > 0" >/dev/null' \
  _ "$_m10x_cloud_projet"
check_cmd "panne M10-E41 close (lab/bin/break 10 41 --annuler après réparation)" _m10x_aucune_panne_active E41
