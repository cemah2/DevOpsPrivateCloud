# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées dans la VM
#
# check-E21.sh — M03-E21 « Panne : cloud-init ignore la configuration »
# La VM de Julien (2037) a appliqué la configuration demandée, cloud-init fonctionne
# normalement (source de données NoCloud) et aucune entrave ne subsiste pour la suite.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E21 — Panne : cloud-init ignore la configuration"
require_cmd jq ssh
_m03_charger
_m03_v=2037

check_cmd "VM 2037 (agenda-dev01) démarrée" _m03_en_marche "$_m03_v"
check_cmd "VM 2037 : lecteur cloud-init présent dans la configuration Proxmox" \
  bash -c 'grep -Eq "^(ide|sata|scsi)[0-9]+: .*cloudinit" <<<"$1"' _ "$(_m03_conf "$_m03_v" || true)"
check_cmd "VM 2037 : configuration demandée par Julien (ipconfig0 10.10.99.37/24)" \
  bash -c 'grep -Eq "^ipconfig0: .*ip=10\.10\.99\.37/24" <<<"$1"' _ "$(_m03_conf "$_m03_v" || true)"
check_cmd "adresse 10.10.99.37 appliquée dans la VM" \
  _m03_gexec_match "$_m03_v" 'ip -4 -o addr show' '10\.10\.99\.37/24'
check_cmd "clé de Julien (julien.petit@medisphere) installée pour admin" \
  _m03_gexec "$_m03_v" 'grep -q "julien\.petit@medisphere" /home/admin/.ssh/authorized_keys'
check_cmd "clé de adm01 toujours installée (accès de l'équipe)" \
  _m03_gexec "$_m03_v" '[ "$(grep -vc "julien\.petit@medisphere" /home/admin/.ssh/authorized_keys)" -ge 1 ]'
check_cmd "cloud-init : statut done, sans erreur" _m03_gexec "$_m03_v" 'cloud-init status --wait >/dev/null'
check_cmd "cloud-init : source de données NoCloud (lecteur Proxmox)" \
  _m03_gexec_match "$_m03_v" 'cloud-init status --long' 'detail: .*DataSourceNoCloud'
check_cmd "cloud-init : aucun marqueur de désactivation" _m03_gexec "$_m03_v" '[ ! -e /etc/cloud/cloud-init.disabled ]'
check_cmd "cloud-init : le cache est vérifié à chaque démarrage (pas de manual_cache_clean)" \
  _m03_gexec "$_m03_v" '! grep -rqsE "^[[:space:]]*manual_cache_clean:[[:space:]]*(true|True)" /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.d/ && [ ! -e /var/lib/cloud/instance/manual-clean ]'
check_cmd "cloud-init : configuration système valide (schema --system)" \
  _m03_gexec "$_m03_v" 'cloud-init schema --system >/dev/null 2>&1'

title "Prévention"
check_cmd "journal de diagnostic de l'incident (docs/socle/journal/, INC-3007)" \
  bash -c 'grep -rqs "INC-3007" "$1"' _ "$_M03_DOC/journal"
