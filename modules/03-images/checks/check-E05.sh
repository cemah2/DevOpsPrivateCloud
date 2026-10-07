# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant ou dans la VM
#
# check-E05.sh — M03-E05 « Construire depuis l'ISO : proxmox-iso et preseed Debian 13 »
# VM de contrôle 2030 démarrée. Lecture seule ; recalcule la somme de l'ISO sur pve01
# (quelques secondes sur le HDD).

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E05 — Construire depuis l'ISO : proxmox-iso et preseed Debian 13"
require_cmd jq git packer shellcheck
_m03_charger
_m03_e05_bulk="${WB_STORAGE_BULK:-hdd-bulk}"
_m03_e05_d="$_M03_SRC/debian13-base"

# _m03_e05_defaut FICHIER VARIABLE — valeur par défaut (chaîne) d'une variable Packer.
_m03_e05_defaut() {
  awk -v v="variable \"$2\"" 'index($0, v) == 1 { dans = 1 }
    dans && /default *=/ { sub(/.*default *= *"/, ""); sub(/".*/, ""); print; exit }' "$1" 2>/dev/null
}

title "ISO et dépôt"
_m03_e05_iso="$(_m03_e05_defaut "$_m03_e05_d/variables.pkr.hcl" iso_name)"
_m03_e05_sha="$(_m03_e05_defaut "$_m03_e05_d/variables.pkr.hcl" iso_sha256)"
check_cmd "variables.pkr.hcl : ISO netinst Debian 13 déclarée (iso_name = ${_m03_e05_iso:-?})" \
  grep -Eq '^debian-13\.[0-9]+\.[0-9]+-amd64-netinst\.iso$' <<<"$_m03_e05_iso"
check_ssh "ISO présente sur $_m03_e05_bulk et somme conforme à iso_sha256" "$WB_PVE_HOST" \
  "f=\"\$(pvesm path '$_m03_e05_bulk:iso/$_m03_e05_iso')\" && [ \"\$(sha256sum \"\$f\" | cut -d' ' -f1)\" = '$_m03_e05_sha' ]"
check_cmd "outils/deposer-iso.sh exécutable" test -x "$_M03_SRC/outils/deposer-iso.sh"
check_cmd "outils/deposer-iso.sh sans remarque ShellCheck" shellcheck -x "$_M03_SRC/outils/deposer-iso.sh"
check_cmd "deposer-iso.sh vérifie une signature GPG (gpg --verify / VALIDSIG)" \
  grep -Eq 'gpgv?.*--verify|VALIDSIG' "$_M03_SRC/outils/deposer-iso.sh"

title "Code du build (copie locale et main)"
for _m03_e05_f in debian13-base/build.pkr.hcl debian13-base/variables.pkr.hcl debian13-base/http/preseed.cfg vars/lab.pkrvars.hcl outils/deposer-iso.sh; do
  check_cmd "$_m03_e05_f sur main" _m03_fichier_main "$_m03_e05_f"
done
check_cmd "packer fmt -check sans écart" bash -c 'cd "$1" && packer fmt -check -recursive . >/dev/null' _ "$_M03_SRC"
check_cmd "ISO déclarée dans un bloc boot_iso (pas d'options iso_* dépréciées)" \
  bash -c 'grep -q "boot_iso *{" "$1" && ! grep -Eq "^  (iso_file|iso_url|iso_storage_pool|unmount_iso) *=" "$1"' _ "$_m03_e05_d/build.pkr.hcl"
check_cmd "vérification TLS active (pas d'insecure_skip_tls_verify = true)" \
  bash -c '! grep -Eq "insecure_skip_tls_verify *= *true" "$1"' _ "$_m03_e05_d/build.pkr.hcl"
check_cmd "serveur HTTP de Packer : adresse et ports fixés" \
  bash -c 'grep -q "http_bind_address" "$1" && grep -q "http_port_min" "$1"' _ "$_m03_e05_d/build.pkr.hcl"
check_cmd "preseed : mot de passe injecté au build, jamais écrit dans le fichier" \
  bash -c 'grep -Eq "user-password password \\$\\{" "$1" && ! grep -Eq "root-password(-crypted)? password [^$]" "$1"' _ "$_m03_e05_d/http/preseed.cfg"

