# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-S11.sh — F4-S11 « Panne : la VM migrée ne démarre pas comme avant » (INC-6011).
#
# Cibles : ftp-part01 (3402) ou stats01 (3403), JAMAIS legacy-rdv01 (3401). Avant toute modification,
# un instantané Proxmox « avant_f4_s11 » (sans état mémoire) est pris. --annuler : si la VM est déjà
# saine (réparée par l'apprenant : démarrée, agent, adresse, scsi0), il supprime seulement l'instantané ;
# sinon il arrête la VM, revient à l'instantané (disque ET configuration), redémarre, attend l'agent et
# supprime l'instantané.
#   1. stats01 : « Lucas applique le wiki d'InfoGér » : fstab par nom de périphérique (/dev/sda1,
#      /dev/sda15) puis disque passé de scsi0 (VirtIO SCSI) à virtio0 (virtio-blk) « pour les
#      performances » : le disque devient /dev/vda, /boot/efi attend /dev/sda15 → mode urgence ;
#   2. ftp-part01 : nom d'interface figé par la MAC (fichier .link « lan0 », configuration ifupdown
#      passée à lan0), puis nouvelle MAC sur net0 (carte « refaite ») → l'interface garde son nom ens18,
#      la configuration vise lan0 : aucune adresse, plus de FTP (l'agent, lui, répond) ;
#   3. stats01 : initramfs « réduit » d'InfoGér (MODULES=list, modules vmw_pvscsi, vmxnet3, ext4),
#      régénéré, redémarrage → plus de pilote virtio_scsi : racine introuvable, shell (initramfs).
# Tout passe par pve01 (root) : qm, qm guest exec (agent). Journal : /var/lib/workbook/pannes.log de pve01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_S11_INSTANTANE=avant_f4_s11

# _s11_vmid VARIANTE — VM visée par la variante.
_s11_vmid() { if [[ "$1" == 2 ]]; then echo 3402; else echo 3403; fi; }

