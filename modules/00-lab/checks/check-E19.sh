# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E19.sh — M00-E19 : Snapshots, clones liés et clones complets
# À lancer depuis adm01, AVANT de détruire sbx02 (5002) et sbx03 (5003). Lecture seule.

title "M00-E19 — Snapshots, clones liés et clones complets"

# --- Clone lié 5002 ---
check_ssh "5002 (sbx02) existe" "$WB_PVE_HOST" \
  'qm status 5002 >/dev/null 2>&1'
check_ssh "5002 est un clone lié du template 9000 (disque adossé à base-9000)" "$WB_PVE_HOST" \
  'qm config 5002 | grep -Eq "^(scsi|virtio|sata|ide)[0-9]+: [^,]*base-9000-disk-[0-9]+/vm-5002-disk-"'
check_ssh "5002 : snapshot « etat-initial » présent" "$WB_PVE_HOST" \
  'grep -q "^\[etat-initial\]" /etc/pve/qemu-server/5002.conf'
check_ssh "5002 : snapshot « avec-ram » présent, avec état mémoire" "$WB_PVE_HOST" \
  'awk "/^\[avec-ram\]/ {s=1; next} /^\[/ {s=0} s && /^vmstate:/ {f=1} END {exit !f}" /etc/pve/qemu-server/5002.conf'
check_ssh "5002 : le snapshot « etat-initial » n'embarque pas de RAM" "$WB_PVE_HOST" \
  'awk "/^\[etat-initial\]/ {s=1; next} /^\[/ {s=0} s && /^vmstate:/ {f=1} END {exit f}" /etc/pve/qemu-server/5002.conf'

# --- Clone complet 5003 ---
check_ssh "5003 (sbx03) existe" "$WB_PVE_HOST" \
  'qm status 5003 >/dev/null 2>&1'
check_ssh "5003 a son propre disque (vm-5003-disk-…)" "$WB_PVE_HOST" \
  'qm config 5003 | grep -Eq "^(scsi|virtio|sata|ide)[0-9]+: [^,]*vm-5003-disk-"'
check_ssh "5003 ne dépend pas du template (aucune référence à base-9000)" "$WB_PVE_HOST" \
  '! qm config 5003 | grep -q "base-9000-disk"'

# --- Rangement ---
check_ssh "5002 et 5003 sont dans le pool lab" "$WB_PVE_HOST" \
  'r=$(pvesh get /cluster/resources --type vm --output-format json | tr "}" "\n" | grep -E "\"pool\" *: *\"lab\""); echo "$r" | grep -Eq "\"vmid\" *: *5002([^0-9]|$)" && echo "$r" | grep -Eq "\"vmid\" *: *5003([^0-9]|$)"'
