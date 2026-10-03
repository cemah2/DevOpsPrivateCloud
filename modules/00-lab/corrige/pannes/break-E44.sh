# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E44.sh — M00-E44 « Panne : une VM refuse de démarrer »
#
# Ne touche jamais au socle : le script prépare une VM sandbox dédiée 5044 (sbx44), clone
# complet du template 9000 sur un stockage répertoire dédié « sbx-store » (créé sur hdd-bulk
# si c'est un stockage de type répertoire ou ZFS, sinon sous /var/lib/workbook), puis :
#   1. verrou résiduel « backup » sur la VM ;
#   2. stockage sbx-store désactivé ;
#   3. mémoire demandée (3 × RAM de l'hôte) impossible à allouer (si vm.overcommit_memory=0,
#      sinon bascule sur la variante 4) ;
#   4. disque système référencé vers un volume inexistant (configuration sauvegardée avant).
# Sauvegardes : /var/lib/workbook/E44.* sur pve01. La VM et le stockage restent après
# annulation (à supprimer par l'apprenant en fin d'exercice, voir corrigé).

# shellcheck source=_commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_commun.sh"

WB_VMID_SBX44=5044

_E44_preparer() {
  echo "Préparation de la VM de l'exercice (1 à 3 min la première fois)…"
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_SBX44" TPL="$WB_VMID_TPL" BULK="${WB_STORAGE_BULK:-hdd-bulk}" >/dev/null <<'EOF'
set -e
if ! pvesm status --storage sbx-store >/dev/null 2>&1; then
  json="$(pvesh get "/storage/$BULK" --output-format json 2>/dev/null || true)"
  type="$(printf '%s' "$json" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')"
  dir=""
  case "$type" in
    dir|nfs|cifs|cephfs|btrfs)
      base="$(printf '%s' "$json" | sed -n 's/.*"path":"\([^"]*\)".*/\1/p')"
      [ -n "$base" ] && dir="$base/sbx-store" ;;
    zfspool)
      pool="$(printf '%s' "$json" | sed -n 's/.*"pool":"\([^"]*\)".*/\1/p')"
      if [ -n "$pool" ]; then
        zfs list "$pool/sbx-store" >/dev/null 2>&1 || zfs create "$pool/sbx-store"
        dir="$(zfs get -H -o value mountpoint "$pool/sbx-store")"
      fi ;;
  esac
  [ -n "$dir" ] || dir="$WB_DIR/sbx-store"
  mkdir -p "$dir"
  pvesm add dir sbx-store --path "$dir" --content images
  printf '%s\n' "$dir" > "$WB_DIR/E44.sbx-store"
  journal "stockage sbx-store créé ($dir) pour la VM d'exercice"
fi
pvesm set sbx-store --disable 0 >/dev/null 2>&1 || true
if ! qm status "$VMID" >/dev/null 2>&1; then
  qm clone "$TPL" "$VMID" --name sbx44 --full 1 --storage sbx-store --format qcow2 --pool lab
  if pvesh get /cluster/sdn/vnets/vsandbox >/dev/null 2>&1; then
    qm set "$VMID" --net0 virtio,bridge=vsandbox
  else
    qm set "$VMID" --net0 virtio,bridge=vmbr1,tag=99
  fi
  qm set "$VMID" --ipconfig0 ip=dhcp --onboot 0 --description "VM d'exercice M00-E44 (jetable)"
  journal "VM $VMID (sbx44) créée par clone complet de $TPL sur sbx-store"
fi
qm stop "$VMID" --skiplock 1 >/dev/null 2>&1 || true
EOF
}

panne_E44_v1() {
  _E44_preparer || return 1
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_SBX44" >/dev/null <<'EOF'
qm set "$VMID" --lock backup || exit 1
: > "$WB_DIR/E44.lock"
journal "verrou « backup » posé sur la VM $VMID"
EOF
}

panne_E44_v2() {
  _E44_preparer || return 1
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF'
pvesm set sbx-store --disable 1 || exit 1
: > "$WB_DIR/E44.disable"
journal "stockage sbx-store désactivé"
EOF
}

panne_E44_v3() {
  local oc
  oc="$(remote "$WB_PVE_HOST" "sysctl -n vm.overcommit_memory" 2>/dev/null)" || oc=""
  if [[ "$oc" != 0 ]]; then
    # Surallocation permissive : QEMU démarrerait quand même. Variante 4 à la place.
    WB_VAR=4
    panne_E44_v4
    return
  fi
  _E44_preparer || return 1
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_SBX44" >/dev/null <<'EOF'
total_mib=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 ))
demande=$(( total_mib * 3 ))
if [ ! -f "$WB_DIR/E44.memory" ]; then
  qm config "$VMID" | awk '/^memory:/{m=$2} /^balloon:/{b=$2} END{print m, b}' > "$WB_DIR/E44.memory"
fi
qm set "$VMID" --memory "$demande" --balloon 0 || exit 1
journal "mémoire de la VM $VMID passée à $demande MiB (3 × RAM de l'hôte), ballooning désactivé"
EOF
}

panne_E44_v4() {
  _E44_preparer || return 1
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_SBX44" >/dev/null <<'EOF'
conf="/etc/pve/qemu-server/$VMID.conf"
[ -f "$WB_DIR/E44.conf" ] || cp -a "$conf" "$WB_DIR/E44.conf"
ligne="$(grep -Em1 "^(scsi|virtio|sata|ide)[0-9]+: [^,]*vm-$VMID-disk-[0-9]+" "$conf" | cut -d: -f1)"
[ -n "$ligne" ] || exit 1
sed -i -E "s/^($ligne: [^,]*vm-$VMID-disk-)([0-9]+)/\\11\\2/" "$conf"
journal "disque $ligne de la VM $VMID repointé vers un volume inexistant (configuration sauvegardée)"
EOF
}

annuler_E44() {
  wb_exec "$WB_PVE_HOST" VMID="$WB_VMID_SBX44" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01"
if [ -f "$WB_DIR/E44.disable" ]; then
  pvesm set sbx-store --disable 0 && rm -f "$WB_DIR/E44.disable"
fi
if [ -f "$WB_DIR/E44.lock" ]; then
  qm unlock "$VMID" 2>/dev/null; rm -f "$WB_DIR/E44.lock"
fi
if [ -f "$WB_DIR/E44.memory" ]; then
  read -r mem bal < "$WB_DIR/E44.memory"
  if [ -n "${bal:-}" ]; then
    qm set "$VMID" --memory "${mem:-2048}" --balloon "$bal"
  else
    qm set "$VMID" --memory "${mem:-2048}" --delete balloon
  fi
  rm -f "$WB_DIR/E44.memory"
fi
if [ -f "$WB_DIR/E44.conf" ]; then
  cp "$WB_DIR/E44.conf" "/etc/pve/qemu-server/$VMID.conf" && rm -f "$WB_DIR/E44.conf"
fi
journal "annulation : VM $VMID démarrable (verrou, stockage, mémoire, disque rétablis)"
EOF
}

resume_E44() {
  echo "La VM de test sbx44 (5044) refuse de démarrer : « qm start 5044 » renvoie une erreur."
}

symptome_E44() {
  wb_symptome "Ticket DEV-0318 — De : Julien Petit" \
    "La VM sbx44 (5044) que tu m'as préparée pour mes tests refuse de démarrer :" \
    "le bouton Start dans l'interface (et « qm start 5044 ») renvoie une erreur." \
    "J'en ai besoin cet après-midi pour valider un correctif de MédiAgenda." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 00 44"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main E44 4 "$@"; }
fi