# _s11_pve ACTION VMID — exécute l'action sur pve01 (root). Actions : prealable, instantane, v1, v2, v3,
# constat1, constat2, constat3, annuler. Code ≠ 0 en cas d'échec.
_s11_pve() {
  wb_exec "$WB_PVE_HOST" ACTION="$1" VMID="$2" INSTANTANE="$_S11_INSTANTANE" <<'DISTANT'
set -u
agent_ok() { qm guest cmd "$VMID" ping >/dev/null 2>&1; }
attendre_agent() {   # attendre_agent SECONDES — 0 dès que l'agent répond
  local i
  for i in $(seq 1 $(($1 / 5))); do agent_ok && return 0; sleep 5; done
  return 1
}
invite() {           # invite "script sh" — exécuté dans la VM par l'agent ; 0 si code de sortie 0
  qm guest exec "$VMID" --timeout 120 -- sh -c "$1" 2>/dev/null | grep -Eq '"exitcode"[[:space:]]*:[[:space:]]*0([^0-9]|$)'
}
arreter() {
  qm shutdown "$VMID" --timeout 120 >/dev/null 2>&1 || qm stop "$VMID" >/dev/null 2>&1
  qm status "$VMID" | grep -q stopped
}

case "$ACTION" in
  prealable)
    [ "$VMID" = 3402 ] || [ "$VMID" = 3403 ] || exit 1
    qm status "$VMID" 2>/dev/null | grep -q running || { echo "VM $VMID absente ou arrêtée" >&2; exit 1; }
    agent_ok || { echo "l'agent QEMU de $VMID ne répond pas : termine F4-S10 d'abord" >&2; exit 1; }
    qm config "$VMID" | grep -Eq '^scsi0: ' || { echo "VM $VMID : pas de disque scsi0 (configuration inattendue)" >&2; exit 1; }
    qm config "$VMID" | grep -Eq '^net0: virtio=' || { echo "VM $VMID : carte net0 non virtio" >&2; exit 1; }
    if qm listsnapshot "$VMID" | grep -qw "$INSTANTANE"; then
      echo "un instantané $INSTANTANE existe déjà sur $VMID : lance d'abord lab/bin/break F4 11 --annuler" >&2; exit 1
    fi
    ;;
  instantane)
    qm snapshot "$VMID" "$INSTANTANE" --description "F4-S11 : état sain avant la panne (lab/bin/break F4 11 --annuler)" >/dev/null || exit 1
    journal "instantané $INSTANTANE pris sur $VMID"
    ;;
  v1)
    invite '
      set -e
      grep -Eq "^[^#[:space:]]+[[:space:]]+/[[:space:]]" /etc/fstab
      racine=$(findmnt -n -o SOURCE /)
      awk -v r="$racine" "\$2 == \"/\" && \$1 !~ /^#/ { \$1 = r } { print }" /etc/fstab > /etc/fstab.s11
      if grep -Eq "^[^#[:space:]]+[[:space:]]+/boot/efi[[:space:]]" /etc/fstab.s11; then
        esp=$(findmnt -n -o SOURCE /boot/efi || echo /dev/sda15)
        awk -v e="$esp" "\$2 == \"/boot/efi\" && \$1 !~ /^#/ { \$1 = e } { print }" /etc/fstab.s11 > /etc/fstab.s11b
        mv /etc/fstab.s11b /etc/fstab.s11
      else
        [ -b /dev/sda15 ]
        printf "/dev/sda15 /boot/efi vfat defaults 0 2\n" >> /etc/fstab.s11
      fi
      printf "# Wiki InfoGér « VM Debian » §4.2 : désigner les disques par leur nom (lisible).\n" | cat - /etc/fstab.s11 > /etc/fstab
      rm -f /etc/fstab.s11
      grep -q "^/dev/sd" /etc/fstab
    ' || exit 1
    journal "fstab de $VMID réécrit par noms de périphériques"
    arreter || exit 1
    ligne=$(qm config "$VMID" | sed -nE 's/^scsi0: (.*)$/\1/p')
    volid=${ligne%%,*}
    opts=$(printf '%s' "$ligne" | tr ',' '\n' | sed 1d | grep -Ev '^(ssd|size)=' | paste -sd, -)
    qm set "$VMID" --delete scsi0 >/dev/null || exit 1
    qm set "$VMID" --virtio0 "$volid${opts:+,$opts}" --boot order=virtio0 >/dev/null || exit 1
    journal "disque de $VMID déplacé de scsi0 vers virtio0 ($volid)"
    qm start "$VMID" >/dev/null || exit 1
    ;;
  v2)
    ancienne=$(qm config "$VMID" | sed -nE 's/^net0: virtio=([0-9A-Fa-f:]{17}).*/\1/p')
    [ -n "$ancienne" ] || exit 1
    invite '
      set -e
      dev=$(ip -o -4 route show default | sed -n "s/.* dev \([^ ]*\).*/\1/p" | head -n 1)
      [ -n "$dev" ]
      grep -Eq "^(auto|iface)[[:space:]]+$dev([[:space:]]|\$)" /etc/network/interfaces
      mac=$(cat /sys/class/net/$dev/address)
      mkdir -p /etc/systemd/network
      printf "# Wiki InfoGér : nom d interface stable, lié à la carte (MAC).\n[Match]\nMACAddress=%s\n\n[Link]\nName=lan0\n" "$mac" \
        > /etc/systemd/network/10-infoger-lan0.link
      sed -i "s/\b$dev\b/lan0/g" /etc/network/interfaces
      update-initramfs -u >/dev/null 2>&1
      grep -q lan0 /etc/network/interfaces
    ' || exit 1
    journal "interface de $VMID figée sur lan0 par la MAC $ancienne"
    arreter || exit 1
    neuve=$(printf 'BC:24:11:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
    reste=$(qm config "$VMID" | sed -nE 's/^net0: virtio=[0-9A-Fa-f:]{17}(.*)$/\1/p')
    qm set "$VMID" --net0 "virtio=$neuve$reste" >/dev/null || exit 1
    journal "MAC de net0 de $VMID changée : $ancienne -> $neuve"
    qm start "$VMID" >/dev/null || exit 1
    ;;
  v3)
    invite '
      set -e
      mkdir -p /var/lib/workbook
      [ -f /var/lib/workbook/modules.s11 ] || cp -a /etc/initramfs-tools/modules /var/lib/workbook/modules.s11
      printf "# Wiki InfoGér « initramfs minimal » : démarrage plus rapide sur VMware.\nMODULES=list\n" \
        > /etc/initramfs-tools/conf.d/zz-infoger-reduit.conf
      printf "\n# Wiki InfoGér : pilotes VMware\nvmw_pvscsi\nvmxnet3\next4\n" >> /etc/initramfs-tools/modules
      update-initramfs -u -k all >/dev/null 2>&1
      for i in /boot/initrd.img-*; do
        if lsinitramfs "$i" | grep -q "virtio_scsi"; then exit 1; fi
      done
    ' || exit 1
    journal "initramfs de $VMID régénéré en MODULES=list (sans virtio_scsi)"
    arreter || exit 1
    qm start "$VMID" >/dev/null || exit 1
    ;;
  constat1|constat3)
    qm status "$VMID" | grep -q running || exit 1
    if [ "$ACTION" = constat1 ]; then qm config "$VMID" | grep -q '^virtio0: ' || exit 1; fi
    # La panne est réelle si l'agent ne répond pas pendant 150 s après le démarrage.
    if attendre_agent 150; then exit 1; fi
    ;;
  constat2)
    qm status "$VMID" | grep -q running || exit 1
    attendre_agent 180 || exit 1
    sleep 20
    if qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | grep -q '"10\.10\.20\.45"'; then exit 1; fi
    ;;
  annuler)
    if qm listsnapshot "$VMID" 2>/dev/null | grep -qw "$INSTANTANE"; then
      # VM déjà réparée par l'apprenant (démarrée, agent, adresse, scsi0, pas de virtio0) : on garde sa
      # réparation et on retire seulement l'instantané.
      ip=10.10.20.45; [ "$VMID" = 3403 ] && ip=10.10.20.46
      if qm status "$VMID" | grep -q running && agent_ok \
         && qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | grep -q "\"$ip\"" \
         && qm config "$VMID" | grep -q '^scsi0: ' && ! qm config "$VMID" | grep -q '^virtio0: '; then
        qm delsnapshot "$VMID" "$INSTANTANE" >/dev/null || echo "avertissement : instantané $INSTANTANE à supprimer à la main sur $VMID" >&2
        journal "VM $VMID saine (réparée) : instantané $INSTANTANE supprimé, aucun retour arrière"
        exit 0
      fi
      qm stop "$VMID" >/dev/null 2>&1 || true
      qm rollback "$VMID" "$INSTANTANE" >/dev/null || { echo "retour à l'instantané impossible sur $VMID" >&2; exit 1; }
      qm start "$VMID" >/dev/null 2>&1 || true
      attendre_agent 240 || echo "avertissement : l'agent de $VMID ne répond pas encore (vérifie : qm terminal $VMID)" >&2
      qm delsnapshot "$VMID" "$INSTANTANE" >/dev/null || echo "avertissement : instantané $INSTANTANE à supprimer à la main sur $VMID" >&2
      journal "VM $VMID revenue à $INSTANTANE ; instantané supprimé"
    fi
    ;;
  *) exit 2 ;;
