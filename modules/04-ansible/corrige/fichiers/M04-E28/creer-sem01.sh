#!/usr/bin/env bash
# creer-sem01.sh — crée la VM sem01 (2041) depuis l'image dorée courante (M04-E28)
# À lancer sur adm01 (alias SSH pve01 en root). Refuse si le VMID ou l'adresse sont pris.
# shellcheck disable=SC2029  # $VMID & co. sont volontairement développés sur adm01
set -euo pipefail

VMID=2041
NOM=sem01
IP=10.10.20.41
STOCKAGE="${WB_STORAGE_NVME:-local-nvme}"

# Image dorée Debian « current » : le seul template étiqueté gold + debian13 + current.
modele="$(ssh pve01 pvesh get /cluster/resources --type vm --output-format json \
  | jq -r '[.[] | select((.template // 0) == 1)
            | select(((.tags // "") | split(";")) as $t
                     | ($t | index("gold")) and ($t | index("debian13")) and ($t | index("current")))]
           | if length == 1 then .[0].vmid else empty end')"
[[ -n "$modele" ]] || { echo "Image dorée current introuvable (ou plusieurs)" >&2; exit 1; }

if ssh pve01 qm status "$VMID" >/dev/null 2>&1; then
  echo "Le VMID $VMID existe déjà : rien n'est fait." >&2; exit 1
fi
if ping -c 1 -W 1 "$IP" >/dev/null 2>&1; then
  echo "L'adresse $IP répond déjà : rien n'est fait." >&2; exit 1
fi

# Clé publique de adm01, injectée par cloud-init (jamais cuite dans l'image, M03).
ssh pve01 "cat > /root/adm01.pub" <"$HOME/.ssh/id_ed25519.pub"
ssh pve01 qm clone "$modele" "$VMID" --name "$NOM" --pool lab --full 1 --storage "$STOCKAGE"
# Le clone hérite des étiquettes du template : on les REMPLACE (pas de gold/current sur une VM).
ssh pve01 qm set "$VMID" --cores 2 --memory 2048 --tags "env-m04;role-semaphore" \
  --net0 virtio,bridge=vinfra --ipconfig0 "ip=$IP/24,gw=10.10.20.1" \
  --ciuser admin --sshkeys /root/adm01.pub --ciupgrade 0 --onboot 1
ssh pve01 qm disk resize "$VMID" scsi0 20G
ssh pve01 qm start "$VMID"
echo "sem01 démarre : attends cloud-init, puis : ssh admin@$IP cloud-init status --wait"
