# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes et filtres jq entre apostrophes, évalués ailleurs
#
# check-E03.sh — M11-E03 : PXE et iPXE : démarrer sur le réseau
# À lancer depuis adm01, après avoir démarré bm03 et bm01 au moins une fois. Lecture seule.

# shellcheck source=_m11-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-decouverte.sh"

title "M11-E03 — PXE et iPXE : démarrer sur le réseau"
require_cmd jq curl

# --- Les quatre serveurs nus ------------------------------------------------------------------------
# VMID nom MAC firmware(ovmf|seabios)
while read -r _m11d_vmid _m11d_nom _m11d_mac _m11d_fw; do
  _m11d_conf="$(_m11d_qm_config "$_m11d_vmid")"
  check_output "$_m11d_nom ($_m11d_vmid) : MAC fixe $_m11d_mac sur vprov" \
    "^net0: [a-z0-9]+=${_m11d_mac},.*bridge=vprov" sed 's/=\([0-9A-Fa-f:]*\)/=\U\1/' <<<"$_m11d_conf"
  check_output "$_m11d_nom : démarrage réseau d'abord, puis disque" '^boot: order=net0;scsi0' echo "$_m11d_conf"
  check_output "$_m11d_nom : CPU host (x86-64-v3 pour Rocky Linux 10)" '^cpu: (cputype=)?host' echo "$_m11d_conf"
  if [[ "$_m11d_fw" == ovmf ]]; then
    check_output "$_m11d_nom : OVMF (UEFI)" '^bios: ovmf' echo "$_m11d_conf"
    check_output "$_m11d_nom : disque EFI sans clés préinstallées (Secure Boot désactivé)" \
      '^efidisk0: .*pre-enrolled-keys=0' echo "$_m11d_conf"
  else
    check_cmd "$_m11d_nom : SeaBIOS (BIOS)" bash -c '[ -n "$1" ] && ! grep -q "^bios: ovmf" <<<"$1"' _ "$_m11d_conf"
  fi
done <<'LISTE'
2112 bm01 02:4D:53:60:00:01 seabios
2113 bm02 02:4D:53:60:00:02 seabios
2114 bm03 02:4D:53:60:00:03 ovmf
2115 bm04 02:4D:53:60:00:04 ovmf
LISTE

# --- Kea : trois classes exclusives, sur les deux pairs ------------------------------------------------
for _m11d_h in dns01 dns02; do
  _m11d_k="$(_m11d_kea "$_m11d_h")"
  check_cmd "$_m11d_h : une classe pour iPXE (option 77) qui renvoie l'URL de boot.ipxe" \
    jq -e '[.arguments.Dhcp4["client-classes"][]? | select((.test | test("option\\[77\\]"))
            and (.test | test("not") | not) and (.["boot-file-name"] // "" | test("^https?://pxe01\\.par1\\.medisphere\\.internal/boot\\.ipxe$")))] | length == 1' <<<"$_m11d_k"
  check_cmd "$_m11d_h : une classe BIOS (option 93 = 0x0000) → undionly.kpxe, qui exclut iPXE" \
    jq -e '[.arguments.Dhcp4["client-classes"][]? | select((.test | test("option\\[93\\]\\.hex == 0x0000"))
            and (.test | test("not")) and .["boot-file-name"] == "undionly.kpxe")] | length == 1' <<<"$_m11d_k"
  check_cmd "$_m11d_h : une classe UEFI x86-64 (0x0007 et 0x0009) → ipxe.efi, qui exclut iPXE" \
    jq -e '[.arguments.Dhcp4["client-classes"][]? | select((.test | test("0x0007")) and (.test | test("0x0009"))
            and (.test | test("not")) and .["boot-file-name"] == "ipxe.efi")] | length == 1' <<<"$_m11d_k"
done

# --- Scripts iPXE servis, identiques à main -------------------------------------------------------------
for _m11d_f in boot.ipxe:ipxe/boot.ipxe ipxe/menu.ipxe:ipxe/menu.ipxe; do
  _m11d_url="${_m11d_f%%:*}"; _m11d_depot="${_m11d_f#*:}"
  _m11d_servi="$(_m11d_http "$_m11d_url")"
  check_output "pxe01 sert /$_m11d_url, qui commence par #!ipxe" '^#!ipxe$' head -n 1 <<<"$_m11d_servi"
  check_cmd "/$_m11d_url publié = $_m11d_depot de main (plateforme/provisioning)" \
    test "$(sha256sum <<<"$_m11d_servi")" = "$(_m11d_contenu_main "$_M11D_PROJET_PROV" "$_m11d_depot" | sha256sum)"
done
check_cmd "plateforme/provisioning : outils/publier.sh sur main" _m11d_fichier_main "$_M11D_PROJET_PROV" outils/publier.sh
check_cmd "plateforme/provisioning : pipeline (.gitlab-ci.yml) sur main" _m11d_fichier_main "$_M11D_PROJET_PROV" .gitlab-ci.yml

# --- Les traces d'un vrai démarrage ---------------------------------------------------------------------
check_ssh "pxe01 : une lecture TFTP de ipxe.efi est journalisée (démarrage UEFI)" pxe01 \
  'sudo -n journalctl --since "-30 days" --no-pager 2>/dev/null | grep -Eq "RRQ from 10\.10\.60\.[0-9]+ filename ipxe\.efi"'
check_ssh "pxe01 : boot.ipxe a été téléchargé par un client du VLAN 60" pxe01 \
  'sudo -n sh -c "cat /var/log/nginx/pxe-acces.log /var/log/nginx/pxe-acces.log.1 2>/dev/null" | grep -Eq "^10\.10\.60\.[0-9]+ .*\"GET /boot\.ipxe HTTP/[0-9.]+\" 200"'

# --- La note ---------------------------------------------------------------------------------------------
_m11d_note="${WB_DEPOT:-$HOME/medisphere}/docs/provisioning/demarrage-reseau.md"
check_cmd "documentation : demarrage-reseau.md décrit les séquences UEFI et BIOS" \
  bash -c 'grep -qi "uefi" "$1" && grep -qi "bios" "$1" && grep -qi "tftp" "$1"' _ "$_m11d_note"
