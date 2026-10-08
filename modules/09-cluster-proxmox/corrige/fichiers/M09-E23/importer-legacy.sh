#!/usr/bin/env bash
# importer-legacy.sh — import de l'OVA d'InfoGér et mise aux standards (M09-E23).
# À lancer en root sur hv01, après generer-ova.sh (ressources/M09-E23). Étapes « contrôle » et
# « import » ; la reprise de main par cloud-init et l'agent suivent dans le corrigé.
#
#   ./importer-legacy.sh [OVA]     (défaut : /var/lib/vz/import/legacy-rdv01.ova)
set -euo pipefail

OVA="${1:-/var/lib/vz/import/legacy-rdv01.ova}"
VMID=150
STOCKAGE=ceph-vm
TRAVAIL="/var/lib/vz/import/legacy-rdv01.d"

qm status "$VMID" >/dev/null 2>&1 && { echo "la VM $VMID existe déjà : arrêt" >&2; exit 1; }

# --- 1. Contrôle de l'archive AVANT tout import ------------------------------------------------------
premier="$(tar -tf "$OVA" | head -n 1)"
[[ "$premier" == *.ovf ]] || { echo "le premier fichier de l'OVA n'est pas le descripteur ($premier)" >&2; exit 1; }
rm -rf "$TRAVAIL"; mkdir -p "$TRAVAIL"
tar -xf "$OVA" -C "$TRAVAIL"
# Aucun chemin absolu ni « .. » ne doit sortir du dossier (tar -t l'aurait montré) :
find "$TRAVAIL" -mindepth 1 -maxdepth 1 -printf '%f\n'
(
  cd "$TRAVAIL"
  # Manifeste « SHA256(fichier)= somme » → format de sha256sum « somme  fichier »
  sed -nE 's/^SHA256\(([^)]+)\)= ([0-9a-f]{64})$/\2  \1/p' ./*.mf | sha256sum -c -
)

# --- 2. Simulation puis import ------------------------------------------------------------------------
ovf="$(find "$TRAVAIL" -maxdepth 1 -name '*.ovf' | head -n 1)"
qm importovf "$VMID" "$ovf" "$STOCKAGE" --dryrun 1
qm importovf "$VMID" "$ovf" "$STOCKAGE"

# --- 3. Mise aux standards (avant le premier démarrage utile) -------------------------------------
qm set "$VMID" --scsihw virtio-scsi-single \
  --cpu x86-64-v2-AES \
  --serial0 socket --vga serial0 \
  --agent enabled=1 \
  --ostype l26 \
  --tags "env-m09;legacy" \
  --description "Legacy-RDV, import de l'OVA InfoGér (PLAT-1033)"
# Carte réseau : importovf ne recrée pas forcément la carte du descripteur ; on pose la nôtre.
qm set "$VMID" --net0 virtio,bridge=vinv99
# Lecteur cloud-init : reprise de main sans le mot de passe d'InfoGér (voir le corrigé, étape 5).
qm set "$VMID" --ide2 "$STOCKAGE:cloudinit" --ciuser admin --ipconfig0 ip=dhcp
echo ">> ajoute ta clé : qm set $VMID --sshkeys /root/cle-admin.pub   (fichier .pub copié depuis adm01)"
qm config "$VMID"
rm -rf "$TRAVAIL"
