# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées dans les VMs
#
# check-E20.sh — M03-E20 « Panne : les clones se marchent dessus »
# Les deux VMs de Julien (2038, 2039) ont chacune leur identité : machine-id, clés d'hôte,
# nom, adresse MAC, adresse IPv4. La régression est couverte par le test d'image (E14).

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E20 — Panne : les clones se marchent dessus"
require_cmd jq ssh
_m03_charger

for _m03_id in 2038 2039; do
  check_cmd "VM $_m03_id démarrée" _m03_en_marche "$_m03_id"
  check_cmd "VM $_m03_id : agent QEMU et cloud-init terminé" _m03_gexec "$_m03_id" 'cloud-init status --wait >/dev/null'
done

# _m03_e20_differe 'commande' — la commande donne un résultat non vide et différent sur 2038 et 2039.
_m03_e20_differe() {
  local a b
  a="$(_m03_gexec 2038 "$1")" || return 1
  b="$(_m03_gexec 2039 "$1")" || return 1
  [[ -n "$a" && -n "$b" && "$a" != "$b" ]]
}
_m03_e20_mac() { _m03_conf "$1" | sed -nE 's/^net0: [a-z0-9]+=([0-9A-Fa-f:]{17}),.*/\1/p' | tr 'A-F' 'a-f'; }
_m03_e20_macs() { local a b; a="$(_m03_e20_mac 2038)"; b="$(_m03_e20_mac 2039)"; [[ -n "$a" && "$a" != "$b" ]]; }

check_cmd "machine-id différents" _m03_e20_differe 'cat /etc/machine-id'
check_cmd "machine-id initialisés (ni vides ni « uninitialized »)" bash -c \
  '[[ "$1" =~ ^[0-9a-f]{32}$ && "$2" =~ ^[0-9a-f]{32}$ ]]' _ \
  "$(_m03_gexec 2038 'cat /etc/machine-id' || true)" "$(_m03_gexec 2039 'cat /etc/machine-id' || true)"
check_cmd "clés d'hôte SSH différentes (empreinte ed25519)" _m03_e20_differe \
  'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | cut -d" " -f2'
check_cmd "noms d'hôte différents" _m03_e20_differe 'hostname'
check_cmd "adresses MAC différentes (configuration Proxmox)" _m03_e20_macs
check_cmd "adresses IPv4 différentes sur vsandbox" _m03_e20_differe \
  'ip -4 -o addr show scope global | awk "{print \$4}" | grep "^10\.10\.99\."'

title "Prévention"
check_cmd "le test d'image contrôle l'unicité du machine-id (tests/tester-image.sh)" \
  grep -q 'machine-id' "$_M03_SRC/tests/tester-image.sh"
check_cmd "journal de diagnostic de l'incident (docs/socle/journal/, INC-3004)" \
  bash -c 'grep -rqs "INC-3004" "$1"' _ "$_M03_DOC/journal"
