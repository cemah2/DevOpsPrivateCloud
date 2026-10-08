# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E04.sh — M08-E04 : Les OSD : spécifications et classes de disques
# À lancer depuis adm01. Lecture seule : commandes « ceph » d'observation sur le nœud _admin,
# API GitLab en GET.

# shellcheck source=_m08-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-decouverte.sh"

title "M08-E04 — Les OSD : spécifications et classes de disques"
require_cmd jq curl

_m08d_e04_arbre="$(_m08d_ceph "osd tree -f json")"
_m08d_e04_meta="$(_m08d_ceph "osd metadata -f json")"
_m08d_e04_dump="$(_m08d_ceph "osd dump -f json")"

# --- 1. Les neuf OSD -------------------------------------------------------------------------------
check_cmd "Neuf OSD, tous « up » et « in »" _m08d_json "$_m08d_e04_dump" \
  '(.osds | length) == 9 and all(.osds[]; .up == 1 and .in == 1)'
for _m08d_e04_h in ceph01 ceph02 ceph03; do
  check_cmd "$_m08d_e04_h : 3 OSD (2 de classe ssd, 1 de classe hdd)" _m08d_json "$_m08d_e04_arbre" \
    '(.nodes | map({key: (.id | tostring), value: .}) | from_entries) as $n
     | [.nodes[] | select(.type == "host" and .name == $h) | .children[] | $n[tostring].device_class] as $c
     | ($c | length) == 3 and ($c | map(select(. == "ssd")) | length) == 2 and ($c | map(select(. == "hdd")) | length) == 1' \
    --arg h "$_m08d_e04_h"
done
# La classe doit correspondre au disque réel : rotatif (hdd-bulk) ⇒ hdd, non rotatif (ssd-lab) ⇒ ssd.
_m08d_e04_classes_coherentes() {
  local classes
  classes="$(jq -c '[.nodes[] | select(.type == "osd") | {key: (.id | tostring), value: .device_class}] | from_entries' <<<"$_m08d_e04_arbre" 2>/dev/null)" || return 1
  [[ -n "$classes" && -n "$_m08d_e04_meta" ]] || return 1
  jq -e --argjson c "$classes" \
    'length == 9 and all(.[]; ((.bluestore_bdev_rotational // .rotational) == "1") == ($c[(.id | tostring)] == "hdd"))' \
    <<<"$_m08d_e04_meta" >/dev/null 2>&1
}
check_cmd "Classe CRUSH conforme au disque de chaque OSD (rotatif ⇒ hdd, non rotatif ⇒ ssd)" \
  _m08d_e04_classes_coherentes
check_cmd "Chaque OSD est sur un disque de données (pas le disque système)" _m08d_json "$_m08d_e04_meta" \
  'length == 9 and all(.[]; (.devices // "") | test("^sd[b-z]"))'

# --- 2. Les spécifications -------------------------------------------------------------------------
_m08d_e04_services="$(_m08d_ceph "orch ls osd -f json")"
check_cmd "Services osd.ssd et osd.hdd déclarés, placés par l'étiquette « osd »" _m08d_json "$_m08d_e04_services" \
  '([.[] | select(.service_name == "osd.ssd" or .service_name == "osd.hdd") | .placement.label] | sort) == ["osd", "osd"]'
check_cmd "Aucun service « tous les disques disponibles » (osd.all-available-devices)" _m08d_json "$_m08d_e04_services" \
  '[.[] | select(.service_name == "osd.all-available-devices")] | length == 0'
check_cmd "osd.ssd filtre les disques non rotatifs, osd.hdd les rotatifs" _m08d_json "$_m08d_e04_services" \
  '(.[] | select(.service_name == "osd.ssd") | .spec.data_devices.rotational | tostring | test("^(0|false)$"))
   and (.[] | select(.service_name == "osd.hdd") | .spec.data_devices.rotational | tostring | test("^(1|true)$"))'

# --- 3. La mémoire -------------------------------------------------------------------------------------
check_output "osd_memory_target effectif de osd.0 : 1 Gio" '^1073741824$' _m08d_ceph "config get osd.0 osd_memory_target"
check_cmd "Aucune cible mémoire par hôte qui l'emporterait (masque host:…)" _m08d_json "$(_m08d_ceph "config dump -f json")" \
  '[.[] | select(.name == "osd_memory_target" and ((.location_type // "") != "" or (.mask // "") != ""))] | length == 0'

# --- 4. Santé et code ------------------------------------------------------------------------------------
check_output "Cluster en HEALTH_OK" '^HEALTH_OK$' _m08d_sante
check_cmd "plateforme/ceph (main) : specs/osd.yaml" _m08d_fichier_main plateforme/ceph specs/osd.yaml
check_output "plateforme/ceph (main) : osd.yaml décrit les deux classes" 'crush_device_class: *hdd' \
  _m08d_contenu_main plateforme/ceph specs/osd.yaml
