# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E03.sh — M08-E03 : Amorcer le cluster avec cephadm
# À lancer depuis adm01. Lecture seule : commandes « ceph » d'observation sur le nœud _admin
# (sudo -n), fichiers des nœuds en SSH, copie de travail de plateforme/ansible, API GitLab en GET.

# shellcheck source=_m08-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-decouverte.sh"

title "M08-E03 — Amorcer le cluster avec cephadm"
require_cmd jq curl

_m08d_e03_fsid="$(_m08d_ceph "fsid" | tr -d '[:space:]')"
check_cmd "Le cluster répond depuis $_M08D_ADMIN (ceph fsid)" \
  bash -c '[[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]' _ "$_m08d_e03_fsid"

# --- 1. Moniteurs et gestionnaires -----------------------------------------------------------------
_m08d_e03_quorum="$(_m08d_ceph "quorum_status -f json")"
check_cmd "Trois moniteurs en quorum : ceph01, ceph02, ceph03" _m08d_json "$_m08d_e03_quorum" \
  '(.quorum_names | sort) == ["ceph01", "ceph02", "ceph03"]'
check_cmd "Moniteurs sur le réseau public, en msgr2 (3300) et msgr1 (6789)" _m08d_json "$_m08d_e03_quorum" \
  '[.monmap.mons[].public_addrs.addrvec[] | "\(.type) \(.addr)"]
   | (map(select(test("^v2 10\\.10\\.30\\.5[1-3]:3300$"))) | length == 3)
     and (map(select(test("^v1 10\\.10\\.30\\.5[1-3]:6789$"))) | length == 3)'
_m08d_e03_mgr="$(_m08d_ceph "mgr dump -f json")"
check_cmd "Un mgr actif et un mgr en attente" _m08d_json "$_m08d_e03_mgr" \
  '.available == true and (.standbys | length) == 1'

# --- 2. Réseaux et configuration ---------------------------------------------------------------------
check_output "public_network = 10.10.30.0/24" '^10\.10\.30\.0/24$' _m08d_ceph "config get mon public_network"
check_output "cluster_network = 10.10.31.0/24" '^10\.10\.31\.0/24$' _m08d_ceph "config get osd cluster_network"
check_output "Réglage automatique de la mémoire des OSD désactivé" '^false$' \
  _m08d_ceph "config get osd osd_memory_target_autotune"
check_output "osd_memory_target = 1 Gio (1073741824)" '^1073741824$' _m08d_ceph "config get osd osd_memory_target"
check_output "Suppression des pools verrouillée (mon_allow_pool_delete = false)" '^false$' \
  _m08d_ceph "config get mon mon_allow_pool_delete"

# --- 3. Version et image --------------------------------------------------------------------------------
_m08d_e03_versions="$(_m08d_ceph "versions -f json")"
check_cmd "Tous les démons en $_M08D_VERSION" _m08d_json "$_m08d_e03_versions" \
  '(.overall | keys) as $k | ($k | length) == 1 and ($k[0] | test("^ceph version " + $v + " "))' --arg v "${_M08D_VERSION//./\\.}"
check_output "Image des démons épinglée (v$_M08D_VERSION ou empreinte sha256, jamais « :v20 » ni « latest »)" \
  "(:v${_M08D_VERSION//./\\.}$|@sha256:[0-9a-f]{64}$)" _m08d_ceph "config get mgr container_image"

# --- 4. Hôtes, étiquettes, services -----------------------------------------------------------------------
_m08d_e03_hotes="$(_m08d_ceph "orch host ls -f json")"
for _m08d_e03_n in 1 2 3; do
  check_cmd "Hôte ceph0$_m08d_e03_n : adresse 10.10.30.5$_m08d_e03_n, étiquettes _admin, mon, mgr, osd" \
    _m08d_json "$_m08d_e03_hotes" \
    '.[] | select(.hostname == $h) | .addr == $a and ((.labels | sort) as $l | ["_admin", "mgr", "mon", "osd"] - $l == [])' \
    --arg h "ceph0$_m08d_e03_n" --arg a "10.10.30.5$_m08d_e03_n"
