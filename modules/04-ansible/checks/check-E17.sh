# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E17.sh — M04-E17 : Rôle pare_feu pour gw01 sans se couper la branche
# À lancer depuis adm01. Lecture seule : règles chargées sur gw01 (nft list), validation du
# fichier (nft -c), journal du filet de sécurité, flux traversants testés depuis adm01,
# playbook en --check (le filet n'est jamais armé en --check).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E17 — Rôle pare_feu pour gw01 sans se couper la branche"
require_cmd git jq curl dig

check_cmd "roles/pare_feu : tasks, defaults et meta présents" _m04o_role_complet pare_feu
check_cmd "roles/pare_feu publié sur main" _m04_fichier_main roles/pare_feu/tasks/main.yml
check_cmd "matrice des flux sur main : inventories/lab/host_vars/gw01/pare_feu.yml" \
  _m04_fichier_main inventories/lab/host_vars/gw01/pare_feu.yml
check_cmd "le rôle valide la configuration avec nft -c" \
  bash -c 'grep -rEq "nft[[:space:]]+-c" "$1/roles/pare_feu/tasks"' _ "$_M04_SRC"
check_cmd "le rôle arme un retour automatique (systemd-run) et confirme par une NOUVELLE connexion" \
  bash -c 'd="$1/roles/pare_feu/tasks"; grep -rq "systemd-run" "$d" && grep -rq "reset_connection" "$d" && grep -rq "wait_for_connection" "$d"' \
  _ "$_M04_SRC"

# --- gw01 ----------------------------------------------------------------------------------------------
check_ssh_output "gw01 : /etc/nftables.conf généré par Ansible" gw01 '[Aa]nsible' 'head -n 5 /etc/nftables.conf'
check_ssh "gw01 : /etc/nftables.conf valide (nft -c)" gw01 'sudo -n nft -c -f /etc/nftables.conf'
check_ssh_output "gw01 : politique drop en entrée" gw01 'policy drop' 'sudo -n nft list chain inet filter input'
check_ssh_output "gw01 : politique drop en transit" gw01 'policy drop' 'sudo -n nft list chain inet filter forward'
check_ssh "gw01 : nftables chargé au démarrage" gw01 'systemctl is-enabled --quiet nftables'
check_ssh "gw01 : aucun retour automatique en attente (changement confirmé)" gw01 \
  '! systemctl is-active --quiet pare-feu-retour.timer'
check_ssh "gw01 : script de retour en place (/usr/local/sbin/pare-feu-retour)" gw01 'test -x /usr/local/sbin/pare-feu-retour'
check_ssh "gw01 : le filet a déjà servi au moins une fois (essai de coupure, journal)" gw01 \
  'sudo -n journalctl -q -t pare-feu-retour --no-pager | grep -q "restaur"'
_m04o_regles='sudo -n nft list ruleset'
check_ssh_output "gw01 : flux runner01 → pve01:8006 (M03-E15) toujours là" gw01 'ip saddr 10\.10\.20\.15 .*tcp dport 8006|tcp dport 8006 .*10\.10\.20\.15' "$_m04o_regles"
check_ssh_output "gw01 : flux git01 → PBS:8007 (M01-E28) toujours là" gw01 'ip saddr 10\.10\.20\.12 .*tcp dport 8007' "$_m04o_regles"
check_ssh_output "gw01 : NTP pour les VLANs du lab (M00-E31) toujours là" gw01 'udp dport 123' "$_m04o_regles"
check_ssh_output "gw01 : NAT de sortie du lab toujours là" gw01 'masquerade' "$_m04o_regles"

# --- Le lab fonctionne à travers gw01 -------------------------------------------------------------------
check_port "adm01 → dns01:53/tcp à travers gw01" 10.10.20.10 53
check_port "adm01 → git01:443 à travers gw01" 10.10.20.12 443
check_dns "résolution d'un nom Internet par dns01 (dns01 → amont à travers gw01)" deb.debian.org A '^[0-9.]+$' 10.10.20.10
check_cmd "nouvelle connexion SSH à gw01 depuis adm01 (sans multiplexage)" \
  ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8 gw01 true

# --- Documentation et idempotence ------------------------------------------------------------------------
check_cmd "matrice des flux (plateforme/medisphere) : renvoie à host_vars/gw01/pare_feu.yml" \
  bash -c 'grep -q "host_vars/gw01/pare_feu.yml" "$1/docs/socle/matrice-flux.md"' _ "${WB_DEPOT:-$HOME/medisphere}"
_m04o_pb="$(grep -rlE "role:[[:space:]]*pare_feu|^[[:space:]]+-[[:space:]]+pare_feu[[:space:]]*$" "$_M04_SRC/playbooks" 2>/dev/null | grep -v site.yml | head -n 1)" || true
_m04o_sortie="$(_m04_simuler "${_m04o_pb#"$_M04_SRC"/}")"
check_cmd "--check du playbook du pare-feu : aucun changement sur gw01" _m04_recap "$_m04o_sortie" gw01