esac
DISTANT
}

_s11_preparer() {
  local vmid
  vmid="$(_s11_vmid "$WB_VAR")"
  _s11_pve prealable "$vmid" || return 1
  _s11_pve instantane "$vmid" || return 1
  _s11_pve "v$WB_VAR" "$vmid"
}

panne_S11_v1() { _s11_preparer; }
panne_S11_v2() { _s11_preparer; }
panne_S11_v3() { _s11_preparer; }

verifier_S11() {
  _s11_pve "constat$WB_VAR" "$(_s11_vmid "$WB_VAR")"
}

annuler_S11() {
  local v
  # Variante inconnue (marqueur perdu) : on regarde les deux VMs possibles.
  for v in 3402 3403; do
    _s11_pve annuler "$v" || wb_avert "annulation incomplète sur la VM $v (instantané $_S11_INSTANTANE)"
  done
}

symptome_S11() {
  case "$WB_VAR" in
    1) wb_symptome "Ticket INC-6011 — De : Nadia Roussel" \
         "stats01 ne revient pas depuis la maintenance de Lucas : plus de SSH, rien dans la supervision." \
         "La console de Proxmox affiche quelque chose à propos d'un « emergency mode » et attend qu'on" \
         "appuie sur Entrée, mais ça ne mène nulle part. Lucas dit qu'il a juste « appliqué le wiki" \
         "d'InfoGér et mis le disque en virtio, comme c'est plus rapide »." ;;
    2) wb_symptome "Ticket INC-6011 — De : Nadia Roussel" \
         "Le laboratoire nous appelle : impossible de déposer leurs résultats depuis ce matin, la connexion" \
         "FTP n'aboutit pas. La VM ftp-part01 est bien démarrée dans Proxmox, Lucas dit même que « l'agent" \
         "répond », mais plus rien ne passe par le réseau. Il a « stabilisé le nom de la carte » avant de" \
         "refaire la carte réseau." ;;
    *) wb_symptome "Ticket INC-6011 — De : Nadia Roussel" \
         "stats01 ne redémarre pas depuis la maintenance de Lucas. Dans la console, un message dit qu'il" \
         "n'arrive pas à trouver un disque, puis une invite « (initramfs) ». Lucas a seulement « allégé le" \
         "démarrage » en suivant une page du wiki d'InfoGér qu'il a retrouvée." ;;
  esac
  printf '  %s\n\n' "Temps cible : 45 min. Contrôle : lab/bin/check F4 11"
}

resume_S11() {
  case "$WB_VAR" in
    1) echo "stats01 bloquée en mode urgence après une maintenance (disque passé en virtio)." ;;
    2) echo "ftp-part01 démarrée mais injoignable sur le réseau après une maintenance." ;;
    *) echo "stats01 ne trouve plus son disque au démarrage (invite initramfs)." ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F4 S11 3 "$@"; }
fi
