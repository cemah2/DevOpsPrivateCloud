#!/usr/bin/env bash
# optimiser-socle.sh — Proposition de réglages des VMs du socle (M00-E32, PLAT-132).
# À lancer sur pve01 en root, VM par VM : optimiser-socle.sh <VMID>
# Les modifications de matériel (contrôleur, CPU, options de disque) restent EN ATTENTE
# jusqu'à un arrêt/démarrage complet de la VM (pas un reboot depuis l'invité).
# Prérequis dans l'invité : paquet qemu-guest-agent installé et service actif.
set -euo pipefail

vmid="${1:?Usage : $0 <VMID>}"

# Profil par VM : ordre de démarrage, délai avant la suivante (up), délai d'arrêt (down),
# ballooning (0 = désactivé ; sinon mémoire minimale en Mo)
case "$vmid" in
  1000) ordre=1; up=30; down=60; balloon=0 ;;     # gw01 : tout dépend de lui, pas de ballooning
  1002) ordre=2; up=15; down=60; balloon=0 ;;     # dns01 : petite VM, mémoire fixe
  1001) ordre=3; up=0;  down=60; balloon=1024 ;;  # adm01 : outils gourmands par moments
  *) echo "VMID $vmid hors du socle : refus." >&2; exit 1 ;;
esac

# Garde-fou : la VM doit appartenir au pool lab
pvesh get /cluster/resources --type vm --output-format json \
  | VMID="$vmid" perl -MJSON::PP -0777 -ne \
      'exit((grep { $_->{vmid} == $ENV{VMID} && ($_->{pool} // "") eq "lab" } @{decode_json($_)}) ? 0 : 1)' \
  || { echo "VM $vmid absente du pool lab : refus." >&2; exit 1; }

# Copie de la configuration actuelle pour retour arrière
mkdir -p /var/lib/workbook
cp "/etc/pve/qemu-server/${vmid}.conf" "/var/lib/workbook/${vmid}.conf.avant-E32"

# 1. CPU : modèle générique compatible Ivy Bridge (hp01) et Rocket Lake (pve01)
# 2. Contrôleur : un contrôleur virtio-scsi par disque, condition pour un iothread par disque
# 3. Agent : fs-freeze/thaw pendant vzdump, arrêt propre, IP visibles ; TRIM après clonage
# 4. Démarrage : automatique et ordonné
qm set "$vmid" \
  --cpu x86-64-v2-AES \
  --scsihw virtio-scsi-single \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --onboot 1 \
  --startup "order=${ordre},up=${up},down=${down}" \
  --balloon "$balloon"

# 5. Disques : discard (TRIM jusqu'au stockage thin), émulation SSD (l'invité voit un
#    disque non rotatif), iothread. Le volume et les autres options sont conservés.
qm config "$vmid" --current | grep -E '^scsi[0-9]+: ' | grep -v 'media=cdrom' | while IFS= read -r ligne; do
  disque="${ligne%%:*}"
  valeur="${ligne#*: }"
  nouvelle="$(tr ',' '\n' <<<"$valeur" | grep -Ev '^(discard|ssd|iothread)=' | paste -sd, -),discard=on,ssd=1,iothread=1"
  echo "$disque : $nouvelle"
  qm set "$vmid" "--${disque}" "$nouvelle"
done

echo
echo "Modifications en attente :"
qm pending "$vmid" | grep -E '^(new|del)' || echo "(aucune)"
echo
echo "Applique-les par un arrêt/démarrage complet, au moment choisi :"
echo "  qm shutdown $vmid && qm start $vmid"
echo "Puis vérifie : qm agent $vmid ping ; qm pending $vmid"
