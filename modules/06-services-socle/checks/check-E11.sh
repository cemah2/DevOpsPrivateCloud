# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes ($n, $s… sont des variables jq)
#
# check-E11.sh — M06-E11 : Synchroniser Proxmox vers NetBox (LIBRE)
# À lancer depuis adm01. Lecture seule. On vérifie le RÉSULTAT (NetBox reflète Proxmox), quel
# que soit l'outil choisi, plus ses preuves d'exploitation (tests, exécution planifiée).

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E11 — Synchroniser Proxmox vers NetBox"
require_cmd curl jq

_m06o_checks="${WB_NETBOX_TOKEN_FILE:-$_M06O_CFG/netbox-checks.token}"
_m06o_pve="$(_m06o_pve_vms)"
_m06o_nbvms="$(_m06o_nb "$_m06o_checks" 'virtualization/virtual-machines/?cluster=pve01&limit=500&exclude=config_context' || true)"

check_cmd "Proxmox lisible (pvesh sur pve01)" jq -e 'length > 0' <<<"$_m06o_pve"
check_cmd "NetBox lisible (VMs du cluster pve01)" jq -e '.count > 0' <<<"$_m06o_nbvms"

_m06o_statut_pve() { case "$1" in running) echo active ;; stopped) echo offline ;; *) echo "$1" ;; esac; }

# Pour chaque VM du socle visible dans Proxmox : même VMID, statut, vCPU et mémoire dans NetBox.
for _m06o_h in $_M06O_SOCLE; do
  _m06o_ligne="$(jq -c --arg n "$_m06o_h" '.[] | select(.name == $n and (.template // 0) == 0)' <<<"$_m06o_pve" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$_m06o_ligne" ]]; then
    skip "$_m06o_h : cohérence Proxmox/NetBox" "absente de Proxmox"
    continue
  fi
  _m06o_attendu="$(jq -c --arg s "$(_m06o_statut_pve "$(jq -r .status <<<"$_m06o_ligne")")" \
    '{vmid: .vmid, status: $s, vcpus: (.maxcpu | tonumber), memory: ((.maxmem / 1048576) | floor)}' <<<"$_m06o_ligne")"
  _m06o_vu="$(jq -c --arg n "$_m06o_h" '.results[] | select(.name == $n)
      | {vmid: .custom_fields.vmid, status: .status.value, vcpus: (.vcpus // 0 | tonumber), memory: .memory}' \
      <<<"$_m06o_nbvms" 2>/dev/null | head -n 1 || true)"
  check_cmd "$_m06o_h : NetBox porte le VMID, le statut, les vCPU et la mémoire de Proxmox" \
    test "$_m06o_attendu" == "$_m06o_vu"
done

# VMs d'environnement (env-mNN, hors Molecule) présentes dans Proxmox : connues de NetBox.
_m06o_envs="$(jq -r '.[] | select((.tags // "") | test("(^|;)env-m[0-9]+(;|$)"))
  | select((.tags // "") | test("molecule") | not) | .name' <<<"$_m06o_pve" 2>/dev/null || true)"
if [[ -z "$_m06o_envs" ]]; then
  skip "VMs d'environnement présentes dans NetBox" "aucune VM env-mNN en cours"
else
  for _m06o_h in $_m06o_envs; do
    check_cmd "VM d'environnement $_m06o_h connue de NetBox" \
      jq -e --arg n "$_m06o_h" '[.results[] | select(.name == $n)] | length == 1' <<<"$_m06o_nbvms"
  done
fi

# Exploitation : des tests dans le dépôt de l'outil, et une exécution planifiée.
_m06o_tests_netbox() {
  gitlab_api "$_M06O_PROJET_OUTILS/repository/tree?path=tests&recursive=true&per_page=100" \
    | jq -e 'map(select(.name | test("netbox"; "i"))) | length > 0' >/dev/null
}
_m06o_planifie() {
  systemctl list-timers --all --no-legend 2>/dev/null | grep -qi 'netbox' && return 0
  gitlab_api "$_M06O_PROJET_OUTILS/pipeline_schedules" 2>/dev/null \
    | jq -e 'map(select(.active and (.description | test("netbox"; "i")))) | length > 0' >/dev/null 2>&1
}
check_cmd "plateforme/outils : des tests de la synchronisation NetBox (tests/…netbox…)" _m06o_tests_netbox
check_cmd "exécution planifiée de la synchronisation (minuterie sur adm01 ou pipeline planifié)" _m06o_planifie
