# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant ou dans la VM
#
# check-E11.sh — M03-E11 « cloud-init avancé : vendor-data, multi-part, réseau v2 »
# VM 2032 m03-ci-avance démarrée. Lecture seule.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E11 — cloud-init avancé : vendor-data, multi-part, réseau v2"
require_cmd jq
_m03_charger
_m03_e11_bulk="${WB_STORAGE_BULK:-hdd-bulk}"

title "Configuration de la VM 2032 et snippets"
_m03_e11_conf="$(_m03_conf 2032)" || _m03_e11_conf=""
_m03_e11_a() { grep -Eqi -- "$1" <<<"$_m03_e11_conf"; }
check_cmd "VM 2032 m03-ci-avance présente" \
  bash -c 'grep -q "^name: m03-ci-avance$" <<<"$1"' _ "$_m03_e11_conf"
check_cmd "VM 2032 en marche" _m03_en_marche 2032
check_cmd "carte réseau : adresse MAC imposée BC:24:11:03:20:32 sur vsandbox" \
  _m03_e11_a '^net0: virtio=BC:24:11:03:20:32,.*bridge=vsandbox'
check_cmd "cicustom : vendor-data m03-e11-vendor.mime" _m03_e11_a '^cicustom: .*vendor=[^,]*snippets/m03-e11-vendor\.mime'
check_cmd "cicustom : réseau m03-e11-network.yaml" _m03_e11_a '^cicustom: .*network=[^,]*snippets/m03-e11-network\.yaml'
check_ssh "le vendor-data est un MIME multi-part avec une partie Jinja" "$WB_PVE_HOST" \
  "f=\"\$(pvesm path $_m03_e11_bulk:snippets/m03-e11-vendor.mime)\"; grep -qi '^Content-Type: multipart/mixed' \"\$f\" && grep -qi '^Content-Type: text/jinja2' \"\$f\""
check_ssh "la configuration réseau est en version 2" "$WB_PVE_HOST" \
  "grep -Eq '^ *version: *2' \"\$(pvesm path $_m03_e11_bulk:snippets/m03-e11-network.yaml)\""

title "Dans la VM"
check_cmd "eth0 porte 10.10.99.251/24" _m03_gexec_match 2032 'ip -4 -br addr show eth0' '10\.10\.99\.251/24'
check_cmd "résolveur 10.10.20.10" _m03_gexec_match 2032 'resolvectl dns' '10\.10\.20\.10'
check_cmd "/etc/motd : MédiAgenda et identifiant d'instance (rendu Jinja)" \
  _m03_gexec 2032 'grep -q "MédiAgenda" /etc/motd && grep -qF "$(cloud-init query instance_id)" /etc/motd'
check_cmd "git installé" _m03_gexec 2032 'command -v git >/dev/null'
check_cmd "inscription faite (/var/lib/mediagenda/inscription)" _m03_gexec 2032 'test -s /var/lib/mediagenda/inscription'
check_cmd "au moins deux démarrages tracés" \
  _m03_gexec 2032 'test "$(grep -c . /var/log/mediagenda-demarrages.log)" -ge 2'
check_cmd "cloud-init terminé sans erreur ni avertissement (code 0)" _m03_gexec 2032 'cloud-init status >/dev/null'

title "Préparation sur adm01"
_m03_e11_f="$HOME/m03/e11/fabriquer-vendor.sh"
check_cmd "m03/e11/fabriquer-vendor.sh présent dans le dossier personnel" test -s "$_m03_e11_f"
check_cmd "il valide (schema) avant d'assembler (make-mime)" \
  bash -c 'grep -q "cloud-init schema" "$1" && grep -q "make-mime" "$1"' _ "$_m03_e11_f"