done
check_cmd "Aucun hôte hors ligne ou en maintenance" _m08d_json "$_m08d_e03_hotes" \
  'length == 3 and all(.[]; (.status // "") == "")'
_m08d_e03_services="$(_m08d_ceph "orch ls -f json")"
check_cmd "Service mon placé par l'étiquette « mon »" _m08d_json "$_m08d_e03_services" \
  '.[] | select(.service_type == "mon") | .placement.label == "mon"'
check_cmd "Service mgr : étiquette « mgr », 2 démons" _m08d_json "$_m08d_e03_services" \
  '.[] | select(.service_type == "mgr") | .placement.label == "mgr" and .placement.count == 2'
check_cmd "Pas de pile de supervision cephadm (prometheus, grafana, alertmanager, node-exporter)" \
  _m08d_json "$_m08d_e03_services" \
  '[.[] | select(.service_type | IN("prometheus", "grafana", "alertmanager", "node-exporter"))] | length == 0'

# --- 5. L'orchestrateur et les nœuds ----------------------------------------------------------------------
_m08d_e03_pub="$(_m08d_ceph "cephadm get-pub-key" | awk 'NF >= 2 {print $2; exit}')"
for _m08d_e03_h in ceph02 ceph03; do
  check_ssh "$_m08d_e03_h : clé du cluster autorisée pour le compte cephadm" "$_m08d_e03_h" \
    "[ -n '$_m08d_e03_pub' ] && sudo -n grep -qF '$_m08d_e03_pub' /var/lib/cephadm/.ssh/authorized_keys"
  check_ssh "$_m08d_e03_h : clé du cluster ABSENTE des clés autorisées de root" "$_m08d_e03_h" \
    "[ -n '$_m08d_e03_pub' ] && ! sudo -n grep -qsF '$_m08d_e03_pub' /root/.ssh/authorized_keys"
  check_ssh "$_m08d_e03_h : ceph.conf et trousseau client.admin déposés (étiquette _admin)" "$_m08d_e03_h" \
    'sudo -n test -s /etc/ceph/ceph.conf && sudo -n test -s /etc/ceph/ceph.client.admin.keyring'
done
check_ssh "ceph01 : trousseau client.admin lisible par root seul" ceph01 \
  '[ "$(sudo -n stat -c %a /etc/ceph/ceph.client.admin.keyring)" = 600 ]'

# --- 6. Inventaire, secrets et code ---------------------------------------------------------------------
check_cmd "Inventaire Ansible : ceph_fsid (group_vars/env_m08) = fsid du cluster" \
  bash -c '[[ -n "$2" ]] && grep -Eq "^ceph_fsid: *\"?$2\"?" "$1/ansible/inventories/lab/group_vars/env_m08/ceph.yml"' \
  _ "$_M08D_SRC" "$_m08d_e03_fsid"
check_cmd "adm01 : mot de passe du tableau de bord en 600" \
  bash -c '[[ -s "$1" && "$(stat -c %a "$1")" == 600 ]]' _ "$HOME/.config/workbook/ceph-dashboard.pass"
check_output "Module dashboard du mgr publié" '"dashboard": *"https://' _m08d_ceph "mgr services -f json"
for _m08d_e03_f in bootstrap/initial-ceph.conf specs/hosts.yaml specs/mon.yaml specs/mgr.yaml; do
  check_cmd "plateforme/ceph (main) : $_m08d_e03_f" _m08d_fichier_main plateforme/ceph "$_m08d_e03_f"
done
check_output "plateforme/ceph (main) : l'amorçage désactive le réglage automatique de la mémoire" \
  '^ *osd_memory_target_autotune *= *false' _m08d_contenu_main plateforme/ceph bootstrap/initial-ceph.conf
