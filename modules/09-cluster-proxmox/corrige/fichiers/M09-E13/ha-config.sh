#!/usr/bin/env bash
# ha-config.sh — ressources et règles HA de hv-par1 (M09-E13). Rejouable.
#
# À lancer en root sur un nœud du cluster. La configuration HA est dans /etc/pve/ha/ (pmxcfs) :
# une seule exécution vaut pour tout le cluster.
#   resources.cfg : vm:101 (app01), vm:102 (app02), vm:103 (app03) — started, max_restart 1, max_relocate 1
#   rules.cfg     : app01-preferences (node-affinity, non stricte, hv01:3 > hv02:2 > hv03:1)
#                   frontaux-separes  (resource-affinity, negative, vm:102 + vm:103)
set -euo pipefail

declare -A COMMENTAIRE=([101]="app01 — base de démonstration (PLAT-1023)"
  [102]="app02 — frontal (PLAT-1023)" [103]="app03 — frontal (PLAT-1023)")

pvecm status | grep -q 'Quorate:.*Yes' || { echo "cluster sans quorum : arrêt" >&2; exit 1; }

# --- Ressources -------------------------------------------------------------------------------------
for id in 101 102 103; do
  # Le disque doit être sur un stockage partagé : la HA redémarre la VM AILLEURS.
  # (qm config ne lit que les VMs du nœud local : on lit le fichier de pmxcfs, quel que soit le nœud.)
  confs=(/etc/pve/nodes/*/qemu-server/"$id".conf)
  conf="${confs[0]}"
  [[ -f "$conf" ]] || { echo "vm:$id introuvable" >&2; exit 1; }
  if sed '/^\[/q' "$conf" | grep -E '^(scsi|virtio|sata|ide)[0-9]+:' | grep -v 'media=cdrom' | grep -qv 'ceph-vm:'; then
    echo "vm:$id a un disque hors de ceph-vm : refusé (voir M09-E11)" >&2
    exit 1
  fi
  if ha-manager config | grep -q "^vm:$id\$"; then
    ha-manager set "vm:$id" --state started --max_restart 1 --max_relocate 1 --comment "${COMMENTAIRE[$id]}"
  else
    ha-manager add "vm:$id" --state started --max_restart 1 --max_relocate 1 --comment "${COMMENTAIRE[$id]}"
  fi
done

# --- Règles -----------------------------------------------------------------------------------------
regle_existe() { ha-manager rules config --type "$1" 2>/dev/null | grep -q "$2"; }

if regle_existe node-affinity app01-preferences; then
  ha-manager rules set node-affinity app01-preferences --resources vm:101 --nodes 'hv01:3,hv02:2,hv03:1' --strict 0
else
  ha-manager rules add node-affinity app01-preferences --resources vm:101 --nodes 'hv01:3,hv02:2,hv03:1' \
    --strict 0 --comment "app01 : hv01, sinon hv02, sinon hv03 (PLAT-1023)"
fi

if regle_existe resource-affinity frontaux-separes; then
  ha-manager rules set resource-affinity frontaux-separes --resources vm:102,vm:103 --affinity negative
else
  ha-manager rules add resource-affinity frontaux-separes --resources vm:102,vm:103 --affinity negative \
    --comment "les deux frontaux jamais sur le même nœud (PLAT-1023)"
fi

echo "== /etc/pve/ha/resources.cfg"; cat /etc/pve/ha/resources.cfg
echo "== /etc/pve/ha/rules.cfg";     cat /etc/pve/ha/rules.cfg
echo "== état (le CRS applique les règles au tour suivant, ~10 s)"; sleep 15; ha-manager status
