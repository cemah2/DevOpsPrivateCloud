# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E13.sh — M27-E13 « Patroni sur VMs » : l'essai a laissé son code et sa comparaison écrite, et les
# VMs 2271-2273 ont été DÉTRUITES (Proxmox, NetBox, DNS). À lancer une fois l'exercice clos : tant que les
# VMs existent, le contrôle d'absence échoue ; avant l'exercice, ce sont le code et le comparatif. Lecture seule.

# shellcheck source=_m27-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-production.sh"

title "M27-E13 — Patroni sur VMs, puis détruit"
require_cmd jq curl dig

check_cmd "plateforme/infra : envs/m27 déclare pg-patroni (VMID 2271, vsandbox 10.10.99.71, module vm-debian)" \
  _m27p_depot_contient_tout plateforme/infra envs/m27 '2271' '10\.10\.99\.71' 'vm-debian' 'pg-patroni'
check_cmd "plateforme/infra : état OpenTofu à part (clé envs/m27)" \
  _m27p_depot_contient plateforme/infra envs/m27 'envs/m27/terraform\.tfstate'
check_cmd "plateforme/donnees : patroni-essai/ configure Patroni avec etcd v3" \
  _m27p_depot_contient_tout plateforme/donnees patroni-essai 'etcd3' 'scope'
check_cmd "comparatif-patroni-cnpg.md : sortie de patronictl list (Leader, réplica synchrone, trois membres)" \
  _m27p_doc "$_m27p_docs" comparatif-patroni-cnpg 'pg-patroni01' 'pg-patroni02' 'pg-patroni03' 'Leader' 'Sync Standby'
check_cmd "comparatif-patroni-cnpg.md : bascules mesurées des deux côtés et conclusion" \
  _m27p_doc "$_m27p_docs" comparatif-patroni-cnpg 'switchover' 'failover|panne' '[0-9]+([,.][0-9]+)? ?s\b' 'CloudNativePG|CNPG' 'conclusion'

# Absence : Proxmox (la liste doit être lisible, sinon on ne conclut rien), NetBox, DNS.
_m27_e13_qm() {
  local l v
  l="$(remote "$WB_PVE_HOST" "qm list" 2>/dev/null)" || return 1
  grep -q VMID <<<"$l" || return 1
  for v in 2271 2272 2273; do
    if awk '{print $1}' <<<"$l" | grep -qx "$v"; then return 1; fi
  done
}
_m27_e13_netbox() {
  netbox_api "virtualization/virtual-machines/?name__isw=pg-patroni" 2>/dev/null | jq -e '.count == 0' >/dev/null 2>&1
}
_m27_e13_dns() {
  local n
  # Le serveur répond (zone par1 lisible) ET les noms ont disparu.
  [[ -n "$(dig +short +time="$WB_TIMEOUT" par1.medisphere.internal SOA 2>/dev/null)" ]] || return 1
  for n in pg-patroni01 pg-patroni02 pg-patroni03; do
    [[ -z "$(dig +short +time="$WB_TIMEOUT" "$n.par1.medisphere.internal" A 2>/dev/null)" ]] || return 1
  done
}
check_cmd "Proxmox : plus aucune VM 2271-2273 (détruites en fin d'exercice)" _m27_e13_qm
check_cmd "NetBox : plus aucune VM pg-patroni*" _m27_e13_netbox
check_cmd "DNS : pg-patroni01..03.par1.medisphere.internal ne résolvent plus" _m27_e13_dns
