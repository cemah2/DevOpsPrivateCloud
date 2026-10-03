# shellcheck shell=bash
# check-E48.sh — M00-E48 « Mesurer et comprendre les performances disque » : rapport présent
# et VM de mesure supprimée.
title "M00-E48 — Mesurer et comprendre les performances disque"

_wb_depot="${WB_DEPOT:-$HOME/medisphere}"
_wb_rap="$_wb_depot/docs/socle/mesures/perf-disques.md"

check_cmd "rapport présent (docs/socle/mesures/perf-disques.md)" test -s "$_wb_rap"
# Noms réels des stockages (lab/lab.env, M00-E07) ; le rapport peut citer l'un ou l'autre nom.
_wb_nvme="${WB_STORAGE_NVME:-local-nvme}"; _wb_ssd="${WB_STORAGE_SSD:-ssd-lab}"; _wb_bulk="${WB_STORAGE_BULK:-hdd-bulk}"
for _wb_st in "$_wb_nvme" "$_wb_ssd" "$_wb_bulk"; do
  check_output "rapport : mesures sur $_wb_st" "\\|[^|]*$_wb_st" cat "$_wb_rap"
done
check_output "rapport : IOPS consignées" 'IOPS' cat "$_wb_rap"
check_output "rapport : latences au 99e centile consignées" '(p99|99e|99\.00th|99th)' cat "$_wb_rap"
check_output "rapport : test de synchronisation type etcd (fdatasync)" 'fdatasync' cat "$_wb_rap"
check_output "rapport : comparaison des modes de cache" 'writeback' cat "$_wb_rap"
check_output "rapport : recommandation de placement" '([Rr]ecommandation|[Pp]lacement)' cat "$_wb_rap"
check_ssh "pve01 : la VM de mesure 5048 a été supprimée" "$WB_PVE_HOST" "! qm status 5048 >/dev/null 2>&1"
check_ssh "pve01 : aucun volume orphelin de la VM 5048" "$WB_PVE_HOST" \
  "! pvesm list $_wb_nvme 2>/dev/null | grep -q 'vm-5048-' && ! pvesm list $_wb_ssd 2>/dev/null | grep -q 'vm-5048-' && ! pvesm list $_wb_bulk 2>/dev/null | grep -q 'vm-5048-'"
