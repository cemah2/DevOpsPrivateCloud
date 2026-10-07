# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E22.sh — M03-E22 « Panne : la VM Rocky ne démarre pas »
#
# La panne crée la VM de l'éditeur, editeur-rocky01 (2036), clone complet de l'image dorée
# Rocky « current » (à défaut, du template de base 9002), vérifie qu'elle démarre (agent QEMU),
# l'arrête, applique la « recette » de Julien, puis la redémarre. Variantes :
#   1. type de CPU forcé à x86-64-v2-AES (recette des VMs Debian) : Rocky 10 exige x86-64-v3,
#      l'espace utilisateur s'arrête au premier binaire (panique du noyau, « Attempted to kill init ») ;
#   2. contrôleur SCSI forcé à « lsi » (LSI 53C895A) : pilote absent des noyaux RHEL 8+,
#      dracut ne trouve pas le disque racine et tombe en shell d'urgence ;
#   3. micrologiciel inversé (SeaBIOS ↔ OVMF) : plus de chargeur d'amorçage trouvé ;
#   4. ordre d'amorçage réduit au réseau (net0) : iPXE tente le réseau, puis « No bootable device ».
# Aucune ressource de l'apprenant n'est modifiée. La VM 2036 est notée dans
# /var/lib/workbook/M03-E22.vms sur pve01 ; l'annulation la détruit.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m03-commun.sh
source "$WB_ROOT/modules/03-images/corrige/pannes/_m03-commun.sh"

_e22_pve() { { printf '%s\n' "$_M03_PVE_FONCTIONS"; cat; } | wb_exec "$WB_PVE_HOST" "$@"; }

_e22_injecter() {
  local cle
  cle="$(_m03_cle_adm01)" || return 1
  _e22_pve CLE="$cle" STO="$_M03_STOCKAGE" >/dev/null <<'EOF'
SRC="$(m03_current rocky10)"
[ -n "$SRC" ] || SRC=9002
m03_est_template "$SRC" || { echo "ni image dorée Rocky current, ni template 9002" >&2; exit 1; }
m03_libre 2036 || { echo "VMID 2036 déjà utilisé : libère-le avant l'exercice" >&2; exit 1; }
qm clone "$SRC" 2036 --name editeur-rocky01 --full 1 --storage "$STO" --pool lab >/dev/null || exit 1
echo 2036 >"$WB_DIR/M03-E22.vms"
qm set 2036 --net0 virtio,bridge=vsandbox --tags env-m03 >/dev/null || exit 1
if [ -n "$(m03_disque_cloudinit 2036)" ]; then
  printf '%s\n' "$CLE" >"$WB_DIR/M03-E22.cle.pub"
  qm set 2036 --ciuser admin --sshkeys "$WB_DIR/M03-E22.cle.pub" --ipconfig0 ip=dhcp --ciupgrade 0 >/dev/null
fi
# Précondition : la VM démarre telle que clonée.
qm start 2036 || exit 1
m03_attendre_agent 2036 300 || { echo "2036 ne démarre pas AVANT la panne : template Rocky à vérifier" >&2; exit 1; }
qm shutdown 2036 --timeout 120 >/dev/null 2>&1 || qm stop 2036 >/dev/null
case "$WB_VAR" in
  1) qm set 2036 --cpu x86-64-v2-AES ;;
  2) qm set 2036 --scsihw lsi ;;
  3) if qm config 2036 | grep -q '^bios: ovmf'; then
       qm set 2036 --bios seabios
     else
       qm set 2036 --bios ovmf
     fi ;;
  4) qm set 2036 --boot order=net0 ;;
esac >/dev/null 2>&1 || exit 1
qm start 2036 || exit 1
journal "VM 2036 créée depuis $SRC, recette appliquée (variante $WB_VAR)"
EOF
}

panne_E22_v1() { _e22_injecter; }
panne_E22_v2() { _e22_injecter; }
panne_E22_v3() { _e22_injecter; }
panne_E22_v4() { _e22_injecter; }

verifier_E22() {
  _e22_pve >/dev/null <<'EOF'
qm status 2036 | grep -q 'status: running' || exit 1
# 120 s sans agent : la VM tourne mais le système n'est pas arrivé jusqu'à ses services.
! m03_attendre_agent 2036 120
EOF
}

annuler_E22() {
  _e22_pve >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01 (VM 2036)"
if [ -f "$WB_DIR/M03-E22.vms" ]; then
  grep -qx 2036 "$WB_DIR/M03-E22.vms" && m03_detruire 2036
  rm -f "$WB_DIR/M03-E22.vms" "$WB_DIR/M03-E22.cle.pub"
  journal "annulation : VM 2036 détruite"
fi
exit 0
EOF
}

resume_E22() {
  echo "la VM Rocky de l'éditeur (2036) est « running » dans Proxmox mais ne répond à rien (ni réseau, ni agent)."
}

symptome_E22() {
  wb_symptome "Ticket INC-3010 — De : Julien Petit" \
    "J'ai créé editeur-rocky01 (2036) pour l'éditeur certifié RHEL, en clonant le template Rocky" \
    "et en appliquant ma recette habituelle de création de VM. Proxmox la montre « running »," \
    "mais elle ne prend pas d'adresse, l'agent ne répond pas, SSH impossible. La console affiche" \
    "des messages que je ne comprends pas. L'éditeur arrive demain matin pour l'installation." \
    "(2036 sera supprimée par --annuler.)" \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 03 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 03 E22 4 "$@"; }
fi
