# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant ou dans la VM
#
# check-E04.sh — M03-E04 « cloud-init en profondeur : étapes, modules, journaux »
# VM 2032 m03-ci démarrée. Lecture seule : configuration Proxmox, snippet sur pve01,
# contenu de la VM par l'agent QEMU (qm guest exec, en root sur pve01).

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E04 — cloud-init en profondeur"
require_cmd jq
_m03_charger
_m03_e04_bulk="${WB_STORAGE_BULK:-hdd-bulk}"
_m03_e04_snip="$_m03_e04_bulk:snippets/m03-e04-vendor.yaml"

title "VM 2032 et vendor-data"
_m03_e04_conf="$(_m03_conf 2032)" || _m03_e04_conf=""
_m03_e04_a() { grep -Eq -- "$1" <<<"$_m03_e04_conf"; }
check_cmd "VM 2032 m03-ci présente" _m03_e04_a '^name: m03-ci$'
check_cmd "VM 2032 dans le pool lab" jq -e 'any(.[]; .vmid == 2032 and (.pool // "") == "lab")' <<<"$(_m03_vms)"
check_cmd "VM 2032 étiquetée env-m03" _m03_e04_a '^tags: .*env-m03'
check_cmd "VM 2032 démarrée" _m03_en_marche 2032
check_cmd "cicustom référence $_m03_e04_snip" _m03_e04_a "^cicustom: .*vendor=${_m03_e04_snip//./\\.}"
check_ssh "le snippet commence par #cloud-config" "$WB_PVE_HOST" \
  "head -n1 \"\$(pvesm path $_m03_e04_snip)\" | grep -q '^#cloud-config'"
check_ssh "le snippet reprend l'agent QEMU, et contient bootcmd et runcmd" "$WB_PVE_HOST" \
  "f=\"\$(pvesm path $_m03_e04_snip)\"; grep -q qemu-guest-agent \"\$f\" && grep -q '^bootcmd:' \"\$f\" && grep -q '^runcmd:' \"\$f\""

title "Fréquences observées dans la VM (/var/log/m03-e04.log)"
_m03_e04_log="$(_m03_gexec 2032 'cat /var/log/m03-e04.log')" || _m03_e04_log=""
_m03_e04_nb() { grep -c "^$1 " <<<"$_m03_e04_log" || true; }
_m03_e04_boot="$(_m03_e04_nb bootcmd)"
_m03_e04_run="$(_m03_e04_nb runcmd)"
_m03_e04_inst="$(grep -o 'instance=[^ ]*' <<<"$_m03_e04_log" | sort -u | grep -c . || true)"
check_cmd "au moins 4 démarrages tracés par bootcmd (trouvés : $_m03_e04_boot)" test "$_m03_e04_boot" -ge 4
check_cmd "runcmd exécuté, mais moins souvent que bootcmd ($_m03_e04_run contre $_m03_e04_boot)" \
  bash -c '(( $1 >= 1 && $1 < $2 ))' _ "$_m03_e04_run" "$_m03_e04_boot"
check_cmd "au moins deux identifiants d'instance différents (trouvés : $_m03_e04_inst)" test "$_m03_e04_inst" -ge 2

title "État de cloud-init au dernier démarrage"
check_cmd "cloud-init a terminé (status: done)" _m03_gexec_match 2032 'cloud-init status' '^status: done'
check_cmd "cloud-init schema --system sans erreur" _m03_gexec 2032 'cloud-init schema --system >/dev/null'

title "Fiche de diagnostic"
_m03_e04_fiche="$HOME/m03/e04/fiche-cloud-init.md"
check_cmd "fiche ~/m03/e04/fiche-cloud-init.md rédigée" test -s "$_m03_e04_fiche"
check_cmd "la fiche traite de l'identifiant d'instance et du vendor-data" \
  _m03_doc_contient "$_m03_e04_fiche" 'instance' 'vendor'
