# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E18.sh — M08-E18 : Étendre le cluster : un quatrième nœud
# À lancer depuis adm01, ceph04 démarré. Lecture seule (orch host ls, osd tree, NetBox, DNS, ip link).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E18 — Étendre le cluster : un quatrième nœud"
require_cmd jq dig

_m08o_hotes="$(_m08o_ceph orch host ls --format json)"
_m08o_arbre="$(_m08o_ceph osd tree --format json)"

check_cmd "ceph04 est un hôte du cluster (10.10.30.54, étiquette osd)" \
  jq -e '.[] | select(.hostname == "ceph04") | .addr == "10.10.30.54" and ((.labels // []) | index("osd") != null)' <<<"$_m08o_hotes"
check_output "ceph04 dans la baie par1-baie-a de la carte CRUSH" '^par1-baie-a$' _m08o_parent "$_m08o_arbre" ceph04
_m08o_osd04() {
  jq -c '. as $t | [$t.nodes[] | select(.name == "ceph04") | .children[]] as $ids
         | [$t.nodes[] | select(.type == "osd" and (.id as $i | $ids | index($i)))]' <<<"$_m08o_arbre" 2>/dev/null || echo '[]'
}
_m08o_o="$(_m08o_osd04)"
check_cmd "ceph04 : trois OSD, deux ssd et un hdd" \
  jq -e 'length == 3 and (map(.device_class) | sort == ["hdd","ssd","ssd"])' <<<"$_m08o_o"
check_cmd "ceph04 : OSD up et in" jq -e 'length == 3 and all(.status == "up" and .reweight == 1)' <<<"$_m08o_o"
check_cmd "ceph04 : poids CRUSH égal à la taille (≈ 0,0625 pour 64 Gio)" \
  jq -e 'length == 3 and all(.crush_weight > 0.05 and .crush_weight < 0.08)' <<<"$_m08o_o"
_m08o_poids_init="$(_m08o_ceph config get osd osd_crush_initial_weight | tr -d '[:space:]')"
check_output "réglage temporaire osd_crush_initial_weight retiré (valeur : ${_m08o_poids_init:-?})" '^-1(\.0+)?$' echo "$_m08o_poids_init"

# --- Source de vérité, nom, réseau ---------------------------------------------------------------------
_m08o_nb04() {
  netbox_api "ipam/ip-addresses/?virtual_machine=ceph04&limit=10" \
    | jq -e '[.results[].address | split("/")[0]] | (index("10.10.30.54") != null) and (index("10.10.31.54") != null)' >/dev/null
}
check_cmd "NetBox : ceph04 avec 10.10.30.54 et 10.10.31.54" _m08o_nb04
check_dns "ceph04.par1.medisphere.internal → 10.10.30.54" ceph04.par1.medisphere.internal A '^10\.10\.30\.54$' 10.10.20.10
check_ssh "ceph04 : MTU 9000 sur ens18 et ens19" ceph04 \
  '[ "$(cat /sys/class/net/ens18/mtu)" = 9000 ] && [ "$(cat /sys/class/net/ens19/mtu)" = 9000 ]'
check_ssh "ceph04 : trames de 9000 octets vers ceph01 sur le réseau de réplication" ceph04 \
  'ping -c 2 -W 2 -M do -s 8972 10.10.31.51 >/dev/null'

# --- Fin du changement ---------------------------------------------------------------------------------
check_output "cluster en HEALTH_OK" '^HEALTH_OK' _m08o_ceph health
check_cmd "fiche CHG-928 dans plateforme/medisphere (main)" \
  _m08o_fichier_main "$_M08O_PROJET_DOC" docs/stockage/changements/CHG-928-ceph04.md