# _m03_e05_notes VMID — champ « notes » (description) du template, texte brut (API, en root sur pve01).
_m03_e05_notes() {
  remote "$WB_PVE_HOST" "pvesh get /nodes/\$(hostname)/qemu/$1/config --output-format json" 2>/dev/null \
    | jq -r '.description // ""'
}

title "Template 9001 tpl-debian13-base"
_m03_e05_conf="$(_m03_conf 9001)" || _m03_e05_conf=""
_m03_e05_a() { grep -Eq -- "$1" <<<"$_m03_e05_conf"; }
check_cmd "9001 est un template nommé tpl-debian13-base" \
  bash -c 'grep -q "^template: 1" <<<"$1" && grep -q "^name: tpl-debian13-base$" <<<"$1"' _ "$_m03_e05_conf"
check_cmd "9001 dans le pool lab" jq -e 'any(.[]; .vmid == 9001 and (.pool // "") == "lab")' <<<"$(_m03_vms)"
check_cmd "étiquettes base et debian13" \
  bash -c 'grep -Eq "^tags: .*base" <<<"$1" && grep -Eq "^tags: .*debian13" <<<"$1"' _ "$_m03_e05_conf"
check_cmd "contrôleur virtio-scsi-single" _m03_e05_a '^scsihw: virtio-scsi-single$'
check_cmd "CPU x86-64-v2-AES" _m03_e05_a '^cpu: (cputype=)?x86-64-v2-AES'
check_cmd "agent QEMU et port série" \
  bash -c 'grep -Eq "^agent: (1|enabled=1)" <<<"$1" && grep -q "^serial0: socket" <<<"$1"' _ "$_m03_e05_conf"
check_cmd "disque système sur ${WB_STORAGE_NVME:-local-nvme}" _m03_e05_a "^scsi0: ${WB_STORAGE_NVME:-local-nvme}:"
check_cmd "lecteur cloud-init présent" _m03_e05_a '^(ide|sata|scsi)[0-9]+: .*cloudinit'
check_cmd "plus aucune ISO montée" bash -c '! grep -Eq ":iso/" <<<"$1"' _ "$_m03_e05_conf"
check_cmd "carte réseau sur le VNet vsandbox" _m03_e05_a '^net0: .*bridge=vsandbox'
_m03_e05_n="$(_m03_e05_notes 9001)" || _m03_e05_n=""
check_cmd "les notes citent l'ISO source" bash -c '[[ -n "$2" ]] && grep -qF "$2" <<<"$1"' _ "$_m03_e05_n" "$_m03_e05_iso"

title "Réseau de build"
check_ssh_output "gw01 : règle vsandbox → adm01 TCP 8100-8199" gw01 \
  '10\.10\.10\.10.*8100-8199|8100-8199.*10\.10\.10\.10' "sudo -n nft list chain inet filter forward"
check_cmd "matrice des flux : flux 8100-8199 vers adm01" \
  _m03_doc_contient "$_M03_DOC/matrice-flux.md" '8100-8199'

title "VM de contrôle 2030 (clone de 9001)"
check_cmd "VM 2030 démarrée" _m03_en_marche 2030
check_cmd "2030 : adresse statique 10.10.99.250 donnée par cloud-init" \
  _m03_gexec_match 2030 'ip -4 -br addr' '10\.10\.99\.250/24'
check_cmd "2030 : résolveur effectif 10.10.20.10 (systemd-resolved)" \
  _m03_gexec_match 2030 'resolvectl dns' '10\.10\.20\.10'
check_cmd "2030 : pas d'ifupdown" _m03_gexec 2030 '! test -x /usr/sbin/ifup'
check_cmd "2030 : la racine a grandi avec le disque (> 8 Go)" \
  _m03_gexec 2030 'test "$(df -BG --output=size / | tail -n 1 | tr -dc 0-9)" -gt 8'
check_cmd "2030 : compte de construction verrouillé ou absent" \
  _m03_gexec 2030 '! id packer >/dev/null 2>&1 || passwd -S packer | grep -q " L "'
