# shellcheck shell=bash
# check-E44.sh — M00-E44 « Panne : une VM refuse de démarrer » : retour à l'état sain.
title "M00-E44 — Panne : une VM refuse de démarrer"

if remote "$WB_PVE_HOST" "qm status 5044 >/dev/null 2>&1"; then
  check_ssh_output "pve01 : la VM 5044 (sbx44) est démarrée" "$WB_PVE_HOST" '^status: running' "qm status 5044"
  check_ssh "pve01 : la VM 5044 n'est pas verrouillée" "$WB_PVE_HOST" "! qm config 5044 | grep -q '^lock:'"
  check_ssh "pve01 : mémoire de la VM 5044 raisonnable (≤ 8 Gio)" "$WB_PVE_HOST" \
    "qm config 5044 | awk '/^memory:/{m=\$2} END{exit !(m > 0 && m <= 8192)}'"
  check_ssh "pve01 : tous les volumes référencés par 5044 existent" "$WB_PVE_HOST" \
    "qm config 5044 | sed -nE 's/^(scsi|virtio|sata|ide)[0-9]+: ([^,]+).*/\2/p' | grep -v '^none\$' | grep -v 'media=cdrom' | while read -r v; do pvesm path \"\$v\" >/dev/null 2>&1 && [ -e \"\$(pvesm path \"\$v\")\" ] || exit 1; done"
  if remote "$WB_PVE_HOST" "pvesm status --storage sbx-store >/dev/null 2>&1"; then
    check_ssh_output "pve01 : stockage sbx-store actif" "$WB_PVE_HOST" '^sbx-store[[:space:]]+dir[[:space:]]+active' \
      "pvesm status --storage sbx-store"
  else
    skip "stockage sbx-store" "absent"
  fi
else
  skip "VM 5044 (sbx44)" "absente : panne E44 non injectée ou VM déjà supprimée"
fi
