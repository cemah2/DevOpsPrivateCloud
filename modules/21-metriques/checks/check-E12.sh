# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions PromQL, filtres jq et commandes distantes entre apostrophes
#
# check-E12.sh — M21-E12 : Proxmox VE et PBS : pve-exporter
# À lancer depuis adm01. Lecture seule : SSH vers mon01 (systemctl, ss, grep en sudo -n) et vers
# pve01 (pveum/pvesh en lecture), API du Prometheus témoin et du Prometheus du cluster.

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E12 — Proxmox VE et PBS : pve-exporter"
require_cmd jq curl ssh

# --- Proxmox : jeton en lecture seule et IPSet -------------------------------------------------
_m21o_e12_acl="$(remote "$WB_PVE_HOST" 'pveum acl list --output-format json' 2>/dev/null || true)"
check_cmd "pve01 : le jeton wb-supervision@pve!prometheus a PVEAuditor, et seulement lui" _m21o_json "$_m21o_e12_acl" '
  [.[] | select(.ugid == "wb-supervision@pve!prometheus")] as $a
  | ($a | length) >= 1 and ($a | all(.roleid == "PVEAuditor"))'
check_ssh_output "pve01 : IPSet « supervision » du pare-feu Proxmox avec mon01" "$WB_PVE_HOST" '10\.10\.20\.19' \
  'pvesh get /cluster/firewall/ipset/supervision --output-format json'

# --- mon01 : exportateur -------------------------------------------------------------------------
check_ssh "mon01 : service pve-exporter actif" "$_M21O_MON01" 'systemctl is-active --quiet pve-exporter'
check_ssh_output "mon01 : pve-exporter n'écoute que sur 127.0.0.1:9221" "$_M21O_MON01" '^127\.0\.0\.1:9221$' \
  'ss -Htln "sport = :9221" | awk "{print \$4}" | sort -u'
check_ssh "mon01 : aucune configuration ne désactive la vérification TLS (verify_ssl: false)" "$_M21O_MON01" \
  '! sudo -n grep -rEqi "verify_ssl: *false" /etc/prometheus /etc/systemd/system/pve-exporter.service'
check_ssh_output "mon01 : pve.yml lisible par le seul utilisateur du service (600)" "$_M21O_MON01" '^600 pve-exporter$' \
  'sudo -n stat -c "%a %U" /etc/prometheus/pve.yml'

# --- Témoin : séries ---------------------------------------------------------------------------
check_cmd "témoin : pve_up d'au moins un nœud Proxmox VE vaut 1" \
  _m21o_temoin_au_moins 'count(pve_up{job="pve", id=~"node/.+"} == 1)' 1
check_cmd "témoin : node_exporter de pve01 et pbs01 joignables (job hyperviseurs)" \
  _m21o_temoin_au_moins 'count(up{job="hyperviseurs"} == 1)' 2

# --- Cluster : fédération -----------------------------------------------------------------------
check_cmd "cluster : cible federation-mon01 joignable" _m21o_job_up federation-mon01 1
check_cmd "cluster : séries du job pve fédérées avec leurs étiquettes d'origine" \
  _m21o_au_moins 'count(pve_up{job="pve"})' 1
check_cmd "cluster : séries des jobs hyperviseurs et blackbox fédérées" \
  _m21o_au_moins 'count(node_uname_info{job="hyperviseurs"}) + count(probe_success{job="blackbox"})' 3
check_cmd "cluster : aucune étiquette exported_job (honorLabels actif)" \
  _m21o_vide 'count(pve_up{exported_job!=""})'
