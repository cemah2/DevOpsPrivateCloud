#!/usr/bin/env bash
# =============================================================================
# deployer-socle.sh — clone adm01 (1001) et dns01 (1002) depuis 9000 (M00-E12)
# À lancer en root sur pve01. Usage : ./deployer-socle.sh <DNS-PUBLIC>
#   ex. ./deployer-socle.sh 9.9.9.9
# Le résolveur passé en argument est PROVISOIRE (dns01 ne sert pas encore de
# DNS) ; adm01 et dns01 basculeront sur 10.10.20.10 en M00-E13 (le template, lui,
# garde 10.10.20.10 pour les futures VMs).
# =============================================================================
set -euo pipefail

DNS_PROVISOIRE="${1:?Usage : $0 <DNS-PUBLIC>}"
TEMPLATE=9000
STO_SYS="${WB_STORAGE_NVME:-local-nvme}"
DOMAINE=par1.medisphere.internal

# vmid  nom    vlan  ip           passerelle  cœurs  RAM   disque  étiquette  ordre
VMS=(
  "1002   dns01  20    10.10.20.10  10.10.20.1  1      1024  -       dns        2"
  "1001   adm01  10    10.10.10.10  10.10.10.1  2      2048  20G     admin      3"
)

deployer() {
  local id="$1" nom="$2" vlan="$3" ip="$4" gw="$5" cores="$6" mem="$7" disque="$8" tag="$9" ordre="${10}"

  if qm status "$id" >/dev/null 2>&1 || pct status "$id" >/dev/null 2>&1; then
    echo "VMID $id déjà utilisé : $nom ignorée."
    return 0
  fi

  echo "=== $nom ($id) ==="
  qm clone "$TEMPLATE" "$id" --name "$nom" --full 1 --pool lab --storage "$STO_SYS"
  qm set "$id" \
    --cores "$cores" --memory "$mem" \
    --tags "socle;${tag}" \
    --net0 "virtio,bridge=vmbr1,tag=${vlan}" \
    --ipconfig0 "ip=${ip}/24,gw=${gw}" \
    --nameserver "$DNS_PROVISOIRE" --searchdomain "$DOMAINE" \
    --onboot 1 --startup "order=${ordre}"
  if [[ "$disque" != "-" ]]; then
    qm disk resize "$id" scsi0 "$disque"
  fi
  qm start "$id"

  # Attente de l'agent QEMU (installé par le vendor-data au premier démarrage)
  local i
  for i in $(seq 1 60); do
    if qm guest cmd "$id" ping >/dev/null 2>&1; then
      echo "$nom : agent QEMU opérationnel (après ~$((i * 5)) s)."
      return 0
    fi
    sleep 5
  done
  echo "$nom : l'agent ne répond pas après 5 min. Regarde la console : qm terminal $id" >&2
  return 1
}

for ligne in "${VMS[@]}"; do
  # shellcheck disable=SC2086  # découpage volontaire de la ligne en champs
  deployer $ligne
done
